# bwrap-common

## Wrappers

### Environment

`bwrap_base` prepends `--clearenv` by default, so the sandbox does not inherit
the host environment. Only variables set by later `--setenv` options reach the
child, including ones already in the array.

`bwrap_env_base` re-adds `TERM` from the host, falling back to
`xterm-256color`. The display helpers re-add `DISPLAY` and `WAYLAND_DISPLAY`
when the corresponding socket exists.

The default policy intentionally does not forward:

- `USER`, `TZ`
- `LC_*`
- `GTK_THEME`, `QT_*`
- `XDG_CURRENT_DESKTOP`, `XDG_DATA_DIRS`

Toolkit and locale defaults apply inside the sandbox. Add explicit `--setenv`
options for any application that needs a specific value.

To opt out and inherit the host environment, pass `no` as `bwrap_base`'s third
argument or as `bwrap_gui_setup`'s fifth argument. Opting out re-exposes secrets
and loader/interpreter variables from the calling environment.

### hardened_malloc

`hardened_malloc` is opt-out. `bwrap_gui_finish` preloads it by default
(`malloc=default`, or `malloc=light` for the light build). Called directly,
`bwrap_hardened_malloc` also defaults to the full `default` library when no
variant is passed.

If the selected library is missing, `bwrap_hardened_malloc` fails and
`bwrap_gui_finish` propagates that failure. Use `malloc=no` to opt out for
incompatible applications or systems without the package.

### Missing resources

Helpers that expose optional host resources print a warning to stderr and leave
the resource out of the sandbox when it is missing:

`bwrap_gpu`, `bwrap_wayland`, `bwrap_x11`, `bwrap_audio`, `bwrap_themes`,
`bwrap_dbus_session`, `bwrap_dbus_system`, `bwrap_ssh_agent`, `bwrap_ro_bind_dir`,
`bwrap_resolv`, `bwrap_resolve_files`.

`bwrap_x11` still exports `DISPLAY` even when `/tmp/.X11-unix` is absent.

Set `BWRAP_QUIET` to any non-empty value to silence these warnings, including
the seccomp cache warnings. Errors are never silenced.

### D-Bus filtering

`bwrap_dbus_filtered` starts an `xdg-dbus-proxy` instance with `--filter` and the
provided rules, waits for the proxy socket, and binds it into the sandbox as
`$XDG_RUNTIME_DIR/bus`. Proxies are tracked and cleaned up automatically by
`bwrap_exec`.

Use `bwrap_exec`, not `exec bwrap`, with filtered D-Bus: `exec bwrap` bypasses
the cleanup.

Filtered D-Bus is the default for `bwrap_gui_finish`. If `xdg-dbus-proxy` is not
installed, `bwrap_dbus_filtered` and `bwrap_dbus_common` return non-zero and do
not fall back to an unfiltered bus; `bwrap_gui_finish` propagates that failure.

- `dbus=none` — run without D-Bus.
- `unfiltered` — opt into the unfiltered bus explicitly.

If no session bus is available, filtered mode is skipped because there is
nothing to proxy.

`xdg-dbus-proxy` versions before 0.1.7 have CVE-2026-34080 (an eavesdrop filter
bypass). Keep the package updated through your distribution.

## Seccomp

### Default blocklist

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

### Filter cache

The default filter is compiled from `seccomp/default.conf` at runtime and cached.
Cache keys include the generator `--version` (including the loaded libseccomp version), filter mode, and architecture:

- allowlist: `sha256("bwrap-common-seccomp-v4\n<genver>\nallowlist\n<arch>\n<spec>\n")`
- default: `sha256("bwrap-common-seccomp-default-v4\n<genver>\nstrict\n<arch>\n<default_conf_sha256>\n")`
- default+extra: `sha256("bwrap-common-seccomp-default-extra-v4\n<genver>\nstrict\n<arch>\n<default_conf_sha256>\n<extra_spec>\n")`

Cached filters and their `.sha256` sidecars are mode `0600`; a checksum mismatch recompiles the entry.
The resolved cache directory must be owned by the current user
and must not be writable by group or others; otherwise it is bypassed for the runtime fallback.
Symlinks are resolved with `realpath` before validation, but parent directories are not
checked, so use a path under a trusted parent.

If the cache is unavailable, the filter is compiled into a temporary file in
`$XDG_RUNTIME_DIR`, opened, and unlinked; without a writable runtime directory the call fails closed.
Extra blocklist rules can be merged into the default filter with
`bwrap_seccomp A default "RULE"...`; `bwrap_gui_finish` still accepts only
`default`/`none`.

### Allowlist mode

`bwrap_seccomp A "openat read write"` compiles a syscall **allowlist** and caches
the result with the same cache and tmpfs fallback. Allowlist mode is fail-closed:
an unknown syscall name, a missing generator, or a compile failure returns
non-zero.

The allowlist always permits the syscalls needed by the new process and by
bubblewrap's pid 1; everything else must be listed explicitly. It is a
power-user API, not accepted through `bwrap_gui_finish`, which only accepts
`default`/`none`.

### Build and install

- `make build` compiles only `build/bwrap-seccomp-gen`.
- `make install` does not build; run `make build` first. It installs the
  library, the generator to `/usr/lib/bwrap-common/bwrap-seccomp-gen`, and
  `seccomp/default.conf` to `/usr/lib/bwrap-common/seccomp/`. No BPF blob is
  generated or installed.
- `gcc` and the `libseccomp` headers are build-time dependencies; `libseccomp`
  is a runtime dependency of the generator.
