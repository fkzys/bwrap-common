#define _GNU_SOURCE

#include "seccomp-gen.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const struct symbol symbols[] = {
	{ "CLONE_NEWUSER", 0x10000000ULL },
	{ "TIOCSTI",       0x5412ULL },
	{ "TIOCLINUX",     0x541cULL },
	{ "PER_LINUX",     0x0000ULL },
	{ "PER_LINUX32",   0x0008ULL },
};

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

void rule_free_all(struct rule *rules, size_t count)
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
int parse_rules(const char *path, int merge, uint32_t arch,
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
