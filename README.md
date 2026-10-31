# bwrap-common

[![CI](https://github.com/fkzys/bwrap-common/actions/workflows/ci.yml/badge.svg)](https://github.com/fkzys/bwrap-common/actions/workflows/ci.yml)
![License](https://img.shields.io/github/license/fkzys/bwrap-common)
[![Spec](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/fkzys/specs/refs/heads/main/version.json&maxAge=300)](https://github.com/fkzys/specs)

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

`make install` also compiles the seccomp helper and the architecture-specific
default filter, so `gcc` and the `libseccomp` headers are required.

### Uninstall

```sh
sudo make uninstall
```

## Usage

Source with [verify-lib](https://github.com/fkzys/verify-lib) to validate
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
bwrap_gui_setup A yes yes tmpfs          # network, gpu, shm=tmpfs (private; default)
bwrap_bind_dir A "${HOME}/.config/app" "${HOME}/Data"
bwrap_ro_bind_dir A "${MEDIA_DIR}"
bwrap_audio A
bwrap_gui_finish A wayland yes default filtered yes default  # display, network, malloc, dbus, themes, seccomp
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

Equivalent using low-level helpers:

```sh
A=()
bwrap_base A                             # shm=tmpfs by default; use "bind" only if needed
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
bwrap_seccomp A default
bwrap_sandbox A yes
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

## Functions

### Low-level helpers

| Function | Purpose |
|---|---|
| `bwrap_base` | System skeleton (`/usr`, `/etc`, `/proc`, `/sys`, `/dev`, `/tmp`); `$2` selects `shm=tmpfs` (default, private) or `shm=bind` (host `/dev/shm`) |
| `bwrap_lib64` | `/usr/lib64` bind or symlink |
| `bwrap_resolv` | resolv.conf symlink target for DNS |
| `bwrap_gpu` | DRI + NVIDIA device nodes |
| `bwrap_wayland` | Wayland socket (rw for `connect()`) |
| `bwrap_x11` | X11/XWayland socket + Xauthority |
| `bwrap_audio` | PipeWire + PulseAudio sockets |
| `bwrap_dbus_session` | Session D-Bus socket (unfiltered) |
| `bwrap_dbus_system` | System D-Bus socket |
| `bwrap_dbus_filtered` | Filtered D-Bus via `xdg-dbus-proxy` with custom rules; fails if the proxy is unavailable |
| `bwrap_dbus_common` | Pre-configured filtered D-Bus for typical GUI apps (XDG portals, notifications, status notifier, screen saver, login1, a11y); accepts extra rules |
| `bwrap_themes` | GTK2/3, dconf, fontconfig, Qt, Kvantum, fonts, icons |
| `bwrap_fcitx` | fcitx5 input method sockets + env |
| `bwrap_home_tmpfs` | tmpfs `$HOME` with XDG skeleton |
| `bwrap_runtime_dir` | XDG_RUNTIME_DIR with correct permissions |
| `bwrap_env_base` | `HOME`, `LANG`, `PATH`, `XDG_RUNTIME_DIR` |
| `bwrap_sandbox` | `--unshare-all`, optional `--share-net` / `--new-session` |
| `bwrap_seccomp` | Add `--seccomp` from the precompiled default blocklist or a compiled syscall allowlist |
| `bwrap_resolve_files` | Resolve file arguments to bind mounts |
| `bwrap_bind_dir` | Create state dirs on host + add `--bind` |
| `bwrap_ro_bind_dir` | Bind pre-existing dirs read-only, skip missing |
| `bwrap_ssh_agent` | SSH agent socket forwarding |
| `bwrap_hardened_malloc` | Set `LD_PRELOAD` for hardened_malloc (default or light variant) |
| `bwrap_no_hardened_malloc` | Disable hardened_malloc for incompatible apps |
| `bwrap_exec` | Run bwrap as foreground child, clean up D-Bus proxy and seccomp filter fds on exit; falls back to `exec bwrap` when no proxies are active |
| `require_dir` | Validate that directories exist, exit on missing |

### High-level composites

| Function | Purpose |
|---|---|
| `bwrap_gui_setup` | `bwrap_base` + `lib64` + optional `gpu` + optional `resolv` + `runtime_dir` + `home_tmpfs`; optional `shm` mode |
| `bwrap_gui_finish` | `themes` + `wayland`/`x11` + D-Bus (`filtered` by default; `unfiltered`/`none` opt-out) + `env_base` + malloc + seccomp + `sandbox` |

`bwrap_gui_setup` parameters:

- `$1` — array name to append bwrap arguments to (required)
- `$2` — network: `yes`/`no` (default `no`); `yes` adds the resolv.conf bind
- `$3` — GPU: `yes`/`no` (default `no`); `yes` exposes the DRI/NVIDIA device nodes, `no` omits them. GPU exposure expands the attack surface, so it is opt-in.
- `$4` — shm: `tmpfs` (default) or `bind`. `tmpfs` creates a private, empty `/dev/shm`; `bind` exposes the host `/dev/shm`, which shares POSIX shared memory with host processes and other sandboxes. Use `bind` only for applications that require host shm.

### D-Bus filtering

`bwrap_dbus_filtered` starts an `xdg-dbus-proxy` instance with `--filter`
and the provided rules, waits for the proxy socket, and binds it into the
sandbox as `$XDG_RUNTIME_DIR/bus`. Proxy processes are tracked and cleaned
up automatically by `bwrap_exec`.

The library installs an `EXIT` trap for proxy and seccomp-fd cleanup. If the
caller already has an `EXIT` trap, it is preserved: cleanup runs first, then
the original trap, and the shell exit status is preserved. `exec bwrap`
bypasses shell traps, so use `bwrap_exec` with filtered D-Bus.

Filtered D-Bus is the default for `bwrap_gui_finish`. If `xdg-dbus-proxy` is
not installed, `bwrap_dbus_filtered` and `bwrap_dbus_common` return non-zero
and do not fall back to an unfiltered bus; `bwrap_gui_finish` propagates that
failure. Use `dbus=none` to run without D-Bus, or `unfiltered` to opt into the
unfiltered bus explicitly.
If no session bus is available, filtered mode is skipped because there is
nothing to proxy.

`bwrap_dbus_common` wraps `bwrap_dbus_filtered` with a default rule set:

| Rule group | Bus names |
|---|---|
| XDG portals | `org.freedesktop.portal.Desktop`, `org.freedesktop.portal.Documents` |
| GUI services | `org.freedesktop.Notifications`, `org.kde.StatusNotifierWatcher`, `org.freedesktop.ScreenSaver`, `org.freedesktop.login1`, `org.a11y.Bus` |

Extra `--talk`/`--own` rules can be appended per-app.

`bwrap_gui_finish` parameters:
- `$1` — array name to append bwrap arguments to
- `$2` — display: `wayland`/`x11` (default `wayland`)
- `$3` — network: `yes`/`no` (default `no`); `yes` adds `--share-net`
- `$4` — malloc variant: `default`/`light`/`no`
- `$5` — D-Bus mode: `filtered` (default), `unfiltered`, `none`; `filtered` returns non-zero if `xdg-dbus-proxy` is unavailable
- `$6` — themes: `yes`/`no` (default `yes`)
- `$7` — seccomp: `default`/`none` (default `default`); `default` returns non-zero if the filter blob is unavailable; use `bwrap_seccomp` directly for an allowlist

When using filtered D-Bus, wrappers must call `bwrap_exec` instead of
`exec bwrap` to ensure proxy cleanup.

## Seccomp

`bwrap_gui_finish` applies the precompiled default blocklist unless the 7th
parameter is `none`. The blocklist is default-allow: it denies syscalls that
are dangerous inside a sandbox (`mount`, `pivot_root`, `chroot`, `unshare`,
`setns`, `ptrace`, `bpf`, `io_uring_*`, `userfaultfd`, `process_vm_*`,
keyring operations, `clone` with `CLONE_NEWUSER`, and a few more). See
`seccomp/default.conf` for the exact list.

`bwrap_seccomp A default` applies
`<BWRAP_SECCOMP_DIR>/default.$(uname -m).bpf`. A missing, malformed, or
wrong-architecture blob fails closed: the function returns non-zero and adds
no filter. Architecture magic is checked in the target's native byte order
(including big-endian s390x/mips/parisc); an unsupported `uname -m` also fails
closed. Use `none` to disable seccomp explicitly.

`bwrap_seccomp A "openat read write"` compiles a syscall **allowlist** and
caches the result. Allowlist mode is fail-closed: an unknown syscall name, a
missing generator, or a compile failure returns non-zero. It is a power-user
API and is not accepted through `bwrap_gui_finish`, which only accepts
`default`/`none`.

The filter descriptor stays open so bwrap can inherit it. In proxy mode
`bwrap_exec` closes the parent copy after starting bwrap; if you invoke `bwrap`
directly, the descriptor remains open until the shell exits.

The blocklist uses one comparison per argument (a libseccomp limitation), so the
`personality(0xffffffff)` query form is blocked together with other values above
`PER_LINUX32`; callers that only query the current persona will see `EPERM`.

The allowlist always permits the syscalls needed by the new process
(`execve`, `execveat`, `exit`, `exit_group`, `write`, `rt_sigreturn`,
`sigreturn`) and by bubblewrap's pid 1, which receives the same filter
(`wait4`, `waitid`, `close`). Everything else must be listed explicitly.

Build/install:

- `make build` compiles `build/bwrap-seccomp-gen` and generates
  `build/seccomp/default.$(uname -m).bpf` with `--strict`; set `ARCH=` to build
  a blob for another libseccomp-supported target architecture.
- `bwrap-seccomp-gen --strict` rejects syscall names that no supported
  architecture knows; target-specific legacy names are still skipped with a
  warning.
- `make install` installs the helper to
  `/usr/lib/bwrap-common/bwrap-seccomp-gen` and the blob to
  `/usr/lib/bwrap-common/seccomp/`.
- `gcc` and the `libseccomp` headers are build-time dependencies;
  `libseccomp` is a runtime dependency.

`ioctl` command comparisons are masked to 32 bits because the kernel truncates
the command to `unsigned int`; this prevents high-bit aliases of `TIOCSTI` and
`TIOCLINUX` from bypassing the filter.

`./tests/seccomp-check.sh` invokes every rule in `seccomp/default.conf` inside
a sandbox with the default filter and verifies the expected `EPERM`/`ENOSYS`,
including high-bit `ioctl` aliases.

| Variable | Default |
|---|---|
| `BWRAP_SECCOMP_DIR` | `/usr/lib/bwrap-common/seccomp` |
| `BWRAP_SECCOMP_GEN` | `/usr/lib/bwrap-common/bwrap-seccomp-gen` |
| `BWRAP_SECCOMP_CACHE_DIR` | `${XDG_CACHE_HOME:-$HOME/.cache}/bwrap-common/seccomp` |
| `BWRAP_SECCOMP_ARCH` | overrides `uname -m` for the default blob (cross-arch tests) |

The allowlist cache key is
`sha256("bwrap-common-seccomp-v2\n<arch>\n<spec>\n")`; cached files are mode
`0600`.

## Dependencies

- `bubblewrap` (`bwrap`)
- `bash`
- `libseccomp` (runtime, for the seccomp helper)
- `gcc` + `libseccomp` headers (build-time, for `make build`/`make install`)
- [verify-lib](https://github.com/fkzys/verify-lib) (recommended, for integrity verification before sourcing)
- `xdg-dbus-proxy` (required for the default `filtered` D-Bus mode; optional with `dbus=none`/`unfiltered`)

- [hardened_malloc](https://github.com/fkzys/hardened_malloc) (optional)
## Files

| Path | Purpose |
|---|---|
| `/usr/lib/bwrap-common/bwrap-common.sh` | Library |
| `/usr/lib/bwrap-common/bwrap-seccomp-gen` | Allowlist compiler |
| `/usr/lib/bwrap-common/seccomp/default.<arch>.bpf` | Precompiled default blocklist |
| `seccomp/default.conf` | Default blocklist source |

## License

AGPL-3.0-or-later
