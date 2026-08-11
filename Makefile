PREFIX ?= /usr/local
BIN := .build/release/backlit

.PHONY: build release install uninstall clean test

build:
	swift build

release:
	swift build -c release

install: release
	install -d $(PREFIX)/bin
	install $(BIN) $(PREFIX)/bin/backlit
	@echo "installed to $(PREFIX)/bin/backlit"

uninstall:
	rm -f $(PREFIX)/bin/backlit

test:
	swift test

clean:
	swift package clean
	rm -rf .build
