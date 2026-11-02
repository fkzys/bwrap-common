#include "seccomp-gen.h"

#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int strict_mode;

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
	const struct scmp_version *libver;
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
		libver = seccomp_version();
		if (libver)
			printf("4 (libseccomp %u.%u.%u)\n",
			       libver->major, libver->minor, libver->micro);
		else
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
