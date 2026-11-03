# bwrap-common

## Functions

### Low-level helpers

| Function | Purpose |
|---|---|
| `bwrap_base` | Clears the inherited environment by default (`--clearenv`) and provides the system skeleton (`/usr`, `/etc`, `/proc`, `/sys`, `/dev`, `/tmp`); `$2` selects `shm=tmpfs` (default, private) or `shm=bind` (host `/dev/shm`); `$3` selects `clearenv=yes` (default) or `no` |
| `bwrap_lib64` | `/usr/lib64` bind or symlink |
| `bwrap_resolv` | resolv.conf symlink target for DNS |
| `bwrap_gpu` | DRI + NVIDIA device nodes |
| `bwrap_wayland` | Wayland socket (rw for `connect()`) |
| `bwrap_x11` | X11/XWayland socket + Xauthority |
| `bwrap_audio` | PipeWire + PulseAudio sockets |
| `bwrap_dbus_session` | Session D-Bus socket (unfiltered) |
| `bwrap_dbus_system` | System D-Bus socket |
| `bwrap_dbus_system_filtered` | Filtered system D-Bus via `xdg-dbus-proxy`; caller supplies rules |
| `bwrap_dbus_filtered` | Filtered D-Bus via `xdg-dbus-proxy` with custom rules; fails if the proxy is unavailable and a session bus exists (with no bus it is skipped) |
| `bwrap_dbus_common` | Pre-configured filtered D-Bus for session desktop apps (XDG portals, notifications, status notifier, screen saver, a11y); accepts extra rules |
| `bwrap_themes` | GTK2/3, dconf, fontconfig, Qt, Kvantum, fonts, icons |
| `bwrap_fcitx` | fcitx5 input method sockets + env |
| `bwrap_home_tmpfs` | tmpfs `$HOME` with XDG skeleton |
| `bwrap_runtime_dir` | XDG_RUNTIME_DIR with correct permissions |
| `bwrap_env_base` | `HOME`, `LANG`, `PATH`, `TERM`, `XDG_RUNTIME_DIR`, `XDG_CACHE_HOME=$HOME/.cache` |
| `bwrap_sandbox` | `--unshare-all`, optional `--share-net` / `--new-session` |
| `bwrap_seccomp` | Compile `seccomp/default.conf` (optionally merged with extra rules) or a syscall allowlist at runtime, then add one `--seccomp` descriptor |
| `bwrap_resolve_files` | Resolve file arguments to bind mounts |
| `bwrap_bind_dir` | Create state dirs on host + add `--bind` |
| `bwrap_ro_bind_dir` | Bind pre-existing dirs read-only, skip missing |
| `bwrap_ssh_agent` | SSH agent socket forwarding |
| `bwrap_hardened_malloc` | Preload hardened_malloc: full `default` when omitted, or `light`; fails if the selected library is missing; `bwrap_gui_finish` enables it by default |
| `bwrap_no_hardened_malloc` | Opt out of hardened_malloc by masking installed variants with an empty stub |
| `bwrap_exec` | Run bwrap as foreground child, clean up D-Bus proxy and seccomp filter fds on exit; falls back to `exec bwrap` when no proxies are active |
| `require_dir` | Validate that directories exist, exit on missing |

### High-level composites

| Function | Purpose |
|---|---|
| `bwrap_gui_setup` | `bwrap_base` + `lib64` + optional `gpu` + optional `resolv` + `runtime_dir` + `home_tmpfs`; optional `shm` and `clearenv` modes |
| `bwrap_gui_finish` | `themes` + `wayland`/`x11` + D-Bus (`filtered` by default; `unfiltered`/`none` opt-out) + `env_base` + malloc (enabled by default; `malloc=no` opts out) + seccomp + `sandbox` |

`bwrap_gui_setup` parameters:

- `$1` — array name to append bwrap arguments to (required)
- `$2` — network: `yes`/`no` (default `no`); `yes` adds the resolv.conf bind
- `$3` — GPU: `yes`/`no` (default `no`); `yes` exposes the DRI/NVIDIA device nodes, `no` omits them. GPU exposure expands the attack surface, so it is opt-in.
- `$4` — shm: `tmpfs` (default) or `bind`. `tmpfs` creates a private, empty `/dev/shm`; `bind` exposes the host `/dev/shm`, which shares POSIX shared memory with host processes and other sandboxes. Use `bind` only for applications that require host shm.
- `$5` — clearenv: `yes` (default) or `no`. `yes` drops the inherited environment; `no` keeps it and re-exposes host secrets and loader/interpreter variables.

`bwrap_gui_finish` parameters:
- `$1` — array name to append bwrap arguments to
- `$2` — display: `wayland`/`x11` (default `wayland`)
- `$3` — network: `yes`/`no` (default `no`); `yes` adds `--share-net`
- `$4` — malloc: `default` (default, enabled), `light`, or `no` (opt-out)
- `$5` — D-Bus mode: `filtered` (default), `unfiltered`, `none`; `filtered` returns non-zero if `xdg-dbus-proxy` is unavailable when a bus exists (with no bus it is skipped)
- `$6` — themes: `yes`/`no` (default `yes`)
- `$7` — seccomp: `default`/`none` (default `default`); `default` returns non-zero if the default config or generator is unavailable; no blob is used; use `bwrap_seccomp` directly for an allowlist or `default` plus extra rules

## D-Bus

### Session-bus rules

`bwrap_dbus_common` wraps `bwrap_dbus_filtered` with a session-bus default rule
set:

| Rule group | Bus names |
|---|---|
| XDG portals | `org.freedesktop.portal.Desktop`, `org.freedesktop.portal.Documents` |
| GUI services | `org.freedesktop.Notifications`, `org.kde.StatusNotifierWatcher`, `org.freedesktop.ScreenSaver`, `org.a11y.Bus` |

Extra `--talk`/`--own` rules can be appended per-app:

```sh
bwrap_dbus_common A \
    --own==some.app.client \
    --talk=org.freedesktop.secrets \
    --talk=org.kde.kwalletd5 \
    --talk=org.kde.kwalletd6
```

`bwrap_dbus_common` does not load system-bus services; add those explicitly
(see below).

### Adding system-bus access

The services below are deliberately not part of a common preset; add the ones
the application needs.

| Application type | Services to consider | Notes |
|---|---|---|
| Media player or browser | `org.freedesktop.login1`, `org.freedesktop.UPower` | power/session control; logind is a system-bus service, so access requires explicit rules. Use `logind` inhibit calls and `UPower` property reads; avoid power-off/suspend methods |
| File manager or disk utility | `org.freedesktop.UDisks2` | mount/unmount and filesystem operations are privileged; start with enumeration and add mount/eject calls only when required |
| Network or VPN applet | `org.freedesktop.NetworkManager`, `org.freedesktop.ModemManager1` | can change network state and connections; add `ModemManager1` only for mobile broadband |
| Bluetooth applet or audio | `org.bluez` | pairing, connecting, file transfer; add pairing/connect calls only when required |
| Audio application or DAW | `org.freedesktop.RealtimeKit1` | affects process scheduling |
| System settings | `hostname1`, `timedate1`, `locale1`, `Accounts` | writes are privileged and app-specific; try read-only calls first |
| Software updater | `systemd1`, `PackageKit`, `fwupd` | package and unit management is privileged; prefer host-side `PackageKit`, `fwupd`, or `systemd1` and do not expose them to a general-purpose sandbox |
| Virtual machine manager | `org.libvirt` | VM management should stay outside the sandbox |
| Authentication or policy | `org.freedesktop.PolicyKit1`, `fprintd` | authorization and biometrics should stay outside the sandbox; use host-side agents |
| Color or location app | `ColorManager`, `GeoClue2` | privacy- and security-sensitive |

No system-bus service is enabled by default. Use
`bwrap_dbus_system_filtered ARRAY RULE...` and pass only the rules the
application needs; it accepts the same `xdg-dbus-proxy` rules as
`bwrap_dbus_filtered` (`--talk`, `--see`, `--own`, `--call`, `--broadcast`) and
loads no default rules.

`--call` and `--broadcast` require an explicit rule: `--call=NAME=RULE` /
`--broadcast=NAME=RULE`, where `RULE` is `[METHOD][@PATH]`:

- `METHOD` is `*`, an interface, or a fully-qualified method.
- `PATH` is an object path.

A bare `--call=NAME` is rejected by the proxy. Examples:

```sh
--call=org.freedesktop.UPower=*
--call=org.freedesktop.UPower=org.freedesktop.UPower.*@/org/freedesktop/UPower/*
```

It binds the proxy at the standard system socket and sets
`DBUS_SYSTEM_BUS_ADDRESS`, so applications that use the default address work
without extra setup. Prefer `--call` over full `--talk` where the installed
`xdg-dbus-proxy` supports it.

Do not combine it with `bwrap_dbus_system` for the same sandbox. Call it after
`bwrap_base`/`bwrap_runtime_dir` so its `--dir /run` entries are not shadowed by
a later `/run` mount. When neither `DBUS_SYSTEM_BUS_ADDRESS` nor
`/run/dbus/system_bus_socket` exists, it warns on stderr and returns 0, leaving
the sandbox without a system bus.

## Seccomp

### Extra rules

Extra rules can be appended to `default`; each argument is one blocklist rule:

```sh
bwrap_seccomp A default "getppid EPERM" "kexec_load ENOSYS"
```

Base rules and extra rules are compiled into one filter (not stacked). User
rules win over base rules:

- An unconditional extra rule removes all base rules for that syscall, then
  adds the user's action; an unconditional `ALLOW` unblocks it.
- A conditional extra rule removes only the base rule with the same normalized
  condition, then adds the user's rule.
- A conditional extra rule cannot override an unconditional default deny.

Example — replaces only the matching `personality a0 == 1` rule:

```sh
bwrap_seccomp A default "personality ALLOW a0 == 1"
```

`ALLOW` is valid in extra rules; an extra `ALLOW` that removes a matching
default deny prints a warning. In the base `default.conf`, `--strict` rejects
`ALLOW`. `bwrap_gui_finish` accepts only `default`/`none`, so extra rules go
through `bwrap_seccomp` directly.

Rules use the `seccomp/default.conf` format: base actions are `EPERM` or
`ENOSYS`, extra rules may also use `ALLOW`, and argument conditions are
supported.

## Cache directory

`XDG_CACHE_HOME` is normalized to `$HOME/.cache` inside the private home tmpfs.
To expose additional cache, bind it **after** `bwrap_env_base`/`bwrap_gui_finish`
so it overlays the tmpfs:

```sh
CACHE_DIR=/mnt/ssd/cache/app
mkdir -p "$CACHE_DIR"
A+=(--bind "$CACHE_DIR" "$HOME/.cache/app")
```

Only `app` is exposed; the rest of `$HOME/.cache` stays private, and no
`--setenv` is needed. This form cannot use `bwrap_bind_dir` (it binds a path to
itself).

To expose the cache at its original host path instead:

```sh
bwrap_bind_dir A "$CACHE_DIR"
A+=(--setenv XDG_CACHE_HOME "$CACHE_DIR")
```

Use the second form only when the original path is required by the application.
Both give the sandbox write access to the host cache.
