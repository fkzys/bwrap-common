# bwrap-common

## Wrappers

`hardened_malloc` is opt-out: `bwrap_gui_finish` preloads it by default
(`malloc=default`, or `malloc=light` for the light build). When called
directly, `bwrap_hardened_malloc` also defaults to the full `default` library
when no variant is passed. If the selected library is missing,
`bwrap_hardened_malloc` fails and `bwrap_gui_finish` propagates that failure.
Use `malloc=no` to opt out for incompatible applications or systems without
the package.

`bwrap_base` prepends `--clearenv` by default, so the sandbox does not inherit
the host environment. Only variables set by `--setenv` options that follow it
(including ones already in the array) reach the child. `TERM` is re-added by
`bwrap_env_base` from the host, falling back to `xterm-256color`; `DISPLAY` and
`WAYLAND_DISPLAY` are re-added by the display helpers when the corresponding
socket exists.

The default policy intentionally does not forward `USER`, `TZ`, `LC_*`,
`GTK_THEME`, `QT_*`, `XDG_CURRENT_DESKTOP`, or `XDG_DATA_DIRS`. Toolkit and
locale defaults apply inside the sandbox; add explicit `--setenv` options for
any application that needs a specific value.

`XDG_CACHE_HOME` is normalized to `$HOME/.cache` inside the private home
tmpfs. If the app's cache lives elsewhere, bind only that app's cache directory
explicitly **after** `bwrap_env_base`/`bwrap_gui_finish` so the mount overlays
the tmpfs cache directory:

```sh
CACHE_DIR=/mnt/ssd/cache/app
mkdir -p "$CACHE_DIR"
A+=(--bind "$CACHE_DIR" "$HOME/.cache/app")
```

Only the `app` cache is exposed; the rest of `$HOME/.cache` stays private.
`XDG_CACHE_HOME` already points at `$HOME/.cache`, so no `--setenv` is needed.
This form cannot use `bwrap_bind_dir`, because that helper always binds a path
to itself rather than to a different target.

If the application treats `XDG_CACHE_HOME` as its own cache directory and must
expose it at the original host path, use `bwrap_bind_dir` and override the
variable explicitly:

```sh
bwrap_bind_dir A "$CACHE_DIR"
A+=(--setenv XDG_CACHE_HOME "$CACHE_DIR")
```

Both calls append to the same argument array; bwrap still receives one command.

Use this second form only when the original path is part of the application's
contract. Both variants give the sandbox write access to the host cache; use a
dedicated cache directory if that access is not desired.

Pass `no` as `bwrap_base`'s third argument, or as `bwrap_gui_setup`'s fifth
argument, to opt out and inherit the host environment. Opting out re-exposes
secrets and loader/interpreter variables from the calling environment.

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
| `bwrap_dbus_filtered` | Filtered D-Bus via `xdg-dbus-proxy` with custom rules; fails if the proxy is unavailable |
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
- `$5` — D-Bus mode: `filtered` (default), `unfiltered`, `none`; `filtered` returns non-zero if `xdg-dbus-proxy` is unavailable
- `$6` — themes: `yes`/`no` (default `yes`)
- `$7` — seccomp: `default`/`none` (default `default`); `default` returns non-zero if the default config or generator is unavailable; no blob is used; use `bwrap_seccomp` directly for an allowlist or `default` plus extra rules

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

`bwrap_dbus_common` wraps `bwrap_dbus_filtered` with a session-bus default rule set:

| Rule group | Bus names |
|---|---|
| XDG portals | `org.freedesktop.portal.Desktop`, `org.freedesktop.portal.Documents` |
| GUI services | `org.freedesktop.Notifications`, `org.kde.StatusNotifierWatcher`, `org.freedesktop.ScreenSaver`, `org.a11y.Bus` |

Extra `--talk`/`--own` rules can be appended per-app.

`bwrap_dbus_common` intentionally does not load system-bus services. The
following groups were considered and excluded:

| Group | Examples | Reason |
|---|---|---|
| Power and sessions | `org.freedesktop.login1`, `org.freedesktop.UPower` | power/session control; logind is a system-bus service, so access requires explicit system-bus rules |
| Storage | `org.freedesktop.UDisks2` | mount/unmount and filesystem operations are privileged |
| Networking | `org.freedesktop.NetworkManager`, `org.freedesktop.ModemManager1` | can change network state and connections |
| Bluetooth | `org.bluez` | pairing, connecting, file transfer |
| System configuration | `hostname1`, `timedate1`, `locale1`, `Accounts` | writes are privileged and app-specific |
| Realtime scheduling | `org.freedesktop.RealtimeKit1` | affects process scheduling; audio apps only |
| Updates and services | `systemd1`, `PackageKit`, `fwupd` | package and unit management is privileged |
| Virtualization and policy | `org.libvirt`, `org.freedesktop.PolicyKit1` | VM management and authorization should stay outside the sandbox |
| Color, location, biometrics | `ColorManager`, `GeoClue2`, `fprintd` | privacy- and security-sensitive |

### Why there is no `bwrap_dbus_system_common`

A single system-bus default cannot be both safe and useful. A default based on
`--talk` would grant full access to power, storage, networking and Bluetooth
services. A default based on `--call` would need a brittle, per-service method
allowlist that changes with each upstream API. System services are privileged
and every application needs a different subset, so the library requires
explicit rules instead of shipping a common preset.

### Adding system-bus access

Use `bwrap_dbus_system_filtered ARRAY RULE...` and pass only the rules the
application needs. It accepts the same `xdg-dbus-proxy` rules as
`bwrap_dbus_filtered` (`--talk`, `--see`, `--own`, `--call`, `--broadcast`) and
loads no default rules. It binds the proxy at the standard system socket and
sets `DBUS_SYSTEM_BUS_ADDRESS`, so applications that use the default address
work without extra setup. Do not combine it with `bwrap_dbus_system` for the
same sandbox. Prefer `--call` over full `--talk` where the installed
`xdg-dbus-proxy` supports it.

Typical additions:

| Application type | Rules to consider |
|---|---|
| Media player or browser | `logind` inhibit calls and `UPower` property reads; avoid power-off/suspend methods |
| File manager or disk utility | `UDisks2` enumeration; add mount/eject calls only when required |
| Network or VPN applet | `NetworkManager`; add `ModemManager1` for mobile broadband |
| Bluetooth applet or audio | `org.bluez`; add pairing/connect calls only when required |
| Audio application or DAW | `RealtimeKit1` |
| System settings | `hostname1`, `timedate1`, `locale1` read-only calls first |
| Software updater | Prefer host-side `PackageKit`, `fwupd`, or `systemd1`; do not expose them to a general-purpose sandbox |
| Virtual machine manager | Keep `org.libvirt` outside the sandbox |
| Authentication or policy | Keep `PolicyKit1` and `fprintd` out of the sandbox; use host-side agents |

When using filtered D-Bus, wrappers must call `bwrap_exec` instead of
`exec bwrap` to ensure proxy cleanup.

## Seccomp

`bwrap_gui_finish` applies the default blocklist unless the 7th parameter is
`none`. The blocklist is default-allow: it denies syscalls that are dangerous
inside a sandbox (`mount`, `pivot_root`, `chroot`, `unshare`, `setns`, `ptrace`,
`bpf`, `io_uring_*`, `userfaultfd`, `process_vm_*`, keyring operations, `clone`
with `CLONE_NEWUSER`, and a few more). See `seccomp/default.conf` for the exact
list.

`bwrap_seccomp A default` compiles
`${BWRAP_SECCOMP_CONF:-<BWRAP_SECCOMP_DIR>/default.conf}` at runtime with the
installed generator and caches the resulting BPF filter. A missing or unreadable
config, a missing generator, or a compile failure returns non-zero and adds no
filter. Use `none` to disable seccomp explicitly.

Extra rules can be appended to `default`; each argument is one blocklist rule:

```sh
bwrap_seccomp A default "getppid EPERM" "kexec_load ENOSYS"
```

The default config and the extra rules are compiled into one combined filter,
not stacked filters. There is no second `--add-seccomp-fd`; `bwrap_seccomp`
appends a single `--seccomp FD`. User rules have priority over the base rules:

- An unconditional extra rule removes all base rules for that syscall, then
  adds the user's action. An unconditional `ALLOW` therefore unblocks it.
- A conditional extra rule removes only the base rule with the same normalized
  condition, then adds the user's rule.
- A conditional extra rule cannot override an unconditional default deny; the
  unconditional rule still dominates.

For example, this replaces only the matching `personality a0 == 1` default rule;
the other execution-domain rules remain blocked:

```sh
bwrap_seccomp A default "personality ALLOW a0 == 1"
```

`ALLOW` is a valid action in extra rules. An extra `ALLOW` rule that removes a
matching default deny prints a warning. In the base `default.conf`, `--strict`
rejects `ALLOW`.
`bwrap_gui_finish` still accepts only `default`/`none`, so extra rules go through
`bwrap_seccomp` directly.

Rules use `seccomp/default.conf` format: base actions are `EPERM` or `ENOSYS`,
extra rules may also use `ALLOW`, and argument conditions are supported.

Cache keys include the generator `--version` (including the loaded libseccomp version), filter mode, architecture, and
the content of `default.conf`, so a generator upgrade, config edit, or
architecture switch produces a new entry:

- default: `sha256("bwrap-common-seccomp-default-v4\n<genver>\nstrict\n<arch>\n<default_conf_sha256>\n")`
- default+extra: `sha256("bwrap-common-seccomp-default-extra-v4\n<genver>\nstrict\n<arch>\n<default_conf_sha256>\n<extra_spec>\n")`

Each cached filter has a `.sha256` sidecar; a checksum mismatch recompiles the
entry. The sidecar is installed before the filter, and invalid entries are
overwritten rather than removed, so concurrent writers cannot delete a fresh
entry. The generator reports version 4 plus the loaded libseccomp version. The
cache directory must be owned by the current user and must not be writable by
group or others; otherwise it is bypassed for the runtime fallback. Symlinks are
resolved with `realpath` before that check, but parent directories are not
validated, so the cache path must be under a trusted parent. The cache is
host-side and trusted; the key and checksum catch stale or corrupted outputs,
not a malicious writer. If the cache directory is unavailable, `bwrap_seccomp`
warns once per cache directory and compiles into a temporary file in
`$XDG_RUNTIME_DIR` (tmpfs), opens it, unlinks it immediately, and passes
`--seccomp FD`. If there is no writable runtime dir, it fails closed.

`bwrap_seccomp A "openat read write"` compiles a syscall **allowlist** and
caches the result with the same cache and tmpfs fallback machinery. Its cache
key is `sha256("bwrap-common-seccomp-v4\n<genver>\nallowlist\n<arch>\n<spec>\n")`.
Allowlist mode is fail-closed: an unknown syscall name, a missing generator, or
a compile failure returns non-zero. It is a power-user API and is not accepted
through `bwrap_gui_finish`, which only accepts `default`/`none`.

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

- `make build` compiles only `build/bwrap-seccomp-gen`.
- `bwrap-seccomp-gen --strict` rejects syscall names that no supported
  architecture knows; target-specific legacy names are still skipped with a
  warning.
- `make install` does not build; run `make build` first. It installs the
  library, the helper to `/usr/lib/bwrap-common/bwrap-seccomp-gen`, and the
  runtime source `seccomp/default.conf` to `/usr/lib/bwrap-common/seccomp/`.
  No BPF blob is generated or installed.
- `gcc` and the `libseccomp` headers are build-time dependencies;
  `libseccomp` is a runtime dependency of the generator.

`ioctl` command comparisons are masked to 32 bits because the kernel truncates
the command to `unsigned int`; this prevents high-bit aliases of `TIOCSTI` and
`TIOCLINUX` from bypassing the filter.

`./tests/seccomp-check.sh` invokes every rule in `seccomp/default.conf` inside
a sandbox with the default filter and verifies the expected `EPERM`/`ENOSYS`,
including high-bit `ioctl` aliases.
