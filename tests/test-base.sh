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

QW=()
BWRAP_QUIET=1 bwrap_ro_bind_dir QW "${TMPDIR_TEST}/missing-ro-dir" 2>"$WARN_ERR"
[[ ! -s "$WARN_ERR" ]] && ok "BWRAP_QUIET silences warnings" || fail "BWRAP_QUIET did not silence the warning"


