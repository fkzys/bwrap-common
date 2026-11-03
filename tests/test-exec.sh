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

