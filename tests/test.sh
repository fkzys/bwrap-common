#!/usr/bin/env bash
set -euo pipefail

# ── Test harness ─────────────────────────────────────────────

PASS=0
FAIL=0
TESTS=0

ok() {
    PASS=$((PASS + 1))
    TESTS=$((TESTS + 1))
    echo "  ✓ $1"
}

fail() {
    FAIL=$((FAIL + 1))
    TESTS=$((TESTS + 1))
    echo "  ✗ $1"
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

count_flag() {
    local -n _arr=$1; local flag=$2; local count=0
    for arg in "${_arr[@]}"; do [[ "$arg" == "$flag" ]] && count=$((count + 1)); done
    echo "$count"
}

# ── Source ──────────────────────────────────────────────────

. ./bwrap-common.sh || { echo "FATAL: cannot source bwrap-common.sh"; exit 1; }

# ── Setup ───────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

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
    bwrap_sandbox bwrap_ssh_agent
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
has_pair G "--unsetenv" "LD_PRELOAD"                      && ok "--unsetenv LD_PRELOAD present"          || fail "--unsetenv LD_PRELOAD missing"
has_triple G "--ro-bind" "/dev/null" "/etc/ld.so.preload"  && ok "/dev/null → /etc/ld.so.preload bind"   || fail "/dev/null bind missing"

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

Q=()
bwrap_gui_setup Q yes
ok "bwrap_gui_setup with x11=yes runs without error"

# ── bwrap_gui_finish ────────────────────────────────────────

section "bwrap_gui_finish"

R=()
bwrap_gui_finish R wayland no default unfiltered
[[ ${#R[@]} -gt 0 ]]      && ok "produces non-empty array"   || fail "empty array"
has_arg R "--unshare-all"  && ok "--unshare-all present"      || fail "--unshare-all missing"

S=()
bwrap_gui_finish S wayland no no none
has_pair S "--unsetenv" "LD_PRELOAD" && ok "no-malloc sets --unsetenv LD_PRELOAD" || fail "--unsetenv LD_PRELOAD missing"

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

# ── Summary ─────────────────────────────────────────────────

summary
