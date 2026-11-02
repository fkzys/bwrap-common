PREFIX = /usr
pkgname = bwrap-common

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

BUILD_DIR = build
SECCOMP_GEN = $(BUILD_DIR)/bwrap-seccomp-gen
SECCOMP_SRCS = tools/seccomp-gen.c tools/seccomp-arch.c \
	tools/seccomp-rule.c tools/seccomp-filter.c
SECCOMP_OBJS = $(SECCOMP_SRCS:tools/%.c=$(BUILD_DIR)/%.o)

.PHONY: build install uninstall reinstall test clean

build: $(SECCOMP_GEN)

$(BUILD_DIR)/%.o: tools/%.c tools/seccomp-gen.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(SECCOMP_GEN): $(SECCOMP_OBJS)
	$(CC) $(CFLAGS) -o $@ $(SECCOMP_OBJS) -lseccomp

test:
	bash tests/test.sh

install:
	install -Dm644 bwrap-common.sh $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	install -Dm644 bwrap-common-seccomp.sh $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common-seccomp.sh
	install -Dm644 bwrap-common-dbus.sh $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common-dbus.sh
	install -Dm755 $(SECCOMP_GEN) $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-seccomp-gen
	install -Dm644 seccomp/default.conf $(DESTDIR)$(PREFIX)/lib/bwrap-common/seccomp/default.conf
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/LICENSE

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	rm -f $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-seccomp-gen
	rm -rf $(DESTDIR)$(PREFIX)/lib/bwrap-common/
	rm -rf $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/

reinstall: uninstall install

clean:
	rm -rf $(BUILD_DIR)
