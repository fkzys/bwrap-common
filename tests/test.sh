#!/usr/bin/env bash
set -uo pipefail
# Note: no -e. Tests must continue running when assertions fail
# so failures can be counted and reported.

# ── Test harness ─────────────────────────────────────────────

PASS=0
FAIL=0
TESTS=0

ok() {
    PASS=$((PASS + 1))
    TESTS=$((TESTS + 1))
    echo "  ✓ $1"
    return 0
}

fail() {
    FAIL=$((FAIL + 1))
    TESTS=$((TESTS + 1))
    echo "  ✗ $1"
    return 0
}

section() {
    echo ""
    echo "── $1 ──"
}

summary() {
    local name="${0##*/}"
    echo ""
    echo "════════════════════════════════════"
    echo " ${name}: ${PASS} passed, ${FAIL} failed (total: ${TESTS})"
    echo "════════════════════════════════════"
    [[ $FAIL -eq 0 ]]
}

has_arg() {
    local -n _arr=$1; local flag=$2
    for arg in "${_arr[@]}"; do
        [[ "$arg" == "$flag" ]] && return 0
    done
    return 1
}

has_pair() {
    local -n _arr=$1; local flag=$2 val=$3
    for ((i=0; i<${#_arr[@]}-1; i++)); do
        [[ "${_arr[$i]}" == "$flag" && "${_arr[$((i+1))]}" == "$val" ]] && return 0
    done
    return 1
}

has_triple() {
    local -n _arr=$1; local a=$2 b=$3 c=$4
    for ((i=0; i<${#_arr[@]}-2; i++)); do
        [[ "${_arr[$i]}" == "$a" && "${_arr[$((i+1))]}" == "$b" && "${_arr[$((i+2))]}" == "$c" ]] && return 0
    done
    return 1
}

has_sequence() {
    local -n _arr=$1; shift
    local -a _want=("$@")
    local _n=${#_want[@]} _i _j
    (( _n > 0 && _n <= ${#_arr[@]} )) || return 1
    for ((_i=0; _i <= ${#_arr[@]} - _n; _i++)); do
        for ((_j=0; _j < _n; _j++)); do
            [[ "${_arr[$((_i + _j))]}" == "${_want[$_j]}" ]] || break
        done
        (( _j == _n )) && return 0
    done
    return 1
}

has_ordered_pairs() {
    local -n _arr=$1; shift
    local _len=${#_arr[@]} _i=0 _flag _val _found
    while (( $# >= 2 )); do
        _flag=$1
        _val=$2
        shift 2
        _found=0
        for ((; _i < _len - 1; _i++)); do
            if [[ "${_arr[$_i]}" == "$_flag" && "${_arr[$((_i + 1))]}" == "$_val" ]]; then
                _i=$((_i + 2))
                _found=1
                break
            fi
        done
        (( _found )) || return 1
    done
    return 0
}

count_flag() {
    local -n _arr=$1; local flag=$2; local count=0
    for arg in "${_arr[@]}"; do [[ "$arg" == "$flag" ]] && count=$((count + 1)); done
    echo "$count"
}

arrays_equal() {
    local -n _a=$1; local -n _b=$2
    [[ ${#_a[@]} -eq ${#_b[@]} ]] || return 1
    local i
    for ((i = 0; i < ${#_a[@]}; i++)); do
        [[ "${_a[$i]}" == "${_b[$i]}" ]] || return 1
    done
    return 0
}

# ── Source ──────────────────────────────────────────────────

. ./bwrap-common.sh || { echo "FATAL: cannot source bwrap-common.sh"; exit 1; }

# ── Setup ───────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d) || {
    echo "FATAL: cannot create temporary directory" >&2
    exit 1
}
if [[ ! -w "$TMPDIR_TEST" ]]; then
    echo "FATAL: TMPDIR_TEST is not writable: $TMPDIR_TEST" >&2
    exit 1
fi
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── seccomp fixtures ────────────────────────────────────────

SECCOMP_ARCH=$(_bwrap_seccomp_arch)
if ! SECCOMP_MAGIC=$(_bwrap_seccomp_arch_magic "$SECCOMP_ARCH"); then
    # Do not silently pretend an unsupported host is x86_64.  BWRAP_SECCOMP_ARCH
    # is an explicit opt-in for cross-arch fixture testing only.
    echo "FATAL: unsupported host architecture '$SECCOMP_ARCH'" >&2
    echo "Set BWRAP_SECCOMP_ARCH to a supported architecture only for cross-arch testing." >&2
    exit 1
fi

write_fake_blob() {
    local _file=$1 _magic=$2
    printf '\x20\x00\x00\x00\x04\x00\x00\x00\x15\x00\x00\x01' > "$_file"
    printf '%b' "\\x${_magic:0:2}\\x${_magic:2:2}\\x${_magic:4:2}\\x${_magic:6:2}" >> "$_file"
}

SECCOMP_FIXTURE_DIR="${TMPDIR_TEST}/seccomp"
mkdir -p "$SECCOMP_FIXTURE_DIR"
SECCOMP_FIXTURE_BLOB="${SECCOMP_FIXTURE_DIR}/default.${SECCOMP_ARCH}.bpf"
write_fake_blob "$SECCOMP_FIXTURE_BLOB" "$SECCOMP_MAGIC"

export BWRAP_SECCOMP_DIR="$SECCOMP_FIXTURE_DIR"
export BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/seccomp-cache"

# ── Guard re-source ─────────────────────────────────────────

section "Source guard"

. ./bwrap-common.sh
ok "re-source does not error"

# ── Function definitions ───────────────────────────────────

section "Function definitions"

FUNCTIONS=(
    bwrap_base bwrap_gpu bwrap_lib64 bwrap_resolv
    bwrap_wayland bwrap_x11 bwrap_audio
    bwrap_dbus_session bwrap_dbus_system bwrap_dbus_filtered bwrap_dbus_common
    bwrap_themes bwrap_fcitx
    bwrap_home_tmpfs bwrap_runtime_dir bwrap_env_base
    bwrap_bind_dir bwrap_ro_bind_dir
    bwrap_hardened_malloc bwrap_no_hardened_malloc
    bwrap_sandbox bwrap_seccomp bwrap_ssh_agent
    bwrap_resolve_files
    bwrap_gui_setup bwrap_gui_finish
    bwrap_exec
    require_dir
)

for fn in "${FUNCTIONS[@]}"; do
    declare -f "$fn" >/dev/null 2>&1 && ok "function $fn defined" || fail "function $fn not defined"
done

# ── VERSION ─────────────────────────────────────────────────

section "VERSION"

[[ -n "${VERSION:-}" ]] && ok "VERSION is set ('$VERSION')" || fail "VERSION not set"

# ── bwrap_base ──────────────────────────────────────────────

section "bwrap_base"

A=()
bwrap_base A
[[ ${#A[@]} -gt 0 ]]            && ok "produces non-empty array"       || fail "empty array"
has_pair A "--ro-bind" "/usr"    && ok "--ro-bind /usr present"         || fail "--ro-bind /usr missing"
has_pair A "--proc" "/proc"      && ok "--proc /proc present"           || fail "--proc /proc missing"
has_pair A "--tmpfs" "/tmp"      && ok "--tmpfs /tmp present"           || fail "--tmpfs /tmp missing"
has_sequence A "--perms" "1777" "--tmpfs" "/dev/shm" && ok "default shm uses adjacent private tmpfs perms 1777" || fail "default shm tmpfs sequence missing"
has_pair A "--bind" "/dev/shm"   && fail "default shm binds host /dev/shm" || ok "default shm does not bind host /dev/shm"

SHM_BIND=()
bwrap_base SHM_BIND bind
has_sequence SHM_BIND "--bind" "/dev/shm" "/dev/shm" && ok "shm=bind has exact source and target path" || fail "shm=bind source/target mismatch"
has_ordered_pairs SHM_BIND "--dev" "/dev" "--bind" "/dev/shm" "--ro-bind" "/etc" && ok "shm=bind is ordered after --dev and before --ro-bind /etc" || fail "shm=bind ordering missing"
has_pair SHM_BIND "--tmpfs" "/dev/shm" && fail "shm=bind unexpectedly adds tmpfs" || ok "shm=bind does not add tmpfs"
has_pair SHM_BIND "--perms" "1777" && fail "shm=bind unexpectedly adds perms" || ok "shm=bind does not add perms"

SHM_TMPFS=()
bwrap_base SHM_TMPFS tmpfs
if arrays_equal SHM_TMPFS A; then
    ok "explicit shm=tmpfs matches default"
else
    fail "explicit shm=tmpfs differs from default"
fi

SHM_INVALID=()
SHM_INVALID_ERR="${TMPDIR_TEST}/shm-invalid.err"
bwrap_base SHM_INVALID invalid 2>"$SHM_INVALID_ERR"
SHM_INVALID_RC=$?
SHM_INVALID_MSG="bwrap_base: invalid shm mode 'invalid' (expected tmpfs or bind)"
if [[ $SHM_INVALID_RC -eq 2 ]] && grep -qxF "$SHM_INVALID_MSG" "$SHM_INVALID_ERR"; then
    ok "invalid shm mode is rejected by bwrap_base with its own message"
else
    fail "invalid bwrap_base shm mode (rc=$SHM_INVALID_RC, stderr=$(cat "$SHM_INVALID_ERR" 2>/dev/null))"
fi

# ── bwrap_home_tmpfs ────────────────────────────────────────

section "bwrap_home_tmpfs"

B=()
bwrap_home_tmpfs B
[[ ${#B[@]} -gt 0 ]]                  && ok "produces non-empty array"      || fail "empty array"
has_pair B "--tmpfs" "$HOME"           && ok "--tmpfs \$HOME present"        || fail "--tmpfs \$HOME missing"
has_pair B "--dir" "${HOME}/.config"   && ok "--dir ~/.config present"       || fail "--dir ~/.config missing"

# ── bwrap_env_base ──────────────────────────────────────────

section "bwrap_env_base"

C=()
bwrap_env_base C
has_pair C "--setenv" "HOME"            && ok "sets HOME"            || fail "HOME missing"
has_pair C "--setenv" "PATH"            && ok "sets PATH"            || fail "PATH missing"
has_pair C "--setenv" "XDG_RUNTIME_DIR" && ok "sets XDG_RUNTIME_DIR" || fail "XDG_RUNTIME_DIR missing"

# ── bwrap_sandbox ──────────────────────────────────────────

section "bwrap_sandbox"

D=()
bwrap_sandbox D
has_arg D "--unshare-all"     && ok "--unshare-all present"     || fail "--unshare-all missing"
has_arg D "--die-with-parent" && ok "--die-with-parent present" || fail "--die-with-parent missing"
has_arg D "--new-session"     && ok "--new-session present"     || fail "--new-session missing"

# ── bwrap_sandbox with network ──────────────────────────────

section "bwrap_sandbox (network=yes)"

E=()
bwrap_sandbox E yes
has_arg E "--share-net" && ok "--share-net present" || fail "--share-net missing"

# ── bwrap_sandbox without new-session ───────────────────────

section "bwrap_sandbox (network=no, new_session=no)"

F=()
bwrap_sandbox F no no
has_arg F "--new-session" && fail "--new-session should not be present" || ok "--new-session correctly absent"

# ── bwrap_no_hardened_malloc ────────────────────────────────

section "bwrap_no_hardened_malloc"

G=()
bwrap_no_hardened_malloc G
if [[ -f /usr/lib/libhardened_malloc.so.empty ]]; then
    has_triple G "--ro-bind" "/usr/lib/libhardened_malloc.so.empty" "/usr/lib/libhardened_malloc-light.so" \
        && ok "stub bind (light variant) present" || fail "stub bind (light variant) missing"
    has_triple G "--ro-bind" "/usr/lib/libhardened_malloc.so.empty" "/usr/lib/libhardened_malloc.so" \
        && ok "stub bind (default variant) present" || fail "stub bind (default variant) missing"
else
    ok "stub binds skipped (libhardened_malloc.so.empty not installed)"
fi

# ── bwrap_runtime_dir ───────────────────────────────────────

section "bwrap_runtime_dir"

H=()
bwrap_runtime_dir H
[[ ${#H[@]} -gt 0 ]]                    && ok "produces non-empty array"         || fail "empty array"
has_pair H "--dir" "${XDG_RUNTIME_DIR}"  && ok "--dir \$XDG_RUNTIME_DIR present"  || fail "--dir \$XDG_RUNTIME_DIR missing"

# ── bwrap_gpu / bwrap_lib64 ─────────────────────────────────

section "bwrap_gpu / bwrap_lib64"

I=()
bwrap_gpu I
ok "bwrap_gpu runs without error"

J=()
bwrap_lib64 J
[[ ${#J[@]} -gt 0 ]] && ok "bwrap_lib64 produces non-empty array" || fail "bwrap_lib64 empty"

# ── bwrap_bind_dir ──────────────────────────────────────────

section "bwrap_bind_dir"

BIND_TARGET="${TMPDIR_TEST}/testdir"
K=()
bwrap_bind_dir K "$BIND_TARGET"
[[ -d "$BIND_TARGET" ]]           && ok "creates target directory"   || fail "did not create directory"
has_pair K "--bind" "$BIND_TARGET" && ok "--bind target present"      || fail "--bind target missing"

# ── bwrap_bind_dir multiple dirs ────────────────────────────

section "bwrap_bind_dir (multiple)"

L=()
bwrap_bind_dir L "${TMPDIR_TEST}/a" "${TMPDIR_TEST}/b"
[[ -d "${TMPDIR_TEST}/a" && -d "${TMPDIR_TEST}/b" ]] && ok "creates both directories" || fail "did not create both"

count=$(count_flag L "--bind")
[[ $count -eq 2 ]] && ok "2 --bind flags present" || fail "expected 2 --bind, got $count"

# ── bwrap_ro_bind_dir ──────────────────────────────────────

section "bwrap_ro_bind_dir"

M=()
bwrap_ro_bind_dir M "$TMPDIR_TEST"
has_pair M "--ro-bind" "$TMPDIR_TEST" && ok "--ro-bind for existing dir" || fail "--ro-bind missing"

N=()
bwrap_ro_bind_dir N "/nonexistent/path/12345"
[[ ${#N[@]} -eq 0 ]] && ok "skips nonexistent path" || fail "should skip nonexistent path"

# ── require_dir ─────────────────────────────────────────────

section "require_dir"

require_dir /tmp 2>/dev/null                && ok "require_dir /tmp succeeds"           || fail "require_dir /tmp failed"
(require_dir /nonexistent/path 2>/dev/null)  && fail "require_dir should fail on missing" || ok "require_dir rejects missing path"

# ── bwrap_fcitx ─────────────────────────────────────────────

section "bwrap_fcitx"

O=()
bwrap_fcitx O
has_pair O "--setenv" "QT_IM_MODULE" && ok "sets QT_IM_MODULE" || fail "QT_IM_MODULE missing"
has_pair O "--setenv" "XMODIFIERS"   && ok "sets XMODIFIERS"   || fail "XMODIFIERS missing"

# ── bwrap_gui_setup ─────────────────────────────────────────

section "bwrap_gui_setup"

P=()
bwrap_gui_setup P no
[[ ${#P[@]} -gt 0 ]]         && ok "produces non-empty array"       || fail "empty array"
has_pair P "--ro-bind" "/usr" && ok "includes base --ro-bind /usr"   || fail "base --ro-bind /usr missing"
has_pair P "--tmpfs" "$HOME"  && ok "includes home tmpfs"            || fail "home tmpfs missing"
has_pair P "--tmpfs" "/dev/shm" && ok "default gui setup uses private shm" || fail "default gui setup shm missing"

SETUP_SHM_BIND=()
bwrap_gui_setup SETUP_SHM_BIND no no bind
has_sequence SETUP_SHM_BIND "--bind" "/dev/shm" "/dev/shm" && ok "gui setup forwards exact shm=bind sequence" || fail "gui setup did not forward shm=bind"
has_pair SETUP_SHM_BIND "--tmpfs" "/dev/shm" && fail "gui setup shm=bind added tmpfs" || ok "gui setup shm=bind omits tmpfs"

SETUP_SHM_INVALID=()
SETUP_SHM_INVALID_ERR="${TMPDIR_TEST}/setup-shm-invalid.err"
bwrap_gui_setup SETUP_SHM_INVALID no no invalid 2>"$SETUP_SHM_INVALID_ERR"
SETUP_SHM_INVALID_RC=$?
SETUP_SHM_INVALID_MSG="bwrap_gui_setup: invalid shm mode 'invalid' (expected tmpfs or bind)"
if [[ $SETUP_SHM_INVALID_RC -eq 2 ]] && grep -qxF "$SETUP_SHM_INVALID_MSG" "$SETUP_SHM_INVALID_ERR"; then
    ok "gui setup rejects invalid shm mode with its own message"
else
    fail "invalid bwrap_gui_setup shm mode (rc=$SETUP_SHM_INVALID_RC, stderr=$(cat "$SETUP_SHM_INVALID_ERR" 2>/dev/null))"
fi

Q=()
bwrap_gui_setup Q yes
ok "bwrap_gui_setup with x11=yes runs without error"

# ── bwrap_gui_setup (gpu toggle) ─────────────────────────────

section "bwrap_gui_setup (gpu toggle)"

EXPECT_GPU_YES=()
bwrap_base EXPECT_GPU_YES
bwrap_lib64 EXPECT_GPU_YES
bwrap_gpu EXPECT_GPU_YES
bwrap_runtime_dir EXPECT_GPU_YES
bwrap_home_tmpfs EXPECT_GPU_YES

EXPECT_GPU_NO=()
bwrap_base EXPECT_GPU_NO
bwrap_lib64 EXPECT_GPU_NO
bwrap_runtime_dir EXPECT_GPU_NO
bwrap_home_tmpfs EXPECT_GPU_NO

SETUP_GPU_YES=()
bwrap_gui_setup SETUP_GPU_YES no yes
SETUP_GPU_NO=()
bwrap_gui_setup SETUP_GPU_NO no no
SETUP_GPU_DEFAULT=()
bwrap_gui_setup SETUP_GPU_DEFAULT no

if arrays_equal SETUP_GPU_DEFAULT SETUP_GPU_NO; then
    ok "default gpu argument matches gpu=no"
else
    fail "default gpu argument differs from gpu=no"
fi

if arrays_equal SETUP_GPU_YES EXPECT_GPU_YES; then
    ok "gpu=yes emits base+lib64+gpu+runtime_dir+home_tmpfs"
else
    fail "gpu=yes output differs from expected composition"
fi

if arrays_equal SETUP_GPU_NO EXPECT_GPU_NO; then
    ok "gpu=no emits base+lib64+runtime_dir+home_tmpfs without GPU resources"
else
    fail "gpu=no leaks GPU resources"
fi

# ── bwrap_gui_setup (net/gpu independence) ───────────────────

section "bwrap_gui_setup (net/gpu independence)"

RESOLV_REF=()
bwrap_resolv RESOLV_REF

EXPECT_NET_YES=()
bwrap_base EXPECT_NET_YES
bwrap_lib64 EXPECT_NET_YES
bwrap_resolv EXPECT_NET_YES
bwrap_runtime_dir EXPECT_NET_YES
bwrap_home_tmpfs EXPECT_NET_YES

EXPECT_NET_NO=()
bwrap_base EXPECT_NET_NO
bwrap_lib64 EXPECT_NET_NO
bwrap_runtime_dir EXPECT_NET_NO
bwrap_home_tmpfs EXPECT_NET_NO

EXPECT_NET_GPU_YES=()
bwrap_base EXPECT_NET_GPU_YES
bwrap_lib64 EXPECT_NET_GPU_YES
bwrap_gpu EXPECT_NET_GPU_YES
bwrap_resolv EXPECT_NET_GPU_YES
bwrap_runtime_dir EXPECT_NET_GPU_YES
bwrap_home_tmpfs EXPECT_NET_GPU_YES

SETUP_NET_YES=()
bwrap_gui_setup SETUP_NET_YES yes no
SETUP_NET_NO=()
bwrap_gui_setup SETUP_NET_NO no no
SETUP_NET_GPU_YES=()
bwrap_gui_setup SETUP_NET_GPU_YES yes yes

if arrays_equal SETUP_NET_NO EXPECT_NET_NO; then
    ok "net=no emits base+lib64+runtime_dir+home_tmpfs without resolv"
else
    fail "net=no output differs from expected composition"
fi

if [[ ${#RESOLV_REF[@]} -ge 2 ]]; then
    if arrays_equal SETUP_NET_YES EXPECT_NET_YES; then
        ok "net=yes emits base+lib64+resolv+runtime_dir+home_tmpfs"
    else
        fail "net=yes output differs from expected composition"
    fi
    if arrays_equal SETUP_NET_GPU_YES EXPECT_NET_GPU_YES; then
        ok "net=yes gpu=yes emits base+lib64+gpu+resolv+runtime_dir+home_tmpfs"
    else
        fail "net=yes gpu=yes output differs from expected composition"
    fi
else
    ok "resolv assertion skipped (/etc/resolv.conf is not a symlink)"
    ok "net=yes gpu=yes resolv assertion skipped (/etc/resolv.conf is not a symlink)"
fi

# ── bwrap_gui_finish ────────────────────────────────────────

section "bwrap_gui_finish"

R=()
bwrap_gui_finish R wayland no default unfiltered
[[ ${#R[@]} -gt 0 ]]      && ok "produces non-empty array"   || fail "empty array"
has_arg R "--unshare-all"  && ok "--unshare-all present"      || fail "--unshare-all missing"

S=()
bwrap_gui_finish S wayland no no none
if [[ -f /usr/lib/libhardened_malloc.so.empty ]]; then
    has_triple S "--ro-bind" "/usr/lib/libhardened_malloc.so.empty" "/usr/lib/libhardened_malloc.so" \
        && ok "malloc=no masks hardened_malloc with stub" || fail "malloc=no stub bind missing"
else
    ok "malloc=no stub bind skipped (libhardened_malloc.so.empty not installed)"
fi

# ── bwrap_gui_finish (seccomp) ──────────────────────────────

section "bwrap_gui_finish (seccomp)"

SN=()
bwrap_gui_finish SN wayland no default unfiltered no default
SN_RC=$?
[[ $SN_RC -eq 0 ]] && ok "seccomp=default returns 0" || fail "seccomp=default returned $SN_RC"
has_arg SN "--seccomp" && ok "seccomp=default appends --seccomp" || fail "seccomp=default missing --seccomp"

SO=()
bwrap_gui_finish SO wayland no default unfiltered no none
SO_RC=$?
[[ $SO_RC -eq 0 ]] && ok "seccomp=none returns 0" || fail "seccomp=none returned $SO_RC"
has_arg SO "--seccomp" && fail "seccomp=none appended --seccomp" || ok "seccomp=none appends nothing"

SP=()
bwrap_gui_finish SP wayland no default unfiltered no "openat" 2>/dev/null
SP_RC=$?
[[ $SP_RC -eq 1 ]] && ok "allowlist via gui_finish is rejected" || fail "allowlist via gui_finish returned $SP_RC"
has_arg SP "--seccomp" && fail "rejected allowlist appended --seccomp" || ok "rejected allowlist appends nothing"

SNM=()
BWRAP_SECCOMP_DIR="${TMPDIR_TEST}/missing" bwrap_gui_finish SNM wayland no default unfiltered no default 2>/dev/null
SNM_RC=$?
[[ $SNM_RC -eq 1 ]] && ok "seccomp=default fails when the blob is missing" || fail "missing seccomp blob returned $SNM_RC"
has_arg SNM "--seccomp" && fail "failed seccomp setup appended --seccomp" || ok "failed seccomp setup appends nothing"

SOM=()
BWRAP_SECCOMP_DIR="${TMPDIR_TEST}/missing" bwrap_gui_finish SOM wayland no default unfiltered no none 2>/dev/null
SOM_RC=$?
[[ $SOM_RC -eq 0 ]] && ok "seccomp=none ignores a missing blob" || fail "seccomp=none returned $SOM_RC"
has_arg SOM "--seccomp" && fail "seccomp=none appended --seccomp" || ok "seccomp=none appends nothing when the blob is missing"

# ── bwrap_seccomp ───────────────────────────────────────────

section "bwrap_seccomp"

SA=()
bwrap_seccomp SA none
SA_RC=$?
[[ $SA_RC -eq 0 ]] && ok "none returns 0" || fail "none returned $SA_RC"
[[ ${#SA[@]} -eq 0 ]] && ok "none appends nothing" || fail "none appended ${SA[*]}"

SB=()
bwrap_seccomp SB default
SB_RC=$?
[[ $SB_RC -eq 0 ]] && ok "default returns 0 with a valid fixture" || fail "default returned $SB_RC"
if [[ ${#SB[@]} -eq 2 && "${SB[0]}" == "--seccomp" && "${SB[1]}" =~ ^[0-9]+$ ]]; then
    ok "default appends --seccomp <fd>"
else
    fail "default output was: ${SB[*]}"
fi
SECCOMP_FD="${SB[1]:-}"
_bwrap_seccomp_close_fds
if [[ -n "$SECCOMP_FD" ]] && { : <&"$SECCOMP_FD"; } 2>/dev/null; then
    fail "seccomp filter fd was left open"
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
[[ $SC_RC -eq 1 ]] && ok "missing default fails closed" || fail "missing default returned $SC_RC"
[[ ${#SC[@]} -eq 0 ]] && ok "missing default appends nothing" || fail "missing default appended ${SC[*]}"

BAD_SIZE_DIR="${TMPDIR_TEST}/bad-size"
mkdir -p "$BAD_SIZE_DIR"
head -c 12 /dev/zero > "${BAD_SIZE_DIR}/default.${SECCOMP_ARCH}.bpf"
SE=()
BWRAP_SECCOMP_DIR="$BAD_SIZE_DIR" bwrap_seccomp SE default 2>/dev/null
SE_RC=$?
[[ $SE_RC -eq 1 && ${#SE[@]} -eq 0 ]] && ok "invalid size fails closed" || fail "invalid size returned $SE_RC"

if [[ "$SECCOMP_MAGIC" != "00000000" ]]; then
    BAD_ARCH_DIR="${TMPDIR_TEST}/bad-arch"
    mkdir -p "$BAD_ARCH_DIR"
    write_fake_blob "${BAD_ARCH_DIR}/default.${SECCOMP_ARCH}.bpf" "deadbeef"
    SG=()
    BWRAP_SECCOMP_DIR="$BAD_ARCH_DIR" bwrap_seccomp SG default 2>/dev/null
    SG_RC=$?
    [[ $SG_RC -eq 1 && ${#SG[@]} -eq 0 ]] && ok "arch mismatch fails closed" || fail "arch mismatch returned $SG_RC"
else
    ok "arch mismatch test skipped (unknown host arch)"
fi

FAKE_GEN="${TMPDIR_TEST}/fake-seccomp-gen"
GEN_COUNTER="${TMPDIR_TEST}/gen-count"
cat > "$FAKE_GEN" <<'GEN'
#!/usr/bin/env bash
printf 'x' >> "${FAKE_GEN_COUNTER:?}"
_out=""
while (($#)); do
    case "$1" in
        -o) _out=$2; shift 2 ;;
        --allowlist) shift 2 ;;
        *) shift ;;
    esac
done
cp "${FAKE_GEN_BLOB:?}" "$_out"
GEN
chmod +x "$FAKE_GEN"

export FAKE_GEN_COUNTER="$GEN_COUNTER"
export FAKE_GEN_BLOB="$SECCOMP_FIXTURE_BLOB"
export BWRAP_SECCOMP_GEN="$FAKE_GEN"
rm -rf "$BWRAP_SECCOMP_CACHE_DIR" "$GEN_COUNTER"

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

unset BWRAP_SECCOMP_GEN FAKE_GEN_COUNTER FAKE_GEN_BLOB

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

S390_DIR="${TMPDIR_TEST}/seccomp-s390x"
mkdir -p "$S390_DIR"
write_fake_blob "${S390_DIR}/default.s390x.bpf" "80000016"
S390=()
BWRAP_SECCOMP_ARCH=s390x BWRAP_SECCOMP_DIR="$S390_DIR" bwrap_seccomp S390 default
S390_RC=$?
if [[ $S390_RC -eq 0 && ${#S390[@]} -eq 2 && "${S390[0]}" == "--seccomp" ]]; then
    ok "s390x big-endian fixture is accepted"
else
    fail "s390x fixture returned $S390_RC (${S390[*]})"
fi
_bwrap_seccomp_close_fds

write_fake_blob "${S390_DIR}/default.s390x.bpf" "16000080"
S390BAD=()
BWRAP_SECCOMP_ARCH=s390x BWRAP_SECCOMP_DIR="$S390_DIR" bwrap_seccomp S390BAD default 2>/dev/null
S390BAD_RC=$?
[[ $S390BAD_RC -eq 1 && ${#S390BAD[@]} -eq 0 ]] \
    && ok "s390x little-endian fixture is rejected" \
    || fail "s390x wrong-endian fixture returned $S390BAD_RC"

UNKNOWN_DIR="${TMPDIR_TEST}/seccomp-unknown"
mkdir -p "$UNKNOWN_DIR"
write_fake_blob "${UNKNOWN_DIR}/default.weird.bpf" "3e0000c0"
SU=()
BWRAP_SECCOMP_ARCH=weird BWRAP_SECCOMP_DIR="$UNKNOWN_DIR" bwrap_seccomp SU default 2>/dev/null
SU_RC=$?
[[ $SU_RC -eq 1 && ${#SU[@]} -eq 0 ]] \
    && ok "unknown architecture fails closed" \
    || fail "unknown architecture returned $SU_RC"

# ── bwrap_ssh_agent ─────────────────────────────────────────

section "bwrap_ssh_agent"

unset SSH_AUTH_SOCK 2>/dev/null || true
T=()
bwrap_ssh_agent T
[[ ${#T[@]} -eq 0 ]] && ok "empty without SSH_AUTH_SOCK" || fail "should be empty without socket"

# ── bwrap_dbus_system ───────────────────────────────────────

section "bwrap_dbus_system"

U=()
bwrap_dbus_system U
ok "bwrap_dbus_system runs without error"

# ── bwrap_dbus_filtered ─────────────────────────────────────

section "bwrap_dbus_filtered"

EMPTY_PATH="${TMPDIR_TEST}/empty-path"
mkdir -p "$EMPTY_PATH"
NO_PROXY_ADDR="unix:path=/nonexistent"

DF=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_dbus_filtered DF 2>/dev/null
DF_RC=$?
[[ $DF_RC -eq 1 ]] && ok "missing xdg-dbus-proxy fails closed" || fail "missing proxy returned $DF_RC"
[[ ${#DF[@]} -eq 0 ]] && ok "missing proxy appends nothing" || fail "missing proxy appended ${DF[*]}"

DC=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_dbus_common DC 2>/dev/null
DC_RC=$?
[[ $DC_RC -eq 1 && ${#DC[@]} -eq 0 ]] && ok "bwrap_dbus_common propagates the missing proxy error" || fail "bwrap_dbus_common returned $DC_RC"

DGF=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGF wayland no default filtered no none 2>/dev/null
DGF_RC=$?
[[ $DGF_RC -eq 1 ]] && ok "dbus=filtered fails when the proxy is missing" || fail "dbus=filtered returned $DGF_RC"
has_arg DGF "${XDG_RUNTIME_DIR}/bus" && fail "failed dbus=filtered bound the bus socket" || ok "failed dbus=filtered appends no bus bind"
has_arg DGF "DBUS_SESSION_BUS_ADDRESS" && fail "failed dbus=filtered set the bus address" || ok "failed dbus=filtered appends no bus env"

DGD=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGD wayland no default 2>/dev/null
DGD_RC=$?
[[ $DGD_RC -eq 1 ]] && ok "dbus defaults to filtered when the mode is omitted" || fail "default dbus mode returned $DGD_RC"
has_arg DGD "${XDG_RUNTIME_DIR}/bus" && fail "default dbus mode bound the bus socket" || ok "default dbus mode appends no bus bind"
has_arg DGD "DBUS_SESSION_BUS_ADDRESS" && fail "default dbus mode set the bus address" || ok "default dbus mode appends no bus env"

DGN=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGN wayland no default none no none 2>/dev/null
DGN_RC=$?
[[ $DGN_RC -eq 0 ]] && ok "dbus=none ignores a missing proxy" || fail "dbus=none returned $DGN_RC"
has_arg DGN "${XDG_RUNTIME_DIR}/bus" && fail "dbus=none bound the bus socket" || ok "dbus=none appends no bus bind"

DGU=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGU wayland no default unfiltered no none 2>/dev/null
DGU_RC=$?
[[ $DGU_RC -eq 0 ]] && ok "dbus=unfiltered does not require the proxy" || fail "dbus=unfiltered returned $DGU_RC"

# ── bwrap_exec ──────────────────────────────────────────────

section "bwrap_exec"

FAKEBIN="${TMPDIR_TEST}/fakebin"
mkdir -p "$FAKEBIN"

cat > "${FAKEBIN}/bwrap" << 'EOF'
#!/usr/bin/env bash
if [[ -n "${FAKE_BWRAP_ARGS_FILE:-}" ]]; then
    printf '%s\0' "$@" > "$FAKE_BWRAP_ARGS_FILE"
fi
if [[ -n "${FAKE_BWRAP_STDIN_FILE:-}" ]]; then
    cat > "$FAKE_BWRAP_STDIN_FILE"
fi
exit "${FAKE_BWRAP_EXIT:-0}"
EOF
chmod +x "${FAKEBIN}/bwrap"

read_args() {
    local _file="$1"
    local -n _arr="$2"
    _arr=()
    mapfile -d '' -t _arr < "$_file"
}

run_bwrap_exec() {
    (
        export PATH="${FAKEBIN}:${PATH}"
        _BWRAP_DBUS_PROXY_PIDS=()
        _BWRAP_DBUS_PROXY_SOCKETS=()
        bwrap_exec "$@"
    )
}

run_bwrap_exec_proxy() {
    (
        # Most proxy tests only inspect args/stdin/status. Clear the harness
        # EXIT trap here; Test 7 calls bwrap_exec directly to verify that a
        # caller trap and proxy cleanup coexist.
        trap - EXIT
        export PATH="${FAKEBIN}:${PATH}"
        _BWRAP_DBUS_PROXY_PIDS=(999999)
        _BWRAP_DBUS_PROXY_SOCKETS=()
        _bwrap_dbus_cleanup() { printf 'cleanup\n' >> "${FAKE_CLEANUP_FILE:-/dev/null}"; }
        bwrap_exec "$@"
    )
}

# Test 1: Exec branch (no proxy pids) - exit status 0 propagates; forwarded args captured exactly
ARGS_FILE1="${TMPDIR_TEST}/args1"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE1"
export FAKE_BWRAP_EXIT=0
EXPECTED1=( --ro-bind /usr "arg with space" "" )
run_bwrap_exec --ro-bind /usr "arg with space" "" < /dev/null
RC1=$?
GOT1=()
read_args "$ARGS_FILE1" GOT1
if [[ $RC1 -eq 0 ]] && arrays_equal GOT1 EXPECTED1; then
    ok "exec branch propagates exit 0 and forwards args exactly (spaces/empty preserved)"
else
    fail "exec branch propagates exit 0 and forwards args exactly (spaces/empty preserved)"
fi

# Test 2: Exec branch does not run _bwrap_dbus_cleanup
CLEANUP_MARKER2="${TMPDIR_TEST}/cleanup2"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="${TMPDIR_TEST}/args2"
export FAKE_BWRAP_EXIT=0
(
    export PATH="${FAKEBIN}:${PATH}"
    _BWRAP_DBUS_PROXY_PIDS=()
    _BWRAP_DBUS_PROXY_SOCKETS=()
    _bwrap_dbus_cleanup() { : > "$CLEANUP_MARKER2"; }
    bwrap_exec --test < /dev/null
)
if [[ ! -f "$CLEANUP_MARKER2" ]]; then
    ok "exec branch does not run _bwrap_dbus_cleanup"
else
    fail "exec branch does not run _bwrap_dbus_cleanup"
fi

# Test 3: Exec branch inherits stdin from fd 0
STDIN_FILE3="${TMPDIR_TEST}/stdin3"
PAYLOAD3=$'hello\nworld'
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="${TMPDIR_TEST}/args3"
export FAKE_BWRAP_STDIN_FILE="$STDIN_FILE3"
export FAKE_BWRAP_EXIT=0
printf '%s' "$PAYLOAD3" > "${TMPDIR_TEST}/payload3"
run_bwrap_exec --test < "${TMPDIR_TEST}/payload3"
if [[ -f "$STDIN_FILE3" ]] && [[ "$(cat "$STDIN_FILE3")" == "$PAYLOAD3" ]]; then
    ok "exec branch inherits stdin from fd 0"
else
    fail "exec branch inherits stdin from fd 0"
fi

# Test 4: Proxy branch stdin regression (THE d308327 test)
STDIN_FILE4="${TMPDIR_TEST}/stdin4"
PAYLOAD4=$'pipe-data-12345'
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="${TMPDIR_TEST}/args4"
export FAKE_BWRAP_STDIN_FILE="$STDIN_FILE4"
export FAKE_BWRAP_EXIT=0
export FAKE_CLEANUP_FILE="${TMPDIR_TEST}/cleanup4"
printf '%s' "$PAYLOAD4" | run_bwrap_exec_proxy --read-stdin
if [[ -f "$STDIN_FILE4" ]] && [[ "$(cat "$STDIN_FILE4")" == "$PAYLOAD4" ]]; then
    ok "proxy branch inherits stdin from pipe (regression test for d308327)"
else
    fail "proxy branch inherits stdin from pipe (regression test for d308327)"
fi

# Test 5: Proxy branch forwards args exactly and exits 0
ARGS_FILE5="${TMPDIR_TEST}/args5"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE5"
export FAKE_BWRAP_EXIT=0
export FAKE_CLEANUP_FILE="${TMPDIR_TEST}/cleanup5"
EXPECTED5=( --ro-bind /usr "arg with space" "" )
run_bwrap_exec_proxy --ro-bind /usr "arg with space" "" < /dev/null
RC5=$?
GOT5=()
read_args "$ARGS_FILE5" GOT5
if [[ $RC5 -eq 0 ]] && arrays_equal GOT5 EXPECTED5; then
    ok "proxy branch forwards args exactly and exits 0"
else
    fail "proxy branch forwards args exactly and exits 0"
fi

# Test 6: Proxy branch propagates non-zero exit status and runs cleanup exactly once
ARGS_FILE6="${TMPDIR_TEST}/args6"
CLEANUP_FILE6="${TMPDIR_TEST}/cleanup6"
: > "$CLEANUP_FILE6"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE6"
export FAKE_BWRAP_EXIT=7
export FAKE_CLEANUP_FILE="$CLEANUP_FILE6"
run_bwrap_exec_proxy --test < /dev/null
RC6=$?
CLEANUP_COUNT6=$(grep -c 'cleanup' "$CLEANUP_FILE6" 2>/dev/null || echo 0)
if [[ $RC6 -eq 7 ]] && [[ "$CLEANUP_COUNT6" -eq 1 ]]; then
    ok "proxy branch propagates non-zero exit status and runs cleanup exactly once"
else
    fail "proxy branch propagates non-zero exit status and runs cleanup exactly once"
fi

# Test 7: Proxy branch: cleanup runs first, then the caller's EXIT trap,
# with the original bwrap exit status preserved.
ARGS_FILE7="${TMPDIR_TEST}/args7"
ORDER_FILE7="${TMPDIR_TEST}/order7"
: > "$ORDER_FILE7"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE7"
export FAKE_BWRAP_EXIT=7
(
    trap 'printf "caller:%s\n" "$?" >> "$ORDER_FILE7"' EXIT
    export PATH="${FAKEBIN}:${PATH}"
    _BWRAP_DBUS_PROXY_PIDS=(999999)
    _BWRAP_DBUS_PROXY_SOCKETS=()
    _bwrap_dbus_cleanup() { printf 'cleanup\n' >> "$ORDER_FILE7"; }
    bwrap_exec --test < /dev/null
)
RC7=$?
GOT_ORDER7=$(cat "$ORDER_FILE7" 2>/dev/null)
EXPECTED_ORDER7=$'cleanup\ncaller:7'
if [[ $RC7 -eq 7 && "$GOT_ORDER7" == "$EXPECTED_ORDER7" ]]; then
    ok "proxy branch runs cleanup then caller EXIT trap, preserving status"
else
    fail "proxy branch EXIT order/status (rc=$RC7, got='$GOT_ORDER7', want='$EXPECTED_ORDER7')"
fi

# ── Summary ─────────────────────────────────────────────────

summary
