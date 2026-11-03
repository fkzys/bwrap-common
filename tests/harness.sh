#!/usr/bin/env bash
set -uo pipefail
# Note: no -e. Tests must continue running when assertions fail
# so failures can be counted and reported.

# ── Test harness ─────────────────────────────────────────────

PASS=0
FAIL=0
TESTS=0

ok() {
    PASS=$((PASS + 1))
    TESTS=$((TESTS + 1))
    echo "  ✓ $1"
    return 0
}

fail() {
    FAIL=$((FAIL + 1))
    TESTS=$((TESTS + 1))
    echo "  ✗ $1"
    return 0
}

section() {
    echo ""
    echo "── $1 ──"
}

summary() {
    local name="${0##*/}"
    echo ""
    echo "════════════════════════════════════"
    echo " ${name}: ${PASS} passed, ${FAIL} failed (total: ${TESTS})"
    echo "════════════════════════════════════"
    [[ $FAIL -eq 0 ]]
}

has_arg() {
    local -n _arr=$1; local flag=$2
    for arg in "${_arr[@]}"; do
        [[ "$arg" == "$flag" ]] && return 0
    done
    return 1
}

has_pair() {
    local -n _arr=$1; local flag=$2 val=$3
    for ((i=0; i<${#_arr[@]}-1; i++)); do
        [[ "${_arr[$i]}" == "$flag" && "${_arr[$((i+1))]}" == "$val" ]] && return 0
    done
    return 1
}

has_triple() {
    local -n _arr=$1; local a=$2 b=$3 c=$4
    for ((i=0; i<${#_arr[@]}-2; i++)); do
        [[ "${_arr[$i]}" == "$a" && "${_arr[$((i+1))]}" == "$b" && "${_arr[$((i+2))]}" == "$c" ]] && return 0
    done
    return 1
}

has_sequence() {
    local -n _arr=$1; shift
    local -a _want=("$@")
    local _n=${#_want[@]} _i _j
    (( _n > 0 && _n <= ${#_arr[@]} )) || return 1
    for ((_i=0; _i <= ${#_arr[@]} - _n; _i++)); do
        for ((_j=0; _j < _n; _j++)); do
            [[ "${_arr[$((_i + _j))]}" == "${_want[$_j]}" ]] || break
        done
        (( _j == _n )) && return 0
    done
    return 1
}

has_ordered_pairs() {
    local -n _arr=$1; shift
    local _len=${#_arr[@]} _i=0 _flag _val _found
    while (( $# >= 2 )); do
        _flag=$1
        _val=$2
        shift 2
        _found=0
        for ((; _i < _len - 1; _i++)); do
            if [[ "${_arr[$_i]}" == "$_flag" && "${_arr[$((_i + 1))]}" == "$_val" ]]; then
                _i=$((_i + 2))
                _found=1
                break
            fi
        done
        (( _found )) || return 1
    done
    return 0
}

count_flag() {
    local -n _arr=$1; local flag=$2; local count=0
    for arg in "${_arr[@]}"; do [[ "$arg" == "$flag" ]] && count=$((count + 1)); done
    echo "$count"
}

arrays_equal() {
    local -n _a=$1; local -n _b=$2
    [[ ${#_a[@]} -eq ${#_b[@]} ]] || return 1
    local i
    for ((i = 0; i < ${#_a[@]}; i++)); do
        [[ "${_a[$i]}" == "${_b[$i]}" ]] || return 1
    done
    return 0
}

