#!/usr/bin/env bash
# Common bubblewrap helpers
#
# Source directly:
#   . /usr/lib/bwrap-common/bwrap-common.sh
#
# Source with verify-lib (recommended):
#   _src() { local p; p=$(verify-lib "$1" "$2") && . "$p" || exit 1; }
#   _src /usr/lib/bwrap-common/bwrap-common.sh /usr/lib/bwrap-common/

VERSION="1.0.0"

[[ -n "${_BWRAP_COMMON_LOADED:-}" ]] && return 0

# Set before loading modules so any top-level module code can rely on it.
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Diagnostics; suppressed by BWRAP_QUIET.
_bwrap_warn() {
    [[ -n "${BWRAP_QUIET:-}" ]] && return 0
    printf '%s\n' "$*" >&2
}

# Resolve this file after following symlinks so a symlinked entry point still
# finds its sibling modules.
_bwrap_common_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd) || {
    echo "bwrap-common: cannot resolve library directory from '${BASH_SOURCE[0]}'" >&2
    return 1
}

# Load implementation modules; this file is the only supported entry point.
for _bwrap_module in bwrap-common-seccomp.sh bwrap-common-dbus.sh; do
    if [[ ! -r "${_bwrap_common_dir}/${_bwrap_module}" ]]; then
        echo "bwrap-common: module not found: ${_bwrap_common_dir}/${_bwrap_module}" >&2
        unset -v _bwrap_common_dir _bwrap_module
        return 1
    fi
done
# shellcheck source=./bwrap-common-seccomp.sh disable=SC1091
. "${_bwrap_common_dir}/bwrap-common-seccomp.sh" || { unset -v _bwrap_common_dir _bwrap_module; return 1; }
# shellcheck source=./bwrap-common-dbus.sh disable=SC1091
. "${_bwrap_common_dir}/bwrap-common-dbus.sh" || { unset -v _bwrap_common_dir _bwrap_module; return 1; }
unset -v _bwrap_common_dir _bwrap_module

_BWRAP_COMMON_LOADED=1

# ── Validation ───────────────────────────────────────────────
require_dir() {
    local _d
    for _d in "$@"; do
        [[ -d "$_d" ]] || { echo "Missing dir: $_d" >&2; exit 1; }
    done
}

_bwrap_shm_valid() {
    case "${1:-}" in
        tmpfs|bind) return 0 ;;
        *) return 1 ;;
    esac
}

_bwrap_clearenv_valid() {
    case "${1:-}" in
        yes|no) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Common base bwrap args ────────────────────────────────────
# $2 = shm mode: "tmpfs" or "bind"
# $3 = clear environment: "yes" or "no"
# Default clears inherited environment so only explicit --setenv entries survive.
bwrap_base() {
    local -n _arr=$1
    local _shm="${2:-tmpfs}"
    local _clearenv="${3:-yes}"
    if ! _bwrap_shm_valid "$_shm"; then
        echo "bwrap_base: invalid shm mode '$_shm' (expected tmpfs or bind)" >&2
        return 2
    fi
    if ! _bwrap_clearenv_valid "$_clearenv"; then
        echo "bwrap_base: invalid clearenv mode '$_clearenv' (expected yes or no)" >&2
        return 2
    fi
    # Prepend: any --setenv already present in the array must run after this.
    if [[ "$_clearenv" == "yes" && "${_arr[0]:-}" != "--clearenv" ]]; then
        _arr=(--clearenv "${_arr[@]}")
    fi
    _arr+=(
        --ro-bind /usr /usr
        --symlink /usr/bin /bin
        --symlink /usr/bin /sbin
        --symlink /usr/lib /lib
        --proc /proc
        --ro-bind /sys /sys
        --dev /dev
        --tmpfs /tmp
    )
    if [[ "$_shm" == "bind" ]]; then
        _arr+=(--bind /dev/shm /dev/shm)
    else
        _arr+=(--perms 1777 --tmpfs /dev/shm)
    fi
    _arr+=(--ro-bind /etc /etc)
}

# ── GPU + NVIDIA ──────────────────────────────────────────────
bwrap_gpu() {
    local -n _arr=$1
    local _found=0 dev
    [[ -d /dev/dri ]] && { _arr+=(--dev-bind /dev/dri /dev/dri); _found=1; }
    for dev in /dev/nvidia{0,1,2,3,ctl,-modeset,-uvm,-uvm-tools}; do
        [[ -e "$dev" ]] && { _arr+=(--dev-bind "$dev" "$dev"); _found=1; }
    done
    [[ -d /dev/nvidia-caps ]] && { _arr+=(--dev-bind /dev/nvidia-caps /dev/nvidia-caps); _found=1; }
    (( _found )) || _bwrap_warn "bwrap_gpu: no GPU device nodes found (/dev/dri, /dev/nvidia*)"
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
    [[ -L /etc/resolv.conf ]] || return 0
    local _real _rd
    _real="$(realpath /etc/resolv.conf 2>/dev/null)" || {
        _bwrap_warn "bwrap_resolv: cannot resolve /etc/resolv.conf; skipping"
        return 0
    }
    _rd="$(dirname "$_real")"
    if [[ -n "$_rd" && "$_rd" != "/" && -d "$_rd" ]]; then
        _arr+=(--ro-bind "$_rd" "$_rd")
    else
        _bwrap_warn "bwrap_resolv: no usable resolver directory ($_rd); skipping"
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
    else
        _bwrap_warn "bwrap_wayland: no Wayland socket at $_wl; skipping"
    fi
}

# ── X11 / XWayland ────────────────────────────────────────────
bwrap_x11() {
    local -n _arr=$1
    if [[ -z "${DISPLAY:-}" ]]; then
        _bwrap_warn "bwrap_x11: DISPLAY is not set; skipping"
        return 0
    fi
    if [[ -d /tmp/.X11-unix ]]; then
        _arr+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
    else
        _bwrap_warn "bwrap_x11: /tmp/.X11-unix not found; X11 socket not bound"
    fi
    _arr+=(--setenv DISPLAY "${DISPLAY}")
    if [[ -n "${XAUTHORITY:-}" && -f "${XAUTHORITY}" ]]; then
        _arr+=(--ro-bind "${XAUTHORITY}" "${XAUTHORITY}" --setenv XAUTHORITY "${XAUTHORITY}")
    elif [[ -f "${HOME}/.Xauthority" ]]; then
        _arr+=(--ro-bind "${HOME}/.Xauthority" "${HOME}/.Xauthority" \
               --setenv XAUTHORITY "${HOME}/.Xauthority")
    fi
}

# ── Audio (PipeWire + PulseAudio) ─────────────────────────────
bwrap_audio() {
    local -n _arr=$1
    local _found=0
    [[ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]] && {
        _arr+=(--bind "${XDG_RUNTIME_DIR}/pipewire-0" "${XDG_RUNTIME_DIR}/pipewire-0")
        _found=1
    }
    [[ -d "${XDG_RUNTIME_DIR}/pulse" ]] && {
        _arr+=(--bind "${XDG_RUNTIME_DIR}/pulse" "${XDG_RUNTIME_DIR}/pulse")
        _found=1
    }
    (( _found )) || _bwrap_warn "bwrap_audio: no PipeWire or PulseAudio socket found"
    :
}

# ── unfiltered D-Bus session ──────────────────────────────────
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
        else
            _bwrap_warn "bwrap_dbus_session: session bus socket not found: $_bus_path"
        fi
    elif [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
        _arr+=(
            --bind "${XDG_RUNTIME_DIR}/bus" "${XDG_RUNTIME_DIR}/bus"
            --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=${XDG_RUNTIME_DIR}/bus"
        )
    else
        _bwrap_warn "bwrap_dbus_session: no session bus found; skipping"
    fi
}

# ── system D-Bus ──────────────────────────────────────────────
bwrap_dbus_system() {
    local -n _arr=$1
    if [[ -S /run/dbus/system_bus_socket ]]; then
        _arr+=(
            --perms 0755 --dir /run
            --perms 0755 --dir /run/dbus
            --bind /run/dbus/system_bus_socket /run/dbus/system_bus_socket
        )
    else
        _bwrap_warn "bwrap_dbus_system: no system bus found; skipping"
    fi
}

# ── filtered D-Bus proxy ─────────────────────────────────────
# Start a filtered session bus proxy and bind its socket into the sandbox.
# Must be paired with bwrap_exec.
bwrap_dbus_filtered() {
    local _arrname="$1"; shift
    local -n _df="$_arrname"

    local bus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    if [[ -z "$bus_addr" ]]; then
        if [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
            bus_addr="unix:path=${XDG_RUNTIME_DIR}/bus"
        else
            _bwrap_warn "bwrap_dbus_filtered: no session bus found, skipping"
            return 0
        fi
    fi

    if ! command -v xdg-dbus-proxy >/dev/null 2>&1; then
        echo "bwrap_dbus_filtered: xdg-dbus-proxy not found (required for filtered D-Bus)" >&2
        return 1
    fi

    local proxy_sock="${XDG_RUNTIME_DIR}/bwrap-dbus-proxy-$$-${RANDOM}.sock"
    _bwrap_dbus_proxy_start bwrap_dbus_filtered "$bus_addr" "$proxy_sock" "$@" || return $?

    _df+=(
        --bind "$proxy_sock" "${XDG_RUNTIME_DIR}/bus"
        --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=${XDG_RUNTIME_DIR}/bus"
    )
}

# Start a filtered system bus proxy and bind it at the standard system socket.
# Do not combine with bwrap_dbus_system for the same sandbox.
bwrap_dbus_system_filtered() {
    local _arrname="$1"; shift
    local -n _ds="$_arrname"

    local bus_addr="${DBUS_SYSTEM_BUS_ADDRESS:-}"
    if [[ -z "$bus_addr" ]]; then
        if [[ -S /run/dbus/system_bus_socket ]]; then
            bus_addr="unix:path=/run/dbus/system_bus_socket"
        else
            _bwrap_warn "bwrap_dbus_system_filtered: no system bus found, skipping"
            return 0
        fi
    fi

    if ! command -v xdg-dbus-proxy >/dev/null 2>&1; then
        echo "bwrap_dbus_system_filtered: xdg-dbus-proxy not found (required for filtered D-Bus)" >&2
        return 1
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

# ── seccomp filter ───────────────────────────────────────────
# bwrap_seccomp ARRAYNAME MODE [EXTRA_RULE...]
#   none     no seccomp filter
#   default  compile seccomp/default.conf at runtime and cache the result
#   default EXTRA_RULE...
#            compile one combined default + extra blocklist filter; each
#            EXTRA_RULE is a blocklist line ("syscall EPERM|ENOSYS|ALLOW [condition]")
#            merged into the default filter (user rules win on duplicates)
#   <spec>   syscall allowlist (space/comma separated), compiled on first use
#            and cached like the other filters
# Filters are cached under BWRAP_SECCOMP_CACHE_DIR.  If the cache is
# unavailable the generator runs into a temporary file in XDG_RUNTIME_DIR
# which is opened and unlinked immediately; when that is unavailable
# too, the function fails closed.
# Env vars:
#   BWRAP_SECCOMP_CONF       default blocklist source (${BWRAP_SECCOMP_DIR}/default.conf)
#   BWRAP_SECCOMP_DIR        default seccomp source dir (/usr/lib/bwrap-common/seccomp)
#   BWRAP_SECCOMP_GEN        rule compiler (/usr/lib/bwrap-common/bwrap-seccomp-gen)
#   BWRAP_SECCOMP_CACHE_DIR  compiled filter cache (~/.cache/bwrap-common/seccomp)
#   BWRAP_SECCOMP_ARCH       override uname -m (cross-arch testing)
bwrap_seccomp() {
    local _arrname="$1" _mode="$2"
    case "$_mode" in
        none)
            return 0
            ;;
        default)
            _bwrap_seccomp_default "$_arrname" "${@:3}"
            return $?
            ;;
        *)
            _bwrap_seccomp_allowlist "$_arrname" "$_mode"
            return $?
            ;;
    esac
}

# ── Optional read-only home paths ─────────
bwrap_themes() {
    local -n _arr=$1
    local p _found=0
    for p in \
        "${HOME}/.gtkrc-2.0" \
        "${HOME}/.config/gtk-2.0" \
        "${HOME}/.config/dconf" \
        "${HOME}/.config/fontconfig" \
        "${HOME}/.config/qt6ct" \
        "${HOME}/.config/qt5ct" \
        "${HOME}/.config/gtk-3.0" \
        "${HOME}/.config/gtk-4.0" \
        "${HOME}/.config/Kvantum" \
        "${HOME}/.local/share/fonts" \
        "${HOME}/.local/share/icons" \
        "${HOME}/.icons"; do
        [[ -e "$p" ]] && { _arr+=(--ro-bind "$p" "$p"); _found=1; }
    done
    (( _found )) || _bwrap_warn "bwrap_themes: no theme/config paths found"
    :
}

_bwrap_is_home_or_ancestor() {
    local _home=$1 _path=$2
    [[ -n "$_home" && ( "$_path" == "$_home" || "$_home" == "$_path"/* ) ]]
}

# Resolve file arguments to bind mounts.
# Usage: bwrap_resolve_files BINDS_ARRAY ARGS_ARRAY [LAYOUT] [MODE] ARG...
#   LAYOUT  leaf (default) mounts each argument itself; parent mounts the
#           directory containing it (legacy behavior). Both refuse the
#           filesystem root, HOME, and HOME's ancestors; parent falls back to
#           the argument when the containing directory would expose them.
#   MODE    --ro-bind (default), --bind, --dev-bind, --*-try
#   Returns 1 when a non-try bind is refused for HOME/ancestor; -try modes
#   still return 0.
bwrap_resolve_files() {
    local -n _binds=$1
    local -n _args=$2
    shift 2
    local _mode="--ro-bind"
    local _layout="leaf"
    while (( $# > 0 )); do
        case "$1" in
            --)
                shift; break ;;
            --layout=*)
                _layout=${1#--layout=}; shift ;;
            --layout)
                shift
                _layout=${1:-}
                if [[ -z "$_layout" ]]; then
                    echo "bwrap_resolve_files: --layout needs leaf or parent" >&2
                    return 2
                fi
                shift ;;
            --ro-bind|--bind|--dev-bind|--ro-bind-try|--bind-try|--dev-bind-try)
                _mode=$1; shift ;;
            *) break ;;
        esac
    done
    case "$_layout" in
        leaf|parent) ;;
        *)
            echo "bwrap_resolve_files: unknown layout: $_layout" >&2
            return 2 ;;
    esac
    # HOME can be a symlink (/home -> /var/home), while targets are resolved
    # with realpath; compare against the physical path.
    local _home_real=""
    if [[ -n "${HOME:-}" ]]; then
        _home_real="$(realpath -m -- "$HOME" 2>/dev/null)" || _home_real=""
        [[ -n "$_home_real" ]] || _home_real=$HOME
    fi
    local _refused=0 arg
    for arg in "$@"; do
        if [[ "$arg" == -* ]]; then
            _args+=("$arg")
        elif [[ -e "$arg" ]]; then
            local _real _dir
            _real="$(realpath "$arg")"
            if [[ "$_layout" == "parent" ]]; then
                _dir="$(dirname "$_real")"
                case "$_dir" in
                    /)
                        # A depth-1 path resolves to the filesystem root; binding
                        # it would expose the whole host root, so refuse it.
                        _bwrap_warn "bwrap_resolve_files: refusing to bind the filesystem root for: $arg"
                        ;;
                    /usr|/usr/*|/etc|/etc/*|/proc|/proc/*|/dev|/dev/*|/tmp|/tmp/*|/sys|/sys/*) ;;
                    *)
                        if _bwrap_is_home_or_ancestor "$_home_real" "$_dir"; then
                            if _bwrap_is_home_or_ancestor "$_home_real" "$_real"; then
                                _bwrap_warn "bwrap_resolve_files: refusing to bind HOME or an ancestor for: $arg"
                                _refused=1
                            else
                                _binds+=("$_mode" "$_real" "$_real")
                            fi
                        else
                            _binds+=("$_mode" "$_dir" "$_dir")
                        fi
                        ;;
                esac
            else
                case "$_real" in
                    /)
                        _bwrap_warn "bwrap_resolve_files: refusing to bind the filesystem root for: $arg"
                        ;;
                    /usr|/usr/*|/etc|/etc/*|/proc|/proc/*|/dev|/dev/*|/tmp|/tmp/*|/sys|/sys/*) ;;
                    *)
                        # Binding HOME or one of its ancestors exposes the whole
                        # home tree (and siblings) regardless of the bind mode.
                        # Descendants such as HOME/projects remain valid targets.
                        if _bwrap_is_home_or_ancestor "$_home_real" "$_real"; then
                            _bwrap_warn "bwrap_resolve_files: refusing to bind HOME or an ancestor for: $arg"
                            _refused=1
                        else
                            _binds+=("$_mode" "$_real" "$_real")
                        fi
                        ;;
                esac
            fi
            _args+=("$_real")
        else
            case "$arg" in
                /*|./*|../*) _bwrap_warn "bwrap_resolve_files: not found, left as-is: $arg" ;;
            esac
            _args+=("$arg")
        fi
    done
    if (( _refused )) && [[ "$_mode" != *-try ]]; then
        return 1
    fi
    return 0
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
        --setenv TERM "${TERM:-xterm-256color}"
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

# Bind pre-existing dirs read-only
bwrap_ro_bind_dir() {
    local -n _arr=$1
    shift
    local _d
    for _d in "$@"; do
        if [[ -d "$_d" ]]; then
            _arr+=(--ro-bind "$_d" "$_d")
        else
            _bwrap_warn "bwrap_ro_bind_dir: skipping missing directory: $_d"
        fi
    done
    :
}

# ── hardened_malloc ───────────────────────────────────────────
bwrap_hardened_malloc() {
    local -n _arr=$1
    local _variant="${2:-default}"
    local _lib="/usr/lib/libhardened_malloc.so"
    if [[ "$_variant" == "light" ]]; then
        _lib="/usr/lib/libhardened_malloc-light.so"
    fi
    if [[ ! -f "$_lib" ]]; then
        echo "bwrap_hardened_malloc: hardened_malloc library not found: $_lib" >&2
        return 1
    fi
    _arr+=(--setenv LD_PRELOAD "$_lib")
}

bwrap_no_hardened_malloc() {
    local -n _arr=$1
    local _stub="/usr/lib/libhardened_malloc.so.empty"
    local _variant
    [[ -f "$_stub" ]] || return 0
    for _variant in /usr/lib/libhardened_malloc-light.so /usr/lib/libhardened_malloc.so; do
        [[ -e "$_variant" ]] && _arr+=(--ro-bind "$_stub" "$_variant")
    done
    :
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

# Internal: run cleanup, then the caller's original EXIT trap.
_bwrap_exit_trap() {
    local _status=$?
    local _previous="${_BWRAP_PREVIOUS_EXIT_TRAP:-}"
    _bwrap_cleanup
    if [[ -n "$_previous" ]]; then
        (exit "$_status")
        eval "$_previous"
    fi
    exit "$_status"
}

# Internal: install cleanup without dropping an existing EXIT trap.
_bwrap_install_cleanup() {
    local _current _previous
    _current=$(trap -p EXIT)
    if [[ "$_current" == *"_bwrap_exit_trap"* || "$_current" == *"_bwrap_cleanup"* ]]; then
        return 0
    fi

    # Capture the caller's trap without slicing trap -p output.
    # The temporary trap() function receives the command as $2 when eval parses the builtin's output.
    # It does not execute the caller's command.
    _previous=$(
        trap() { printf '%s' "$2"; }
        eval "$(builtin trap -p EXIT)"
    )
    _BWRAP_PREVIOUS_EXIT_TRAP="$_previous"
    trap '_bwrap_exit_trap' EXIT
}
# Internal: run pending cleanup: D-Bus proxies, seccomp descriptors, temp files.
_bwrap_cleanup() {
    _bwrap_dbus_cleanup
    _bwrap_seccomp_close_fds
    _bwrap_seccomp_tmp_cleanup
    _bwrap_fcitx_close_fds
}

# ── fcitx5 input method ──────────────────────────────────────
_BWRAP_FCITX_FDS=()

# fcitx5 keeps its socket directory under the caller's own name: /tmp/fcitx5-<euid>
# when XDG_RUNTIME_DIR is unset, or $XDG_RUNTIME_DIR/fcitx5 otherwise.  These exact
# paths are used instead of a /tmp/fcitx5-* glob so another user's entry is never
# even considered.
_bwrap_fcitx_paths() {
    printf '%s\n' "/tmp/fcitx5-${EUID}"
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s\n' "${XDG_RUNTIME_DIR}/fcitx5"
    fi
}

_bwrap_fcitx_close_fds() {
    local _fd
    if (( ${#_BWRAP_FCITX_FDS[@]} == 0 )); then
        return 0
    fi
    for _fd in "${_BWRAP_FCITX_FDS[@]}"; do
        exec {_fd}<&- 2>/dev/null || true
    done
    _BWRAP_FCITX_FDS=()
}

bwrap_fcitx() {
    local -n _arr=$1
    local -a _out=()
    _out+=(
        --setenv QT_IM_MODULE fcitx
        --setenv XMODIFIERS "@im=fcitx"
    )
    [[ -d "${HOME}/.config/fcitx5" ]] && \
        _out+=(--ro-bind "${HOME}/.config/fcitx5" "${HOME}/.config/fcitx5")
    local sock _fd
    local -a _candidates=() _trusted=()
    mapfile -t _candidates < <(_bwrap_fcitx_paths)
    # Validate every candidate before opening anything, so a refusal leaves
    # _arr untouched; a directory is then bound through --bind-fd so its inode
    # cannot be swapped, and a socket (unopenable from the shell) by path.
    for sock in "${_candidates[@]}"; do
        [[ -S "$sock" || -d "$sock" ]] || continue
        if [[ -L "$sock" || ! -O "$sock" ]]; then
            echo "bwrap_fcitx: refusing untrusted path: $sock" >&2
            return 1
        fi
        _trusted+=("$sock")
    done
    for sock in "${_trusted[@]}"; do
        if [[ -d "$sock" ]]; then
            unset -v _fd
            if ! exec {_fd}< "$sock"; then
                echo "bwrap_fcitx: cannot open $sock for --bind-fd" >&2
                return 1
            fi
            _BWRAP_FCITX_FDS+=("$_fd")
            _out+=(--bind-fd "$_fd" "$sock")
        else
            _out+=(--bind "$sock" "$sock")
        fi
    done
    _arr+=("${_out[@]}")
    :
}

# ── SSH agent forwarding ─────────────────────────────────────
bwrap_ssh_agent() {
    local -n _arr=$1
    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
        _arr+=(--bind "${SSH_AUTH_SOCK}" "${SSH_AUTH_SOCK}"
               --setenv SSH_AUTH_SOCK "${SSH_AUTH_SOCK}")
    else
        _bwrap_warn "bwrap_ssh_agent: SSH_AUTH_SOCK is unset or not a socket; skipping"
    fi
}

# ── Standard GUI sandbox: setup phase ─────────────────────────
# $2 = network: "yes" or "no"
# $3 = GPU: "yes" or "no"
# $4 = shm mode: "tmpfs" or "bind"
# $5 = clear environment: "yes" or "no"
bwrap_gui_setup() {
    local _v=$1 _net="${2:-no}" _gpu="${3:-no}" _shm="${4:-tmpfs}" _clearenv="${5:-yes}"
    if ! _bwrap_shm_valid "$_shm"; then
        echo "bwrap_gui_setup: invalid shm mode '$_shm' (expected tmpfs or bind)" >&2
        return 2
    fi
    if ! _bwrap_clearenv_valid "$_clearenv"; then
        echo "bwrap_gui_setup: invalid clearenv mode '$_clearenv' (expected yes or no)" >&2
        return 2
    fi
    bwrap_base "$_v" "$_shm" "$_clearenv" || return
    bwrap_lib64 "$_v"
    [[ "$_gpu" == "yes" ]] && bwrap_gpu "$_v"
    [[ "$_net" == "yes" ]] && bwrap_resolv "$_v"
    bwrap_runtime_dir "$_v"
    bwrap_home_tmpfs "$_v"
    :
}

# ── Standard GUI sandbox: finish phase ────────────────────────
# $4 = malloc: "default", "light", or "no"
# $5 = dbus mode: "filtered", "unfiltered", or "none"
# $6 = themes: "yes" or "no"
# $7 = seccomp: "default" or "none"
bwrap_gui_finish() {
    local _v=$1 _display="${2:-wayland}" _net="${3:-no}" _malloc="${4:-default}" _dbus="${5:-filtered}" _themes="${6:-yes}" _seccomp="${7:-default}"
    [[ "$_themes" == "yes" ]] && bwrap_themes "$_v"
    if [[ "$_display" == "x11" ]]; then
        bwrap_x11 "$_v"
    else
        bwrap_wayland "$_v"
    fi
    case "$_dbus" in
        filtered)   bwrap_dbus_common "$_v" || return 1 ;;
        unfiltered) bwrap_dbus_session "$_v" ;;
        none)       ;;
    esac
    bwrap_env_base "$_v"
    if [[ "$_malloc" == "no" ]]; then
        bwrap_no_hardened_malloc "$_v"
    else
        bwrap_hardened_malloc "$_v" "$_malloc" || return 1
    fi
    case "$_seccomp" in
        default|none) bwrap_seccomp "$_v" "$_seccomp" || return 1 ;;
        *) echo "bwrap_gui_finish: seccomp must be 'default' or 'none' (call bwrap_seccomp directly for an allowlist)" >&2; return 1 ;;
    esac
    bwrap_sandbox "$_v" "$_net"
}

# Run bwrap as foreground child, clean up proxies on exit.
bwrap_exec() {
    if [[ ${#_BWRAP_DBUS_PROXY_PIDS[@]} -eq 0 ]]; then
        exec bwrap "$@"
    fi

    _bwrap_install_cleanup

    local _bwrap_pid _rc=0

    bwrap "$@" <&0 &
    _bwrap_pid=$!
    _bwrap_seccomp_close_fds
    _bwrap_fcitx_close_fds

    # shellcheck disable=SC2329
    _bwrap_on_signal() {
        kill "$_bwrap_pid" 2>/dev/null || true
        wait "$_bwrap_pid" 2>/dev/null || true
    }
    trap '_bwrap_on_signal; exit 143' TERM
    trap '_bwrap_on_signal; exit 130' INT
    trap '_bwrap_on_signal; exit 129' HUP

    wait "$_bwrap_pid" || _rc=$?

    # Exit through _bwrap_exit_trap so cleanup and the caller's original
    # EXIT trap both run, with the bwrap status preserved.
    exit "$_rc"
}
