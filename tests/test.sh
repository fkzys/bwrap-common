#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

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

# ── Source ──────────────────────────────────────────────
. ./bwrap-common.sh || { echo "FATAL: cannot source bwrap-common.sh"; exit 1; }

# ── Guard re-source ─────────────────────────────────────
. ./bwrap-common.sh
ok

# ── All public functions defined ────────────────────────
FUNCTIONS=(
    bwrap_base bwrap_gpu bwrap_lib64 bwrap_resolv
    bwrap_wayland bwrap_x11 bwrap_audio
    bwrap_dbus_session bwrap_dbus_system bwrap_dbus_filtered bwrap_dbus_common
    bwrap_themes bwrap_gtk_theme_env bwrap_fcitx
    bwrap_home_tmpfs bwrap_runtime_dir bwrap_env_base
    bwrap_bind_dir bwrap_ro_bind_dir
    bwrap_hardened_malloc bwrap_no_hardened_malloc
    bwrap_sandbox bwrap_ssh_agent
    bwrap_resolve_files
    bwrap_gui_setup bwrap_gui_finish
    bwrap_exec
    require_dir
)

for fn in "${FUNCTIONS[@]}"; do
    declare -f "$fn" >/dev/null 2>&1 && ok || fail "function $fn not defined"
done

# ── VERSION is set ──────────────────────────────────────
[[ -n "${VERSION:-}" ]] && ok || fail "VERSION not set"

# ── bwrap_base ──────────────────────────────────────────
A=()
bwrap_base A
[[ ${#A[@]} -gt 0 ]]            && ok || fail "bwrap_base empty"
has_pair A "--ro-bind" "/usr"    && ok || fail "bwrap_base missing --ro-bind /usr"
has_pair A "--proc" "/proc"      && ok || fail "bwrap_base missing --proc /proc"
has_pair A "--tmpfs" "/tmp"      && ok || fail "bwrap_base missing --tmpfs /tmp"

# ── bwrap_home_tmpfs ────────────────────────────────────
B=()
bwrap_home_tmpfs B
[[ ${#B[@]} -gt 0 ]]            && ok || fail "bwrap_home_tmpfs empty"
has_pair B "--tmpfs" "$HOME"     && ok || fail "bwrap_home_tmpfs missing --tmpfs HOME"
has_pair B "--dir" "${HOME}/.config" && ok || fail "bwrap_home_tmpfs missing .config dir"

# ── bwrap_env_base ──────────────────────────────────────
C=()
bwrap_env_base C
has_pair C "--setenv" "HOME"             && ok || fail "bwrap_env_base missing HOME"
has_pair C "--setenv" "PATH"             && ok || fail "bwrap_env_base missing PATH"
has_pair C "--setenv" "XDG_RUNTIME_DIR"  && ok || fail "bwrap_env_base missing XDG_RUNTIME_DIR"

# ── bwrap_sandbox ──────────────────────────────────────
D=()
bwrap_sandbox D
has_arg D "--unshare-all"    && ok || fail "bwrap_sandbox missing --unshare-all"
has_arg D "--die-with-parent" && ok || fail "bwrap_sandbox missing --die-with-parent"
has_arg D "--new-session"    && ok || fail "bwrap_sandbox missing --new-session"

# ── bwrap_sandbox with network ──────────────────────────
E=()
bwrap_sandbox E yes
has_arg E "--share-net"      && ok || fail "bwrap_sandbox yes missing --share-net"

# ── bwrap_sandbox without new-session ───────────────────
F=()
bwrap_sandbox F no no
has_arg F "--new-session"    && fail "bwrap_sandbox no no should not have --new-session" || ok

# ── bwrap_no_hardened_malloc ────────────────────────────
G=()
bwrap_no_hardened_malloc G
has_pair G "--unsetenv" "LD_PRELOAD"                   && ok || fail "bwrap_no_hardened_malloc missing --unsetenv LD_PRELOAD"
has_triple G "--ro-bind" "/dev/null" "/etc/ld.so.preload" && ok || fail "bwrap_no_hardened_malloc missing /dev/null bind"

# ── bwrap_runtime_dir ───────────────────────────────────
H=()
bwrap_runtime_dir H
[[ ${#H[@]} -gt 0 ]]                       && ok || fail "bwrap_runtime_dir empty"
has_pair H "--dir" "${XDG_RUNTIME_DIR}"     && ok || fail "bwrap_runtime_dir missing XDG_RUNTIME_DIR dir"

# ── bwrap_gpu / bwrap_lib64 ─────────────────────────────
I=()
bwrap_gpu I
ok

J=()
bwrap_lib64 J
[[ ${#J[@]} -gt 0 ]] && ok || fail "bwrap_lib64 empty"

# ── bwrap_bind_dir ──────────────────────────────────────
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

BIND_TARGET="${TMPDIR_TEST}/testdir"
K=()
bwrap_bind_dir K "$BIND_TARGET"
[[ -d "$BIND_TARGET" ]]                && ok || fail "bwrap_bind_dir didn't create dir"
has_pair K "--bind" "$BIND_TARGET"      && ok || fail "bwrap_bind_dir missing --bind"

# ── bwrap_bind_dir multiple dirs ────────────────────────
L=()
bwrap_bind_dir L "${TMPDIR_TEST}/a" "${TMPDIR_TEST}/b"
[[ -d "${TMPDIR_TEST}/a" && -d "${TMPDIR_TEST}/b" ]] && ok || fail "bwrap_bind_dir multi didn't create"

count=0
for arg in "${L[@]}"; do [[ "$arg" == "--bind" ]] && count=$((count + 1)); done
[[ $count -eq 2 ]] && ok || fail "bwrap_bind_dir multi: expected 2 --bind, got $count"

# ── bwrap_ro_bind_dir ──────────────────────────────────
M=()
bwrap_ro_bind_dir M "$TMPDIR_TEST"
has_pair M "--ro-bind" "$TMPDIR_TEST"   && ok || fail "bwrap_ro_bind_dir missing --ro-bind"

N=()
bwrap_ro_bind_dir N "/nonexistent/path/12345"
[[ ${#N[@]} -eq 0 ]] && ok || fail "bwrap_ro_bind_dir should skip missing"

# ── require_dir ─────────────────────────────────────────
require_dir /tmp 2>/dev/null              && ok || fail "require_dir /tmp"
(require_dir /nonexistent/path 2>/dev/null) && fail "require_dir should fail on missing" || ok

# ── bwrap_fcitx ─────────────────────────────────────────
O=()
bwrap_fcitx O
has_pair O "--setenv" "QT_IM_MODULE"    && ok || fail "bwrap_fcitx missing QT_IM_MODULE"
has_pair O "--setenv" "XMODIFIERS"      && ok || fail "bwrap_fcitx missing XMODIFIERS"

# ── bwrap_gui_setup ─────────────────────────────────────
P=()
bwrap_gui_setup P no
[[ ${#P[@]} -gt 0 ]]                   && ok || fail "bwrap_gui_setup empty"
has_pair P "--ro-bind" "/usr"           && ok || fail "bwrap_gui_setup missing base --ro-bind /usr"
has_pair P "--tmpfs" "$HOME"            && ok || fail "bwrap_gui_setup missing home tmpfs"

Q=()
bwrap_gui_setup Q yes
ok

# ── bwrap_gui_finish ────────────────────────────────────
R=()
bwrap_gui_finish R wayland no default unfiltered
[[ ${#R[@]} -gt 0 ]]                   && ok || fail "bwrap_gui_finish empty"
has_arg R "--unshare-all"               && ok || fail "bwrap_gui_finish missing --unshare-all"

S=()
bwrap_gui_finish S wayland no no none
has_pair S "--unsetenv" "LD_PRELOAD"    && ok || fail "bwrap_gui_finish no malloc missing --unsetenv"

# ── bwrap_ssh_agent without SSH_AUTH_SOCK ───────────────
unset SSH_AUTH_SOCK 2>/dev/null || true
T=()
bwrap_ssh_agent T
[[ ${#T[@]} -eq 0 ]] && ok || fail "bwrap_ssh_agent should be empty without socket"

# ── bwrap_dbus_system ───────────────────────────────────
U=()
bwrap_dbus_system U
ok

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
