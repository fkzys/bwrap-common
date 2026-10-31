PREFIX = /usr
pkgname = bwrap-common

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra
ARCH ?= $(shell uname -m)
BUILD_USER ?= $(SUDO_USER)

BUILD_DIR = build
SECCOMP_GEN = $(BUILD_DIR)/bwrap-seccomp-gen
SECCOMP_BPF = $(BUILD_DIR)/seccomp/default.$(ARCH).bpf

.PHONY: build _build install uninstall reinstall test clean

ifeq ($(shell id -u),0)
build:
	@if [ -z "$(BUILD_USER)" ] || [ "$(BUILD_USER)" = root ]; then \
		echo "build: refusing to build as root; run make as a user or set BUILD_USER=<user>" >&2; \
		exit 1; \
	fi
	@sudo -u "$(BUILD_USER)" $(MAKE) --no-print-directory -C "$(CURDIR)" \
		_build ARCH="$(ARCH)" CC="$(CC)" CFLAGS="$(CFLAGS)" BUILD_DIR="$(BUILD_DIR)"
else
build: _build
endif

_build: $(SECCOMP_GEN) $(SECCOMP_BPF)

$(SECCOMP_GEN): tools/seccomp-gen.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $< -lseccomp

$(SECCOMP_BPF): $(SECCOMP_GEN) seccomp/default.conf
	@mkdir -p $(dir $@)
	$(SECCOMP_GEN) --blocklist seccomp/default.conf --arch "$(ARCH)" --strict -o $@

test:
	bash tests/test.sh

install: build
	install -Dm644 bwrap-common.sh $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	install -Dm755 $(SECCOMP_GEN) $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-seccomp-gen
	install -Dm644 $(SECCOMP_BPF) $(DESTDIR)$(PREFIX)/lib/bwrap-common/seccomp/default.$(ARCH).bpf
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/LICENSE

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	rm -f $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-seccomp-gen
	rm -rf $(DESTDIR)$(PREFIX)/lib/bwrap-common/
	rm -rf $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/

reinstall: uninstall install

clean:
	rm -rf $(BUILD_DIR)
