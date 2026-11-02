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
make build
sudo make install
```

`make build` builds only `build/bwrap-seccomp-gen`, the seccomp rule compiler.
`make install` installs the library, the generator, and `seccomp/default.conf`;
no BPF blob is generated or installed. `gcc` and the `libseccomp` headers are
required to build the generator.

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
| `BWRAP_SECCOMP_CONF` | `${BWRAP_SECCOMP_DIR}/default.conf` (default blocklist source) |
| `BWRAP_SECCOMP_DIR` | `/usr/lib/bwrap-common/seccomp` (seccomp source dir) |
| `BWRAP_SECCOMP_GEN` | `/usr/lib/bwrap-common/bwrap-seccomp-gen` (rule compiler) |
| `BWRAP_SECCOMP_CACHE_DIR` | `${XDG_CACHE_HOME:-$HOME/.cache}/bwrap-common/seccomp` |
| `BWRAP_SECCOMP_ARCH` | overrides `uname -m` (cross-arch tests) |

The default filter is compiled from `seccomp/default.conf` at runtime and cached.
Cache keys include the generator `--version`, filter mode, and architecture:

- allowlist: `sha256("bwrap-common-seccomp-v4\n<genver>\nallowlist\n<arch>\n<spec>\n")`
- default: `sha256("bwrap-common-seccomp-default-v4\n<genver>\nstrict\n<arch>\n<default_conf_sha256>\n")`
- default+extra: `sha256("bwrap-common-seccomp-default-extra-v4\n<genver>\nstrict\n<arch>\n<default_conf_sha256>\n<extra_spec>\n")`

Cached filters and their `.sha256` sidecars are mode `0600`; a checksum
mismatch discards the entry and recompiles it. If the cache is unavailable, the
filter is compiled into a temporary file in `$XDG_RUNTIME_DIR`, opened, and
unlinked; without a writable runtime directory the call fails closed. Extra
blocklist rules can be merged into the default filter with
`bwrap_seccomp A default "RULE"...`; `bwrap_gui_finish` still accepts only
`default`/`none`.

## Files

| Path | Purpose |
|---|---|
| `/usr/lib/bwrap-common/bwrap-common.sh` | Library |
| `/usr/lib/bwrap-common/bwrap-seccomp-gen` | Runtime rule compiler |
| `/usr/lib/bwrap-common/seccomp/default.conf` | Default blocklist source, compiled at runtime |
| `seccomp/default.conf` | Default blocklist source in the repo |

## Dependencies

- `bubblewrap`
- `bash`
- `libseccomp`
- `gcc`
- [verify-lib](https://github.com/fkzys/verify-lib) (recommended, for integrity verification before sourcing)
- `xdg-dbus-proxy` (required for the default `filtered` D-Bus mode)

- [hardened_malloc](https://github.com/fkzys/hardened_malloc) (required by default; opt out with `malloc=no`)

## License

AGPL-3.0-or-later
