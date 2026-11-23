#!/usr/bin/env bash
# bwrap-common: filtered D-Bus proxy internals.
# Loaded by bwrap-common.sh; do not source directly.
#
# Copyright (C) 2026 fkzys <fkzys@proton.me>
#                    https://github.com/fkzys/bwrap-common
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

_dbus_portal_rules() {
    local -n _pr=$1
    _pr+=(--talk=org.freedesktop.portal.Desktop)
    _pr+=(--talk=org.freedesktop.portal.Documents)
}

_dbus_gui_service_rules() {
    local -n _gr=$1
    _gr+=(--talk=org.freedesktop.Notifications)
    _gr+=(--talk=org.kde.StatusNotifierWatcher)
    _gr+=(--talk=org.freedesktop.ScreenSaver)
    _gr+=(--talk=org.a11y.Bus)
}

_dbus_fcitx5_rules() {
    local -n _fr=$1
    _fr+=(
        --own="org.fcitx.Fcitx5*"
        --talk=org.freedesktop.IBus
    )
}

# Start a filtered xdg-dbus-proxy and wait for its socket.
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
