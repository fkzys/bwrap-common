#!/usr/bin/env bash
# seccomp-check.sh — exercise every syscall blocked by seccomp/default.conf
# inside a bubblewrap sandbox with the default filter, and verify the errno
# the filter is supposed to return (EPERM or ENOSYS).
#
# Usage: ./tests/seccomp-check.sh
#
# The probe is compiled from the embedded C source below and runs as a child
# of bwrap, so the filter is installed by bubblewrap exactly as for real apps.
# Exit status: 0 = all rules verified, 1 = a rule failed or was not exercised,
# 2 = the default filter was not active, 77 = the sandbox environment is
# unavailable (e.g. unprivileged user namespaces are disabled).

set -euo pipefail

_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
_conf="$_root/seccomp/default.conf"

if [[ ! -f "$_conf" ]]; then
    echo "seccomp-check: missing $_conf" >&2
    exit 1
fi

if [[ -z "${BWRAP_SECCOMP_DIR:-}" ]]; then
    make -C "$_root" ARCH="$(uname -m)" build
    BWRAP_SECCOMP_DIR="$_root/build/seccomp"
fi
export BWRAP_SECCOMP_DIR

_tmp=$(mktemp -d "${TMPDIR:-/tmp}/seccomp-check.XXXXXX")
trap 'rm -rf "$_tmp"' EXIT

cat >"$_tmp/probe.c" <<'PROBE'
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sched.h>

#ifndef CLONE_NEWUSER
#define CLONE_NEWUSER 0x10000000UL
#endif
#ifndef TIOCSTI
#define TIOCSTI 0x5412UL
#endif
#ifndef TIOCLINUX
#define TIOCLINUX 0x541cUL
#endif
#ifndef PER_LINUX
#define PER_LINUX 0UL
#endif
#ifndef PER_LINUX32
#define PER_LINUX32 0x0008UL
#endif
#ifndef SYS_umount
#if defined(__x86_64__) && !defined(__ILP32__)
#define SYS_umount 166
#endif
#endif

enum action {
	A_EPERM,
	A_ENOSYS,
	A_ALLOW,
};

static int failures;

static const char *action_name(enum action action)
{
	switch (action) {
	case A_EPERM:
		return "EPERM";
	case A_ENOSYS:
		return "ENOSYS";
	case A_ALLOW:
		return "allow";
	}
	return "?";
}

static void report_result(const char *name, enum action want, long rc, int err)
{
	int ok;

	if (want == A_ALLOW)
		ok = !(rc == -1 && err == EPERM);
	else
		ok = rc == -1 && err == (want == A_EPERM ? EPERM : ENOSYS);

	printf("%s %s want=%s got=%s\n",
	       ok ? "PASS" : "FAIL", name, action_name(want),
	       rc == -1 ? strerror(err) : "success");
	if (!ok)
		failures++;
}

/*
 * Evaluate the syscall expression after clearing errno, then capture errno
 * immediately. Passing syscall(...) and errno as separate function arguments
 * would leave their evaluation order unspecified and could read a stale errno.
 */
#define report(name, want, expr) do { \
	long _rc; \
	int _err; \
	errno = 0; \
	_rc = (expr); \
	_err = errno; \
	report_result((name), (want), _rc, _err); \
} while (0)

#define SKIP(name) do { printf("SKIP %s undefined-on-arch\n", name); return; } while (0)

static void t_syslog(void)
{
#ifdef SYS_syslog
	report("syslog", A_EPERM, syscall(SYS_syslog, 3, NULL, 0));
#else
	SKIP("syslog");
#endif
}

static void t_acct(void)
{
#ifdef SYS_acct
	report("acct", A_EPERM, syscall(SYS_acct, "/nonexistent"));
#else
	SKIP("acct");
#endif
}

static void t_quotactl(void)
{
#ifdef SYS_quotactl
	report("quotactl", A_EPERM,
	       syscall(SYS_quotactl, 0, "/dev/null", 0, NULL));
#else
	SKIP("quotactl");
#endif
}

static void t_uselib(void)
{
#ifdef SYS_uselib
	report("uselib", A_EPERM, syscall(SYS_uselib, "/nonexistent"));
#else
	SKIP("uselib");
#endif
}

static void t_add_key(void)
{
#ifdef SYS_add_key
	report("add_key", A_EPERM,
	       syscall(SYS_add_key, "user", "bwrap-probe", "x", 1UL, -1));
#else
	SKIP("add_key");
#endif
}

static void t_keyctl(void)
{
#ifdef SYS_keyctl
	report("keyctl", A_EPERM, syscall(SYS_keyctl, 0, -1, 0));
#else
	SKIP("keyctl");
#endif
}

static void t_request_key(void)
{
#ifdef SYS_request_key
	report("request_key", A_EPERM,
	       syscall(SYS_request_key, "user", "bwrap-probe", NULL, -1));
#else
	SKIP("request_key");
#endif
}

static void t_mount(void)
{
#ifdef SYS_mount
	report("mount", A_EPERM,
	       syscall(SYS_mount, "none", "/nonexistent", "tmpfs", 0UL, NULL));
#else
	SKIP("mount");
#endif
}

static void t_umount(void)
{
#ifdef SYS_umount
	report("umount", A_EPERM, syscall(SYS_umount, "/nonexistent"));
#else
	SKIP("umount");
#endif
}

static void t_umount2(void)
{
#ifdef SYS_umount2
	report("umount2", A_EPERM,
	       syscall(SYS_umount2, "/nonexistent", 0));
#else
	SKIP("umount2");
#endif
}

static void t_pivot_root(void)
{
#ifdef SYS_pivot_root
	report("pivot_root", A_EPERM,
	       syscall(SYS_pivot_root, "/nonexistent", "/nonexistent"));
#else
	SKIP("pivot_root");
#endif
}

static void t_chroot(void)
{
#ifdef SYS_chroot
	report("chroot", A_EPERM, syscall(SYS_chroot, "/nonexistent"));
#else
	SKIP("chroot");
#endif
}

static void t_setns(void)
{
#ifdef SYS_setns
	report("setns", A_EPERM, syscall(SYS_setns, -1, 0));
#else
	SKIP("setns");
#endif
}

static void *stack_alloc(size_t size)
{
	void *stack;

	stack = mmap(NULL, size, PROT_READ | PROT_WRITE,
		     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	return stack == MAP_FAILED ? NULL : stack;
}

static void t_clone_newuser(void)
{
#ifdef SYS_clone
	const size_t size = 64 * 1024;
	void *stack = stack_alloc(size);
	long rc;
	int err;

	if (!stack) {
		printf("SKIP clone:CLONE_NEWUSER mmap-failed\n");
		return;
	}

	errno = 0;
	rc = syscall(SYS_clone, (unsigned long)(CLONE_NEWUSER | SIGCHLD),
		     (char *)stack + size, NULL, NULL, 0);
	if (rc == 0)
		_exit(0);
	err = errno;
	if (rc > 0)
		waitpid((pid_t)rc, NULL, 0);
	munmap(stack, size);
	report_result("clone:CLONE_NEWUSER", A_EPERM, rc, err);
#else
	SKIP("clone:CLONE_NEWUSER");
#endif
}

static void t_clone_allowed(void)
{
#ifdef SYS_clone
	const size_t size = 64 * 1024;
	void *stack = stack_alloc(size);
	long rc;
	int err;

	if (!stack) {
		printf("SKIP clone:SIGCHLD mmap-failed\n");
		return;
	}

	errno = 0;
	rc = syscall(SYS_clone, (unsigned long)SIGCHLD,
		     (char *)stack + size, NULL, NULL, 0);
	if (rc == 0)
		_exit(0);
	err = errno;
	if (rc > 0)
		waitpid((pid_t)rc, NULL, 0);
	munmap(stack, size);
	report_result("clone:SIGCHLD", A_ALLOW, rc, err);
#else
	SKIP("clone:SIGCHLD");
#endif
}

static void t_clone3(void)
{
#ifdef SYS_clone3
	report("clone3", A_ENOSYS, syscall(SYS_clone3, NULL, 0));
#else
	SKIP("clone3");
#endif
}

static void t_open_tree(void)
{
#ifdef SYS_open_tree
	report("open_tree", A_ENOSYS,
	       syscall(SYS_open_tree, -1, "/", 0));
#else
	SKIP("open_tree");
#endif
}

static void t_move_mount(void)
{
#ifdef SYS_move_mount
	report("move_mount", A_ENOSYS,
	       syscall(SYS_move_mount, -1, "", -1, "", 0));
#else
	SKIP("move_mount");
#endif
}

static void t_fsopen(void)
{
#ifdef SYS_fsopen
	report("fsopen", A_ENOSYS, syscall(SYS_fsopen, "tmpfs", 0));
#else
	SKIP("fsopen");
#endif
}

static void t_fsconfig(void)
{
#ifdef SYS_fsconfig
	report("fsconfig", A_ENOSYS,
	       syscall(SYS_fsconfig, -1, 0, NULL, NULL, 0));
#else
	SKIP("fsconfig");
#endif
}

static void t_fsmount(void)
{
#ifdef SYS_fsmount
	report("fsmount", A_ENOSYS, syscall(SYS_fsmount, -1, 0, 0));
#else
	SKIP("fsmount");
#endif
}

static void t_fspick(void)
{
#ifdef SYS_fspick
	report("fspick", A_ENOSYS, syscall(SYS_fspick, -1, "/", 0));
#else
	SKIP("fspick");
#endif
}

static void t_mount_setattr(void)
{
#ifdef SYS_mount_setattr
	report("mount_setattr", A_ENOSYS,
	       syscall(SYS_mount_setattr, -1, "/", 0, NULL, 0));
#else
	SKIP("mount_setattr");
#endif
}

static int open_devnull(void)
{
	return open("/dev/null", O_RDONLY);
}

static void t_ioctl_tiocsti(void)
{
#ifdef SYS_ioctl
	char c = 0;
	int fd, err;
	long rc;

	fd = open_devnull();
	if (fd < 0) {
		printf("SKIP ioctl:TIOCSTI no-devnull\n");
		return;
	}
	errno = 0;
	rc = syscall(SYS_ioctl, fd, (unsigned long)TIOCSTI, &c);
	err = errno;
	close(fd);
	report_result("ioctl:TIOCSTI", A_EPERM, rc, err);
#else
	SKIP("ioctl:TIOCSTI");
#endif
}

static void t_ioctl_tioclinux(void)
{
#ifdef SYS_ioctl
	char c = 0;
	int fd, err;
	long rc;

	fd = open_devnull();
	if (fd < 0) {
		printf("SKIP ioctl:TIOCLINUX no-devnull\n");
		return;
	}
	errno = 0;
	rc = syscall(SYS_ioctl, fd, (unsigned long)TIOCLINUX, &c);
	err = errno;
	close(fd);
	report_result("ioctl:TIOCLINUX", A_EPERM, rc, err);
#else
	SKIP("ioctl:TIOCLINUX");
#endif
}

static void t_ioctl_allowed(void)
{
#ifdef SYS_ioctl
	int n = 0;
	int fd, err;
	long rc;

	fd = open_devnull();
	if (fd < 0) {
		printf("SKIP ioctl:FIONREAD no-devnull\n");
		return;
	}
	errno = 0;
	rc = syscall(SYS_ioctl, fd, (unsigned long)FIONREAD, &n);
	err = errno;
	close(fd);
	report_result("ioctl:FIONREAD", A_ALLOW, rc, err);
#else
	SKIP("ioctl:FIONREAD");
#endif
}

static void t_ioctl_tiocsti_high(void)
{
#if defined(SYS_ioctl) && (defined(__LP64__) || defined(_LP64))
	char c = 0;
	int fd, err;
	long rc;

	fd = open_devnull();
	if (fd < 0) {
		printf("SKIP ioctl:TIOCSTI-high no-devnull\n");
		return;
	}
	errno = 0;
	rc = syscall(SYS_ioctl, fd,
		     (unsigned long)TIOCSTI | 0x100000000ULL, &c);
	err = errno;
	close(fd);
	report_result("ioctl:TIOCSTI-high", A_EPERM, rc, err);
#else
	SKIP("ioctl:TIOCSTI-high");
#endif
}

static void t_ioctl_tioclinux_high(void)
{
#if defined(SYS_ioctl) && (defined(__LP64__) || defined(_LP64))
	char c = 0;
	int fd, err;
	long rc;

	fd = open_devnull();
	if (fd < 0) {
		printf("SKIP ioctl:TIOCLINUX-high no-devnull\n");
		return;
	}
	errno = 0;
	rc = syscall(SYS_ioctl, fd,
		     (unsigned long)TIOCLINUX | 0x100000000ULL, &c);
	err = errno;
	close(fd);
	report_result("ioctl:TIOCLINUX-high", A_EPERM, rc, err);
#else
	SKIP("ioctl:TIOCLINUX-high");
#endif
}

static void t_perf_event_open(void)
{
#ifdef SYS_perf_event_open
	report("perf_event_open", A_EPERM,
	       syscall(SYS_perf_event_open, NULL, 0, -1, -1, 0));
#else
	SKIP("perf_event_open");
#endif
}

static void t_ptrace(void)
{
#ifdef SYS_ptrace
	report("ptrace", A_EPERM,
	       syscall(SYS_ptrace, (long)PTRACE_TRACEME, 0, NULL, NULL));
#else
	SKIP("ptrace");
#endif
}

static void t_personality_bad(void)
{
#ifdef SYS_personality
	report("personality:bad", A_EPERM,
	       syscall(SYS_personality, 0xffffffffUL));
#else
	SKIP("personality:bad");
#endif
}

static void t_personality_domain(void)
{
#ifdef SYS_personality
	report("personality:domain", A_EPERM,
	       syscall(SYS_personality, 1));
#else
	SKIP("personality:domain");
#endif
}

static void t_personality_good(void)
{
#ifdef SYS_personality
	report("personality:good", A_ALLOW,
	       syscall(SYS_personality, PER_LINUX));
#else
	SKIP("personality:good");
#endif
}

static void t_personality_linux32(void)
{
#ifdef SYS_personality
	long rc;
	int err;

	errno = 0;
	rc = syscall(SYS_personality, PER_LINUX32);
	err = errno;
	if (rc != -1)
		syscall(SYS_personality, PER_LINUX);
	report_result("personality:linux32", A_ALLOW, rc, err);
#else
	SKIP("personality:linux32");
#endif
}

static void t_modify_ldt(void)
{
#ifdef SYS_modify_ldt
	report("modify_ldt", A_EPERM,
	       syscall(SYS_modify_ldt, 0, NULL, 0));
#else
	SKIP("modify_ldt");
#endif
}

static void t_io_uring_setup(void)
{
#ifdef SYS_io_uring_setup
	report("io_uring_setup", A_EPERM,
	       syscall(SYS_io_uring_setup, 1, NULL));
#else
	SKIP("io_uring_setup");
#endif
}

static void t_io_uring_enter(void)
{
#ifdef SYS_io_uring_enter
	report("io_uring_enter", A_EPERM,
	       syscall(SYS_io_uring_enter, -1, 0, 0, 0, NULL, 0));
#else
	SKIP("io_uring_enter");
#endif
}

static void t_io_uring_register(void)
{
#ifdef SYS_io_uring_register
	report("io_uring_register", A_EPERM,
	       syscall(SYS_io_uring_register, -1, 0, NULL, 0));
#else
	SKIP("io_uring_register");
#endif
}

static void t_userfaultfd(void)
{
#ifdef SYS_userfaultfd
	long rc;
	int err;

	errno = 0;
	rc = syscall(SYS_userfaultfd, 0);
	err = errno;
	if (rc >= 0)
		close((int)rc);
	report_result("userfaultfd", A_EPERM, rc, err);
#else
	SKIP("userfaultfd");
#endif
}

static void t_bpf(void)
{
#ifdef SYS_bpf
	report("bpf", A_EPERM, syscall(SYS_bpf, 0, NULL, 0));
#else
	SKIP("bpf");
#endif
}

static void t_process_vm_readv(void)
{
#ifdef SYS_process_vm_readv
	char buf[8] = { 0 };
	struct iovec local = { .iov_base = buf, .iov_len = sizeof(buf) };
	struct iovec remote = { .iov_base = buf, .iov_len = sizeof(buf) };

	report("process_vm_readv", A_EPERM,
	       syscall(SYS_process_vm_readv, getpid(), &local, 1, &remote, 1, 0));
#else
	SKIP("process_vm_readv");
#endif
}

static void t_process_vm_writev(void)
{
#ifdef SYS_process_vm_writev
	char buf[8] = { 0 };
	struct iovec local = { .iov_base = buf, .iov_len = sizeof(buf) };
	struct iovec remote = { .iov_base = buf, .iov_len = sizeof(buf) };

	report("process_vm_writev", A_EPERM,
	       syscall(SYS_process_vm_writev, getpid(), &local, 1, &remote, 1, 0));
#else
	SKIP("process_vm_writev");
#endif
}

static void t_unshare(void)
{
#ifdef SYS_unshare
	report("unshare", A_EPERM, syscall(SYS_unshare, CLONE_NEWUSER));
#else
	SKIP("unshare");
#endif
}

static int filter_active(void)
{
#ifdef SYS_personality
	errno = 0;
	return syscall(SYS_personality, 0xffffffffUL) == -1 && errno == EPERM;
#elif defined(SYS_unshare)
	errno = 0;
	return syscall(SYS_unshare, CLONE_NEWUSER) == -1 && errno == EPERM;
#else
	return 0;
#endif
}

int main(void)
{
	if (!filter_active()) {
		fprintf(stderr,
			"seccomp probe: default filter is not active; "
			"refusing to invoke blocked syscalls\n");
		return 2;
	}

	t_syslog();
	t_acct();
	t_quotactl();
	t_uselib();
	t_add_key();
	t_keyctl();
	t_request_key();
	t_mount();
	t_umount();
	t_umount2();
	t_pivot_root();
	t_chroot();
	t_setns();
	t_clone_newuser();
	t_clone_allowed();
	t_clone3();
	t_open_tree();
	t_move_mount();
	t_fsopen();
	t_fsconfig();
	t_fsmount();
	t_fspick();
	t_mount_setattr();
	t_ioctl_tiocsti();
	t_ioctl_tioclinux();
	t_ioctl_allowed();
	t_ioctl_tiocsti_high();
	t_ioctl_tioclinux_high();
	t_perf_event_open();
	t_ptrace();
	t_personality_bad();
	t_personality_domain();
	t_personality_good();
	t_personality_linux32();
	t_modify_ldt();
	t_io_uring_setup();
	t_io_uring_enter();
	t_io_uring_register();
	t_userfaultfd();
	t_bpf();
	t_process_vm_readv();
	t_process_vm_writev();
	t_unshare();

	if (failures) {
		printf("SUMMARY %d failed\n", failures);
		return 1;
	}
	printf("SUMMARY all passed\n");
	return 0;
}
PROBE

if ! cc -O2 -static -o "$_tmp/probe" "$_tmp/probe.c" 2>"$_tmp/cc.err"; then
    if ! cc -O2 -o "$_tmp/probe" "$_tmp/probe.c"; then
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

if (( _fail )); then
    exit 1
fi

_passed=$(awk '/^PASS / { n++ } END { print n + 0 }' "$_tmp/out")
_skipped=$(awk '/^SKIP / { n++ } END { print n + 0 }' "$_tmp/out")
echo "seccomp-check: $_passed passed, $_skipped skipped (${#_rules[@]} unique rules)"
