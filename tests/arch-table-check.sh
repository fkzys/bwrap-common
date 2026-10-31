#!/usr/bin/env bash
# arch-table-check.sh — verify _bwrap_seccomp_arch_magic() against the real
# BPF header emitted by bwrap-seccomp-gen --arch.
#
# Architectures not recognised by the local libseccomp build are reported as
# SKIP using the generator's dedicated exit status, not by matching stderr
# text.  Run this script natively on the target architecture to check its
# native entry.

set -euo pipefail

_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
_gen="${BWRAP_SECCOMP_GEN:-$_root/build/bwrap-seccomp-gen}"
_tmp=$(mktemp -d "${TMPDIR:-/tmp}/arch-table-check.XXXXXX")
trap 'rm -rf "$_tmp"' EXIT

# shellcheck source=../bwrap-common.sh disable=SC1091
. "$_root/bwrap-common.sh"

if [[ -z "${BWRAP_SECCOMP_GEN:-}" ]]; then
    make -C "$_root" build >/dev/null
fi
if [[ ! -x "$_gen" ]]; then
    echo "arch-table-check: generator not executable: $_gen" >&2
    exit 1
fi

# An empty blocklist is enough: this test only inspects the BPF header's
# AUDIT_ARCH field, and a ruleless filter lets libseccomp cross-export targets
# whose syscall tables cannot be combined with the native architecture.
: >"$_tmp/min.conf"

_archs=(
    x86_64 aarch64 i386 armv7l riscv64 ppc64le ppc64 ppc
    s390x s390 loongarch64
    mips mipsel mips64 mips64el mips64n32 mips64n32el
    parisc parisc64
)

_checked=0
_skipped=0
_failed=0

for _arch in "${_archs[@]}"; do
    if ! _want=$(_bwrap_seccomp_arch_magic "$_arch"); then
        echo "FAIL $_arch: missing entry in _bwrap_seccomp_arch_magic" >&2
        _failed=1
        continue
    fi

    _out="$_tmp/$_arch.bpf"
    _err="$_tmp/$_arch.err"
    if "$_gen" --blocklist "$_tmp/min.conf" --arch "$_arch" -o "$_out" 2>"$_err"; then
        :
    else
        _gen_rc=$?
        if (( _gen_rc == 3 )); then
            printf 'SKIP %s (unsupported by local libseccomp)\n' "$_arch"
            _skipped=$((_skipped + 1))
            continue
        fi
        echo "FAIL $_arch: generator failed with status $_gen_rc" >&2
        cat "$_err" >&2
        _failed=1
        continue
    fi

    _got=$(od -An -tx1 -j12 -N4 "$_out" | tr -d ' \n')
    if [[ "$_got" != "$_want" ]]; then
        echo "FAIL $_arch: table=$_want generated=$_got" >&2
        _failed=1
        continue
    fi
    printf 'PASS %s %s\n' "$_arch" "$_got"
    _checked=$((_checked + 1))
done

if (( _checked == 0 )); then
    echo "arch-table-check: no architecture was actually checked" >&2
    _failed=1
fi

echo "arch-table-check: $_checked passed, $_skipped skipped"
exit "$_failed"
