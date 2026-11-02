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

DBUS_FAKE_BIN="${TMPDIR_TEST}/dbus-fakebin"
mkdir -p "$DBUS_FAKE_BIN"
printf '#!/bin/sh\nexit 0\n' > "${DBUS_FAKE_BIN}/xdg-dbus-proxy"
chmod +x "${DBUS_FAKE_BIN}/xdg-dbus-proxy"

DF=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_dbus_filtered DF 2>/dev/null
DF_RC=$?
[[ $DF_RC -eq 1 ]] && ok "missing xdg-dbus-proxy fails closed" || fail "missing proxy returned $DF_RC"
[[ ${#DF[@]} -eq 0 ]] && ok "missing proxy appends nothing" || fail "missing proxy appended ${DF[*]}"

DNB_RUNTIME="${TMPDIR_TEST}/no-bus-runtime"
mkdir -p "$DNB_RUNTIME"
DNB=()
XDG_RUNTIME_DIR="$DNB_RUNTIME" PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="" bwrap_dbus_filtered DNB 2>/dev/null
DNB_RC=$?
[[ $DNB_RC -eq 0 && ${#DNB[@]} -eq 0 ]] && ok "no session bus is skipped before the proxy check" || fail "no session bus returned $DNB_RC"

DSESS_PROXY_ARGS="${TMPDIR_TEST}/session-filtered-proxy-args"
DSESS_ARRAY="${TMPDIR_TEST}/session-filtered-array"
(
    _bwrap_dbus_proxy_start() {
        printf '%s\n' "$@" > "$DSESS_PROXY_ARGS"
    }
    DS=()
    PATH="${DBUS_FAKE_BIN}:${PATH}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" \
        bwrap_dbus_filtered DS --talk=org.example.Session
    _rc=$?
    : > "$DSESS_ARRAY"
    for _arg in "${DS[@]}"; do
        printf '%s\n' "$_arg" >> "$DSESS_ARRAY"
    done
    exit "$_rc"
)
DS_RC=$?
DSESS_PROXY_LINES=()
[[ -f "$DSESS_PROXY_ARGS" ]] && mapfile -t DSESS_PROXY_LINES < "$DSESS_PROXY_ARGS"
DSESS_LINES=()
[[ -f "$DSESS_ARRAY" ]] && mapfile -t DSESS_LINES < "$DSESS_ARRAY"
if [[ $DS_RC -eq 0 && "${DSESS_PROXY_LINES[0]:-}" == "bwrap_dbus_filtered" &&
      "${DSESS_PROXY_LINES[1]:-}" == "unix:path=/nonexistent" &&
      "${DSESS_PROXY_LINES[2]:-}" == "${XDG_RUNTIME_DIR}/bwrap-dbus-proxy-"*.sock ]]; then
    ok "session filtered resolves address and proxy socket"
else
    fail "session filtered proxy args: ${DSESS_PROXY_LINES[*]:-none} (rc=$DS_RC)"
fi
has_arg DSESS_PROXY_LINES "--talk=org.example.Session" && ok "session filtered forwards rules" || fail "session filtered rules not forwarded"
has_arg DSESS_LINES "${XDG_RUNTIME_DIR}/bus" && ok "session filtered binds the session bus socket" || fail "session filtered missing bus bind"
has_triple DSESS_LINES "--setenv" "DBUS_SESSION_BUS_ADDRESS" "unix:path=${XDG_RUNTIME_DIR}/bus" && ok "session filtered exports the session bus address" || fail "session filtered missing bus env"

DC_RULES_FILE="${TMPDIR_TEST}/dbus-common-rules"
DC_DEFAULT=()
(
    bwrap_dbus_filtered() {
        printf '%s\n' "$@" > "$DC_RULES_FILE"
    }
    bwrap_dbus_common DC_DEFAULT
)
DC_RULES_RC=$?
DC_RULES_LINES=()
[[ -f "$DC_RULES_FILE" ]] && mapfile -t DC_RULES_LINES < "$DC_RULES_FILE"
if [[ $DC_RULES_RC -eq 0 && ${#DC_RULES_LINES[@]} -gt 0 ]]; then
    ok "dbus_common default rules are captured"
else
    fail "dbus_common default rules empty (rc=$DC_RULES_RC)"
fi
has_arg DC_RULES_LINES "--talk=org.freedesktop.portal.Desktop" && ok "dbus_common keeps session portal defaults" || fail "dbus_common missing portal default"
has_arg DC_RULES_LINES "--talk=org.freedesktop.login1" && fail "dbus_common still grants system-bus login1" || ok "dbus_common omits system-bus login1"

DC=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_dbus_common DC 2>/dev/null
DC_RC=$?
[[ $DC_RC -eq 1 && ${#DC[@]} -eq 0 ]] && ok "bwrap_dbus_common propagates the missing proxy error" || fail "bwrap_dbus_common returned $DC_RC"

DGF=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGF wayland no no filtered no none 2>/dev/null
DGF_RC=$?
[[ $DGF_RC -eq 1 ]] && ok "dbus=filtered fails when the proxy is missing" || fail "dbus=filtered returned $DGF_RC"
has_arg DGF "${XDG_RUNTIME_DIR}/bus" && fail "failed dbus=filtered bound the bus socket" || ok "failed dbus=filtered appends no bus bind"
has_arg DGF "DBUS_SESSION_BUS_ADDRESS" && fail "failed dbus=filtered set the bus address" || ok "failed dbus=filtered appends no bus env"

DGD=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGD wayland no no 2>/dev/null
DGD_RC=$?
[[ $DGD_RC -eq 1 ]] && ok "dbus defaults to filtered when the mode is omitted" || fail "default dbus mode returned $DGD_RC"
has_arg DGD "${XDG_RUNTIME_DIR}/bus" && fail "default dbus mode bound the bus socket" || ok "default dbus mode appends no bus bind"
has_arg DGD "DBUS_SESSION_BUS_ADDRESS" && fail "default dbus mode set the bus address" || ok "default dbus mode appends no bus env"

DGN=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGN wayland no no none no none 2>/dev/null
DGN_RC=$?
[[ $DGN_RC -eq 0 ]] && ok "dbus=none ignores a missing proxy" || fail "dbus=none returned $DGN_RC"
has_arg DGN "${XDG_RUNTIME_DIR}/bus" && fail "dbus=none bound the bus socket" || ok "dbus=none appends no bus bind"

DGU=()
PATH="$EMPTY_PATH" DBUS_SESSION_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_gui_finish DGU wayland no no unfiltered no none 2>/dev/null
DGU_RC=$?
[[ $DGU_RC -eq 0 ]] && ok "dbus=unfiltered does not require the proxy" || fail "dbus=unfiltered returned $DGU_RC"

# ── bwrap_dbus_system_filtered ──────────────────────────────

section "bwrap_dbus_system_filtered"

DSF=()
PATH="$EMPTY_PATH" DBUS_SYSTEM_BUS_ADDRESS="$NO_PROXY_ADDR" bwrap_dbus_system_filtered DSF --talk=org.freedesktop.UPower 2>/dev/null
DSF_RC=$?
[[ $DSF_RC -eq 1 && ${#DSF[@]} -eq 0 ]] && ok "system filtered missing proxy fails closed" || fail "system filtered missing proxy returned $DSF_RC"

if [[ ! -S /run/dbus/system_bus_socket ]]; then
    DNS=()
    PATH="$EMPTY_PATH" DBUS_SYSTEM_BUS_ADDRESS="" bwrap_dbus_system_filtered DNS 2>/dev/null
    DNS_RC=$?
    [[ $DNS_RC -eq 0 && ${#DNS[@]} -eq 0 ]] && ok "no system bus is skipped before the proxy check" || fail "no system bus returned $DNS_RC"
fi

DSYS_PROXY_ARGS="${TMPDIR_TEST}/system-filtered-proxy-args"
DSYS_ARRAY="${TMPDIR_TEST}/system-filtered-array"
(
    _bwrap_dbus_proxy_start() {
        printf '%s\n' "$@" > "$DSYS_PROXY_ARGS"
    }
    DSW=()
    PATH="${DBUS_FAKE_BIN}:${PATH}" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent" \
        bwrap_dbus_system_filtered DSW --talk=org.freedesktop.UPower --own=org.example.System
    _rc=$?
    : > "$DSYS_ARRAY"
    for _arg in "${DSW[@]}"; do
        printf '%s\n' "$_arg" >> "$DSYS_ARRAY"
    done
    exit "$_rc"
)
DSW_RC=$?
DSYS_PROXY_LINES=()
[[ -f "$DSYS_PROXY_ARGS" ]] && mapfile -t DSYS_PROXY_LINES < "$DSYS_PROXY_ARGS"
DSYS_LINES=()
[[ -f "$DSYS_ARRAY" ]] && mapfile -t DSYS_LINES < "$DSYS_ARRAY"
if [[ $DSW_RC -eq 0 && "${DSYS_PROXY_LINES[0]:-}" == "bwrap_dbus_system_filtered" &&
      "${DSYS_PROXY_LINES[1]:-}" == "unix:path=/nonexistent" &&
      "${DSYS_PROXY_LINES[2]:-}" == "${XDG_RUNTIME_DIR}/bwrap-system-bus-proxy-"*.sock ]]; then
    ok "system filtered resolves address and proxy socket"
else
    fail "system filtered proxy args: ${DSYS_PROXY_LINES[*]:-none} (rc=$DSW_RC)"
fi
has_arg DSYS_PROXY_LINES "--talk=org.freedesktop.UPower" && ok "system filtered forwards talk rules" || fail "system filtered talk rule not forwarded"
has_arg DSYS_PROXY_LINES "--own=org.example.System" && ok "system filtered forwards own rules" || fail "system filtered own rule not forwarded"
has_arg DSYS_LINES "/run" && ok "system filtered creates /run" || fail "system filtered missing /run"
has_arg DSYS_LINES "/run/dbus" && ok "system filtered creates /run/dbus" || fail "system filtered missing /run/dbus"
has_arg DSYS_LINES "/run/dbus/system_bus_socket" && ok "system filtered binds the system bus socket" || fail "system filtered missing system bus bind"
has_triple DSYS_LINES "--setenv" "DBUS_SYSTEM_BUS_ADDRESS" "unix:path=/run/dbus/system_bus_socket" && ok "system filtered exports the system bus address" || fail "system filtered missing system bus env"

# Real xdg-dbus-proxy is a hard test dependency: these proxy tests must fail,
# not skip, when it is missing.
if ! command -v xdg-dbus-proxy >/dev/null 2>&1; then
    fail "xdg-dbus-proxy is required for the D-Bus proxy tests"
else
    RP_PRESENT="${TMPDIR_TEST}/real-sock-present"
    RP_GONE="${TMPDIR_TEST}/real-sock-gone"
    RP_CMDLINE="${TMPDIR_TEST}/real-proxy-cmdline"
    (
        DSR=()
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent" \
            bwrap_dbus_system_filtered DSR --call=org.freedesktop.UPower=* --talk=org.example.X
        _rc=$?
        _pid="${_BWRAP_DBUS_PROXY_PIDS[${#_BWRAP_DBUS_PROXY_PIDS[@]}-1]:-}"
        _sock="${_BWRAP_DBUS_PROXY_SOCKETS[${#_BWRAP_DBUS_PROXY_SOCKETS[@]}-1]:-}"
        [[ -n "$_pid" && -r "/proc/$_pid/cmdline" ]] && tr '\0' '\n' < "/proc/$_pid/cmdline" > "$RP_CMDLINE"
        [[ -n "$_sock" && -S "$_sock" ]] && : > "$RP_PRESENT"
        _bwrap_dbus_cleanup
        [[ -n "$_sock" && ! -e "$_sock" ]] && : > "$RP_GONE"
        exit "$_rc"
    ) >/dev/null 2>&1
    RP_RC=$?
    RP_LINES=()
    [[ -f "$RP_CMDLINE" ]] && mapfile -t RP_LINES < "$RP_CMDLINE"
    [[ $RP_RC -eq 0 && -f "$RP_PRESENT" ]] && ok "real system proxy start waits for the socket" || fail "real system proxy start rc=$RP_RC"
    has_arg RP_LINES "--filter" && ok "real proxy started with --filter" || fail "real proxy missing --filter"
    has_arg RP_LINES "--call=org.freedesktop.UPower=*" && ok "real proxy receives the call rule" || fail "real proxy missing the call rule"
    has_arg RP_LINES "--talk=org.example.X" && ok "real proxy receives extra rules" || fail "real proxy missing extra rules"
    [[ -f "$RP_GONE" ]] && ok "cleanup removes the proxy socket" || fail "cleanup left the proxy socket"

    # Control is the successful run above: identical bus address, valid
    # --call=NAME=*. This run alone proves only the fail-fast mechanism (early
    # exit, not a socket timeout); the address cannot be the cause, so the bare
    # --call must be, and the two runs together pin the rejection on the rule.
    RP_BAD_ERR="${TMPDIR_TEST}/real-bad-call.err"
    (
        DSRB=()
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent" \
            bwrap_dbus_system_filtered DSRB --call=org.freedesktop.UPower
        exit $?
    ) >/dev/null 2>"$RP_BAD_ERR"
    RP_BAD_RC=$?
    [[ $RP_BAD_RC -eq 1 ]] && ok "real proxy rejects --call=NAME without a rule" || fail "invalid --call unexpectedly accepted (rc=$RP_BAD_RC)"
    if grep -q "proxy exited prematurely" "$RP_BAD_ERR" && ! grep -q "timeout waiting for proxy socket" "$RP_BAD_ERR"; then
        ok "fail-fast: proxy exits early rather than timing out on the socket"
    else
        fail "bare --call did not fail via early proxy exit: $(tr '\n' ' ' < "$RP_BAD_ERR")"
    fi
fi


