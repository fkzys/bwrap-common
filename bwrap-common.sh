#!/usr/bin/env bash
# Common bubblewrap helpers
#
# Source directly:
#   . /usr/lib/bwrap-common/bwrap-common.sh
#
# Source with verify-lib (recommended):
#   _src() { local p; p=$(verify-lib "$1" "$2") && . "$p" || exit 1; }
#   _src /usr/lib/bwrap-common/bwrap-common.sh /usr/lib/bwrap-common/

VERSION="0.0.4"

[[ -n "${_BWRAP_COMMON_LOADED:-}" ]] && return 0
_BWRAP_COMMON_LOADED=1

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ── Validation ───────────────────────────────────────────────
require_dir() {
    local _d
    for _d in "$@"; do
        [[ -d "$_d" ]] || { echo "Missing dir: $_d" >&2; exit 1; }
    done
}

# ── Common base bwrap args ────────────────────────────────────
bwrap_base() {
    local -n _arr=$1
    _arr+=(
        --ro-bind /usr /usr
        --symlink /usr/bin /bin
        --symlink /usr/bin /sbin
        --symlink /usr/lib /lib
        --proc /proc
        --ro-bind /sys /sys
        --dev /dev
        --tmpfs /tmp
        --dev-bind /dev/shm /dev/shm
        --ro-bind /etc /etc
    )
}

# ── GPU + NVIDIA ──────────────────────────────────────────────
bwrap_gpu() {
    local -n _arr=$1
    [[ -d /dev/dri ]] && _arr+=(--dev-bind /dev/dri /dev/dri)
    local dev
    for dev in /dev/nvidia{0,1,2,3,ctl,-modeset,-uvm,-uvm-tools}; do
        [[ -e "$dev" ]] && _arr+=(--dev-bind "$dev" "$dev")
    done
    [[ -d /dev/nvidia-caps ]] && _arr+=(--dev-bind /dev/nvidia-caps /dev/nvidia-caps)
    :
}

# ── /usr/lib64 + symlinks ─────────────────────────────────────
bwrap_lib64() {
    local -n _arr=$1
    if [[ -d /usr/lib64 && ! -L /usr/lib64 ]]; then
        _arr+=(--ro-bind /usr/lib64 /usr/lib64 --symlink /usr/lib64 /lib64)
    else
        _arr+=(--symlink /usr/lib /lib64)
    fi
}

# ── resolv.conf (often symlink into /run) ─────────────────────
bwrap_resolv() {
    local -n _arr=$1
    if [[ -L /etc/resolv.conf ]]; then
        local _rd
        _rd="$(dirname "$(realpath /etc/resolv.conf)")"
        _arr+=(--ro-bind "$_rd" "$_rd")
    fi
}

# ── Wayland (native, connect() needs write) ───────────────────
bwrap_wayland() {
    local -n _arr=$1
    local _wl="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY:-wayland-1}"
    if [[ -S "$_wl" ]]; then
        _arr+=(
            --bind "$_wl" "$_wl"
            --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-wayland-1}"
        )
        [[ -f "${_wl}.lock" ]] && _arr+=(--ro-bind "${_wl}.lock" "${_wl}.lock")
    fi
}

# ── X11 / XWayland ────────────────────────────────────────────
bwrap_x11() {
    local -n _arr=$1
    if [[ -n "${DISPLAY:-}" ]]; then
        [[ -d /tmp/.X11-unix ]] && _arr+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
        _arr+=(--setenv DISPLAY "${DISPLAY}")
        if [[ -n "${XAUTHORITY:-}" && -f "${XAUTHORITY}" ]]; then
            _arr+=(--ro-bind "${XAUTHORITY}" "${XAUTHORITY}" --setenv XAUTHORITY "${XAUTHORITY}")
        elif [[ -f "${HOME}/.Xauthority" ]]; then
            _arr+=(--ro-bind "${HOME}/.Xauthority" "${HOME}/.Xauthority" \
                   --setenv XAUTHORITY "${HOME}/.Xauthority")
        fi
    fi
}

# ── Audio (PipeWire + PulseAudio) ─────────────────────────────
bwrap_audio() {
    local -n _arr=$1
    [[ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]] && \
        _arr+=(--bind "${XDG_RUNTIME_DIR}/pipewire-0" "${XDG_RUNTIME_DIR}/pipewire-0")
    [[ -d "${XDG_RUNTIME_DIR}/pulse" ]] && \
        _arr+=(--bind "${XDG_RUNTIME_DIR}/pulse" "${XDG_RUNTIME_DIR}/pulse")
    :
}

# ── D-Bus session (unfiltered) ────────────────────────────────
bwrap_dbus_session() {
    local -n _arr=$1
    local _bus="${DBUS_SESSION_BUS_ADDRESS:-}"
    if [[ "$_bus" == unix:path=* ]]; then
        local _bus_path="${_bus#unix:path=}"
        if [[ -S "$_bus_path" ]]; then
            _arr+=(
                --bind "$_bus_path" "$_bus_path"
                --setenv DBUS_SESSION_BUS_ADDRESS "$_bus"
            )
        fi
    elif [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
        _arr+=(
            --bind "${XDG_RUNTIME_DIR}/bus" "${XDG_RUNTIME_DIR}/bus"
            --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=${XDG_RUNTIME_DIR}/bus"
        )
    fi
}

# ── D-Bus system ──────────────────────────────────────────────
bwrap_dbus_system() {
    local -n _arr=$1
    if [[ -S /run/dbus/system_bus_socket ]]; then
        _arr+=(
            --perms 0755 --dir /run
            --perms 0755 --dir /run/dbus
            --bind /run/dbus/system_bus_socket /run/dbus/system_bus_socket
        )
    fi
}

# ── Optional read-only home paths (themes, fonts, Qt) ─────────
bwrap_themes() {
    local -n _arr=$1
    local p
    for p in \
        "${HOME}/.gtkrc-2.0" \
        "${HOME}/.config/gtk-2.0" \
        "${HOME}/.config/dconf" \
        "${HOME}/.config/fontconfig" \
        "${HOME}/.config/qt6ct" \
        "${HOME}/.config/qt5ct" \
        "${HOME}/.config/gtk-3.0" \
        "${HOME}/.config/Kvantum" \
        "${HOME}/.local/share/fonts" \
        "${HOME}/.local/share/icons" \
        "${HOME}/.icons"; do
        [[ -e "$p" ]] && _arr+=(--ro-bind "$p" "$p")
    done
    :
}

# ── Resolve file arguments to bind mounts ─────────────────────
bwrap_resolve_files() {
    local -n _binds=$1
    local -n _args=$2
    local _mode="${3:---ro-bind}"
    shift 3
    local arg
    for arg in "$@"; do
        if [[ "$arg" != -* && -e "$arg" ]]; then
            local _real _dir
            _real="$(realpath "$arg")"
            _dir="$(dirname "$_real")"
            case "$_dir" in
                /usr/*|/etc/*|/proc/*|/dev/*|/tmp*|/sys/*) ;;
                "${HOME}")
                    _binds+=("$_mode" "$_real" "$_real")
                    ;;
                *) _binds+=("$_mode" "$_dir" "$_dir") ;;
            esac
            _args+=("$_real")
        else
            _args+=("$arg")
        fi
    done
}

# ── Common home tmpfs skeleton ────────────────────────────────
bwrap_home_tmpfs() {
    local -n _arr=$1
    _arr+=(
        --tmpfs "${HOME}"
        --perms 0700 --dir "${HOME}/.config"
        --perms 0700 --dir "${HOME}/.local"
        --perms 0700 --dir "${HOME}/.local/share"
        --perms 0700 --dir "${HOME}/.local/state"
        --perms 0700 --dir "${HOME}/.cache"
    )
}

# ── XDG_RUNTIME_DIR setup ────────────────────────────────────
bwrap_runtime_dir() {
    local -n _arr=$1
    _arr+=(--perms 0755 --dir /run/user
           --perms 0700 --dir "${XDG_RUNTIME_DIR}")
}

# ── Common env vars ───────────────────────────────────────────
bwrap_env_base() {
    local -n _arr=$1
    _arr+=(
        --setenv HOME "${HOME}"
        --setenv LANG "${LANG:-en_US.UTF-8}"
        --setenv PATH "/usr/bin:/bin"
        --setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}"
        --setenv XDG_CACHE_HOME "${HOME}/.cache"
    )
}

# ── Create state dirs on host + bind-mount ────────────────────
bwrap_bind_dir() {
    local -n _arr=$1
    shift
    local _d
    for _d in "$@"; do
        mkdir -p "$_d"
        _arr+=(--bind "$_d" "$_d")
    done
}

# Bind pre-existing dirs read-only, skip missing
bwrap_ro_bind_dir() {
    local -n _arr=$1
    shift
    local _d
    for _d in "$@"; do
        [[ -d "$_d" ]] && _arr+=(--ro-bind "$_d" "$_d")
    done
    :
}

# ── hardened_malloc ───────────────────────────────────────────
bwrap_hardened_malloc() {
    local -n _arr=$1
    local _variant="${2:-light}"
    local _lib="/usr/local/lib/libhardened_malloc.so"
    if [[ "$_variant" == "light" ]]; then
        _lib="/usr/local/lib/libhardened_malloc-light.so"
    fi
    [[ -f "$_lib" ]] && _arr+=(--setenv LD_PRELOAD "$_lib")
    :
}

bwrap_no_hardened_malloc() {
    local -n _arr=$1
    _arr+=(--unsetenv LD_PRELOAD
           --ro-bind /dev/null /etc/ld.so.preload)
}

# ── Common sandbox flags ─────────────────────────────────────
bwrap_sandbox() {
    local -n _arr=$1
    local _net="${2:-no}"
    local _new_session="${3:-yes}"
    _arr+=(--unshare-all)
    [[ "$_net" == "yes" ]] && _arr+=(--share-net)
    [[ "$_new_session" == "yes" ]] && _arr+=(--new-session)
    _arr+=(--die-with-parent)
}

# ── fcitx5 input method ──────────────────────────────────────
bwrap_fcitx() {
    local -n _arr=$1
    _arr+=(
        --setenv QT_IM_MODULE fcitx
        --setenv XMODIFIERS "@im=fcitx"
    )
    [[ -d "${HOME}/.config/fcitx5" ]] && \
        _arr+=(--ro-bind "${HOME}/.config/fcitx5" "${HOME}/.config/fcitx5")
    local sock
    for sock in /tmp/fcitx5-*; do
        [[ -e "$sock" ]] && _arr+=(--bind "$sock" "$sock")
    done
    :
}

# ── SSH agent forwarding ─────────────────────────────────────
bwrap_ssh_agent() {
    local -n _arr=$1
    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
        _arr+=(--bind "${SSH_AUTH_SOCK}" "${SSH_AUTH_SOCK}"
               --setenv SSH_AUTH_SOCK "${SSH_AUTH_SOCK}")
    fi
}

# ── Standard GUI sandbox: setup phase ─────────────────────────
bwrap_gui_setup() {
    local _v=$1 _net="${2:-no}"
    bwrap_base "$_v"
    bwrap_lib64 "$_v"
    bwrap_gpu "$_v"
    [[ "$_net" == "yes" ]] && bwrap_resolv "$_v"
    bwrap_runtime_dir "$_v"
    bwrap_home_tmpfs "$_v"
    :
}

# ── Standard GUI sandbox: finish phase ────────────────────────
# $4 = malloc variant (default/light/no)
# $5 = dbus mode: "unfiltered" (default), "filtered", or "none"
bwrap_gui_finish() {
    local _v=$1 _display="${2:-wayland}" _net="${3:-no}" _malloc="${4:-default}" _dbus="${5:-unfiltered}"
    bwrap_themes "$_v"
    if [[ "$_display" == "x11" ]]; then
        bwrap_x11 "$_v"
    else
        bwrap_wayland "$_v"
    fi
    case "$_dbus" in
        filtered)   bwrap_dbus_common "$_v" ;;
        unfiltered) bwrap_dbus_session "$_v" ;;
        none)       ;;
    esac
    bwrap_env_base "$_v"
    if [[ "$_malloc" == "no" ]]; then
        bwrap_no_hardened_malloc "$_v"
    else
        bwrap_hardened_malloc "$_v" "$_malloc"
    fi
    bwrap_sandbox "$_v" "$_net"
}

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
    _gr+=(--talk=org.freedesktop.login1)
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

# Start xdg-dbus-proxy with filter rules, bind socket into sandbox.
# Must be paired with bwrap_exec (not raw `exec bwrap`).
bwrap_dbus_filtered() {
    local _arrname="$1"; shift
    local -n _df="$_arrname"

    local bus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    if [[ -z "$bus_addr" ]]; then
        if [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
            bus_addr="unix:path=${XDG_RUNTIME_DIR}/bus"
        else
            echo "bwrap_dbus_filtered: no session bus found, skipping" >&2
            return 0
        fi
    fi

    if ! command -v xdg-dbus-proxy >/dev/null 2>&1; then
        echo "bwrap_dbus_filtered: xdg-dbus-proxy not found, falling back to unfiltered" >&2
        bwrap_dbus_session "$_arrname"
        return 0
    fi

    local proxy_sock="${XDG_RUNTIME_DIR}/bwrap-dbus-proxy-$$-${RANDOM}.sock"

    xdg-dbus-proxy "$bus_addr" "$proxy_sock" --filter "$@" &
    local proxy_pid=$!
    _BWRAP_DBUS_PROXY_PIDS+=("$proxy_pid")
    _BWRAP_DBUS_PROXY_SOCKETS+=("$proxy_sock")

    trap '_bwrap_dbus_cleanup' EXIT

    local _attempts=0
    while [[ ! -S "$proxy_sock" ]]; do
        if ! kill -0 "$proxy_pid" 2>/dev/null; then
            echo "bwrap_dbus_filtered: proxy exited prematurely" >&2
            return 1
        fi
        if (( ++_attempts > 50 )); then
            echo "bwrap_dbus_filtered: timeout waiting for proxy socket" >&2
            kill "$proxy_pid" 2>/dev/null || true
            return 1
        fi
        sleep 0.1
    done

    _df+=(
        --bind "$proxy_sock" "${XDG_RUNTIME_DIR}/bus"
        --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=${XDG_RUNTIME_DIR}/bus"
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

# Run bwrap as foreground child, clean up proxies on exit.
# Use instead of `exec bwrap` when using bwrap_dbus_filtered.
bwrap_exec() {
    if [[ ${#_BWRAP_DBUS_PROXY_PIDS[@]} -eq 0 ]]; then
        exec bwrap "$@"
    fi

    local _bwrap_pid _rc=0

    bwrap "$@" &
    _bwrap_pid=$!

    _bwrap_on_signal() {
        kill "$_bwrap_pid" 2>/dev/null || true
        wait "$_bwrap_pid" 2>/dev/null || true
        _bwrap_dbus_cleanup
    }
    trap '_bwrap_on_signal; exit 143' TERM
    trap '_bwrap_on_signal; exit 130' INT
    trap '_bwrap_on_signal; exit 129' HUP
    trap '' EXIT

    wait "$_bwrap_pid" || _rc=$?

    _bwrap_dbus_cleanup

    exit "$_rc"
}
