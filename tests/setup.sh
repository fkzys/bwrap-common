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
SECCOMP_FIXTURE_CONF="${SECCOMP_FIXTURE_DIR}/default.conf"
printf '# bwrap-common test fixture\n' > "$SECCOMP_FIXTURE_CONF"
SECCOMP_FIXTURE_BLOB="${TMPDIR_TEST}/default.bpf"
write_fake_blob "$SECCOMP_FIXTURE_BLOB" "$SECCOMP_MAGIC"

FAKE_GEN="${TMPDIR_TEST}/fake-seccomp-gen"
GEN_COUNTER="${TMPDIR_TEST}/gen-count"
cat > "$FAKE_GEN" <<'GEN'
#!/usr/bin/env bash
set -u
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "${FAKE_GEN_VERSION:-4}"
    exit 0
fi
printf 'x' >> "${FAKE_GEN_COUNTER:?}"
_out=""
_extra=""
while (($#)); do
    case "$1" in
        -o) _out=$2; shift 2 ;;
        --extra) _extra=$2; shift 2 ;;
        --allowlist|--blocklist|--arch) shift 2 ;;
        --strict) shift ;;
        *) shift ;;
    esac
done
if [[ -n "$_extra" ]]; then
    if [[ -n "${FAKE_GEN_EXTRA_COPY:-}" ]]; then
        if [[ "$_extra" == "-" ]]; then
            cat > "$FAKE_GEN_EXTRA_COPY"
        else
            cp "$_extra" "$FAKE_GEN_EXTRA_COPY"
        fi
    elif [[ "$_extra" == "-" ]]; then
        cat >/dev/null
    fi
fi
[[ -n "$_out" ]] || exit 1
cp "${FAKE_GEN_BLOB:?}" "$_out"
GEN
chmod +x "$FAKE_GEN"

export XDG_RUNTIME_DIR="${TMPDIR_TEST}/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export BWRAP_SECCOMP_DIR="$SECCOMP_FIXTURE_DIR"
export BWRAP_SECCOMP_CACHE_DIR="${TMPDIR_TEST}/seccomp-cache"
export BWRAP_SECCOMP_GEN="$FAKE_GEN"
export FAKE_GEN_COUNTER="$GEN_COUNTER"
export FAKE_GEN_BLOB="$SECCOMP_FIXTURE_BLOB"
unset BWRAP_SECCOMP_CONF 2>/dev/null || true

