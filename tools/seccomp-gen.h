#ifndef BWRAP_SECCOMP_GEN_H
#define BWRAP_SECCOMP_GEN_H

#include <stddef.h>
#include <stdint.h>

#include <seccomp.h>

#define PROG "bwrap-seccomp-gen"

/* Exit status for a target architecture not recognised by this libseccomp. */
#define EXIT_ARCH_UNSUPPORTED 3

struct symbol {
	const char *name;
	uint64_t value;
};

struct rule {
	int nr;
	uint32_t action;
	int have_cond;
	struct scmp_arg_cmp cmp;
	char *name;
	const char *source;
};

/* Set by main() from --strict before any blocklist is parsed. */
extern int strict_mode;

int select_arch(scmp_filter_ctx ctx, const char *name, uint32_t *arch);
int known_on_any_arch(const char *name);
void rule_free_all(struct rule *rules, size_t count);
int parse_rules(const char *path, int merge, uint32_t arch,
		struct rule **rules, size_t *count, size_t *cap);
int run_blocklist(const char *path, const char *extra, const char *out,
		  const char *arch_name);
int run_allowlist(const char *spec, const char *out, const char *arch_name);

#endif /* BWRAP_SECCOMP_GEN_H */
