PREFIX ?= /usr/local
BIN := .build/release/kbdlight

.PHONY: build release install uninstall clean test

build:
	swift build

release:
	swift build -c release

install: release
	install -d $(PREFIX)/bin
	install $(BIN) $(PREFIX)/bin/kbdlight
	@echo "installed to $(PREFIX)/bin/kbdlight"

uninstall:
	rm -f $(PREFIX)/bin/kbdlight

test:
	swift test

clean:
	swift package clean
	rm -rf .build
