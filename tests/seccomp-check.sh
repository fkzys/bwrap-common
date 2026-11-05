#!/usr/bin/env bash
# seccomp-check.sh — exercise every syscall blocked by seccomp/default.conf
# inside a bubblewrap sandbox with the default filter, and verify the errno
# the filter is supposed to return (EPERM or ENOSYS).
#
# Usage: ./tests/seccomp-check.sh
#
# The probe is compiled from tests/fixtures/seccomp-probe.c and runs as a child
# of bwrap, so the filter is installed by bubblewrap exactly as for real apps.
# Exit status: 0 = all rules verified, 1 = a rule failed or was not exercised,
# 2 = the default filter was not active, 77 = the sandbox environment is
# unavailable (e.g. unprivileged user namespaces are disabled).

set -euo pipefail

_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -n "${BWRAP_SECCOMP_CONF:-}" ]]; then
    _conf="$BWRAP_SECCOMP_CONF"
elif [[ -n "${BWRAP_SECCOMP_DIR:-}" ]]; then
    _conf="${BWRAP_SECCOMP_DIR}/default.conf"
else
    _conf="$_root/seccomp/default.conf"
fi

if [[ ! -f "$_conf" ]]; then
    echo "seccomp-check: missing $_conf" >&2
    exit 1
fi

if [[ -z "${BWRAP_SECCOMP_GEN:-}" ]]; then
    make -C "$_root" build
    BWRAP_SECCOMP_GEN="$_root/build/bwrap-seccomp-gen"
fi
if [[ -z "${BWRAP_SECCOMP_CONF:-}" && -z "${BWRAP_SECCOMP_DIR:-}" ]]; then
    BWRAP_SECCOMP_CONF="$_conf"
fi
export BWRAP_SECCOMP_GEN
[[ -n "${BWRAP_SECCOMP_CONF:-}" ]] && export BWRAP_SECCOMP_CONF
[[ -n "${BWRAP_SECCOMP_DIR:-}" ]] && export BWRAP_SECCOMP_DIR

_tmp=$(mktemp -d "${TMPDIR:-/tmp}/seccomp-check.XXXXXX")
trap 'rm -rf "$_tmp"' EXIT
_probe_src="$_root/tests/fixtures/seccomp-probe.c"
_extra_probe_src="$_root/tests/fixtures/seccomp-extra-probe.c"
export BWRAP_SECCOMP_CACHE_DIR="${BWRAP_SECCOMP_CACHE_DIR:-$_tmp/cache}"


if ! cc -O2 -static -o "$_tmp/probe" "$_probe_src" 2>"$_tmp/cc.err"; then
    if ! cc -O2 -o "$_tmp/probe" "$_probe_src"; then
        cat "$_tmp/cc.err" >&2
        echo "seccomp-check: cannot compile probe" >&2
        exit 1
    fi
    _dynamic=1
else
    _dynamic=0
fi

# shellcheck source=../bwrap-common.sh disable=SC1091
. "$_root/bwrap-common.sh"

printf 'getppid ALLOW\n' >"$_tmp/base-allow.conf"
if "$BWRAP_SECCOMP_GEN" --blocklist "$_tmp/base-allow.conf" --strict \
        -o "$_tmp/base-allow.bpf" 2>/dev/null; then
    echo "seccomp-check: strict mode accepted ALLOW in the base blocklist" >&2
    exit 1
fi

printf 'ptrace EPERM\n' >"$_tmp/extra-base.conf"
printf 'ptrace ALLOW\n' >"$_tmp/extra.rules"
if ! "$BWRAP_SECCOMP_GEN" --blocklist "$_tmp/extra-base.conf" \
        --extra "$_tmp/extra.rules" -o "$_tmp/extra-allow.bpf" \
        2>"$_tmp/extra-allow.err"; then
    echo "seccomp-check: extra ALLOW rule was rejected" >&2
    exit 1
fi
if ! grep -q "overrides a default deny with ALLOW" "$_tmp/extra-allow.err"; then
    echo "seccomp-check: extra ALLOW override did not warn" >&2
    exit 1
fi

if printf 'getppid EPERM\n' |
        "$BWRAP_SECCOMP_GEN" --blocklist - --extra - -o "$_tmp/two-stdin.bpf" \
        2>/dev/null; then
    echo "seccomp-check: generator accepted two stdin inputs" >&2
    exit 1
fi

if ! bwrap --unshare-all --ro-bind / / -- /usr/bin/true \
        >"$_tmp/preflight" 2>&1; then
    cat "$_tmp/preflight" >&2
    if grep -Eqi 'namespace|permission|operation not permitted|unshare' \
            "$_tmp/preflight"; then
        echo "seccomp-check: unprivileged sandbox unavailable" >&2
        exit 77
    fi
    echo "seccomp-check: bwrap preflight failed" >&2
    exit 1
fi

_args=()
if (( _dynamic )); then
    bwrap_base _args
    bwrap_lib64 _args
else
    _args+=(--dev /dev)
fi
_args+=(--ro-bind "$_tmp/probe" /probe)
bwrap_sandbox _args no
bwrap_seccomp _args default

_status=0
bwrap "${_args[@]}" -- /probe >"$_tmp/out" 2>&1 || _status=$?
cat "$_tmp/out"

if (( _status == 2 )); then
    echo "seccomp-check: default filter is not active" >&2
    exit 2
fi

_fail=0
if (( _status != 0 )); then
    echo "seccomp-check: probe failed (status $_status)" >&2
    _fail=1
fi

mapfile -t _rules < <(
    awk '!/^[[:space:]]*#/ && NF { print $1 }' "$_conf" | sort -u
)

declare -A _seen=()
while IFS= read -r _line; do
    case "$_line" in
        PASS\ *|FAIL\ *|SKIP\ *)
            _name=${_line#* }
            _name=${_name%% *}
            _name=${_name%%:*}
            _seen["$_name"]=1
            ;;
    esac
done <"$_tmp/out"

for _rule in "${_rules[@]}"; do
    if [[ -z "${_seen[$_rule]:-}" ]]; then
        echo "seccomp-check: default.conf rule was not exercised: $_rule" >&2
        _fail=1
    fi
done

if (( _fail == 0 )); then

    if ! cc -O2 -static -o "$_tmp/extra-probe" "$_extra_probe_src" 2>"$_tmp/extra-cc.err"; then
        if ! cc -O2 -o "$_tmp/extra-probe" "$_extra_probe_src"; then
            cat "$_tmp/extra-cc.err" >&2
            echo "seccomp-check: cannot compile extra-rule probe" >&2
            _fail=1
        fi
    fi
fi

if (( _fail == 0 )); then
    _extra_args=()
    if (( _dynamic )); then
        bwrap_base _extra_args
        bwrap_lib64 _extra_args
    else
        _extra_args+=(--dev /dev)
    fi
    _extra_args+=(--ro-bind "$_tmp/extra-probe" /extra-probe)
    bwrap_sandbox _extra_args no
    if ! bwrap_seccomp _extra_args default \
            "ptrace ALLOW" "personality ALLOW a0 == 1" "getppid EPERM"; then
        echo "seccomp-check: cannot build the default+extra filter" >&2
        _fail=1
    else
        _extra_status=0
        bwrap "${_extra_args[@]}" -- /extra-probe >"$_tmp/extra-out" 2>&1 || _extra_status=$?
        cat "$_tmp/extra-out"
        if (( _extra_status != 0 )); then
            echo "seccomp-check: extra-rule merge failed (status $_extra_status)" >&2
            _fail=1
        fi
    fi
fi

if (( _fail )); then
    exit 1
fi

_passed=$(awk '/^PASS / { n++ } END { print n + 0 }' "$_tmp/out")
_skipped=$(awk '/^SKIP / { n++ } END { print n + 0 }' "$_tmp/out")
mapfile -t _skipped_names < <(awk '/^SKIP / { print $2 }' "$_tmp/out")
if (( ${#_skipped_names[@]} > 0 )); then
    echo " skipped:"
    for _name in "${_skipped_names[@]}"; do
        echo "  ⊘ $_name"
    done
fi
echo "seccomp-check: $_passed passed, $_skipped skipped (${#_rules[@]} unique rules), including extra-rule merge"
