# ── bwrap_exec ──────────────────────────────────────────────

section "bwrap_exec"

FAKEBIN="${TMPDIR_TEST}/fakebin"
mkdir -p "$FAKEBIN"

cat > "${FAKEBIN}/bwrap" << 'EOF'
#!/usr/bin/env bash
_argv=()
_fd=""
while (($#)); do
    case "$1" in
        --args)
            _fd=$2
            shift 2
            while IFS= read -r -d '' _arg; do
                _argv+=("$_arg")
            done <&"$_fd"
            ;;
        *)
            _argv+=("$1")
            shift
            ;;
    esac
done
_seccomp_len=-1
for ((_i=0; _i<${#_argv[@]}; _i++)); do
    if [[ "${_argv[_i]}" == "--seccomp" ]]; then
        _seccomp_fd="${_argv[_i+1]:-}"
        if [[ -n "$_seccomp_fd" ]]; then
            _seccomp_len=$(wc -c <&"$_seccomp_fd" 2>/dev/null) || _seccomp_len=-1
        fi
        break
    fi
done
if [[ -n "${FAKE_BWRAP_SECCOMP_LEN_FILE:-}" ]]; then
    printf '%s' "$_seccomp_len" > "$FAKE_BWRAP_SECCOMP_LEN_FILE"
fi
if [[ -n "${FAKE_BWRAP_ARGS_FILE:-}" ]]; then
    printf '%s\0' "${_argv[@]}" > "$FAKE_BWRAP_ARGS_FILE"
fi
if [[ -n "${FAKE_BWRAP_ARGS_FD_PATH_FILE:-}" && -n "$_fd" ]]; then
    readlink "/proc/$$/fd/$_fd" > "$FAKE_BWRAP_ARGS_FD_PATH_FILE" 2>/dev/null || true
fi
if [[ -n "${FAKE_BWRAP_CMDLINE_FILE:-}" ]]; then
    tr '\0' '\n' < "/proc/$$/cmdline" > "$FAKE_BWRAP_CMDLINE_FILE"
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
        _BWRAP_ARGS_FDS=()
        _BWRAP_SECCOMP_REFRESH_FDS=()
        _BWRAP_EXEC_BUNDLED=0
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
        _BWRAP_ARGS_FDS=()
        _BWRAP_SECCOMP_REFRESH_FDS=()
        _BWRAP_EXEC_BUNDLED=0
        _bwrap_dbus_cleanup() { printf 'cleanup\n' >> "${FAKE_CLEANUP_FILE:-/dev/null}"; }
        bwrap_exec "$@"
    )
}

run_bwrap_exec_bundled() {
    (
        trap - EXIT
        export PATH="${FAKEBIN}:${PATH}"
        _BWRAP_DBUS_PROXY_PIDS=()
        _BWRAP_DBUS_PROXY_SOCKETS=()
        _BWRAP_ARGS_FDS=()
        _BWRAP_SECCOMP_REFRESH_FDS=()
        _BWRAP_EXEC_BUNDLED=0
        bwrap_exec_bundled
        bwrap_exec "$@"
    )
}

run_bwrap_exec_bundled_proxy() {
    (
        trap - EXIT
        export PATH="${FAKEBIN}:${PATH}"
        _BWRAP_DBUS_PROXY_PIDS=(999999)
        _BWRAP_DBUS_PROXY_SOCKETS=()
        _BWRAP_ARGS_FDS=()
        _BWRAP_SECCOMP_REFRESH_FDS=()
        _BWRAP_EXEC_BUNDLED=0
        _bwrap_dbus_cleanup() { printf 'cleanup\n' >> "${FAKE_CLEANUP_FILE:-/dev/null}"; }
        bwrap_exec_bundled
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
    _BWRAP_ARGS_FDS=()
    _BWRAP_SECCOMP_REFRESH_FDS=()
    _BWRAP_EXEC_BUNDLED=0
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

# ── bwrap_exec_bundled ──────────────────────────────────────

section "bwrap_exec_bundled"

# Test 8: options are expanded from --args and forwarded before the command
ARGS_FILE8="${TMPDIR_TEST}/args8"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
unset FAKE_BWRAP_ARGS_FD_PATH_FILE FAKE_BWRAP_CMDLINE_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE8"
export FAKE_BWRAP_EXIT=0
B_OPTS8=(
    --ro-bind /usr
    --setenv SECRET "s3cr3t value"
    --setenv MULTILINE $'line1\nline2'
    ""
)
B_CMD8=( /usr/bin/app "cmd arg" "" )
run_bwrap_exec_bundled "${B_OPTS8[@]}" -- "${B_CMD8[@]}" < /dev/null
RC8=$?
GOT8=()
read_args "$ARGS_FILE8" GOT8
EXPECTED8=( "${B_OPTS8[@]}" -- "${B_CMD8[@]}" )
if [[ $RC8 -eq 0 ]] && arrays_equal GOT8 EXPECTED8; then
    ok "bundled exec expands --args and forwards the command exactly"
else
    fail "bundled exec args mismatch (rc=$RC8)"
fi

# Test 9: option values are absent from bwrap's cmdline; the args fd is unlinked
ARGS_FILE9="${TMPDIR_TEST}/args9"
CMDLINE_FILE9="${TMPDIR_TEST}/cmdline9"
FD_PATH_FILE9="${TMPDIR_TEST}/fdpath9"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
unset FAKE_BWRAP_ARGS_FD_PATH_FILE FAKE_BWRAP_CMDLINE_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE9"
export FAKE_BWRAP_CMDLINE_FILE="$CMDLINE_FILE9"
export FAKE_BWRAP_ARGS_FD_PATH_FILE="$FD_PATH_FILE9"
export FAKE_BWRAP_EXIT=0
SECRET9="unique-secret-$$-${RANDOM}"
B_OPTS9=( --setenv TOKEN "$SECRET9" --ro-bind /usr )
run_bwrap_exec_bundled "${B_OPTS9[@]}" -- /usr/bin/app < /dev/null
RC9=$?
GOT9=()
read_args "$ARGS_FILE9" GOT9
CONTAINS9=0
for _arg9 in "${GOT9[@]}"; do
    [[ "$_arg9" == "$SECRET9" ]] && CONTAINS9=1
done
FD_PATH9=$(cat "$FD_PATH_FILE9" 2>/dev/null || true)
if [[ $RC9 -eq 0 ]] &&
   [[ $CONTAINS9 -eq 1 ]] &&
   [[ -f "$CMDLINE_FILE9" ]] &&
   ! grep -Fq -- "$SECRET9" "$CMDLINE_FILE9" &&
   [[ "$FD_PATH9" == *"(deleted)"* ]]; then
    ok "bundled exec keeps option values out of /proc cmdline and unlinks the args fd"
else
    fail "bundled exec secret/fd visibility (rc=$RC9, contains=$CONTAINS9, fd='$FD_PATH9')"
fi

# Test 10: an empty options array falls back to a plain command invocation
ARGS_FILE10="${TMPDIR_TEST}/args10"
FD_PATH_FILE10="${TMPDIR_TEST}/fdpath10"
rm -f -- "$FD_PATH_FILE10"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
unset FAKE_BWRAP_ARGS_FD_PATH_FILE FAKE_BWRAP_CMDLINE_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE10"
export FAKE_BWRAP_ARGS_FD_PATH_FILE="$FD_PATH_FILE10"
export FAKE_BWRAP_EXIT=0
B_OPTS10=()
run_bwrap_exec_bundled -- /usr/bin/app < /dev/null
RC10=$?
GOT10=()
read_args "$ARGS_FILE10" GOT10
EXPECTED10=( -- /usr/bin/app )
if [[ $RC10 -eq 0 ]] && arrays_equal GOT10 EXPECTED10 && [[ ! -e "$FD_PATH_FILE10" ]]; then
    ok "bundled exec skips --args for an empty options array"
else
    fail "bundled exec empty-array path mismatch (rc=$RC10)"
fi

# Test 11: proxy branch expands --args, propagates status, cleans up once, keeps stdin
ARGS_FILE11="${TMPDIR_TEST}/args11"
STDIN_FILE11="${TMPDIR_TEST}/stdin11"
CLEANUP_FILE11="${TMPDIR_TEST}/cleanup11"
PAYLOAD11=$'bundled-proxy-stdin'
: > "$CLEANUP_FILE11"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
unset FAKE_BWRAP_ARGS_FD_PATH_FILE FAKE_BWRAP_CMDLINE_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE11"
export FAKE_BWRAP_STDIN_FILE="$STDIN_FILE11"
export FAKE_BWRAP_EXIT=7
export FAKE_CLEANUP_FILE="$CLEANUP_FILE11"
B_OPTS11=( --setenv SECRET value )
B_CMD11=( /usr/bin/app "cmd arg" )
printf '%s' "$PAYLOAD11" | run_bwrap_exec_bundled_proxy "${B_OPTS11[@]}" -- "${B_CMD11[@]}"
RC11=$?
GOT11=()
read_args "$ARGS_FILE11" GOT11
EXPECTED11=( "${B_OPTS11[@]}" -- "${B_CMD11[@]}" )
CLEANUP_COUNT11=$(grep -c '^cleanup$' "$CLEANUP_FILE11" 2>/dev/null || echo 0)
if [[ $RC11 -eq 7 ]] &&
   arrays_equal GOT11 EXPECTED11 &&
   [[ "$(cat "$STDIN_FILE11")" == "$PAYLOAD11" ]] &&
   [[ "$CLEANUP_COUNT11" -eq 1 ]]; then
    ok "bundled proxy branch forwards args/stdin, propagates status, cleans up once"
else
    fail "bundled proxy branch (rc=$RC11, cleanup=$CLEANUP_COUNT11)"
fi

# Test 12: no private staging directory fails closed without running bwrap
ARGS_FILE12="${TMPDIR_TEST}/args12"
rm -f -- "$ARGS_FILE12"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
unset FAKE_BWRAP_ARGS_FD_PATH_FILE FAKE_BWRAP_CMDLINE_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE12"
export FAKE_BWRAP_EXIT=0
(
    trap - EXIT
    export PATH="${FAKEBIN}:${PATH}"
    _BWRAP_DBUS_PROXY_PIDS=()
    _BWRAP_DBUS_PROXY_SOCKETS=()
    _BWRAP_ARGS_FDS=()
    _BWRAP_SECCOMP_REFRESH_FDS=()
    _BWRAP_EXEC_BUNDLED=0
    XDG_RUNTIME_DIR="${TMPDIR_TEST}/missing-runtime"
    TMPDIR="${TMPDIR_TEST}/missing-tmp"
    bwrap_exec_bundled
    bwrap_exec --ro-bind /usr -- /usr/bin/app
) 2>/dev/null
RC12=$?
if [[ $RC12 -eq 1 && ! -e "$ARGS_FILE12" ]]; then
    ok "bundled exec fails closed when no private staging directory exists"
else
    fail "bundled exec fail-closed path (rc=$RC12)"
fi

# Test 13: bundled mode requires -- before the command
ARGS_FILE13="${TMPDIR_TEST}/args13"
rm -f -- "$ARGS_FILE13"
unset FAKE_BWRAP_ARGS_FILE FAKE_BWRAP_STDIN_FILE FAKE_BWRAP_EXIT FAKE_CLEANUP_FILE
unset FAKE_BWRAP_ARGS_FD_PATH_FILE FAKE_BWRAP_CMDLINE_FILE
export FAKE_BWRAP_ARGS_FILE="$ARGS_FILE13"
(
    trap - EXIT
    export PATH="${FAKEBIN}:${PATH}"
    _BWRAP_DBUS_PROXY_PIDS=()
    _BWRAP_DBUS_PROXY_SOCKETS=()
    _BWRAP_ARGS_FDS=()
    _BWRAP_SECCOMP_REFRESH_FDS=()
    _BWRAP_EXEC_BUNDLED=0
    bwrap_exec_bundled
    bwrap_exec --ro-bind /usr /usr/bin/app
) 2>/dev/null
RC13=$?
if [[ $RC13 -eq 2 && ! -e "$ARGS_FILE13" ]]; then
    ok "bundled mode requires -- before the command"
else
    fail "bundled mode missing -- (rc=$RC13)"
fi

# Test 14: a consumed seccomp descriptor is refreshed for the next run in both
# flat and bundled modes.
SECCOMP_LEN14_FLAT="${TMPDIR_TEST}/seccomp-len14-flat"
SECCOMP_LEN14_BUNDLED="${TMPDIR_TEST}/seccomp-len14-bundled"
rm -f -- "$SECCOMP_LEN14_FLAT" "$SECCOMP_LEN14_BUNDLED"
SECCOMP_SIZE14=$(stat -c %s "$SECCOMP_FIXTURE_BLOB")
exec {SECCOMP_FD14}< "$SECCOMP_FIXTURE_BLOB"
_BWRAP_SECCOMP_FDS=("$SECCOMP_FD14")
_BWRAP_SECCOMP_REFRESH_FDS=()
cat <&"$SECCOMP_FD14" > /dev/null
export FAKE_BWRAP_SECCOMP_LEN_FILE="$SECCOMP_LEN14_FLAT"
run_bwrap_exec --seccomp "$SECCOMP_FD14" -- /usr/bin/app < /dev/null
RC14_FLAT=$?
export FAKE_BWRAP_SECCOMP_LEN_FILE="$SECCOMP_LEN14_BUNDLED"
run_bwrap_exec_bundled --seccomp "$SECCOMP_FD14" -- /usr/bin/app < /dev/null
RC14_BUNDLED=$?
GOT14_FLAT=$(cat "$SECCOMP_LEN14_FLAT" 2>/dev/null || true)
GOT14_BUNDLED=$(cat "$SECCOMP_LEN14_BUNDLED" 2>/dev/null || true)
exec {SECCOMP_FD14}<&-
_BWRAP_SECCOMP_FDS=()
unset FAKE_BWRAP_SECCOMP_LEN_FILE
if [[ $RC14_FLAT -eq 0 && $RC14_BUNDLED -eq 0 &&
      "$GOT14_FLAT" == "$SECCOMP_SIZE14" &&
      "$GOT14_BUNDLED" == "$SECCOMP_SIZE14" ]]; then
    ok "seccomp descriptors are refreshed for repeated flat and bundled runs"
else
    fail "seccomp refresh (flat=$RC14_FLAT/$GOT14_FLAT, bundled=$RC14_BUNDLED/$GOT14_BUNDLED, want=$SECCOMP_SIZE14)"
fi

