#!/usr/bin/env bash
set -uo pipefail

_tests_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

. "$_tests_dir/harness.sh"
. "$_tests_dir/setup.sh"
. "$_tests_dir/test-base.sh"
. "$_tests_dir/test-gui.sh"
. "$_tests_dir/test-seccomp.sh"
. "$_tests_dir/test-dbus.sh"
. "$_tests_dir/test-exec.sh"

summary
