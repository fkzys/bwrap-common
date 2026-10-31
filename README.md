# bwrap-common

[![CI](https://github.com/fkzys/bwrap-common/actions/workflows/ci.yml/badge.svg)](https://github.com/fkzys/bwrap-common/actions/workflows/ci.yml)
![License](https://img.shields.io/github/license/fkzys/bwrap-common)
[![Spec](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/fkzys/specs/refs/heads/main/version.json&maxAge=300)](https://github.com/fkzys/specs)

Reusable bubblewrap sandbox helpers for shell wrappers. Each function
takes an array variable name and appends bwrap arguments to it via nameref.

## Docs
- **[notes](docs/notes.md)**
    - [Wrappers](docs/notes.md#wrappers)
    - [Functions](docs/notes.md#functions)
    - [Seccomp](docs/notes.md#seccomp)

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
bwrap_gui_setup A yes yes tmpfs          # network, gpu, shm=tmpfs
bwrap_bind_dir A "${HOME}/.config/app" "${HOME}/Data"
bwrap_ro_bind_dir A "${MEDIA_DIR}"
bwrap_audio A
bwrap_gui_finish A wayland yes default filtered yes default  # display, network, malloc, dbus, themes, seccomp
bwrap_exec "${A[@]}" -- /usr/bin/app "$@"
```

Equivalent using low-level helpers:

```sh
A=()
bwrap_base A tmpfs                            # shm=tmpfs; use "bind" only if needed
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

| Variable | Default |
|---|---|
| `BWRAP_SECCOMP_DIR` | `/usr/lib/bwrap-common/seccomp` |
| `BWRAP_SECCOMP_GEN` | `/usr/lib/bwrap-common/bwrap-seccomp-gen` |
| `BWRAP_SECCOMP_CACHE_DIR` | `${XDG_CACHE_HOME:-$HOME/.cache}/bwrap-common/seccomp` |
| `BWRAP_SECCOMP_ARCH` | overrides `uname -m` for the default blob (cross-arch tests) |

The allowlist cache key is
`sha256("bwrap-common-seccomp-v2\n<arch>\n<spec>\n")`; cached files are mode
`0600`.

## Files

| Path | Purpose |
|---|---|
| `/usr/lib/bwrap-common/bwrap-common.sh` | Library |
| `/usr/lib/bwrap-common/bwrap-seccomp-gen` | Allowlist compiler |
| `/usr/lib/bwrap-common/seccomp/default.<arch>.bpf` | Precompiled default blocklist |
| `seccomp/default.conf` | Default blocklist source |

## Dependencies

- `bubblewrap` (`bwrap`)
- `bash`
- `libseccomp` (runtime, for the seccomp helper)
- `gcc` + `libseccomp` headers (build-time, for `make build`/`make install`)
- [verify-lib](https://github.com/fkzys/verify-lib) (recommended, for integrity verification before sourcing)
- `xdg-dbus-proxy` (required for the default `filtered` D-Bus mode; optional with `dbus=none`/`unfiltered`)

- [hardened_malloc](https://github.com/fkzys/hardened_malloc) (required by default; opt out with `malloc=no` if it is not installed)

## License

AGPL-3.0-or-later
