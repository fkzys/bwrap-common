PREFIX = /usr
pkgname = bwrap-common

.PHONY: install uninstall reinstall test clean

test:
	bash tests/test.sh

install:
	install -Dm644 bwrap-common.sh $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/LICENSE

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	rm -rf $(DESTDIR)$(PREFIX)/lib/bwrap-common/
	rm -rf $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/

reinstall: uninstall install

clean:
	@echo "Nothing to clean."
