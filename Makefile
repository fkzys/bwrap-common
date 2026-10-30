PREFIX = /usr
pkgname = bwrap-common

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra
ARCH ?= $(shell uname -m)

BUILD_DIR = build
SECCOMP_GEN = $(BUILD_DIR)/bwrap-seccomp-gen
SECCOMP_BPF = $(BUILD_DIR)/seccomp/default.$(ARCH).bpf

.PHONY: build install uninstall reinstall test clean

build: $(SECCOMP_GEN) $(SECCOMP_BPF)

$(SECCOMP_GEN): tools/seccomp-gen.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $< -lseccomp

$(SECCOMP_BPF): $(SECCOMP_GEN) seccomp/default.conf
	@mkdir -p $(dir $@)
	$(SECCOMP_GEN) --blocklist seccomp/default.conf -o $@

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
