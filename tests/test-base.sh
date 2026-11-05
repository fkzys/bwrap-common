# ── Guard re-source ─────────────────────────────────────────

section "Source guard"

. ./bwrap-common.sh
ok "re-source does not error"

(
    unset _BWRAP_COMMON_LOADED _BWRAP_SECCOMP_WARNED_CACHES
    _source_in_function() { . ./bwrap-common.sh; }
    _source_in_function
    declare -p _BWRAP_SECCOMP_WARNED_CACHES >/dev/null 2>&1
) && ok "global warning cache survives source from a function" ||
    fail "warning cache was local to the sourcing function"

_tests_root="$PWD"
(
    cd / || exit 1
    bash -c '. "$1/bwrap-common.sh" &&
        declare -f bwrap_seccomp >/dev/null 2>&1 &&
        declare -f bwrap_dbus_common >/dev/null 2>&1' _ "$_tests_root"
) && ok "entry point loads its modules from a foreign working directory" ||
    fail "entry point failed to load its modules from a foreign working directory"

(
    _symlink_dir="${TMPDIR_TEST}/symlink-entry"
    mkdir -p "$_symlink_dir"
    ln -sf "${_tests_root}/bwrap-common.sh" "${_symlink_dir}/bwrap-common.sh"
    cd / || exit 1
    bash -c '. "$1/bwrap-common.sh" &&
        declare -f bwrap_seccomp >/dev/null 2>&1 &&
        declare -f bwrap_dbus_common >/dev/null 2>&1' _ "$_symlink_dir"
) && ok "symlinked entry point resolves its sibling modules" ||
    fail "symlinked entry point failed to find its modules"

# ── Function definitions ───────────────────────────────────

section "Function definitions"

FUNCTIONS=(
    bwrap_base bwrap_gpu bwrap_lib64 bwrap_resolv
    bwrap_wayland bwrap_x11 bwrap_audio
    bwrap_dbus_session bwrap_dbus_system bwrap_dbus_system_filtered bwrap_dbus_filtered bwrap_dbus_common
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
[[ "${A[0]}" == "--clearenv" ]] && ok "--clearenv is the first argument" || fail "--clearenv is not first"
has_pair A "--ro-bind" "/usr"    && ok "--ro-bind /usr present"         || fail "--ro-bind /usr missing"
has_pair A "--proc" "/proc"      && ok "--proc /proc present"           || fail "--proc /proc missing"
has_pair A "--tmpfs" "/tmp"      && ok "--tmpfs /tmp present"           || fail "--tmpfs /tmp missing"
has_sequence A "--perms" "1777" "--tmpfs" "/dev/shm" && ok "default shm uses adjacent private tmpfs perms 1777" || fail "default shm tmpfs sequence missing"
has_pair A "--bind" "/dev/shm"   && fail "default shm binds host /dev/shm" || ok "default shm does not bind host /dev/shm"

PRESET=()
PRESET+=(--setenv KEEP value)
bwrap_base PRESET
has_sequence PRESET "--clearenv" "--setenv" "KEEP" && ok "existing --setenv is kept after --clearenv" || fail "existing --setenv was cleared"

NO_CLEAR=()
bwrap_base NO_CLEAR tmpfs no
has_arg NO_CLEAR "--clearenv" && fail "clearenv=no still adds --clearenv" || ok "clearenv=no omits --clearenv"
has_pair NO_CLEAR "--ro-bind" "/usr" && ok "clearenv=no keeps base mounts" || fail "clearenv=no lost base mounts"

REPEATED=()
bwrap_base REPEATED
bwrap_base REPEATED
[[ $(count_flag REPEATED "--clearenv") -eq 1 ]] && ok "repeated bwrap_base keeps one --clearenv" || fail "repeated bwrap_base duplicated --clearenv"

CLEAR_INVALID=()
CLEAR_INVALID_ERR="${TMPDIR_TEST}/clearenv-invalid.err"
bwrap_base CLEAR_INVALID tmpfs invalid 2>"$CLEAR_INVALID_ERR"
CLEAR_INVALID_RC=$?
CLEAR_INVALID_MSG="bwrap_base: invalid clearenv mode 'invalid' (expected yes or no)"
if [[ $CLEAR_INVALID_RC -eq 2 ]] && grep -qxF "$CLEAR_INVALID_MSG" "$CLEAR_INVALID_ERR"; then
    ok "invalid clearenv mode is rejected by bwrap_base with its own message"
else
    fail "invalid bwrap_base clearenv mode (rc=$CLEAR_INVALID_RC, stderr=$(cat "$CLEAR_INVALID_ERR" 2>/dev/null))"
fi

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
has_sequence C "--setenv" "TERM" "${TERM:-xterm-256color}" && ok "sets TERM" || fail "TERM missing"
has_pair C "--setenv" "XDG_RUNTIME_DIR" && ok "sets XDG_RUNTIME_DIR" || fail "XDG_RUNTIME_DIR missing"
has_sequence C "--setenv" "XDG_CACHE_HOME" "${HOME}/.cache" && ok "normalizes XDG_CACHE_HOME to private HOME/.cache" || fail "XDG_CACHE_HOME not normalized"

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
    skip "stub binds (libhardened_malloc.so.empty not installed)"
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
_bwrap_fcitx_close_fds

mapfile -t FCTX_PATHS < <(_bwrap_fcitx_paths)
has_arg FCTX_PATHS "/tmp/fcitx5-${EUID}" \
    && ok "targets /tmp/fcitx5-<euid>" || fail "missing /tmp/fcitx5-<euid> candidate"
has_arg FCTX_PATHS "${XDG_RUNTIME_DIR}/fcitx5" \
    && ok "targets \$XDG_RUNTIME_DIR/fcitx5" || fail "missing \$XDG_RUNTIME_DIR/fcitx5 candidate"

FCTX_RT="${TMPDIR_TEST}/fcitx-rt"
mkdir -p "${FCTX_RT}/fcitx5"
FC=()
XDG_RUNTIME_DIR="$FCTX_RT" bwrap_fcitx FC && FCTX_RC=0 || FCTX_RC=$?
if [[ $FCTX_RC -eq 0 ]] && has_arg FC "${FCTX_RT}/fcitx5" && has_arg FC --bind-fd; then
    ok "binds a caller-owned fcitx directory via --bind-fd"
else
    fail "did not bind the fcitx directory (rc=$FCTX_RC)"
fi
_bwrap_fcitx_close_fds
rmdir "${FCTX_RT}/fcitx5"

: > "${FCTX_RT}/fcitx5"
FC=()
XDG_RUNTIME_DIR="$FCTX_RT" bwrap_fcitx FC 2>/dev/null && FCTX_RC=0 || FCTX_RC=$?
if [[ $FCTX_RC -eq 0 ]] && ! has_arg FC "${FCTX_RT}/fcitx5"; then
    ok "ignores a plain file at the fcitx path"
else
    fail "mishandled a plain file (rc=$FCTX_RC)"
fi
_bwrap_fcitx_close_fds
rm -f "${FCTX_RT}/fcitx5"

ln -sfn /etc "${FCTX_RT}/fcitx5"
FC=()
XDG_RUNTIME_DIR="$FCTX_RT" bwrap_fcitx FC 2>/dev/null && FCTX_RC=0 || FCTX_RC=$?
[[ $FCTX_RC -ne 0 ]] && ok "hard-fails on a symlinked fcitx path" || fail "accepted a symlinked fcitx path"
_bwrap_fcitx_close_fds
rm -f "${FCTX_RT}/fcitx5"

mkdir -p "${FCTX_RT}/fcitx5"
if chown 65534:65534 "${FCTX_RT}/fcitx5" 2>/dev/null; then
    FC=()
    XDG_RUNTIME_DIR="$FCTX_RT" bwrap_fcitx FC 2>/dev/null && FCTX_RC=0 || FCTX_RC=$?
    [[ $FCTX_RC -ne 0 ]] && ok "hard-fails on a foreign-owned fcitx path" || fail "accepted a foreign-owned fcitx path"
else
    skip "fcitx foreign-owner case (requires root)"
fi
_bwrap_fcitx_close_fds
rm -rf "${FCTX_RT}"


# ── bwrap_ssh_agent ─────────────────────────────────────────

section "bwrap_ssh_agent"

unset SSH_AUTH_SOCK 2>/dev/null || true
T=()
bwrap_ssh_agent T
[[ ${#T[@]} -eq 0 ]] && ok "empty without SSH_AUTH_SOCK" || fail "should be empty without socket"

# ── unavailable-resource warnings ───────────────────────────

section "unavailable-resource warnings"

WARN_ERR="${TMPDIR_TEST}/warn.err"
WARN_HOME="${TMPDIR_TEST}/warn-home"
WARN_RT="${TMPDIR_TEST}/warn-rt"
mkdir -p "$WARN_HOME" "$WARN_RT"

RB=()
bwrap_ro_bind_dir RB "${TMPDIR_TEST}/missing-ro-dir" 2>"$WARN_ERR"
grep -qxF "bwrap_ro_bind_dir: skipping missing directory: ${TMPDIR_TEST}/missing-ro-dir" "$WARN_ERR" \
    && ok "ro_bind_dir warns on a missing directory" || fail "ro_bind_dir warning absent"

( SSH=(); unset SSH_AUTH_SOCK; bwrap_ssh_agent SSH ) 2>"$WARN_ERR"
grep -qxF "bwrap_ssh_agent: SSH_AUTH_SOCK is unset or not a socket; skipping" "$WARN_ERR" \
    && ok "ssh_agent warns without a socket" || fail "ssh_agent warning absent"

TH=()
HOME="$WARN_HOME" bwrap_themes TH 2>"$WARN_ERR"
grep -qxF "bwrap_themes: no theme/config paths found" "$WARN_ERR" \
    && ok "themes warns when nothing is found" || fail "themes warning absent"

AU=()
XDG_RUNTIME_DIR="$WARN_RT" bwrap_audio AU 2>"$WARN_ERR"
grep -qxF "bwrap_audio: no PipeWire or PulseAudio socket found" "$WARN_ERR" \
    && ok "audio warns without sockets" || fail "audio warning absent"

WY=()
XDG_RUNTIME_DIR="$WARN_RT" WAYLAND_DISPLAY="wayland-1" bwrap_wayland WY 2>"$WARN_ERR"
grep -q "bwrap_wayland: no Wayland socket" "$WARN_ERR" \
    && ok "wayland warns without a socket" || fail "wayland warning absent"

XW=()
( unset DISPLAY; bwrap_x11 XW ) 2>"$WARN_ERR"
grep -qxF "bwrap_x11: DISPLAY is not set; skipping" "$WARN_ERR" \
    && ok "x11 warns when DISPLAY is unset" || fail "x11 warning absent"

if [[ ! -d /tmp/.X11-unix ]]; then
    XS=()
    DISPLAY=":0" bwrap_x11 XS 2>"$WARN_ERR"
    grep -qxF "bwrap_x11: /tmp/.X11-unix not found; X11 socket not bound" "$WARN_ERR" \
        && ok "x11 warns when the X11 socket is missing" || fail "x11 socket warning absent"
fi

if [[ ! -d /dev/dri ]] && ! compgen -G '/dev/nvidia*' >/dev/null; then
    GW=()
    bwrap_gpu GW 2>"$WARN_ERR"
    grep -q "bwrap_gpu: no GPU device nodes found" "$WARN_ERR" \
        && ok "gpu warns when no device nodes exist" || fail "gpu warning absent"
fi

if [[ -L /etc/resolv.conf ]]; then
    RESOLV_REAL="$(realpath /etc/resolv.conf 2>/dev/null)"
    RESOLV_DIR="$(dirname "$RESOLV_REAL")"
    RV=()
    bwrap_resolv RV 2>"$WARN_ERR"
    if [[ -n "$RESOLV_REAL" && "$RESOLV_DIR" != "/" && -d "$RESOLV_DIR" ]]; then
        [[ ! -s "$WARN_ERR" ]] && ok "resolv is silent when it binds a real resolver directory" || fail "resolv warned despite a usable directory"
    else
        [[ -s "$WARN_ERR" ]] && ok "resolv warns when the resolver directory is unusable" || fail "resolv did not warn about an unusable directory"
    fi
else
    RV=()
    bwrap_resolv RV 2>"$WARN_ERR"
    [[ ! -s "$WARN_ERR" ]] && ok "resolv is silent when /etc/resolv.conf is not a symlink" || fail "resolv warned on a plain resolv.conf"
fi

RFB=(); RFA=()
bwrap_resolve_files RFB RFA --ro-bind "${TMPDIR_TEST}/missing-app" 2>"$WARN_ERR"
grep -qxF "bwrap_resolve_files: not found, left as-is: ${TMPDIR_TEST}/missing-app" "$WARN_ERR" \
    && ok "resolve_files warns on a missing path (explicit mode)" || fail "resolve_files explicit-mode warning absent"

RFB2=(); RFA2=()
bwrap_resolve_files RFB2 RFA2 "${TMPDIR_TEST}/missing-app" 2>"$WARN_ERR"
grep -qxF "bwrap_resolve_files: not found, left as-is: ${TMPDIR_TEST}/missing-app" "$WARN_ERR" \
    && ok "resolve_files warns on a missing path (default mode)" || fail "resolve_files default-mode warning absent"

RFB3=(); RFA3=()
bwrap_resolve_files RFB3 RFA3 "user/repo" "https://example/x" 2>"$WARN_ERR"
if [[ ! -s "$WARN_ERR" && ${#RFA3[@]} -eq 2 ]]; then
    ok "resolve_files stays silent for non-path slash arguments"
else
    fail "resolve_files warned on non-path arguments"
fi

# A path whose parent is the filesystem root must never resolve to "/".
RFR=(); RFRA=()
bwrap_resolve_files RFR RFRA --bind / 2>/dev/null
has_triple RFR --bind / / \
    && fail "resolve_files bound the root for /" || ok "resolve_files refuses / (bind mode)"

RFRD=(); RFRDA=()
bwrap_resolve_files RFRD RFRDA / 2>/dev/null
has_triple RFRD --ro-bind / / \
    && fail "resolve_files bound the root for / (default mode)" || ok "resolve_files refuses / (default mode)"

ln -sfn / "${TMPDIR_TEST}/rootlink"
RFR2=(); RFRA2=()
bwrap_resolve_files RFR2 RFRA2 --bind "${TMPDIR_TEST}/rootlink" 2>/dev/null
has_triple RFR2 --bind / / \
    && fail "resolve_files bound the root for a symlink to /" || ok "resolve_files refuses a symlink to /"

for ROOTPATH in /home /mnt /opt /var /srv; do
    [[ -e "$ROOTPATH" ]] || continue
    for LAYOUT in leaf parent; do
        RFR3=(); RFRA3=()
        bwrap_resolve_files RFR3 RFRA3 "--layout=$LAYOUT" --bind "$ROOTPATH" 2>/dev/null
        has_triple RFR3 --bind / / \
            && fail "resolve_files ($LAYOUT) bound the root for $ROOTPATH" || ok "resolve_files ($LAYOUT) refuses depth-1 path $ROOTPATH"
    done
done

F2DIR="${HOME}/.bwrap-common-test-$$"
if mkdir -p "$F2DIR" 2>/dev/null; then
    : > "${F2DIR}/arg.bin"
    RFL=(); RFLA=()
    bwrap_resolve_files RFL RFLA "${F2DIR}/arg.bin" 2>/dev/null
    has_triple RFL --ro-bind "${F2DIR}/arg.bin" "${F2DIR}/arg.bin" \
        && ok "resolve_files (leaf default) binds the argument itself" || fail "resolve_files (leaf default) did not bind the argument"
    RFP=(); RFPA=()
    bwrap_resolve_files RFP RFPA --layout=parent "${F2DIR}/arg.bin" 2>/dev/null
    has_triple RFP --ro-bind "$F2DIR" "$F2DIR" \
        && ok "resolve_files (parent mode) binds the containing directory" || fail "resolve_files (parent mode) did not bind the directory"
    rm -rf "$F2DIR"
else
    skip "resolve_files layout cases (HOME not writable)"
fi

test_resolve_files_home_guard() {
    local _base="" _candidate
    for _candidate in /var/tmp "/run/user/$(id -u)"; do
        _base=$(mktemp -d "${_candidate}/bwrap-common-home-guard.XXXXXX" 2>/dev/null) || continue
        case "$(realpath -m -- "$_base")" in
            /tmp|/tmp/*)
                rm -rf -- "$_base"
                _base=""
                continue
                ;;
        esac
        break
    done
    if [[ -z "$_base" ]]; then
        skip "resolve_files HOME guard (no temp base outside /tmp)"
        return
    fi
    TEST_EXTRA_CLEANUP+=("$_base")
    if ! mkdir -p "${_base}/home/user/sub" "${_base}/home/other" 2>/dev/null; then
        skip "resolve_files HOME guard (temp base not writable)"
        return
    fi
    local HOME="${_base}/home/user"
    local _ancestor="${_base}/home"
    local _sibling="${_base}/home/other"
    : > "${HOME}/sub/file.bin"

    local -a B A
    local _rc=0
    B=(); A=()
    bwrap_resolve_files B A --bind "$HOME" 2>"$WARN_ERR" || _rc=$?
    [[ $_rc -ne 0 ]] \
        && ok "resolve_files returns non-zero for a refused hard bind" \
        || fail "resolve_files returned zero for a refused hard bind"
    has_triple B --bind "$HOME" "$HOME" \
        && fail "resolve_files (leaf) bound HOME" || ok "resolve_files (leaf) refuses HOME"
    grep -qxF "bwrap_resolve_files: refusing to bind HOME or an ancestor for: $HOME" "$WARN_ERR" \
        && ok "resolve_files (leaf) warns when refusing HOME" || fail "resolve_files HOME warning absent"
    [[ ${#A[@]} -eq 1 && "${A[0]}" == "$HOME" ]] \
        && ok "resolve_files keeps the refused argument for the child process" \
        || fail "resolve_files dropped the refused argument"

    B=(); A=(); _rc=0
    BWRAP_QUIET=1 bwrap_resolve_files B A --bind "$HOME" 2>"$WARN_ERR" || _rc=$?
    [[ $_rc -ne 0 && ! -s "$WARN_ERR" ]] \
        && ok "BWRAP_QUIET keeps a refused hard bind non-zero without a warning" \
        || fail "BWRAP_QUIET lost the refusal return code or warned"

    B=(); A=(); _rc=0
    bwrap_resolve_files B A --ro-bind "$HOME" 2>/dev/null || _rc=$?
    [[ $_rc -ne 0 ]] \
        && ok "resolve_files returns non-zero for a refused hard ro bind" \
        || fail "resolve_files returned zero for a refused hard ro bind"
    has_triple B --ro-bind "$HOME" "$HOME" \
        && fail "resolve_files (leaf, ro) bound HOME" || ok "resolve_files (leaf) refuses HOME in ro mode"

    B=(); A=(); _rc=0
    bwrap_resolve_files B A --bind-try "$HOME" 2>/dev/null || _rc=$?
    [[ $_rc -eq 0 ]] \
        && ok "resolve_files returns zero for a refused try bind" \
        || fail "resolve_files returned non-zero for a refused try bind"
    has_triple B --bind-try "$HOME" "$HOME" \
        && fail "resolve_files (leaf, try) bound HOME" || ok "resolve_files (leaf, try) refuses HOME"
    [[ ${#A[@]} -eq 1 && "${A[0]}" == "$HOME" ]] \
        && ok "resolve_files keeps the refused try argument" \
        || fail "resolve_files dropped the refused try argument"

    B=(); A=()
    bwrap_resolve_files B A --bind "$_ancestor" 2>"$WARN_ERR"
    has_triple B --bind "$_ancestor" "$_ancestor" \
        && fail "resolve_files (leaf) bound an ancestor of HOME" || ok "resolve_files (leaf) refuses an ancestor of HOME"
    grep -qxF "bwrap_resolve_files: refusing to bind HOME or an ancestor for: $_ancestor" "$WARN_ERR" \
        && ok "resolve_files (leaf) warns when refusing an ancestor" || fail "resolve_files ancestor warning absent"

    B=(); A=(); _rc=0
    bwrap_resolve_files B A --bind "${HOME}/sub" 2>/dev/null || _rc=$?
    [[ $_rc -eq 0 ]] \
        && ok "resolve_files returns zero when it binds a HOME descendant" \
        || fail "resolve_files returned non-zero for a HOME descendant"
    has_triple B --bind "${HOME}/sub" "${HOME}/sub" \
        && ok "resolve_files (leaf) still binds a HOME descendant" || fail "resolve_files refused a HOME descendant"

    B=(); A=()
    bwrap_resolve_files B A --bind "$_sibling" 2>/dev/null
    has_triple B --bind "$_sibling" "$_sibling" \
        && ok "resolve_files (leaf) still binds a HOME sibling" || fail "resolve_files refused a HOME sibling"

    B=(); A=(); _rc=0
    bwrap_resolve_files B A --layout=parent --bind "$HOME" 2>"$WARN_ERR" || _rc=$?
    [[ $_rc -ne 0 ]] \
        && ok "resolve_files returns non-zero for a refused parent hard bind" \
        || fail "resolve_files returned zero for a refused parent hard bind"
    has_triple B --bind "$HOME" "$HOME" \
        && fail "resolve_files (parent) bound HOME" || ok "resolve_files (parent) refuses HOME"
    has_triple B --bind "$_ancestor" "$_ancestor" \
        && fail "resolve_files (parent) bound an ancestor of HOME" \
        || ok "resolve_files (parent) does not bind the ancestor"
    grep -qxF "bwrap_resolve_files: refusing to bind HOME or an ancestor for: $HOME" "$WARN_ERR" \
        && ok "resolve_files (parent) warns when refusing HOME" \
        || fail "resolve_files parent HOME warning absent"

    B=(); A=()
    bwrap_resolve_files B A --layout=parent --bind "${HOME}/sub/file.bin" 2>/dev/null
    has_triple B --bind "${HOME}/sub" "${HOME}/sub" \
        && ok "resolve_files (parent) binds the containing directory for a descendant" \
        || fail "resolve_files (parent) did not bind the containing directory for a descendant"

    B=(); A=()
    bwrap_resolve_files B A --layout=parent --bind "$_sibling" 2>/dev/null
    has_triple B --bind "$_sibling" "$_sibling" \
        && ok "resolve_files (parent) narrows a HOME sibling to the argument" \
        || fail "resolve_files (parent) did not narrow a HOME sibling"
    has_triple B --bind "$_ancestor" "$_ancestor" \
        && fail "resolve_files (parent) bound the ancestor for a sibling" \
        || ok "resolve_files (parent) avoids binding the ancestor for a sibling"

    B=(); A=()
    bwrap_resolve_files B A --layout=parent --bind "${HOME}/sub" 2>/dev/null
    has_triple B --bind "${HOME}/sub" "${HOME}/sub" \
        && ok "resolve_files (parent) falls back to a direct HOME child" \
        || fail "resolve_files (parent) did not bind a direct HOME child"

    HOME="${_base}/link"
    ln -s "${_base}/home/user" "$HOME"
    B=(); A=(); _rc=0
    bwrap_resolve_files B A --bind "$HOME" 2>"$WARN_ERR" || _rc=$?
    [[ $_rc -ne 0 ]] \
        && ok "resolve_files returns non-zero for a refused symlinked HOME" \
        || fail "resolve_files returned zero for a refused symlinked HOME"
    has_triple B --bind "${_base}/home/user" "${_base}/home/user" \
        && fail "resolve_files bound a symlinked HOME" || ok "resolve_files resolves a symlinked HOME"
    grep -qxF "bwrap_resolve_files: refusing to bind HOME or an ancestor for: $HOME" "$WARN_ERR" \
        && ok "resolve_files warns for a symlinked HOME" || fail "resolve_files symlinked HOME warning absent"

    rm -rf "$_base"
}
test_resolve_files_home_guard

BARG=(); BARGA=()
bwrap_resolve_files BARG BARGA -- --bind
[[ ${#BARGA[@]} -eq 1 && "${BARGA[0]}" == "--bind" ]] \
    && ok "resolve_files: -- ends option parsing" || fail "resolve_files: -- did not stop parsing"

LARG=(); LARGA=()
bwrap_resolve_files LARG LARGA --bind leaf
[[ ${#LARGA[@]} -eq 1 && "${LARGA[0]}" == "leaf" ]] \
    && ok "resolve_files: bare 'leaf' is an argument, not a layout" || fail "resolve_files: bare 'leaf' was consumed"

XARG=(); XARGA=()
bwrap_resolve_files XARG XARGA --layout=bogus /tmp 2>/dev/null && XRC=0 || XRC=$?
[[ $XRC -ne 0 ]] && ok "resolve_files: rejects an unknown layout" || fail "resolve_files: accepted an unknown layout"

NARG=(); NARGA=()
bwrap_resolve_files NARG NARGA --layout=parent --bind "${TMPDIR_TEST}/missing-app" 2>/dev/null
[[ ${#NARGA[@]} -eq 1 ]] && ok "resolve_files: --layout=parent is accepted" || fail "resolve_files: --layout=parent rejected"

QW=()
BWRAP_QUIET=1 bwrap_ro_bind_dir QW "${TMPDIR_TEST}/missing-ro-dir" 2>"$WARN_ERR"
[[ ! -s "$WARN_ERR" ]] && ok "BWRAP_QUIET silences warnings" || fail "BWRAP_QUIET did not silence the warning"


