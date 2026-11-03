#include "seccomp-gen.h"

#include <stdio.h>
#include <string.h>

int select_arch(scmp_filter_ctx ctx, const char *name, uint32_t *arch)
{
	const char *resolved = name;
	uint32_t native;
	uint32_t target;

	if (!name) {
		*arch = seccomp_arch_native();
		return 0;
	}

	if (strcmp(name, "i386") == 0 || strcmp(name, "i486") == 0 ||
	    strcmp(name, "i586") == 0 || strcmp(name, "i686") == 0) {
		resolved = "x86";
	} else if (strcmp(name, "armv6l") == 0 ||
		   strcmp(name, "armv7l") == 0 ||
		   strcmp(name, "armv8l") == 0) {
		resolved = "arm";
	}

	target = seccomp_arch_resolve_name(resolved);
	if (target == 0) {
		fprintf(stderr, "%s: unsupported architecture '%s'\n",
			PROG, name);
		return EXIT_ARCH_UNSUPPORTED;
	}

	native = seccomp_arch_native();
	*arch = target;

	if (target == native)
		return 0;

	/*
	 * libseccomp rejects seccomp_arch_add() for a target with a different
	 * endianness or word size while the native arch is still present.  Remove
	 * native first, then add the requested target; this also lets a single
	 * build cross-generate blobs for the other supported architectures.
	 */
	if (seccomp_arch_remove(ctx, native) < 0) {
		fprintf(stderr, "%s: cannot remove native architecture\n", PROG);
		return 1;
	}
	if (seccomp_arch_add(ctx, target) < 0) {
		fprintf(stderr, "%s: cannot add architecture '%s'\n",
			PROG, name);
		return 1;
	}

	return 0;
}

/*
 * Portable blocklists contain legacy syscall names that exist on some
 * architectures but not others (umount, uselib, modify_ldt).  Strict mode
 * rejects names that no supported architecture knows, while still skipping
 * architecture-specific names with a warning.
 */
int known_on_any_arch(const char *name)
{
	static const char *const arches[] = {
		"x86", "x86_64", "x32", "arm", "aarch64", "riscv64",
		"ppc64le", "s390x", "loongarch64", "mips", "mips64",
		"mips64n32", "parisc", "parisc64",
	};
	uint32_t native = seccomp_arch_native();
	size_t i;

	if (seccomp_syscall_resolve_name_arch(native, name) >= 0)
		return 1;

	for (i = 0; i < sizeof(arches) / sizeof(arches[0]); i++) {
		uint32_t arch = seccomp_arch_resolve_name(arches[i]);

		if (arch == 0 || arch == native)
			continue;
		if (seccomp_syscall_resolve_name_arch(arch, name) >= 0)
			return 1;
	}

	return 0;
}
