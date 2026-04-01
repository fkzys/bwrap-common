# Tests

## Overview

| File | Language | Framework | What it tests |
|------|----------|-----------|---------------|
| `tests/test.sh` | Bash | Custom assertions | Source guard (re-source idempotency), function definitions (all 27 public functions exist), VERSION variable, `bwrap_base` (non-empty output, `--ro-bind /usr`, `--proc /proc`, `--tmpfs /tmp`), `bwrap_home_tmpfs` (`--tmpfs $HOME`, `--dir ~/.config`), `bwrap_env_base` (HOME/PATH/XDG_RUNTIME_DIR env vars), `bwrap_sandbox` (`--unshare-all`, `--die-with-parent`, `--new-session`, network/new-session toggles), `bwrap_no_hardened_malloc` (`--unsetenv LD_PRELOAD`, `/dev/null` → `/etc/ld.so.preload`), `bwrap_runtime_dir` (XDG_RUNTIME_DIR directory creation), `bwrap_gpu`/`bwrap_lib64` (no-error execution, non-empty output), `bwrap_bind_dir` (directory creation, `--bind` flags, multiple dirs), `bwrap_ro_bind_dir` (existing dir bound, nonexistent dir skipped), `require_dir` (existing dir passes, missing dir fails), `bwrap_fcitx` (QT_IM_MODULE/XMODIFIERS env vars), `bwrap_gui_setup` (composite: base + home_tmpfs, with/without network), `bwrap_gui_finish` (composite: sandbox flags, malloc=no variant, dbus modes), `bwrap_ssh_agent` (empty without SSH_AUTH_SOCK), `bwrap_dbus_system` (no-error execution) |

## Running

```bash
# From project root
bash tests/test.sh
```

## How they work

### Test harness

The test script provides a minimal assertion framework and array inspection helpers:

- **Assertion functions**: `ok`/`fail`
- **Array helpers**: `has_arg` (flag present), `has_pair` (consecutive flag + value), `has_triple` (three consecutive values), `count_flag` (count occurrences of a flag)
- **Section headers**: `section` for grouping related tests
- **Summary**: final pass/fail counts; exits non-zero if any test failed

### Source and setup

The script sources `./bwrap-common.sh` directly, then creates a temporary directory (`mktemp -d`) cleaned up via `trap EXIT`. All tests run in the same bash process, exercising library functions by passing named arrays (bash namerefs) and inspecting the resulting argument lists.

### Source guard

Verifies that sourcing `bwrap-common.sh` a second time does not error — the `_BWRAP_COMMON_LOADED` guard variable prevents double initialization.

### Function definitions

Iterates over all 27 expected public functions and verifies each is defined via `declare -f`. This catches renames, typos, or accidental deletions.

### Individual function tests

Each function is called with a fresh empty array, then the array contents are inspected:

- **`bwrap_base`**: core filesystem layout — verifies `--ro-bind /usr`, `--proc /proc`, `--tmpfs /tmp` are present
- **`bwrap_home_tmpfs`**: verifies `--tmpfs $HOME` and `--dir ~/.config` for the XDG skeleton
- **`bwrap_env_base`**: verifies `--setenv` for `HOME`, `PATH`, `XDG_RUNTIME_DIR`
- **`bwrap_sandbox`**: verifies `--unshare-all`, `--die-with-parent`, `--new-session` in default mode; tests `--share-net` with `network=yes`; tests `--new-session` absence with `new_session=no`
- **`bwrap_no_hardened_malloc`**: verifies `--unsetenv LD_PRELOAD` and `--ro-bind /dev/null /etc/ld.so.preload` (masks the system preload file)
- **`bwrap_runtime_dir`**: verifies `--dir $XDG_RUNTIME_DIR`
- **`bwrap_gpu`**: verifies no-error execution (device presence is system-dependent)
- **`bwrap_lib64`**: verifies non-empty output (adapts to whether `/usr/lib64` is a real directory or symlink)
- **`bwrap_bind_dir`**: verifies directory creation on the host filesystem and `--bind` flag generation; tests multiple directories in a single call
- **`bwrap_ro_bind_dir`**: verifies `--ro-bind` for existing directories and empty output for nonexistent paths
- **`require_dir`**: verifies success for `/tmp` and failure (in a subshell) for a nonexistent path
- **`bwrap_fcitx`**: verifies `--setenv QT_IM_MODULE` and `--setenv XMODIFIERS` for input method support
- **`bwrap_ssh_agent`**: verifies empty output when `SSH_AUTH_SOCK` is unset

### Composite function tests

- **`bwrap_gui_setup`**: calls `bwrap_base` + `bwrap_lib64` + `bwrap_gpu` + `bwrap_runtime_dir` + `bwrap_home_tmpfs` internally; tests verify the combined output contains base binds and home tmpfs
- **`bwrap_gui_finish`**: calls themes + display + dbus + env + malloc + sandbox internally; tests verify `--unshare-all` presence and `--unsetenv LD_PRELOAD` when `malloc=no`

## CI

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on push/PR when `bwrap-common.sh`, `tests/**`, or the workflow file itself changes:

- **`shellcheck`** job: runs `shellcheck` with `-s bash` and suppressed informational codes (`SC2034`, `SC2178`, `SC2317`)
- **`test`** job: runs `bash tests/test.sh`

## Test environment

- Bash tests create a temporary directory (`mktemp -d`) cleaned up via `trap EXIT`
- No root privileges required
- No real bubblewrap sandboxes are launched — tests only inspect generated argument arrays
- No system files are modified; `bwrap_bind_dir` creates directories only inside the temporary directory
- Functions that check for optional system resources (GPU devices, Wayland socket, PipeWire, D-Bus, SSH agent) produce empty or minimal output when those resources are absent
