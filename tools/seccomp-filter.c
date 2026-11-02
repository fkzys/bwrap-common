#define _GNU_SOURCE

#include "seccomp-gen.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

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

int run_blocklist(const char *path, const char *extra, const char *out,
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

int run_allowlist(const char *spec, const char *out,
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
