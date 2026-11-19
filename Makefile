APP      := Sizer
SRC      := $(wildcard Sources/*.swift)
FLAGS    := -framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement
# Oldest macOS the app supports. Without an explicit -target, swiftc builds for the
# build Mac's own macOS version, so a release built on a macOS 26 runner would
# refuse to launch on anything older. Keep in sync with LSMinimumSystemVersion.
MIN_MACOS := 12.0
ARCHS     := arm64 x86_64

BUILD_DIR := build
DIST_DIR  := dist
INST_DIR  := /Applications
RES_DIR   := Resources

DEV_BUNDLE  := $(BUILD_DIR)/$(APP).app
DIST_BUNDLE := $(DIST_DIR)/$(APP).app
INST_BUNDLE := $(INST_DIR)/$(APP).app
ICON_ICNS   := $(RES_DIR)/$(APP).icns

.PHONY: dev build open close install uninstall reinstall icon clean all test bump

all: open

# Generate the app icon (.icns) from the drawing code.
icon: $(ICON_ICNS)

$(ICON_ICNS): Scripts/generate-icon.swift
	@mkdir -p $(RES_DIR)
	@echo "→ Generating icon…"
	@swiftc Scripts/generate-icon.swift -framework Cocoa -o /tmp/sizer-icon-gen
	@/tmp/sizer-icon-gen
	@iconutil -c icns $(RES_DIR)/$(APP).iconset -o $@
	@rm -rf $(RES_DIR)/$(APP).iconset /tmp/sizer-icon-gen
	@echo "✓ $@"

# Build for development and open.
dev: $(DEV_BUNDLE)
	open $(DEV_BUNDLE)

$(DEV_BUNDLE): $(SRC) Info.plist $(ICON_ICNS)
	@rm -rf $@
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@echo "→ Building (dev)…"
	swiftc $(SRC) $(FLAGS) -target $(shell uname -m)-apple-macos$(MIN_MACOS) -o $@/Contents/MacOS/$(APP)
	@cp Info.plist $@/Contents/Info.plist
	@cp $(ICON_ICNS) $@/Contents/Resources/$(APP).icns
	@echo "✓ $@"

# Build for production.
build:
	@rm -rf $(DIST_BUNDLE)
	@mkdir -p $(DIST_BUNDLE)/Contents/MacOS $(DIST_BUNDLE)/Contents/Resources
	@echo "→ Building (production)…"
	@# Universal binary: one slice per architecture, joined with lipo.
	@set -e; for arch in $(ARCHS); do \
		echo "  swiftc ($$arch, macOS $(MIN_MACOS)+)"; \
		swiftc $(SRC) $(FLAGS) -O -target $$arch-apple-macos$(MIN_MACOS) -o $(DIST_DIR)/$(APP)-$$arch; \
	done
	lipo -create $(foreach arch,$(ARCHS),$(DIST_DIR)/$(APP)-$(arch)) -output $(DIST_BUNDLE)/Contents/MacOS/$(APP)
	@rm -f $(foreach arch,$(ARCHS),$(DIST_DIR)/$(APP)-$(arch))
	@cp Info.plist $(DIST_BUNDLE)/Contents/Info.plist
	@cp $(ICON_ICNS) $(DIST_BUNDLE)/Contents/Resources/$(APP).icns
	@echo "✓ $(DIST_BUNDLE)"

# Build for production and install.
install: build
	@echo "→ Installing to $(INST_BUNDLE)…"
	@rm -rf $(INST_BUNDLE)
	@cp -R $(DIST_BUNDLE) $(INST_BUNDLE)
	@echo "✓ Installed"

# Build for production and open.
open:
	@pkill -x $(APP) || true
	@$(MAKE) install
	open $(INST_BUNDLE)

# Kill the app.
close:
	@pkill -x $(APP) || true

# Close the app and remove if installed.
uninstall:
	@pkill -x $(APP) || true
	@sleep 0.5
	@rm -rf $(INST_BUNDLE)
	@echo "✓ Uninstalled"

# Uninstall and reinstall.
reinstall: uninstall install

# Clean existing builds.
clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR) $(RES_DIR)
	@echo "✓ Cleaned"

# Check that the sources compile.
test:
	@echo "→ Type-checking…"
	@swiftc -typecheck $(SRC)
	@set -e; test_bin=$$(mktemp /tmp/sizer-animation-tests.XXXXXX); \
	trap 'rm -f "$$test_bin"' EXIT; \
	swiftc Sources/Animation.swift Tests/AnimationTests.swift -o "$$test_bin"; \
	"$$test_bin"
	@set -e; test_bin=$$(mktemp /tmp/sizer-snap-tests.XXXXXX); \
	trap 'rm -f "$$test_bin"' EXIT; \
	swiftc Sources/SnapGeometry.swift Tests/SnapTests.swift -o "$$test_bin"; \
	"$$test_bin"
	@echo "✓ Tests passed"

# Bump the patch version, commit (along with any pending changes), tag, and push.
# The tag is v<version>, which makes the Release workflow build the app and
# create the GitHub release with the .dmg attached.
#   make bump                    1.4 -> 1.4.1 -> 1.4.2
#   make bump MSG="Fix sizing"   custom commit message
PLIST_BUDDY := /usr/libexec/PlistBuddy
bump:
	@set -e; \
	if [ -n "$$(git status --porcelain)" ]; then $(MAKE) --no-print-directory test; fi; \
	cur=$$($(PLIST_BUDDY) -c "Print :CFBundleShortVersionString" Info.plist); \
	maj=$$(echo "$$cur" | cut -d. -f1); \
	min=$$(echo "$$cur" | cut -d. -f2); \
	pat=$$(echo "$$cur" | cut -d. -f3); \
	new="$$maj.$${min:-0}.$$(( $${pat:-0} + 1 ))"; \
	if git rev-parse -q --verify "refs/tags/v$$new" >/dev/null; then echo "Tag v$$new already exists"; exit 1; fi; \
	echo "→ $$cur -> $$new"; \
	$(PLIST_BUDDY) -c "Set :CFBundleShortVersionString $$new" Info.plist; \
	git add -A; \
	msg="$(MSG)"; [ -n "$$msg" ] || msg="Bump version to $$new"; \
	git commit -m "$$msg"; \
	git tag "v$$new"; \
	git push origin HEAD "v$$new"; \
	echo "✓ Released $$new"
