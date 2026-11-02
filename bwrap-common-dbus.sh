#!/usr/bin/env bash
# bwrap-common: filtered D-Bus proxy helpers.
# Internal module sourced by bwrap-common.sh; do not source directly.

# ══════════════════════════════════════════════════════════════
# ── D-Bus filtered proxy ─────────────────────────────────────
# ══════════════════════════════════════════════════════════════

_BWRAP_DBUS_PROXY_PIDS=()
_BWRAP_DBUS_PROXY_SOCKETS=()

_bwrap_dbus_cleanup() {
    local pid sock
    for pid in "${_BWRAP_DBUS_PROXY_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    for sock in "${_BWRAP_DBUS_PROXY_SOCKETS[@]}"; do
        rm -f "$sock"
    done
    _BWRAP_DBUS_PROXY_PIDS=()
    _BWRAP_DBUS_PROXY_SOCKETS=()
}

# xdg-dbus-proxy rules: XDG portals
_dbus_portal_rules() {
    local -n _pr=$1
    _pr+=(--talk=org.freedesktop.portal.Desktop)
    _pr+=(--talk=org.freedesktop.portal.Documents)
}

# xdg-dbus-proxy rules: common GUI services
_dbus_gui_service_rules() {
    local -n _gr=$1
    _gr+=(--talk=org.freedesktop.Notifications)
    _gr+=(--talk=org.kde.StatusNotifierWatcher)
    _gr+=(--talk=org.freedesktop.ScreenSaver)
    _gr+=(--talk=org.a11y.Bus)
}

# xdg-dbus-proxy rules: fcitx5 (own bus names)
_dbus_fcitx5_rules() {
    local -n _fr=$1
    _fr+=(
        --own="org.fcitx.Fcitx5*"
        --talk=org.freedesktop.IBus
    )
}

# Internal: start a filtered xdg-dbus-proxy and wait for its socket.
# Usage: _bwrap_dbus_proxy_start LABEL BUS_ADDR PROXY_SOCK [RULES...]
_bwrap_dbus_proxy_start() {
    local _label="$1" _bus_addr="$2" _proxy_sock="$3"
    shift 3

    xdg-dbus-proxy "$_bus_addr" "$_proxy_sock" --filter "$@" &
    local _proxy_pid=$!
    _BWRAP_DBUS_PROXY_PIDS+=("$_proxy_pid")
    _BWRAP_DBUS_PROXY_SOCKETS+=("$_proxy_sock")

    _bwrap_install_cleanup

    local _attempts=0
    while [[ ! -S "$_proxy_sock" ]]; do
        if ! kill -0 "$_proxy_pid" 2>/dev/null; then
            echo "$_label: proxy exited prematurely" >&2
            return 1
        fi
        if (( ++_attempts > 50 )); then
            echo "$_label: timeout waiting for proxy socket" >&2
            kill "$_proxy_pid" 2>/dev/null || true
            return 1
        fi
        sleep 0.1
    done
    return 0
}

# Start a filtered session bus proxy and bind its socket into the sandbox.
# Must be paired with bwrap_exec (not raw `exec bwrap`).
bwrap_dbus_filtered() {
    local _arrname="$1"; shift
    local -n _df="$_arrname"

    if ! command -v xdg-dbus-proxy >/dev/null 2>&1; then
        echo "bwrap_dbus_filtered: xdg-dbus-proxy not found (required for filtered D-Bus)" >&2
        return 1
    fi

    local bus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    if [[ -z "$bus_addr" ]]; then
        if [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
            bus_addr="unix:path=${XDG_RUNTIME_DIR}/bus"
        else
            echo "bwrap_dbus_filtered: no session bus found, skipping" >&2
            return 0
        fi
    fi

    local proxy_sock="${XDG_RUNTIME_DIR}/bwrap-dbus-proxy-$$-${RANDOM}.sock"
    _bwrap_dbus_proxy_start bwrap_dbus_filtered "$bus_addr" "$proxy_sock" "$@" || return $?

    _df+=(
        --bind "$proxy_sock" "${XDG_RUNTIME_DIR}/bus"
        --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=${XDG_RUNTIME_DIR}/bus"
    )
}

# Start a filtered system bus proxy and bind it at the standard system socket.
# RULES are passed to xdg-dbus-proxy; no default rules are loaded.
# Do not combine with bwrap_dbus_system for the same sandbox.
bwrap_dbus_system_filtered() {
    local _arrname="$1"; shift
    local -n _ds="$_arrname"

    if ! command -v xdg-dbus-proxy >/dev/null 2>&1; then
        echo "bwrap_dbus_system_filtered: xdg-dbus-proxy not found (required for filtered D-Bus)" >&2
        return 1
    fi

    local bus_addr="${DBUS_SYSTEM_BUS_ADDRESS:-}"
    if [[ -z "$bus_addr" ]]; then
        if [[ -S /run/dbus/system_bus_socket ]]; then
            bus_addr="unix:path=/run/dbus/system_bus_socket"
        else
            echo "bwrap_dbus_system_filtered: no system bus found, skipping" >&2
            return 0
        fi
    fi

    local proxy_sock="${XDG_RUNTIME_DIR}/bwrap-system-bus-proxy-$$-${RANDOM}.sock"
    _bwrap_dbus_proxy_start bwrap_dbus_system_filtered "$bus_addr" "$proxy_sock" "$@" || return $?

    _ds+=(
        --perms 0755 --dir /run
        --perms 0755 --dir /run/dbus
        --bind "$proxy_sock" /run/dbus/system_bus_socket
        --setenv DBUS_SYSTEM_BUS_ADDRESS "unix:path=/run/dbus/system_bus_socket"
    )
}

# Filtered D-Bus for typical GUI apps (portals + common services).
# Usage: bwrap_dbus_common ARRAYNAME [EXTRA_RULES...]
bwrap_dbus_common() {
    local _arrname="$1"; shift
    local rules=()
    _dbus_portal_rules rules
    _dbus_gui_service_rules rules
    rules+=("$@")
    bwrap_dbus_filtered "$_arrname" "${rules[@]}"
}
