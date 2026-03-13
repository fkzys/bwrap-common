PREFIX = /usr
pkgname = bwrap-common

install:
	install -Dm644 bwrap-common.sh $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/LICENSE

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/bwrap-common/bwrap-common.sh
	rm -rf $(DESTDIR)$(PREFIX)/lib/bwrap-common/
	rm -rf $(DESTDIR)$(PREFIX)/share/licenses/$(pkgname)/

reinstall: install
