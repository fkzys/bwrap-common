# Tests

## Overview

| File | Language | Framework | What it tests |
|------|----------|-----------|---------------|
| `tests/test.sh` | Bash | Custom assertions | Source guard (re-source idempotency), function definitions (all 28 public functions exist), VERSION variable, `bwrap_base` (non-empty output, `--clearenv` first by default, explicit `--setenv` preserved, opt-out and invalid mode handling, `--ro-bind /usr`, `--proc /proc`, `--tmpfs /tmp`, default private `/dev/shm` tmpfs, opt-in host `/dev/shm` bind, invalid shm mode rejection), `bwrap_home_tmpfs` (`--tmpfs $HOME`, `--dir ~/.config`), `bwrap_env_base` (HOME/PATH/XDG_RUNTIME_DIR env vars), `bwrap_sandbox` (`--unshare-all`, `--die-with-parent`, `--new-session`, network/new-session toggles), `bwrap_no_hardened_malloc` (stub `/usr/lib/libhardened_malloc.so.empty` bound over both hardened_malloc variants when installed), `bwrap_runtime_dir` (XDG_RUNTIME_DIR directory creation), `bwrap_gpu`/`bwrap_lib64` (no-error execution, non-empty output), `bwrap_bind_dir` (directory creation, `--bind` flags, multiple dirs), `bwrap_ro_bind_dir` (existing dir bound, nonexistent dir skipped), `require_dir` (existing dir passes, missing dir fails), `bwrap_fcitx` (QT_IM_MODULE/XMODIFIERS env vars), `bwrap_gui_setup` (composite: base + home_tmpfs, with/without network, GPU toggle, shm and clearenv passthrough, exact composition), `bwrap_gui_finish` (composite: sandbox flags, `--clearenv` before explicit `--setenv`, malloc=no variant, dbus modes with filtered default, seccomp default/none/rejection), `bwrap_seccomp` (none/default, missing/invalid/arch-mismatched blobs fail closed, allowlist compile+cache, filter fd cleanup, fail-closed errors, duplicate `--seccomp`), `bwrap_ssh_agent` (empty without SSH_AUTH_SOCK), `bwrap_dbus_system` (no-error execution), `bwrap_exec` (exec vs. proxy branch selection, exact argument forwarding, exit-status propagation, D-Bus proxy cleanup, stdin inheritance — regression test for commit d308327) |
| `tests/seccomp-check.sh` | Bash + embedded C | Self-contained probe | Builds the default blocklist, runs an embedded C probe in a real `bwrap --unshare-all` sandbox, invokes every rule from `seccomp/default.conf`, checks `EPERM`/`ENOSYS`, verifies argument conditions (`clone`, `ioctl`, `personality`), and fails if a config rule has no test or the filter is inactive |
| `tests/arch-table-check.sh` | Bash + `bwrap-seccomp-gen` | Generator/table cross-check | Generates a minimal BPF blob with `--arch` for each known architecture and compares header bytes 12–15 with `_bwrap_seccomp_arch_magic()`; architectures that libseccomp cannot cross-add are reported as `SKIP` |

## Running

```bash
# From project root

# Unit tests (no real sandbox)
bash tests/test.sh

# Real seccomp end-to-end check (needs bwrap, libseccomp-dev, cc, make)
./tests/seccomp-check.sh

# Architecture table vs. generated BPF headers (needs libseccomp-dev, cc, make)
./tests/arch-table-check.sh
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

Iterates over all 28 expected public functions and verifies each is defined via `declare -f`. This catches renames, typos, or accidental deletions.

### Individual function tests

Each function is called with a fresh empty array, then the array contents are inspected:

- **`bwrap_base`**: clears the inherited environment by default — verifies `--clearenv` is first, an existing `--setenv` remains after it, `clearenv=no` omits `--clearenv` but keeps base mounts, an invalid clearenv mode is rejected with the `bwrap_base` message, `--ro-bind /usr`, `--proc /proc`, `--tmpfs /tmp` are present; default `/dev/shm` is the adjacent sequence `--perms 1777 --tmpfs /dev/shm`, `shm=bind` uses `--bind /dev/shm /dev/shm` and is ordered after `--dev /dev` and before `--ro-bind /etc`, explicit `shm=tmpfs` matches the default, and an invalid shm mode is rejected with the `bwrap_base` message
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

- **`bwrap_gui_setup`**: calls `bwrap_base` + `bwrap_lib64` + optional `bwrap_gpu` + optional `bwrap_resolv` + `bwrap_runtime_dir` + `bwrap_home_tmpfs` internally; `bwrap_gpu` is only called when the GPU argument is `yes` (default `no`). The default shm mode is `tmpfs`; `shm=bind` is forwarded to `bwrap_base`, and an invalid shm mode returns non-zero with the `bwrap_gui_setup` message. Environment clearing is on by default; `clearenv=no` omits `--clearenv`, and an invalid value is rejected with the `bwrap_gui_setup` message. The tests compare the generated argument array against the expected composition rebuilt from the same helpers: the default GPU argument matches an explicit `gpu=no` call, `gpu=yes` equals `base+lib64+gpu+runtime_dir+home_tmpfs`, `gpu=no` equals that composition with no GPU resource at all, and the network toggle is independent of it — `net=yes` adds the resolv bind while `net=no` omits it. The combined `net=yes gpu=yes` call is checked as well and must equal `base+lib64+gpu+resolv+runtime_dir+home_tmpfs`. Because the expectation is rebuilt from the helpers rather than from a fixed list of device paths, the assertions hold on hosts with and without GPU devices and catch any resource `bwrap_gpu` may expose in the future; only the resolv checks are skipped when `/etc/resolv.conf` is not a symlink.
- **`bwrap_gui_finish`**: calls themes + display + dbus + env + malloc + seccomp + sandbox internally; tests verify that `--clearenv` from `bwrap_base` stays first and explicit `--setenv HOME` survives, `--unshare-all` presence, the `malloc=no` hardened_malloc stub (skipped when not installed), and the 7th seccomp parameter: `default` appends `--seccomp`, `none` omits it, and an allowlist spec is rejected with a non-zero status. They also verify that `seccomp=default` fails when the blob is missing while `seccomp=none` still succeeds, that `dbus=filtered` (including the omitted-mode default) fails without `xdg-dbus-proxy`, and that `dbus=none`/`unfiltered` do not require the proxy

### Seccomp filter tests

The test harness builds a 16-byte fake cBPF blob whose bytes 12–15 match the
host architecture magic, points `BWRAP_SECCOMP_DIR` at it, and exercises the
shell-side logic without loading a real filter into the kernel:

- `bwrap_seccomp A none` appends nothing and returns 0
- `bwrap_seccomp A default` appends `--seccomp <numeric fd>` for a valid blob
- a missing blob, a wrong-size blob, or a wrong-arch blob fails closed and
  appends nothing
- architecture magic is checked in native byte order: a synthetic s390x
  big-endian blob (`80000016`) is accepted, the old little-endian value is
  rejected, and mips/mips64/parisc/ppc64 mappings are covered
- an unknown architecture fails closed instead of silently skipping the check
- an unsupported host architecture aborts the suite instead of silently
  substituting x86_64; `BWRAP_SECCOMP_ARCH` is only an explicit cross-arch
  test override
- an allowlist compiles through a fake generator once and then reuses the
  cache; the cached file is mode `0600`
- an empty allowlist, a failing generator, and a pre-existing `--seccomp`
  argument all fail closed and leave no temporary files

### D-Bus filtered tests

`bwrap_dbus_filtered`, `bwrap_dbus_common`, and `bwrap_gui_finish` are tested
with an empty `PATH` so `xdg-dbus-proxy` is unavailable:

- `bwrap_dbus_filtered` and `bwrap_dbus_common` return 1 and append nothing
- `bwrap_gui_finish` with `dbus=filtered`, or with the mode omitted (the
  default), returns 1 and adds neither the bus bind nor
  `DBUS_SESSION_BUS_ADDRESS`
- `dbus=none` and `dbus=unfiltered` still return 0; only `none` is guaranteed
  to add no bus arguments

### Architecture table cross-check (`arch-table-check.sh`)

`tests/arch-table-check.sh` builds `bwrap-seccomp-gen`, generates a
header-only blob from an empty blocklist for each architecture with `--arch`,
and compares bytes 12–15 with `_bwrap_seccomp_arch_magic()`. This catches drift
between the shell table and libseccomp's emitted `AUDIT_ARCH` value, including
endianness. Targets not recognised by the local libseccomp build are reported
as `SKIP` using the generator's exit status 3 (not stderr text matching); all
other generation failures are test failures. The s390x CI job runs the same
script natively so the big-endian s390x entry is checked against a real
generated blob.

### Seccomp end-to-end check (`seccomp-check.sh`)

`tests/seccomp-check.sh` verifies the compiled default filter against the real
kernel. It builds `build/bwrap-seccomp-gen` and
`build/seccomp/default.<arch>.bpf`, compiles an embedded C probe (static with a
dynamic fallback), and runs it under `bwrap --unshare-all` with the default
`--seccomp` blob. Each rule in `seccomp/default.conf` is invoked and must return
the configured errno; the probe also checks the argument-conditioned rules
(`clone` with `CLONE_NEWUSER` vs. `SIGCHLD`, `ioctl` `TIOCSTI`/`TIOCLINUX` vs.
`FIONREAD`, high-bit `ioctl` command aliases, `personality` other execution
domains vs. `PER_LINUX`/`PER_LINUX32`). A canary aborts
before any blocked syscall if the filter is not active, and the script fails if
a rule has no corresponding test. It requires `bwrap`, the `libseccomp`
headers, `cc`, and `make`.

### Process execution tests (`bwrap_exec`)

`bwrap_exec` replaces the shell (`exec bwrap ...`) when no filtered D-Bus proxy is running, and otherwise runs bwrap as a background child while forwarding signals and cleaning up the proxies. Both branches are tested through a fake `bwrap` executable written to `$TMPDIR_TEST/fakebin` and prepended to `PATH` for the duration of each call. The fake captures its arguments NUL-delimited (so empty-string arguments survive), optionally copies stdin to a file, and exits with a configurable status. Every call runs in a subshell, so `exec`/`exit` cannot terminate the test runner.

- **exec branch**: arguments are forwarded verbatim (spaces and empty strings included), exit status is propagated, stdin from fd 0 is inherited, and `_bwrap_dbus_cleanup` is not invoked (proves the fast path is taken)
- **proxy branch**: arguments and exit status are still forwarded/propagated, `_bwrap_dbus_cleanup` runs exactly once even on failure, stdin is inherited, and the caller's original `EXIT` trap runs after proxy cleanup with the preserved status
- **stdin regression (commit d308327)**: the proxy branch must pass piped stdin to bwrap. Before the fix, `bwrap "$@" &` ran without job control, so bash redirected the child's stdin to `/dev/null`; the test fails if the line loses the explicit `<&0`

## CI

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on push/PR when `bwrap-common.sh`, `tests/**`, `seccomp/**`, `tools/**`, `Makefile`, or the workflow file itself changes:

- **`shellcheck`** job: runs `shellcheck` with `-s bash` and suppressed informational codes (`SC2034`, `SC2178`, `SC2317`) on `bwrap-common.sh` and `tests/seccomp-check.sh`
- **`test`** job: runs `bash tests/test.sh`
- **`seccomp`** job: installs `bubblewrap`, `libseccomp-dev`, and `build-essential`, enables unprivileged user namespaces, and runs `tests/seccomp-check.sh`; it retries as root only when the script reports exit status `77` (sandbox environment unavailable), so real filter failures are not masked

## Test environment

- Bash tests create a temporary directory (`mktemp -d`) cleaned up via `trap EXIT`
- No root privileges required
- The unit tests do not launch real bubblewrap sandboxes — argument-building tests only inspect generated arrays, and `bwrap_exec` is exercised through a fake `bwrap` placed first in `PATH`
- `tests/test.sh` seccomp tests use fake cBPF blobs and a fake generator; no real seccomp filter is loaded into that test process
- `tests/seccomp-check.sh` does launch a real `bwrap` sandbox and loads the compiled default filter; it needs `bwrap`, `libseccomp-dev`, `cc`, and `make`
- No system files are modified; `bwrap_bind_dir` creates directories only inside the temporary directory
- Functions that check for optional system resources (GPU devices, Wayland socket, PipeWire, D-Bus, SSH agent) produce empty or minimal output when those resources are absent
