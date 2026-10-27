# Tests

## Overview

| File | Language | Framework | What it tests |
|------|----------|-----------|---------------|
| `tests/test.sh` | Bash | Custom assertions | Source guard (re-source idempotency), function definitions (all 27 public functions exist), VERSION variable, `bwrap_base` (non-empty output, `--ro-bind /usr`, `--proc /proc`, `--tmpfs /tmp`), `bwrap_home_tmpfs` (`--tmpfs $HOME`, `--dir ~/.config`), `bwrap_env_base` (HOME/PATH/XDG_RUNTIME_DIR env vars), `bwrap_sandbox` (`--unshare-all`, `--die-with-parent`, `--new-session`, network/new-session toggles), `bwrap_no_hardened_malloc` (stub `/usr/lib/libhardened_malloc.so.empty` bound over both hardened_malloc variants when installed), `bwrap_runtime_dir` (XDG_RUNTIME_DIR directory creation), `bwrap_gpu`/`bwrap_lib64` (no-error execution, non-empty output), `bwrap_bind_dir` (directory creation, `--bind` flags, multiple dirs), `bwrap_ro_bind_dir` (existing dir bound, nonexistent dir skipped), `require_dir` (existing dir passes, missing dir fails), `bwrap_fcitx` (QT_IM_MODULE/XMODIFIERS env vars), `bwrap_gui_setup` (composite: base + home_tmpfs, with/without network, GPU toggle, exact composition), `bwrap_gui_finish` (composite: sandbox flags, malloc=no variant, dbus modes), `bwrap_ssh_agent` (empty without SSH_AUTH_SOCK), `bwrap_dbus_system` (no-error execution), `bwrap_exec` (exec vs. proxy branch selection, exact argument forwarding, exit-status propagation, D-Bus proxy cleanup, stdin inheritance — regression test for commit d308327) |

## Running

```bash
# From project root
bash tests/test.sh
```

## How they work

### Test harness

The test script provides a minimal assertion framework and array inspection helpers:

- **Assertion functions**: `ok`/`fail` — both always exit 0, so `cond && ok "..." || fail "..."` stays unambiguous even if writing the message to stdout fails
- **Array helpers**: `has_arg` (flag present), `has_pair` (consecutive flag + value), `has_triple` (three consecutive values), `count_flag` (count occurrences of a flag), `arrays_equal` (exact element-wise comparison of two arrays)
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
- **`bwrap_no_hardened_malloc`**: verifies `--ro-bind` of the empty stub `/usr/lib/libhardened_malloc.so.empty` over `libhardened_malloc-light.so` and `libhardened_malloc.so` when the stub is installed on the host (skipped otherwise)
- **`bwrap_runtime_dir`**: verifies `--dir $XDG_RUNTIME_DIR`
- **`bwrap_gpu`**: verifies no-error execution (device presence is system-dependent)
- **`bwrap_lib64`**: verifies non-empty output (adapts to whether `/usr/lib64` is a real directory or symlink)
- **`bwrap_bind_dir`**: verifies directory creation on the host filesystem and `--bind` flag generation; tests multiple directories in a single call
- **`bwrap_ro_bind_dir`**: verifies `--ro-bind` for existing directories and empty output for nonexistent paths
- **`require_dir`**: verifies success for `/tmp` and failure (in a subshell) for a nonexistent path
- **`bwrap_fcitx`**: verifies `--setenv QT_IM_MODULE` and `--setenv XMODIFIERS` for input method support
- **`bwrap_ssh_agent`**: verifies empty output when `SSH_AUTH_SOCK` is unset

### Composite function tests

- **`bwrap_gui_setup`**: calls `bwrap_base` + `bwrap_lib64` + optional `bwrap_gpu` + optional `bwrap_resolv` + `bwrap_runtime_dir` + `bwrap_home_tmpfs` internally; `bwrap_gpu` is only called when the GPU argument is `yes` (default). The tests compare the generated argument array against the expected composition rebuilt from the same helpers: the default GPU argument matches an explicit `gpu=yes` call, `gpu=yes` equals `base+lib64+gpu+runtime_dir+home_tmpfs`, `gpu=no` equals that composition with no GPU resource at all, and the network toggle is independent of it — `net=yes` adds the resolv bind while `net=no` omits it. The combined `net=yes gpu=yes` call is checked as well and must equal `base+lib64+gpu+resolv+runtime_dir+home_tmpfs`. Because the expectation is rebuilt from the helpers rather than from a fixed list of device paths, the assertions hold on hosts with and without GPU devices and catch any resource `bwrap_gpu` may expose in the future; only the resolv checks are skipped when `/etc/resolv.conf` is not a symlink.
- **`bwrap_gui_finish`**: calls themes + display + dbus + env + malloc + sandbox internally; tests verify `--unshare-all` presence and, when `malloc=no`, that the hardened_malloc stub is bound (skipped when the stub is not installed)

### Process execution tests (`bwrap_exec`)

`bwrap_exec` replaces the shell (`exec bwrap ...`) when no filtered D-Bus proxy is running, and otherwise runs bwrap as a background child while forwarding signals and cleaning up the proxies. Both branches are tested through a fake `bwrap` executable written to `$TMPDIR_TEST/fakebin` and prepended to `PATH` for the duration of each call. The fake captures its arguments NUL-delimited (so empty-string arguments survive), optionally copies stdin to a file, and exits with a configurable status. Every call runs in a subshell, so `exec`/`exit` cannot terminate the test runner.

- **exec branch**: arguments are forwarded verbatim (spaces and empty strings included), exit status is propagated, stdin from fd 0 is inherited, and `_bwrap_dbus_cleanup` is not invoked (proves the fast path is taken)
- **proxy branch**: arguments and exit status are still forwarded/propagated, `_bwrap_dbus_cleanup` runs exactly once even on failure, and stdin is inherited
- **stdin regression (commit d308327)**: the proxy branch must pass piped stdin to bwrap. Before the fix, `bwrap "$@" &` ran without job control, so bash redirected the child's stdin to `/dev/null`; the test fails if the line loses the explicit `<&0`

## CI

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on push/PR when `bwrap-common.sh`, `tests/**`, or the workflow file itself changes:

- **`shellcheck`** job: runs `shellcheck` with `-s bash` and suppressed informational codes (`SC2034`, `SC2178`, `SC2317`)
- **`test`** job: runs `bash tests/test.sh`

## Test environment

- Bash tests create a temporary directory (`mktemp -d`) cleaned up via `trap EXIT`
- No root privileges required
- No real bubblewrap sandboxes are launched — argument-building tests only inspect generated arrays, and `bwrap_exec` is exercised through a fake `bwrap` placed first in `PATH`
- No system files are modified; `bwrap_bind_dir` creates directories only inside the temporary directory
- Functions that check for optional system resources (GPU devices, Wayland socket, PipeWire, D-Bus, SSH agent) produce empty or minimal output when those resources are absent
