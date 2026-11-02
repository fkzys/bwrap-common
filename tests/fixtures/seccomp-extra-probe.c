#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <unistd.h>

static int failures;

static void report(const char *name, long rc, int err, int want_errno)
{
	int ok;

	if (want_errno)
		ok = rc == -1 && err == want_errno;
	else
		ok = !(rc == -1 && err == EPERM);

	printf("%s %s want=%s got=%s\n", ok ? "PASS" : "FAIL", name,
	       want_errno ? strerror(want_errno) : "allow",
	       rc == -1 ? strerror(err) : "success");
	if (!ok)
		failures++;
}

int main(void)
{
	long rc;
	int err;

	errno = 0;
	rc = syscall(SYS_ptrace, (long)PTRACE_TRACEME, 0, NULL, NULL);
	err = errno;
	report("extra:ptrace", rc, err, 0);

	errno = 0;
	rc = syscall(SYS_personality, 1);
	err = errno;
	report("extra:personality:1", rc, err, 0);

	errno = 0;
	rc = syscall(SYS_personality, 2);
	err = errno;
	report("extra:personality:2", rc, err, EPERM);

	errno = 0;
	rc = syscall(SYS_getppid);
	err = errno;
	report("extra:getppid", rc, err, EPERM);

	return failures ? 1 : 0;
}
