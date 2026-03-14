#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

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
    if declare -f "$fn" >/dev/null 2>&1; then
        ok
    else
        fail "function $fn not defined"
    fi
done

# ── VERSION is set ──────────────────────────────────────
if [[ -n "${VERSION:-}" ]]; then ok; else fail "VERSION not set"; fi

# ── bwrap_base produces args with --ro-bind /usr ────────
A=()
bwrap_base A
if [[ ${#A[@]} -gt 0 ]]; then ok; else fail "bwrap_base empty"; fi

found=0
for ((i=0; i<${#A[@]}-1; i++)); do
    if [[ "${A[$i]}" == "--ro-bind" && "${A[$((i+1))]}" == "/usr" ]]; then
        found=1; break
    fi
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_base missing --ro-bind /usr"; fi

# ── bwrap_base has --proc /proc ─────────────────────────
found=0
for ((i=0; i<${#A[@]}-1; i++)); do
    if [[ "${A[$i]}" == "--proc" && "${A[$((i+1))]}" == "/proc" ]]; then
        found=1; break
    fi
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_base missing --proc /proc"; fi

# ── bwrap_base has --tmpfs /tmp ─────────────────────────
found=0
for ((i=0; i<${#A[@]}-1; i++)); do
    if [[ "${A[$i]}" == "--tmpfs" && "${A[$((i+1))]}" == "/tmp" ]]; then
        found=1; break
    fi
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_base missing --tmpfs /tmp"; fi

# ── bwrap_home_tmpfs ────────────────────────────────────
B=()
bwrap_home_tmpfs B
if [[ ${#B[@]} -gt 0 ]]; then ok; else fail "bwrap_home_tmpfs empty"; fi

found=0
for ((i=0; i<${#B[@]}-1; i++)); do
    [[ "${B[$i]}" == "--tmpfs" && "${B[$((i+1))]}" == "$HOME" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_home_tmpfs missing --tmpfs HOME"; fi

# ── bwrap_home_tmpfs creates XDG dirs ───────────────────
has_config=0
for ((i=0; i<${#B[@]}-1; i++)); do
    [[ "${B[$i]}" == "--dir" && "${B[$((i+1))]}" == "${HOME}/.config" ]] && has_config=1
done
if [[ $has_config -eq 1 ]]; then ok; else fail "bwrap_home_tmpfs missing .config dir"; fi

# ── bwrap_env_base sets HOME ────────────────────────────
C=()
bwrap_env_base C
found=0
for ((i=0; i<${#C[@]}-2; i++)); do
    [[ "${C[$i]}" == "--setenv" && "${C[$((i+1))]}" == "HOME" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_env_base missing HOME"; fi

# ── bwrap_env_base sets PATH ───────────────────────────
found=0
for ((i=0; i<${#C[@]}-2; i++)); do
    [[ "${C[$i]}" == "--setenv" && "${C[$((i+1))]}" == "PATH" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_env_base missing PATH"; fi

# ── bwrap_env_base sets XDG_RUNTIME_DIR ─────────────────
found=0
for ((i=0; i<${#C[@]}-2; i++)); do
    [[ "${C[$i]}" == "--setenv" && "${C[$((i+1))]}" == "XDG_RUNTIME_DIR" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_env_base missing XDG_RUNTIME_DIR"; fi

# ── bwrap_sandbox ──────────────────────────────────────
D=()
bwrap_sandbox D
found=0
for arg in "${D[@]}"; do
    [[ "$arg" == "--unshare-all" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_sandbox missing --unshare-all"; fi

# ── bwrap_sandbox has --die-with-parent ─────────────────
found=0
for arg in "${D[@]}"; do
    [[ "$arg" == "--die-with-parent" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_sandbox missing --die-with-parent"; fi

# ── bwrap_sandbox has --new-session by default ──────────
found=0
for arg in "${D[@]}"; do
    [[ "$arg" == "--new-session" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_sandbox missing --new-session"; fi

# ── bwrap_sandbox with network ──────────────────────────
E=()
bwrap_sandbox E yes
found=0
for arg in "${E[@]}"; do
    [[ "$arg" == "--share-net" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_sandbox yes missing --share-net"; fi

# ── bwrap_sandbox without new-session ───────────────────
F=()
bwrap_sandbox F no no
found=0
for arg in "${F[@]}"; do
    [[ "$arg" == "--new-session" ]] && found=1
done
if [[ $found -eq 0 ]]; then ok; else fail "bwrap_sandbox no no should not have --new-session"; fi

# ── bwrap_no_hardened_malloc ────────────────────────────
G=()
bwrap_no_hardened_malloc G
found=0
for ((i=0; i<${#G[@]}-1; i++)); do
    [[ "${G[$i]}" == "--unsetenv" && "${G[$((i+1))]}" == "LD_PRELOAD" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_no_hardened_malloc missing --unsetenv LD_PRELOAD"; fi

# ── bwrap_no_hardened_malloc has /dev/null bind ─────────
found=0
for ((i=0; i<${#G[@]}-2; i++)); do
    if [[ "${G[$i]}" == "--ro-bind" && "${G[$((i+1))]}" == "/dev/null" && "${G[$((i+2))]}" == "/etc/ld.so.preload" ]]; then
        found=1; break
    fi
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_no_hardened_malloc missing /dev/null bind"; fi

# ── bwrap_runtime_dir ───────────────────────────────────
H=()
bwrap_runtime_dir H
if [[ ${#H[@]} -gt 0 ]]; then ok; else fail "bwrap_runtime_dir empty"; fi

found=0
for ((i=0; i<${#H[@]}-1; i++)); do
    [[ "${H[$i]}" == "--dir" && "${H[$((i+1))]}" == "${XDG_RUNTIME_DIR}" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_runtime_dir missing XDG_RUNTIME_DIR dir"; fi

# ── bwrap_gpu handles missing /dev/dri ──────────────────
I=()
bwrap_gpu I
# should not fail even if /dev/dri doesn't exist
ok

# ── bwrap_lib64 produces output ─────────────────────────
J=()
bwrap_lib64 J
if [[ ${#J[@]} -gt 0 ]]; then ok; else fail "bwrap_lib64 empty"; fi

# ── bwrap_bind_dir creates and binds ────────────────────
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT
BIND_TARGET="${TMPDIR_TEST}/testdir"
K=()
bwrap_bind_dir K "$BIND_TARGET"
if [[ -d "$BIND_TARGET" ]]; then ok; else fail "bwrap_bind_dir didn't create dir"; fi

found=0
for ((i=0; i<${#K[@]}-1; i++)); do
    [[ "${K[$i]}" == "--bind" && "${K[$((i+1))]}" == "$BIND_TARGET" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_bind_dir missing --bind"; fi

# ── bwrap_bind_dir multiple dirs ────────────────────────
BIND_A="${TMPDIR_TEST}/a"
BIND_B="${TMPDIR_TEST}/b"
L=()
bwrap_bind_dir L "$BIND_A" "$BIND_B"
if [[ -d "$BIND_A" && -d "$BIND_B" ]]; then ok; else fail "bwrap_bind_dir multi didn't create"; fi

count=0
for arg in "${L[@]}"; do
    [[ "$arg" == "--bind" ]] && count=$((count + 1))
done
if [[ $count -eq 2 ]]; then ok; else fail "bwrap_bind_dir multi: expected 2 --bind, got $count"; fi

# ── bwrap_ro_bind_dir existing dir ──────────────────────
M=()
bwrap_ro_bind_dir M "$TMPDIR_TEST"
found=0
for ((i=0; i<${#M[@]}-1; i++)); do
    [[ "${M[$i]}" == "--ro-bind" && "${M[$((i+1))]}" == "$TMPDIR_TEST" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_ro_bind_dir missing --ro-bind"; fi

# ── bwrap_ro_bind_dir missing dir (skipped) ─────────────
N=()
bwrap_ro_bind_dir N "/nonexistent/path/12345"
if [[ ${#N[@]} -eq 0 ]]; then ok; else fail "bwrap_ro_bind_dir should skip missing"; fi

# ── require_dir passes on existing ──────────────────────
if require_dir /tmp 2>/dev/null; then ok; else fail "require_dir /tmp"; fi

# ── require_dir fails on missing ────────────────────────
if (require_dir /nonexistent/path 2>/dev/null); then
    fail "require_dir should fail on missing"
else
    ok
fi

# ── bwrap_fcitx sets env vars ──────────────────────────
O=()
bwrap_fcitx O
found_qt=0
found_xmod=0
for ((i=0; i<${#O[@]}-2; i++)); do
    [[ "${O[$i]}" == "--setenv" && "${O[$((i+1))]}" == "QT_IM_MODULE" ]] && found_qt=1
    [[ "${O[$i]}" == "--setenv" && "${O[$((i+1))]}" == "XMODIFIERS" ]] && found_xmod=1
done
if [[ $found_qt -eq 1 ]]; then ok; else fail "bwrap_fcitx missing QT_IM_MODULE"; fi
if [[ $found_xmod -eq 1 ]]; then ok; else fail "bwrap_fcitx missing XMODIFIERS"; fi

# ── bwrap_gui_setup composes correctly ──────────────────
P=()
bwrap_gui_setup P no
if [[ ${#P[@]} -gt 0 ]]; then ok; else fail "bwrap_gui_setup empty"; fi

# should have base args
found=0
for ((i=0; i<${#P[@]}-1; i++)); do
    [[ "${P[$i]}" == "--ro-bind" && "${P[$((i+1))]}" == "/usr" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_gui_setup missing base --ro-bind /usr"; fi

# should have home tmpfs
found=0
for ((i=0; i<${#P[@]}-1; i++)); do
    [[ "${P[$i]}" == "--tmpfs" && "${P[$((i+1))]}" == "$HOME" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_gui_setup missing home tmpfs"; fi

# ── bwrap_gui_setup with network adds resolv ────────────
Q=()
bwrap_gui_setup Q yes
# can't easily check resolv without real symlink, just verify it doesn't crash
ok

# ── bwrap_gui_finish composes correctly ─────────────────
R=()
bwrap_gui_finish R wayland no default unfiltered
if [[ ${#R[@]} -gt 0 ]]; then ok; else fail "bwrap_gui_finish empty"; fi

# should have --unshare-all from sandbox
found=0
for arg in "${R[@]}"; do
    [[ "$arg" == "--unshare-all" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_gui_finish missing --unshare-all"; fi

# ── bwrap_gui_finish with no malloc ─────────────────────
S=()
bwrap_gui_finish S wayland no no none
found=0
for ((i=0; i<${#S[@]}-1; i++)); do
    [[ "${S[$i]}" == "--unsetenv" && "${S[$((i+1))]}" == "LD_PRELOAD" ]] && found=1
done
if [[ $found -eq 1 ]]; then ok; else fail "bwrap_gui_finish no malloc missing --unsetenv"; fi

# ── bwrap_ssh_agent without SSH_AUTH_SOCK ───────────────
unset SSH_AUTH_SOCK 2>/dev/null || true
T=()
bwrap_ssh_agent T
if [[ ${#T[@]} -eq 0 ]]; then ok; else fail "bwrap_ssh_agent should be empty without socket"; fi

# ── bwrap_dbus_system without socket ────────────────────
U=()
bwrap_dbus_system U
# may or may not add args depending on whether /run/dbus exists
ok

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
