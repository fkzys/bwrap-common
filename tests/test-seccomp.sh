# ── bwrap_seccomp ───────────────────────────────────────────

section "bwrap_seccomp"

SA=()
bwrap_seccomp SA none
SA_RC=$?
[[ $SA_RC -eq 0 ]] && ok "none returns 0" || fail "none returned $SA_RC"
[[ ${#SA[@]} -eq 0 ]] && ok "none appends nothing" || fail "none appended ${SA[*]}"

rm -rf "$BWRAP_SECCOMP_CACHE_DIR" "$GEN_COUNTER"
SB=()
bwrap_seccomp SB default
SB_RC=$?
[[ $SB_RC -eq 0 ]] && ok "default returns 0 with a valid fixture" || fail "default returned $SB_RC"
if [[ ${#SB[@]} -eq 2 && "${SB[0]}" == "--seccomp" && "${SB[1]}" =~ ^[0-9]+$ ]]; then
    ok "default appends --seccomp <fd>"
else
    fail "default output was: ${SB[*]}"
fi

SB2=()
bwrap_seccomp SB2 default
SB2_RC=$?
GEN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
if [[ $SB2_RC -eq 0 && "$GEN_CALLS" -eq 1 ]]; then
    ok "default compiles once and reuses the cache"
else
    fail "default cache rc=$SB2_RC generator_calls=$GEN_CALLS"
fi

DEFAULT_CACHE_BLOB=$(find "$BWRAP_SECCOMP_CACHE_DIR" -name '*.bpf' -type f | head -n1)
if [[ -n "$DEFAULT_CACHE_BLOB" && -f "${DEFAULT_CACHE_BLOB}.sha256" ]]; then
    ok "cached default filter has a checksum"
else
    fail "cached default filter checksum missing"
fi

SB3=()
if [[ -n "$DEFAULT_CACHE_BLOB" ]]; then
    printf '\x00' | dd of="$DEFAULT_CACHE_BLOB" bs=1 seek=8 conv=notrunc status=none
    bwrap_seccomp SB3 default 2>/dev/null
    SB3_RC=$?
    GEN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
    if [[ $SB3_RC -eq 0 && ${#SB3[@]} -eq 2 && "$GEN_CALLS" -eq 2 ]]; then
        ok "corrupt .bpf with sidecar is recompiled"
    else
        fail "corrupt cache rc=$SB3_RC generator_calls=$GEN_CALLS"
    fi
else
    fail "cannot test corrupt cache without a cached filter"
fi

VERSION_CACHE="${TMPDIR_TEST}/cache-gen-version"
rm -rf "$VERSION_CACHE" "$GEN_COUNTER"
GV1=()
BWRAP_SECCOMP_CACHE_DIR="$VERSION_CACHE" \
FAKE_GEN_VERSION=4 \
bwrap_seccomp GV1 default
GV1_RC=$?
GV2=()
BWRAP_SECCOMP_CACHE_DIR="$VERSION_CACHE" \
FAKE_GEN_VERSION=5 \
bwrap_seccomp GV2 default
GV2_RC=$?
GEN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
if [[ $GV1_RC -eq 0 && $GV2_RC -eq 0 && "$GEN_CALLS" -eq 2 ]]; then
    ok "generator version changes the cache key"
else
    fail "generator version cache rc=$GV1_RC/$GV2_RC calls=$GEN_CALLS"
fi

CONC_CACHE="${TMPDIR_TEST}/cache-concurrent"
rm -rf "$CONC_CACHE"
CONC_PIDS=()
for _i in 1 2 3 4; do
    (
        CONC_OUT=()
        BWRAP_SECCOMP_CACHE_DIR="$CONC_CACHE" bwrap_seccomp CONC_OUT default
        _rc=$?
        [[ $_rc -eq 0 && ${#CONC_OUT[@]} -eq 2 ]] || exit 1
        _bwrap_seccomp_close_fds
    ) &
    CONC_PIDS+=("$!")
done
CONC_RC=0
for _pid in "${CONC_PIDS[@]}"; do
    wait "$_pid" || CONC_RC=1
done
CONC_BPF=$(find "$CONC_CACHE" -name '*.bpf' -type f | head -n1)
if [[ $CONC_RC -eq 0 && -n "$CONC_BPF" && -f "${CONC_BPF}.sha256" ]] &&
    _bwrap_seccomp_cache_valid "$CONC_BPF"; then
    ok "concurrent cache writers leave a valid entry"
else
    fail "concurrent cache writers left rc=$CONC_RC entry=${CONC_BPF:-none}"
fi

if [[ -z "$DEFAULT_CACHE_BLOB" || ! -f "$DEFAULT_CACHE_BLOB" ||
      ! -f "${DEFAULT_CACHE_BLOB}.sha256" ]]; then
    fail "cannot test unsafe cache without a cached filter"
else
    for _mode in 777 770; do
        SHARED_CACHE="${TMPDIR_TEST}/shared-cache-${_mode}"
        mkdir -p "$SHARED_CACHE"
        cp "$DEFAULT_CACHE_BLOB" "$SHARED_CACHE/"
        cp "${DEFAULT_CACHE_BLOB}.sha256" "$SHARED_CACHE/"
        chmod "$_mode" "$SHARED_CACHE"
        SHARED_BEFORE=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
        SH=()
        BWRAP_SECCOMP_CACHE_DIR="$SHARED_CACHE" \
            bwrap_seccomp SH default 2>"${TMPDIR_TEST}/shared-cache-${_mode}.err"
        SH_RC=$?
        SHARED_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
        SHARED_ERR=$(cat "${TMPDIR_TEST}/shared-cache-${_mode}.err" 2>/dev/null)
        if [[ $SH_RC -eq 0 && ${#SH[@]} -eq 2 &&
              "$SHARED_CALLS" -gt "$SHARED_BEFORE" &&
              "$SHARED_ERR" == *"chmod go-w"* ]]; then
            ok "cache directory mode $_mode is rejected and bypassed"
        else
            fail "cache mode $_mode was used (rc=$SH_RC calls=$SHARED_BEFORE/$SHARED_CALLS)"
        fi
    done

    FOREIGN_CACHE="${TMPDIR_TEST}/foreign-cache"
    mkdir -p "$FOREIGN_CACHE"
    if chown 65534:65534 "$FOREIGN_CACHE" 2>/dev/null; then
        cp "$DEFAULT_CACHE_BLOB" "$FOREIGN_CACHE/"
        cp "${DEFAULT_CACHE_BLOB}.sha256" "$FOREIGN_CACHE/"
        chmod 700 "$FOREIGN_CACHE"
        FOREIGN_BEFORE=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
        FOREIGN=()
        BWRAP_SECCOMP_CACHE_DIR="$FOREIGN_CACHE" \
            bwrap_seccomp FOREIGN default 2>"${TMPDIR_TEST}/foreign-cache.err"
        FOREIGN_RC=$?
        FOREIGN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
        FOREIGN_ERR=$(cat "${TMPDIR_TEST}/foreign-cache.err" 2>/dev/null)
        if [[ $FOREIGN_RC -eq 0 && ${#FOREIGN[@]} -eq 2 &&
              "$FOREIGN_CALLS" -gt "$FOREIGN_BEFORE" &&
              "$FOREIGN_ERR" == *"not current uid"* ]]; then
            ok "foreign-owned cache directory is rejected and bypassed"
        else
            fail "foreign-owned cache was used (rc=$FOREIGN_RC calls=$FOREIGN_BEFORE/$FOREIGN_CALLS)"
        fi
    else
        skip "foreign-owner cache test (requires root)"
    fi
fi

SECCOMP_FD="${SB[1]:-}"
SECCOMP_FD2="${SB2[1]:-}"
SECCOMP_FD3="${SB3[1]:-}"
_bwrap_seccomp_close_fds
if [[ -n "$SECCOMP_FD" ]] && { : <&"$SECCOMP_FD"; } 2>/dev/null; then
    fail "seccomp filter fd was left open"
elif [[ -n "$SECCOMP_FD2" ]] && { : <&"$SECCOMP_FD2"; } 2>/dev/null; then
    fail "cached seccomp filter fd was left open"
elif [[ -n "$SECCOMP_FD3" ]] && { : <&"$SECCOMP_FD3"; } 2>/dev/null; then
    fail "recompiled seccomp filter fd was left open"
else
    ok "seccomp filter fd is closed by cleanup"
fi

TRAP_LOG="${TMPDIR_TEST}/cleanup-trap.log"
(
    trap 'printf "caller rc=%s\n" "$?" >> "$TRAP_LOG"' EXIT
    _bwrap_cleanup() { printf 'cleanup\n' >> "$TRAP_LOG"; }
    _bwrap_install_cleanup
    _bwrap_install_cleanup
    exit 7
)
TRAP_RC=$?
TRAP_OUT=$(cat "$TRAP_LOG" 2>/dev/null)
if [[ $TRAP_RC -eq 7 && "$TRAP_OUT" == $'cleanup\ncaller rc=7' ]]; then
    ok "existing EXIT trap is preserved and cleanup runs once"
else
    fail "EXIT trap chain failed (rc=$TRAP_RC, out=$TRAP_OUT)"
fi

SC=()
BWRAP_SECCOMP_DIR="${TMPDIR_TEST}/missing" bwrap_seccomp SC default 2>/dev/null
SC_RC=$?
[[ $SC_RC -eq 1 ]] && ok "missing default config fails closed" || fail "missing default config returned $SC_RC"
[[ ${#SC[@]} -eq 0 ]] && ok "missing default config appends nothing" || fail "missing default config appended ${SC[*]}"

BAD_SIZE_DIR="${TMPDIR_TEST}/bad-size"
mkdir -p "$BAD_SIZE_DIR"
head -c 12 /dev/zero > "${BAD_SIZE_DIR}/bad.bpf"
SE=()
BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/cache-bad-size" \
BWRAP_SECCOMP_CONF="$SECCOMP_FIXTURE_CONF" \
FAKE_GEN_BLOB="${BAD_SIZE_DIR}/bad.bpf" \
bwrap_seccomp SE default 2>/dev/null
SE_RC=$?
[[ $SE_RC -eq 1 && ${#SE[@]} -eq 0 ]] && ok "invalid size fails closed" || fail "invalid size returned $SE_RC"

if [[ "$SECCOMP_MAGIC" != "00000000" ]]; then
    BAD_ARCH_DIR="${TMPDIR_TEST}/bad-arch"
    mkdir -p "$BAD_ARCH_DIR"
    write_fake_blob "${BAD_ARCH_DIR}/bad.bpf" "deadbeef"
    SG=()
    BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/cache-bad-arch" \
    BWRAP_SECCOMP_CONF="$SECCOMP_FIXTURE_CONF" \
    FAKE_GEN_BLOB="${BAD_ARCH_DIR}/bad.bpf" \
    bwrap_seccomp SG default 2>/dev/null
    SG_RC=$?
    [[ $SG_RC -eq 1 && ${#SG[@]} -eq 0 ]] && ok "arch mismatch fails closed" || fail "arch mismatch returned $SG_RC"
else
    skip "arch mismatch test (unknown host arch)"
fi

rm -rf "$BWRAP_SECCOMP_CACHE_DIR" "$GEN_COUNTER"
unset FAKE_GEN_EXTRA_COPY 2>/dev/null || true

SI=()
bwrap_seccomp SI "openat read"
SI_RC=$?
SJ=()
bwrap_seccomp SJ "openat read"
SJ_RC=$?
GEN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
if [[ $SI_RC -eq 0 && $SJ_RC -eq 0 && "$GEN_CALLS" -eq 1 ]]; then
    ok "allowlist compiles once and reuses the cache"
else
    fail "allowlist rc=$SI_RC/$SJ_RC generator_calls=$GEN_CALLS"
fi
if [[ ${#SI[@]} -eq 2 && "${SI[0]}" == "--seccomp" && "${SI[1]}" =~ ^[0-9]+$ ]]; then
    ok "allowlist appends --seccomp <fd>"
else
    fail "allowlist output was: ${SI[*]}"
fi
CACHE_BLOB=$(find "$BWRAP_SECCOMP_CACHE_DIR" -name '*.bpf' -type f | head -n1)
if [[ -n "$CACHE_BLOB" && "$(stat -c %a "$CACHE_BLOB")" == "600" ]]; then
    ok "cached allowlist filter is mode 600"
else
    fail "cached allowlist filter mode: $(stat -c %a "${CACHE_BLOB:-/nonexistent}" 2>/dev/null)"
fi

SK=()
bwrap_seccomp SK "" 2>/dev/null
SK_RC=$?
[[ $SK_RC -eq 1 && ${#SK[@]} -eq 0 ]] && ok "empty allowlist fails closed" || fail "empty allowlist returned $SK_RC"

FAIL_GEN="${TMPDIR_TEST}/fail-seccomp-gen"
printf '#!/usr/bin/env bash\nexit 2\n' > "$FAIL_GEN"
chmod +x "$FAIL_GEN"
SL=()
BWRAP_SECCOMP_GEN="$FAIL_GEN" bwrap_seccomp SL "openat" 2>/dev/null
SL_RC=$?
[[ $SL_RC -eq 1 && ${#SL[@]} -eq 0 ]] && ok "generator failure fails closed" || fail "generator failure returned $SL_RC"
LEFT=$(find "$BWRAP_SECCOMP_CACHE_DIR" -name '*.tmp.*' -type f | wc -l)
[[ "$LEFT" -eq 0 ]] && ok "generator failure leaves no temp files" || fail "temp files left: $LEFT"

SM=(--seccomp 3)
bwrap_seccomp SM default 2>/dev/null
SM_RC=$?
[[ $SM_RC -eq 1 && ${#SM[@]} -eq 2 ]] && ok "existing --seccomp is rejected" || fail "duplicate --seccomp returned $SM_RC"

DT=()
DT_EXTRA="${TMPDIR_TEST}/extra-rules"
rm -rf "$BWRAP_SECCOMP_CACHE_DIR" "$GEN_COUNTER" "$DT_EXTRA"
FAKE_GEN_EXTRA_COPY="$DT_EXTRA" bwrap_seccomp DT default "getppid EPERM" 2>/dev/null
DT_RC=$?
if [[ $DT_RC -eq 0 && ${#DT[@]} -eq 2 &&
      "${DT[0]}" == "--seccomp" && "${DT[1]}" =~ ^[0-9]+$ ]]; then
    ok "default+extra appends one --seccomp <fd>"
else
    fail "default+extra output was rc=$DT_RC: ${DT[*]}"
fi
has_arg DT "--add-seccomp-fd" && fail "default+extra used --add-seccomp-fd" || ok "default+extra avoids --add-seccomp-fd"
if [[ -f "$DT_EXTRA" ]] && grep -qxF "getppid EPERM" "$DT_EXTRA"; then
    ok "default+extra passes user rules via --extra"
else
    fail "default+extra did not pass the extra rules file"
fi
GEN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
if [[ "$GEN_CALLS" -eq 1 ]]; then
    ok "default+extra compiles once"
else
    fail "default+extra generator_calls=$GEN_CALLS"
fi

DT2=()
FAKE_GEN_EXTRA_COPY="$DT_EXTRA" bwrap_seccomp DT2 default "getppid EPERM" 2>/dev/null
DT2_RC=$?
GEN_CALLS=$(wc -c < "$GEN_COUNTER" 2>/dev/null || echo 0)
if [[ $DT2_RC -eq 0 && ${#DT2[@]} -eq 2 && "$GEN_CALLS" -eq 1 ]]; then
    ok "default+extra reuses the cache"
else
    fail "default+extra cache rc=$DT2_RC generator_calls=$GEN_CALLS"
fi

DT_FD="${DT[1]:-}"
DT2_FD="${DT2[1]:-}"
_bwrap_seccomp_close_fds
if [[ -n "$DT_FD" ]] && { : <&"$DT_FD"; } 2>/dev/null; then
    fail "default+extra left the filter fd open"
elif [[ -n "$DT2_FD" ]] && { : <&"$DT2_FD"; } 2>/dev/null; then
    fail "cached default+extra left the filter fd open"
else
    ok "default+extra closes filter fds"
fi

DE=()
bwrap_seccomp DE default "" 2>/dev/null
DE_RC=$?
[[ $DE_RC -eq 1 && ${#DE[@]} -eq 0 ]] && ok "empty extra blocklist fails closed" || fail "empty extra blocklist returned $DE_RC"

DEW=()
bwrap_seccomp DEW default " " 2>/dev/null
DEW_RC=$?
[[ $DEW_RC -eq 1 && ${#DEW[@]} -eq 0 ]] && ok "whitespace-only extra blocklist fails closed" || fail "whitespace-only extra blocklist returned $DEW_RC"

DTF=()
BWRAP_SECCOMP_GEN="$FAIL_GEN" bwrap_seccomp DTF default "kexec_load ENOSYS" 2>/dev/null
DTF_RC=$?
[[ $DTF_RC -eq 1 && ${#DTF[@]} -eq 0 ]] && ok "extra blocklist compile failure fails closed" || fail "extra compile failure returned $DTF_RC"

DM=(--seccomp 3)
bwrap_seccomp DM default "getppid EPERM" 2>/dev/null
DM_RC=$?
[[ $DM_RC -eq 1 && ${#DM[@]} -eq 2 ]] && ok "default+extra rejects an existing --seccomp" || fail "default+extra duplicate returned $DM_RC"

DMF=(--add-seccomp-fd 3)
bwrap_seccomp DMF default "getppid EPERM" 2>/dev/null
DMF_RC=$?
[[ $DMF_RC -eq 1 && ${#DMF[@]} -eq 2 ]] && ok "default+extra rejects an existing --add-seccomp-fd" || fail "default+extra add-seccomp-fd duplicate returned $DMF_RC"

BAD_CACHE_FILE="${TMPDIR_TEST}/cache-parent-is-file"
: > "$BAD_CACHE_FILE"
RUNTIME_FALLBACK="${TMPDIR_TEST}/runtime-fallback"
mkdir -p "$RUNTIME_FALLBACK"
chmod 700 "$RUNTIME_FALLBACK"
DF=()
BWRAP_SECCOMP_CACHE_DIR="${BAD_CACHE_FILE}/cache" \
XDG_RUNTIME_DIR="$RUNTIME_FALLBACK" \
bwrap_seccomp DF default "getppid EPERM" 2>"${TMPDIR_TEST}/fallback.err"
DF_RC=$?
DF_ERR=$(cat "${TMPDIR_TEST}/fallback.err" 2>/dev/null)
if [[ $DF_RC -eq 0 && ${#DF[@]} -eq 2 && "${DF[0]}" == "--seccomp" ]]; then
    ok "unavailable cache falls back to runtime tmpfs"
else
    fail "cache fallback returned $DF_RC: ${DF[*]}"
fi
if [[ "$DF_ERR" == *"seccomp cache unavailable"* && "$DF_ERR" == *"tmpfs fallback"* ]]; then
    ok "cache fallback warns on stderr"
else
    fail "cache fallback warning was: $DF_ERR"
fi
if [[ -z "$(find "$RUNTIME_FALLBACK" -maxdepth 1 -name 'bwrap-seccomp.*' -print -quit)" ]]; then
    ok "runtime fallback unlinks its temporary filter"
else
    fail "runtime fallback left a temporary filter"
fi

DF2=()
BWRAP_SECCOMP_CACHE_DIR="${BAD_CACHE_FILE}/cache" \
XDG_RUNTIME_DIR="$RUNTIME_FALLBACK" \
bwrap_seccomp DF2 default "getppid EPERM" 2>"${TMPDIR_TEST}/fallback2.err"
DF2_RC=$?
DF2_ERR=$(cat "${TMPDIR_TEST}/fallback2.err" 2>/dev/null)
if [[ $DF2_RC -eq 0 && "$DF2_ERR" != *"seccomp cache unavailable"* ]]; then
    ok "fallback warning is deduplicated"
else
    fail "fallback warning repeated or fallback failed: $DF2_ERR"
fi

DN=()
BWRAP_SECCOMP_CACHE_DIR="${BAD_CACHE_FILE}/cache" \
XDG_RUNTIME_DIR="${TMPDIR_TEST}/missing-runtime" \
bwrap_seccomp DN default 2>/dev/null
DN_RC=$?
if [[ $DN_RC -eq 1 && ${#DN[@]} -eq 0 ]]; then
    ok "missing runtime dir fails closed"
else
    fail "missing runtime dir returned $DN_RC"
fi
_bwrap_seccomp_close_fds

# ── seccomp architecture mapping ────────────────────────────

section "seccomp architecture mapping"

for pair in s390x:80000016 mips:00000008 mips64:80000008 \
            mips64n32:a0000008 parisc:0000000f parisc64:8000000f \
            ppc64:80000015 ppc64le:150000c0; do
    arch=${pair%%:*}
    want=${pair#*:}
    got=$(_bwrap_seccomp_arch_magic "$arch" 2>/dev/null)
    [[ "$got" == "$want" ]] && ok "arch $arch -> $want" || fail "arch $arch -> '${got:-none}', want $want"
done
if _bwrap_seccomp_arch_magic no-such-arch >/dev/null 2>&1; then
    fail "unknown arch mapping is rejected"
else
    ok "unknown arch mapping is rejected"
fi

S390_BLOB="${TMPDIR_TEST}/s390x.bpf"
write_fake_blob "$S390_BLOB" "80000016"
S390=()
BWRAP_SECCOMP_ARCH=s390x \
BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/cache-s390x" \
BWRAP_SECCOMP_CONF="$SECCOMP_FIXTURE_CONF" \
FAKE_GEN_BLOB="$S390_BLOB" \
bwrap_seccomp S390 default
S390_RC=$?
if [[ $S390_RC -eq 0 && ${#S390[@]} -eq 2 && "${S390[0]}" == "--seccomp" ]]; then
    ok "s390x big-endian fixture is accepted"
else
    fail "s390x fixture returned $S390_RC (${S390[*]})"
fi
_bwrap_seccomp_close_fds

S390_BAD_BLOB="${TMPDIR_TEST}/s390x-wrong-endian.bpf"
write_fake_blob "$S390_BAD_BLOB" "16000080"
S390BAD=()
BWRAP_SECCOMP_ARCH=s390x \
BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/cache-s390x-bad" \
BWRAP_SECCOMP_CONF="$SECCOMP_FIXTURE_CONF" \
FAKE_GEN_BLOB="$S390_BAD_BLOB" \
bwrap_seccomp S390BAD default 2>/dev/null
S390BAD_RC=$?
[[ $S390BAD_RC -eq 1 && ${#S390BAD[@]} -eq 0 ]] \
    && ok "s390x little-endian fixture is rejected" \
    || fail "s390x wrong-endian fixture returned $S390BAD_RC"

SU=()
BWRAP_SECCOMP_ARCH=weird \
BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/cache-unknown" \
BWRAP_SECCOMP_CONF="$SECCOMP_FIXTURE_CONF" \
FAKE_GEN_BLOB="$SECCOMP_FIXTURE_BLOB" \
bwrap_seccomp SU default 2>/dev/null
SU_RC=$?
[[ $SU_RC -eq 1 && ${#SU[@]} -eq 0 ]] \
    && ok "unknown architecture fails closed" \
    || fail "unknown architecture returned $SU_RC"

unset BWRAP_SECCOMP_GEN FAKE_GEN_COUNTER FAKE_GEN_BLOB

