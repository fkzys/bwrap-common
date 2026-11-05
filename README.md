# bwrap-common

[![CI](https://github.com/fkzys/bwrap-common/actions/workflows/ci.yml/badge.svg)](https://github.com/fkzys/bwrap-common/actions/workflows/ci.yml)
![License](https://img.shields.io/github/license/fkzys/bwrap-common)
[![Spec](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/fkzys/specs/refs/heads/main/version.json&maxAge=300)](https://github.com/fkzys/specs)

Reusable bubblewrap sandbox helpers for shell wrappers. Each function
takes an array variable name and appends bwrap arguments to it via nameref.

## Docs
- **[usage](docs/usage.md)**
    - [Functions](docs/usage.md#functions)
        - [Low-level helpers](docs/usage.md#low-level-helpers)
        - [High-level composites](docs/usage.md#high-level-composites)
    - [Resolving file arguments](docs/usage.md#resolving-file-arguments)
    - [D-Bus](docs/usage.md#d-bus)
        - [Session-bus rules](docs/usage.md#session-bus-rules)
        - [Adding system-bus access](docs/usage.md#adding-system-bus-access)
    - [Seccomp](docs/usage.md#seccomp)
        - [Extra rules](docs/usage.md#extra-rules)
        - [Cache directory](docs/usage.md#cache-directory)
- **[notes](docs/notes.md)**
    - [Wrappers](docs/notes.md#wrappers)
        - [Environment](docs/notes.md#environment)
        - [hardened_malloc](docs/notes.md#hardened_malloc)
        - [Missing resources](docs/notes.md#missing-resources)
        - [D-Bus filtering](docs/notes.md#d-bus-filtering)
    - [Seccomp](docs/notes.md#seccomp)
        - [Default blocklist](docs/notes.md#default-blocklist)
        - [Filter cache](docs/notes.md#filter-cache)
        - [Allowlist mode](docs/notes.md#allowlist-mode)
        - [Build and install](docs/notes.md#build-and-install)

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
make build
sudo make install
```

`make build` builds only `build/bwrap-seccomp-gen`, the seccomp rule compiler.
`make install` installs the library entry point and its two modules, the
generator, and `seccomp/default.conf`; no BPF blob is generated or installed.
It fails with an error if the generator has not been built yet.
`gcc` and the `libseccomp` headers are required to build the generator.

### Uninstall

```sh
sudo make uninstall
```

## How to use

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
bwrap_gui_setup A yes yes tmpfs                              # network, gpu, shm=tmpfs
bwrap_bind_dir A "${HOME}/.config/app" "${HOME}/Data"
bwrap_ro_bind_dir A "${MEDIA_DIR}"
bwrap_audio A
bwrap_gui_finish A wayland yes default filtered yes default  # display, network, malloc, dbus, themes, seccomp
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

Equivalent using low-level helpers:

```sh
A=()
bwrap_base A tmpfs yes                                       # shm=tmpfs, yes=clearenv
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
bwrap_sandbox A yes yes                                      # yes=net, yes=new-session
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

| Variable | Default |
|---|---|
| `BWRAP_SECCOMP_CONF` | `${BWRAP_SECCOMP_DIR}/default.conf` (default blocklist source) |
| `BWRAP_SECCOMP_DIR` | `/usr/lib/bwrap-common/seccomp` (seccomp source dir) |
| `BWRAP_SECCOMP_GEN` | `/usr/lib/bwrap-common/bwrap-seccomp-gen` (rule compiler) |
| `BWRAP_SECCOMP_CACHE_DIR` | `${XDG_CACHE_HOME:-$HOME/.cache}/bwrap-common/seccomp` |
| `BWRAP_SECCOMP_ARCH` | overrides `uname -m` (cross-arch tests) |
| `BWRAP_QUIET` | unset; any non-empty value silences library warnings on stderr, including seccomp cache warnings (errors are never silenced) |

## Files

| Path | Purpose |
|---|---|
| `/usr/lib/bwrap-common/bwrap-common.sh` | Library entry point (public API); sources the internal modules below |
| `/usr/lib/bwrap-common/bwrap-common-seccomp.sh` | seccomp internals (sourced by the entry point) |
| `/usr/lib/bwrap-common/bwrap-common-dbus.sh` | filtered D-Bus internals (sourced by the entry point) |
| `/usr/lib/bwrap-common/bwrap-seccomp-gen` | Runtime rule compiler |
| `/usr/lib/bwrap-common/seccomp/default.conf` | Default blocklist source, compiled at runtime |
| `seccomp/default.conf` | Default blocklist source in the repo |

## Dependencies

- `bubblewrap`
- `bash`
- `libseccomp`
- `gcc`
- [verify-lib](https://github.com/fkzys/verify-lib) (recommended for integrity verification before sourcing)
- `xdg-dbus-proxy` (required for `filtered` D-Bus mode)

- [hardened_malloc](https://github.com/fkzys/hardened_malloc) (required; opt out with `malloc=no`)

## License

AGPL-3.0-or-later
