#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <seccomp.h>

#define PROG "bwrap-seccomp-gen"

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

static void usage(const char *msg)
{
	if (msg)
		fprintf(stderr, "%s: %s\n", PROG, msg);
	fprintf(stderr,
		"usage: %s --blocklist FILE -o OUT\n"
		"       %s --allowlist \"SPEC\" -o OUT\n"
		"       %s --version\n",
		PROG, PROG, PROG);
	exit(1);
}

static int parse_value(const char *s, uint64_t *out)
{
	const char *digits;
	size_t i;
	char *end = NULL;
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

	if (*digits == '\0')
		return -1;

	for (i = 0; digits[i] != '\0'; i++) {
		unsigned char c = (unsigned char)digits[i];

		if (base == 16) {
			if (!isxdigit(c))
				return -1;
		} else {
			if (!isdigit(c))
				return -1;
		}
	}

	errno = 0;
	*out = (uint64_t)strtoull(digits, &end, base);
	if (errno != 0 || end == digits || *end != '\0')
		return -1;

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

static int export_bpf(scmp_filter_ctx ctx, const char *out)
{
	int fd;

	fd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) {
		fprintf(stderr, "%s: cannot open %s: %s\n",
			PROG, out, strerror(errno));
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

static int run_blocklist(const char *path, const char *out)
{
	char *line = NULL;
	size_t linecap = 0;
	ssize_t nread;
	scmp_filter_ctx ctx;
	FILE *f;
	int rc = 0;

	f = fopen(path, "r");
	if (!f) {
		fprintf(stderr, "%s: cannot open %s: %s\n",
			PROG, path, strerror(errno));
		return 1;
	}

	ctx = seccomp_init(SCMP_ACT_ALLOW);
	if (!ctx) {
		fprintf(stderr, "%s: cannot initialize seccomp filter\n", PROG);
		fclose(f);
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
		int add_rc;

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
		} else {
			fprintf(stderr, "%s: %s: invalid action '%s'\n",
				PROG, path, acttok);
			rc = 1;
			goto done;
		}

		cond[0] = '\0';
		while ((tok = strtok_r(NULL, " \t\r\n", &saveptr)) != NULL) {
			if (strlen(cond) + strlen(tok) + 1 > sizeof(cond)) {
				fprintf(stderr,
					"%s: %s: condition too long\n",
					PROG, path);
				rc = 1;
				goto done;
			}
			strcat(cond, tok);
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

		nr = seccomp_syscall_resolve_name(systok);
		if (nr == __NR_SCMP_ERROR) {
			fprintf(stderr,
				"%s: warning: skipping unknown syscall '%s'\n",
				PROG, systok);
			continue;
		}

		if (have_cond)
			add_rc = seccomp_rule_add(ctx, action, nr, 1, cmp);
		else
			add_rc = seccomp_rule_add(ctx, action, nr, 0);

		if (add_rc < 0) {
			fprintf(stderr,
				"%s: %s: cannot add rule for '%s': %s\n",
				PROG, path, systok, strerror(-add_rc));
			rc = 1;
			goto done;
		}
	}

	rc = export_bpf(ctx, out);

done:
	free(line);
	fclose(f);
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

static int run_allowlist(const char *spec, const char *out)
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

	for (i = 0; i < sizeof(lifelines) / sizeof(lifelines[0]); i++) {
		int nr = seccomp_syscall_resolve_name(lifelines[i]);
		int added;

		if (nr == __NR_SCMP_ERROR)
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

		nr = seccomp_syscall_resolve_name(tok);
		if (nr == __NR_SCMP_ERROR) {
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
		{ "allowlist", required_argument, NULL, 'a' },
		{ "output",    required_argument, NULL, 'o' },
		{ "version",   no_argument,       NULL, 'V' },
		{ NULL,        0,                 NULL, 0   },
	};
	const char *blocklist = NULL;
	const char *allowlist = NULL;
	const char *out = NULL;
	int version = 0;
	int opt;

	while ((opt = getopt_long(argc, argv, "a:b:o:V", longopts, NULL)) != -1) {
		switch (opt) {
		case 'b':
			blocklist = optarg;
			break;
		case 'a':
			allowlist = optarg;
			break;
		case 'o':
			out = optarg;
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
		puts("2");
		return 0;
	}

	if (!blocklist && !allowlist)
		usage("one of --blocklist or --allowlist is required");
	if (blocklist && allowlist)
		usage("--blocklist and --allowlist are mutually exclusive");
	if (!out)
		usage("-o OUT is required");

	if (blocklist)
		return run_blocklist(blocklist, out);

	return run_allowlist(allowlist, out);
}
