# bwrap-common

[![CI](https://github.com/rpPH4kQocMjkm2Ve/bwrap-common/actions/workflows/ci.yml/badge.svg)](https://github.com/rpPH4kQocMjkm2Ve/bwrap-common/actions/workflows/ci.yml)
![License](https://img.shields.io/github/license/rpPH4kQocMjkm2Ve/bwrap-common)

Reusable bubblewrap sandbox helpers for shell wrappers. Each function
takes an array variable name and appends bwrap arguments to it via nameref.

## Install

### With gitpkg

```sh
gitpkg install bwrap-common
```

### Arch Linux (AUR)

```
yay -S bwrap-common
```

### Manual

```sh
sudo make install
```

### Uninstall

```sh
sudo make uninstall
```

## Usage

Source with [verify-lib](https://gitlab.com/fkzys/verify-lib) to validate
ownership and permissions before loading:

```sh
#!/usr/bin/env bash
set -euo pipefail
_src() { local p; p=$(verify-lib "$1" "$2") && . "$p" || exit 1; }
_src /usr/lib/bwrap-common/bwrap-common.sh /usr/lib/bwrap-common/
```

Or source directly:
```sh
. /usr/lib/bwrap-common/bwrap-common.sh
```

### Wrapper pattern

Typical GUI wrapper using high-level composites:

```sh
A=()
bwrap_gui_setup A yes                    # yes = network (adds resolv)
bwrap_bind_dir A "${HOME}/.config/app" "${HOME}/Data"
bwrap_ro_bind_dir A "${MEDIA_DIR}"
bwrap_audio A
bwrap_gui_finish A wayland yes default filtered  # display, network, malloc, dbus
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

Equivalent using low-level helpers:

```sh
A=()
bwrap_base A
bwrap_lib64 A
bwrap_gpu A
bwrap_resolv A
bwrap_runtime_dir A
bwrap_home_tmpfs A
bwrap_bind_dir A "${HOME}/.config/app" "${HOME}/Data"
bwrap_ro_bind_dir A "${MEDIA_DIR}"
bwrap_themes A
bwrap_wayland A
bwrap_audio A
bwrap_dbus_common A
bwrap_env_base A
bwrap_hardened_malloc A default
bwrap_sandbox A yes
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

## Functions

### Low-level helpers

| Function | Purpose |
|---|---|
| `bwrap_base` | System skeleton (`/usr`, `/etc`, `/proc`, `/sys`, `/dev`, `/tmp`) |
| `bwrap_lib64` | `/usr/lib64` bind or symlink |
| `bwrap_resolv` | resolv.conf symlink target for DNS |
| `bwrap_gpu` | DRI + NVIDIA device nodes |
| `bwrap_wayland` | Wayland socket (rw for `connect()`) |
| `bwrap_x11` | X11/XWayland socket + Xauthority |
| `bwrap_audio` | PipeWire + PulseAudio sockets |
| `bwrap_dbus_session` | Session D-Bus socket (unfiltered) |
| `bwrap_dbus_system` | System D-Bus socket |
| `bwrap_dbus_filtered` | Filtered D-Bus via `xdg-dbus-proxy` with custom rules; falls back to unfiltered if proxy is unavailable |
| `bwrap_dbus_common` | Pre-configured filtered D-Bus for typical GUI apps (XDG portals, notifications, status notifier, screen saver, login1, a11y); accepts extra rules |
| `bwrap_themes` | GTK2/3, dconf, fontconfig, Qt, Kvantum, fonts, icons |
| `bwrap_fcitx` | fcitx5 input method sockets + env |
| `bwrap_home_tmpfs` | tmpfs `$HOME` with XDG skeleton |
| `bwrap_runtime_dir` | XDG_RUNTIME_DIR with correct permissions |
| `bwrap_env_base` | `HOME`, `LANG`, `PATH`, `XDG_RUNTIME_DIR` |
| `bwrap_sandbox` | `--unshare-all`, optional `--share-net` / `--new-session` |
| `bwrap_resolve_files` | Resolve file arguments to bind mounts |
| `bwrap_bind_dir` | Create state dirs on host + add `--bind` |
| `bwrap_ro_bind_dir` | Bind pre-existing dirs read-only, skip missing |
| `bwrap_ssh_agent` | SSH agent socket forwarding |
| `bwrap_hardened_malloc` | Set `LD_PRELOAD` for hardened_malloc (default or light variant) |
| `bwrap_no_hardened_malloc` | Disable hardened_malloc for incompatible apps |
| `bwrap_exec` | Run bwrap as foreground child, clean up D-Bus proxy on exit; falls back to `exec bwrap` when no proxies are active |
| `require_dir` | Validate that directories exist, exit on missing |

### High-level composites

| Function | Purpose |
|---|---|
| `bwrap_gui_setup` | `bwrap_base` + `lib64` + `gpu` + optional `resolv` + `runtime_dir` + `home_tmpfs` |
| `bwrap_gui_finish` | `themes` + `wayland`/`x11` + D-Bus (`unfiltered`/`filtered`/`none`) + `env_base` + malloc + `sandbox` |

### D-Bus filtering

`bwrap_dbus_filtered` starts an `xdg-dbus-proxy` instance with `--filter`
and the provided rules, waits for the proxy socket, and binds it into the
sandbox as `$XDG_RUNTIME_DIR/bus`. Proxy processes are tracked and cleaned
up automatically by `bwrap_exec`.

`bwrap_dbus_common` wraps `bwrap_dbus_filtered` with a default rule set:

| Rule group | Bus names |
|---|---|
| XDG portals | `org.freedesktop.portal.Desktop`, `org.freedesktop.portal.Documents` |
| GUI services | `org.freedesktop.Notifications`, `org.kde.StatusNotifierWatcher`, `org.freedesktop.ScreenSaver`, `org.freedesktop.login1`, `org.a11y.Bus` |

Extra `--talk`/`--own` rules can be appended per-app.

`bwrap_gui_finish` 5th parameter (`dbus` mode):
- `unfiltered` (default) — full session bus access
- `filtered` — `bwrap_dbus_common`
- `none` — no D-Bus access

When using filtered D-Bus, wrappers must call `bwrap_exec` instead of
`exec bwrap` to ensure proxy cleanup.

## Dependencies

- `bubblewrap` (`bwrap`)
- `bash`
- [verify-lib](https://gitlab.com/fkzys/verify-lib) (recommended, for integrity verification before sourcing)
- `xdg-dbus-proxy` (optional, for filtered D-Bus)

## Files

| Path | Purpose |
|---|---|
| `/usr/lib/bwrap-common/bwrap-common.sh` | Library |

## License

AGPL-3.0-or-later
