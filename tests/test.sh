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

if arrays_equal SETUP_GPU_DEFAULT SETUP_GPU_YES; then
    ok "default gpu argument matches gpu=yes"
else
    fail "default gpu argument differs from gpu=yes"
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

# ── Summary ─────────────────────────────────────────────────

summary
