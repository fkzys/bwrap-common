#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <seccomp.h>

#define PROG "bwrap-seccomp-gen"

/* Exit status for a target architecture not recognised by this libseccomp. */
#define EXIT_ARCH_UNSUPPORTED 3

struct symbol {
	const char *name;
	uint64_t value;
};

static const struct symbol symbols[] = {
	{ "CLONE_NEWUSER", 0x10000000ULL },
	{ "TIOCSTI",       0x5412ULL },
	{ "TIOCLINUX",     0x541cULL },
	{ "PER_LINUX",     0x0000ULL },
	{ "PER_LINUX32",   0x0008ULL },
};

struct rule {
	int nr;
	uint32_t action;
	int have_cond;
	struct scmp_arg_cmp cmp;
	char *name;
	const char *source;
};

static int strict_mode;

static void usage(const char *msg)
{
	if (msg)
		fprintf(stderr, "%s: %s\n", PROG, msg);
	fprintf(stderr,
		"usage: %s --blocklist FILE [--extra FILE|-] [--arch ARCH] [--strict] -o OUT\n"
		"       %s --allowlist \"SPEC\" [--arch ARCH] -o OUT\n"
		"       %s --version\n",
		PROG, PROG, PROG);
	exit(1);
}

static int parse_value(const char *s, uint64_t *out)
{
	const char *digits;
	size_t i;
	char *end = NULL;
	unsigned long long value;
	int base;

	if (!s || *s == '\0')
		return -1;

	for (i = 0; i < sizeof(symbols) / sizeof(symbols[0]); i++) {
		if (strcmp(s, symbols[i].name) == 0) {
			*out = symbols[i].value;
			return 0;
		}
	}

	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
		digits = s + 2;
		base = 16;
	} else {
		digits = s;
		base = 10;
	}

	if (*digits == '\0' || *digits == '+' || *digits == '-' ||
	    isspace((unsigned char)*digits))
		return -1;

	errno = 0;
	value = strtoull(digits, &end, base);
	if (errno != 0 || end == digits || *end != '\0')
		return -1;

	*out = (uint64_t)value;
	return 0;
}

static int parse_condition(const char *cond, struct scmp_arg_cmp *cmp)
{
	const char *p;
	uint64_t value;
	unsigned int arg;

	memset(cmp, 0, sizeof(*cmp));

	if (cond[0] != 'a' || cond[1] < '0' || cond[1] > '5')
		return -1;

	arg = (unsigned int)(cond[1] - '0');
	p = cond + 2;

	if (p[0] == '=' && p[1] == '=') {
		cmp->op = SCMP_CMP_EQ;
		p += 2;
	} else if (p[0] == '!' && p[1] == '=') {
		cmp->op = SCMP_CMP_NE;
		p += 2;
	} else if (p[0] == '&') {
		cmp->op = SCMP_CMP_MASKED_EQ;
		p += 1;
	} else if (p[0] == '>') {
		cmp->op = SCMP_CMP_GT;
		p += 1;
	} else {
		return -1;
	}

	if (parse_value(p, &value) != 0)
		return -1;

	cmp->arg = arg;
	cmp->datum_a = (scmp_datum_t)value;
	cmp->datum_b = (cmp->op == SCMP_CMP_MASKED_EQ) ?
		(scmp_datum_t)value : 0;

	return 0;
}

static int select_arch(scmp_filter_ctx ctx, const char *name, uint32_t *arch)
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
static int known_on_any_arch(const char *name)
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

static int export_bpf(scmp_filter_ctx ctx, const char *out)
{
	int fd;

	fd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0) {
		fprintf(stderr, "%s: cannot open %s: %s\n",
			PROG, out, strerror(errno));
		return 1;
	}
	if (fchmod(fd, 0600) < 0) {
		fprintf(stderr, "%s: cannot set mode on %s: %s\n",
			PROG, out, strerror(errno));
		close(fd);
		unlink(out);
		return 1;
	}

	if (seccomp_export_bpf(ctx, fd) < 0) {
		fprintf(stderr, "%s: cannot export BPF to %s\n", PROG, out);
		close(fd);
		unlink(out);
		return 1;
	}

	if (close(fd) < 0) {
		fprintf(stderr, "%s: cannot close %s: %s\n",
			PROG, out, strerror(errno));
		unlink(out);
		return 1;
	}

	return 0;
}

static void rule_free_all(struct rule *rules, size_t count)
{
	size_t i;

	for (i = 0; i < count; i++)
		free(rules[i].name);
	free(rules);
}

static void rule_remove_at(struct rule *rules, size_t *count, size_t idx)
{
	free(rules[idx].name);
	if (idx + 1 < *count)
		memmove(&rules[idx], &rules[idx + 1],
			(*count - idx - 1) * sizeof(*rules));
	(*count)--;
}

static void rule_remove_nr(struct rule *rules, size_t *count, int nr)
{
	size_t i = 0;

	while (i < *count) {
		if (rules[i].nr == nr)
			rule_remove_at(rules, count, i);
		else
			i++;
	}
}

static int cmp_equal(const struct scmp_arg_cmp *a,
		     const struct scmp_arg_cmp *b)
{
	return a->arg == b->arg && a->op == b->op &&
	       a->datum_a == b->datum_a && a->datum_b == b->datum_b;
}

static void rule_remove_cond(struct rule *rules, size_t *count, int nr,
			     const struct scmp_arg_cmp *cmp)
{
	size_t i = 0;

	while (i < *count) {
		if (rules[i].nr == nr && rules[i].have_cond &&
		    cmp_equal(&rules[i].cmp, cmp))
			rule_remove_at(rules, count, i);
		else
			i++;
	}
}

static int rule_append(struct rule **rules, size_t *count, size_t *cap,
		       int nr, uint32_t action, int have_cond,
		       const struct scmp_arg_cmp *cmp, const char *name,
		       const char *source)
{
	struct rule *tmp;
	char *dup;
	size_t newcap;

	if (*count == *cap) {
		newcap = *cap ? *cap * 2 : 32;
		if (newcap <= *cap)
			return -1;
		tmp = realloc(*rules, newcap * sizeof(*tmp));
		if (!tmp)
			return -1;
		*rules = tmp;
		*cap = newcap;
	}

	dup = strdup(name);
	if (!dup)
		return -1;

	(*rules)[*count].nr = nr;
	(*rules)[*count].action = action;
	(*rules)[*count].have_cond = have_cond;
	if (have_cond)
		(*rules)[*count].cmp = *cmp;
	else
		memset(&(*rules)[*count].cmp, 0, sizeof((*rules)[*count].cmp));
	(*rules)[*count].name = dup;
	(*rules)[*count].source = source;
	(*count)++;

	return 0;
}

/*
 * Parse one blocklist file into the rule array.  With merge set, each extra
 * rule is applied on top of the rules already stored.  Conditional user rules
 * can refine or tighten the defaults, but they leave unconditional default
 * denies alone: the unconditional rule still dominates.  An unconditional
 * user rule is the escape hatch that replaces every base rule for a syscall.
 */
static int parse_rules(const char *path, int merge, uint32_t arch,
		       struct rule **rules, size_t *count, size_t *cap)
{
	char *line = NULL;
	size_t linecap = 0;
	ssize_t nread;
	FILE *f;
	int close_file = strcmp(path, "-") != 0;
	int rc = 0;

	f = close_file ? fopen(path, "r") : stdin;
	if (!f) {
		fprintf(stderr, "%s: cannot open %s: %s\n",
			PROG, path, strerror(errno));
		return 1;
	}

	while ((nread = getline(&line, &linecap, f)) != -1) {
		struct scmp_arg_cmp cmp = { 0 };
		char *saveptr = NULL;
		char *comment;
		char *systok;
		char *acttok;
		char *tok;
		char cond[256];
		uint32_t action;
		int nr;
		int have_cond = 0;

		comment = strchr(line, '#');
		if (comment)
			*comment = '\0';

		systok = strtok_r(line, " \t\r\n", &saveptr);
		if (!systok)
			continue;

		acttok = strtok_r(NULL, " \t\r\n", &saveptr);
		if (!acttok) {
			fprintf(stderr, "%s: %s: missing action for '%s'\n",
				PROG, path, systok);
			rc = 1;
			goto done;
		}

		if (strcmp(acttok, "EPERM") == 0) {
			action = SCMP_ACT_ERRNO(EPERM);
		} else if (strcmp(acttok, "ENOSYS") == 0) {
			action = SCMP_ACT_ERRNO(ENOSYS);
		} else if (strcmp(acttok, "ALLOW") == 0) {
			action = SCMP_ACT_ALLOW;
		} else {
			fprintf(stderr, "%s: %s: invalid action '%s'\n",
				PROG, path, acttok);
			rc = 1;
			goto done;
		}

		cond[0] = '\0';
		while ((tok = strtok_r(NULL, " \t\r\n", &saveptr)) != NULL) {
			size_t used = strlen(cond);
			size_t need = strlen(tok);

			if (used >= sizeof(cond) || need >= sizeof(cond) - used) {
				fprintf(stderr,
					"%s: %s: condition too long\n",
					PROG, path);
				rc = 1;
				goto done;
			}
			memcpy(cond + used, tok, need + 1);
		}

		if (cond[0] != '\0') {
			if (parse_condition(cond, &cmp) != 0) {
				fprintf(stderr,
					"%s: %s: invalid condition '%s'\n",
					PROG, path, cond);
				rc = 1;
				goto done;
			}
			have_cond = 1;
		}

		nr = seccomp_syscall_resolve_name_arch(arch, systok);
		if (nr < 0) {
			if (strict_mode && !known_on_any_arch(systok)) {
				fprintf(stderr,
					"%s: %s: unknown syscall '%s'\n",
					PROG, path, systok);
				rc = 1;
				goto done;
			}
			fprintf(stderr,
				"%s: warning: skipping syscall '%s' for this architecture\n",
				PROG, systok);
			continue;
		}

		/*
		 * The kernel truncates the ioctl command to unsigned int, so a
		 * 64-bit equality check would let high bits bypass TIOCSTI and
		 * TIOCLINUX filtering.
		 */
		if (have_cond && strcmp(systok, "ioctl") == 0 &&
		    cmp.arg == 1 && cmp.op == SCMP_CMP_EQ) {
			scmp_datum_t value = cmp.datum_a;

			cmp.op = SCMP_CMP_MASKED_EQ;
			cmp.datum_a = 0xffffffffU;
			cmp.datum_b = value & 0xffffffffU;
		}

		if (!merge && action == SCMP_ACT_ALLOW) {
			if (strict_mode) {
				fprintf(stderr,
					"%s: %s: ALLOW is only valid in --extra rules\n",
					PROG, path);
				rc = 1;
				goto done;
			}
			continue;
		}

		if (merge) {
			size_t before = *count;

			if (!have_cond)
				rule_remove_nr(*rules, count, nr);
			else
				rule_remove_cond(*rules, count, nr, &cmp);

			if (action == SCMP_ACT_ALLOW && *count < before)
				fprintf(stderr,
					"%s: warning: extra rule for '%s' overrides a default deny with ALLOW\n",
					PROG, systok);

			/* The default action is ALLOW already. */
			if (!have_cond && action == SCMP_ACT_ALLOW)
				continue;
		}

		if (rule_append(rules, count, cap, nr, action, have_cond,
				&cmp, systok, path) != 0) {
			fprintf(stderr, "%s: out of memory\n", PROG);
			rc = 1;
			goto done;
		}
	}

done:
	free(line);
	if (close_file)
		fclose(f);
	return rc;
}

static int run_blocklist(const char *path, const char *extra, const char *out,
			 const char *arch_name)
{
	scmp_filter_ctx ctx;
	struct rule *rules = NULL;
	size_t count = 0;
	size_t cap = 0;
	size_t i;
	uint32_t arch;
	int rc = 0;

	ctx = seccomp_init(SCMP_ACT_ALLOW);
	if (!ctx) {
		fprintf(stderr, "%s: cannot initialize seccomp filter\n", PROG);
		return 1;
	}
	rc = select_arch(ctx, arch_name, &arch);
	if (rc != 0)
		goto done;

	rc = parse_rules(path, 0, arch, &rules, &count, &cap);
	if (rc != 0)
		goto done;

	if (extra) {
		rc = parse_rules(extra, 1, arch, &rules, &count, &cap);
		if (rc != 0)
			goto done;
	}

	for (i = 0; i < count; i++) {
		int add_rc;

		/*
		 * The filter default is ALLOW, so ALLOW rules are already
		 * satisfied and libseccomp refuses to add them.  They still
		 * participate in the merge above, where they replace matching
		 * deny rules.
		 */
		if (rules[i].action == SCMP_ACT_ALLOW)
			continue;

		if (rules[i].have_cond)
			add_rc = seccomp_rule_add(ctx, rules[i].action,
						  rules[i].nr, 1, rules[i].cmp);
		else
			add_rc = seccomp_rule_add(ctx, rules[i].action,
						  rules[i].nr, 0);

		if (add_rc < 0) {
			fprintf(stderr,
				"%s: %s: cannot add rule for '%s': %s\n",
				PROG, rules[i].source, rules[i].name,
				strerror(-add_rc));
			rc = 1;
			goto done;
		}
	}

	rc = export_bpf(ctx, out);

done:
	rule_free_all(rules, count);
	if (rc != 0)
		unlink(out);
	seccomp_release(ctx);
	return rc;
}

static int valid_name(const char *name)
{
	size_t i;

	if (name[0] == '\0')
		return 0;

	for (i = 0; name[i] != '\0'; i++) {
		unsigned char c = (unsigned char)name[i];

		if (!((c >= 'a' && c <= 'z') ||
		      (c >= '0' && c <= '9') || c == '_'))
			return 0;
	}

	return 1;
}

/* Returns 1 when newly added, 0 when already present, -1 on allocation failure. */
static int seen_add(int **seen, size_t *count, size_t *cap, int nr)
{
	size_t i;
	int *tmp;
	size_t newcap;

	for (i = 0; i < *count; i++) {
		if ((*seen)[i] == nr)
			return 0;
	}

	if (*count == *cap) {
		newcap = *cap ? *cap * 2 : 32;
		if (newcap <= *cap)
			return -1;
		tmp = realloc(*seen, newcap * sizeof(*tmp));
		if (!tmp)
			return -1;
		*seen = tmp;
		*cap = newcap;
	}

	(*seen)[(*count)++] = nr;
	return 1;
}

static int run_allowlist(const char *spec, const char *out,
			 const char *arch_name)
{
	static const char *const lifelines[] = {
		/* the app after exec */
		"execve", "execveat", "exit", "exit_group",
		"write", "rt_sigreturn", "sigreturn",
		/* bubblewrap's pid 1, which also receives the filter */
		"wait4", "waitid", "close",
	};
	scmp_filter_ctx ctx;
	char *copy = NULL;
	char *saveptr = NULL;
	char *tok;
	int *seen = NULL;
	size_t seen_count = 0;
	size_t seen_cap = 0;
	size_t i;
	uint32_t arch;
	int rc = 1;

#ifdef SCMP_ACT_KILL_PROCESS
	ctx = seccomp_init(SCMP_ACT_KILL_PROCESS);
#else
	ctx = seccomp_init(SCMP_ACT_KILL);
#endif
	if (!ctx) {
		fprintf(stderr, "%s: cannot initialize seccomp filter\n", PROG);
		return 1;
	}
	rc = select_arch(ctx, arch_name, &arch);
	if (rc != 0)
		goto done;

	for (i = 0; i < sizeof(lifelines) / sizeof(lifelines[0]); i++) {
		int nr = seccomp_syscall_resolve_name_arch(arch, lifelines[i]);
		int added;

		if (nr < 0)
			continue;

		added = seen_add(&seen, &seen_count, &seen_cap, nr);
		if (added < 0) {
			fprintf(stderr, "%s: out of memory\n", PROG);
			goto done;
		}
		if (added == 0)
			continue;

		if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, nr, 0) < 0) {
			fprintf(stderr, "%s: cannot add lifeline rule for '%s'\n",
				PROG, lifelines[i]);
			goto done;
		}
	}

	copy = strdup(spec);
	if (!copy) {
		fprintf(stderr, "%s: out of memory\n", PROG);
		goto done;
	}

	tok = strtok_r(copy, " \t\r\n,", &saveptr);
	if (!tok) {
		fprintf(stderr, "%s: empty allowlist specification\n", PROG);
		rc = 2;
		goto done;
	}

	do {
		int nr;
		int added;

		if (!valid_name(tok)) {
			fprintf(stderr, "%s: invalid syscall name '%s'\n",
				PROG, tok);
			rc = 2;
			goto done;
		}

		nr = seccomp_syscall_resolve_name_arch(arch, tok);
		if (nr < 0) {
			fprintf(stderr, "%s: unknown syscall '%s'\n",
				PROG, tok);
			rc = 2;
			goto done;
		}

		added = seen_add(&seen, &seen_count, &seen_cap, nr);
		if (added < 0) {
			fprintf(stderr, "%s: out of memory\n", PROG);
			rc = 1;
			goto done;
		}
		if (added == 0)
			continue;

		if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, nr, 0) < 0) {
			fprintf(stderr, "%s: cannot add rule for '%s'\n",
				PROG, tok);
			rc = 1;
			goto done;
		}
	} while ((tok = strtok_r(NULL, " \t\r\n,", &saveptr)) != NULL);

	rc = export_bpf(ctx, out);

done:
	free(copy);
	free(seen);
	if (rc != 0)
		unlink(out);
	seccomp_release(ctx);
	return rc;
}

int main(int argc, char **argv)
{
	static const struct option longopts[] = {
		{ "blocklist", required_argument, NULL, 'b' },
		{ "extra",     required_argument, NULL, 'e' },
		{ "allowlist", required_argument, NULL, 'a' },
		{ "output",    required_argument, NULL, 'o' },
		{ "arch",      required_argument, NULL, 'A' },
		{ "strict",    no_argument,       NULL, 's' },
		{ "version",   no_argument,       NULL, 'V' },
		{ NULL,        0,                 NULL, 0   },
	};
	const char *blocklist = NULL;
	const char *extra = NULL;
	const char *allowlist = NULL;
	const char *out = NULL;
	const char *arch_name = NULL;
	int strict = 0;
	int version = 0;
	int opt;

	while ((opt = getopt_long(argc, argv, "a:A:b:e:o:sV", longopts, NULL)) != -1) {
		switch (opt) {
		case 'b':
			blocklist = optarg;
			break;
		case 'e':
			if (extra)
				usage("--extra may be specified only once");
			extra = optarg;
			break;
		case 'a':
			allowlist = optarg;
			break;
		case 'o':
			out = optarg;
			break;
		case 'A':
			arch_name = optarg;
			break;
		case 's':
			strict = 1;
			break;
		case 'V':
			version = 1;
			break;
		default:
			usage(NULL);
		}
	}

	if (optind < argc)
		usage("unexpected positional argument");

	if (version) {
		puts("4");
		return 0;
	}

	if (!blocklist && !allowlist)
		usage("one of --blocklist or --allowlist is required");
	if (blocklist && allowlist)
		usage("--blocklist and --allowlist are mutually exclusive");
	if (extra && !blocklist)
		usage("--extra requires --blocklist");
	if (extra && allowlist)
		usage("--extra is not valid with --allowlist");
	if (blocklist && extra && strcmp(blocklist, "-") == 0 &&
	    strcmp(extra, "-") == 0)
		usage("--blocklist - and --extra - cannot both read stdin");
	if (strict && !blocklist)
		usage("--strict requires --blocklist");
	if (!out)
		usage("-o OUT is required");

	strict_mode = strict;
	if (blocklist)
		return run_blocklist(blocklist, extra, out, arch_name);

	return run_allowlist(allowlist, out, arch_name);
}
