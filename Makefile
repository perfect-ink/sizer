APP      := Sizer
SRC      := $(wildcard Sources/*.swift)
FLAGS    := -framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement

BUILD_DIR := build
DIST_DIR  := dist
INST_DIR  := /Applications
RES_DIR   := Resources

DEV_BUNDLE  := $(BUILD_DIR)/$(APP).app
DIST_BUNDLE := $(DIST_DIR)/$(APP).app
INST_BUNDLE := $(INST_DIR)/$(APP).app
ICON_ICNS   := $(RES_DIR)/$(APP).icns

.PHONY: appstore appstore-secrets screenshots metadata submit dev build open close install uninstall reinstall icon clean all test bump

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
	swiftc $(SRC) $(FLAGS) -o $@/Contents/MacOS/$(APP)
	@cp Info.plist $@/Contents/Info.plist
	@cp $(ICON_ICNS) $@/Contents/Resources/$(APP).icns
	@echo "✓ $@"

# Build for production.
build:
	@rm -rf $(DIST_BUNDLE)
	@mkdir -p $(DIST_BUNDLE)/Contents/MacOS $(DIST_BUNDLE)/Contents/Resources
	@echo "→ Building (production)…"
	swiftc $(SRC) $(FLAGS) -O -o $(DIST_BUNDLE)/Contents/MacOS/$(APP)
	@cp Info.plist $(DIST_BUNDLE)/Contents/Info.plist
	@cp $(ICON_ICNS) $(DIST_BUNDLE)/Contents/Resources/$(APP).icns
	@echo "✓ $(DIST_BUNDLE)"

# Build, sign and package for the Mac App Store: a universal, sandboxed build with
# the Finder sidebar option compiled out (APPSTORE), as dist/Sizer.pkg ready for
# upload. Needs an "Apple Distribution" and a "3rd Party Mac Developer Installer"
# (a.k.a. "Mac Installer Distribution") identity in the keychain, and a Mac App
# Store provisioning profile for the bundle ID. The release workflow runs this.
#   make appstore PROFILE=path/to/Sizer.provisionprofile
MAS_MIN_OS  := 13.0
MAS_DIR     := $(BUILD_DIR)/appstore
MAS_BUNDLE  := $(MAS_DIR)/$(APP).app
MAS_PKG     := $(DIST_DIR)/$(APP).pkg
BUNDLE_ID    = $(shell $(PLIST_BUDDY) -c "Print :CFBundleIdentifier" Info.plist)
# The Apple Developer team that owns org.perfectink.sizer on the App Store.
TEAM_ID            ?= XS9W9A8FWM
APP_IDENTITY       ?= Apple Distribution
INSTALLER_IDENTITY ?= 3rd Party Mac Developer Installer

appstore: $(ICON_ICNS)
	@[ -n "$(TEAM_ID)" ] || { echo "Set TEAM_ID (Apple Developer team ID)"; exit 1; }
	@[ -f "$(PROFILE)" ] || { echo "Set PROFILE to the Mac App Store .provisionprofile"; exit 1; }
	@rm -rf $(MAS_DIR) $(MAS_PKG)
	@mkdir -p $(MAS_BUNDLE)/Contents/MacOS $(MAS_BUNDLE)/Contents/Resources $(DIST_DIR)
	@echo "→ Building (App Store, universal)…"
	swiftc $(SRC) $(FLAGS) -O -D APPSTORE -target arm64-apple-macos$(MAS_MIN_OS)  -o $(MAS_DIR)/$(APP)-arm64
	swiftc $(SRC) $(FLAGS) -O -D APPSTORE -target x86_64-apple-macos$(MAS_MIN_OS) -o $(MAS_DIR)/$(APP)-x86_64
	lipo -create $(MAS_DIR)/$(APP)-arm64 $(MAS_DIR)/$(APP)-x86_64 -output $(MAS_BUNDLE)/Contents/MacOS/$(APP)
	@cp Info.plist $(MAS_BUNDLE)/Contents/Info.plist
	@plutil -replace LSMinimumSystemVersion -string $(MAS_MIN_OS) $(MAS_BUNDLE)/Contents/Info.plist
	@[ -z "$(VERSION)" ] || plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(MAS_BUNDLE)/Contents/Info.plist
	@[ -z "$(BUILD_NUMBER)" ] || plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" $(MAS_BUNDLE)/Contents/Info.plist
	@cp $(ICON_ICNS) $(MAS_BUNDLE)/Contents/Resources/$(APP).icns
	@cp "$(PROFILE)" $(MAS_BUNDLE)/Contents/embedded.provisionprofile
	@cp $(APP).entitlements $(MAS_DIR)/signing.entitlements
	@$(PLIST_BUDDY) -c "Add :com.apple.application-identifier string $(TEAM_ID).$(BUNDLE_ID)" $(MAS_DIR)/signing.entitlements
	@$(PLIST_BUDDY) -c "Add :com.apple.developer.team-identifier string $(TEAM_ID)" $(MAS_DIR)/signing.entitlements
	@echo "→ Signing…"
	codesign --force --timestamp --entitlements $(MAS_DIR)/signing.entitlements --sign "$(APP_IDENTITY)" $(MAS_BUNDLE)
	codesign --verify --strict --verbose=2 $(MAS_BUNDLE)
	productbuild --component $(MAS_BUNDLE) /Applications --sign "$(INSTALLER_IDENTITY)" $(MAS_PKG)
	@echo "✓ $(MAS_PKG)"

# Set every GitHub secret the App Store workflow needs, from this Mac's keychain and
# the App Store Connect API (creates the provisioning profile if needed).
#   make appstore-secrets            make appstore-secrets DRY_RUN=1
appstore-secrets:
	@DRY_RUN=$(DRY_RUN) Scripts/appstore-secrets.sh

# Render the App Store screenshots (docs/app-store/screenshots/en-US, 2880×1800) from the real
# Settings window plus drawn desktops. See Scripts/generate-screenshots.swift.
screenshots:
	@echo "→ Rendering screenshots…"
	@swiftc -D APPSTORE Scripts/generate-screenshots.swift \
		Sources/SettingsWindowController.swift Sources/BindingStore.swift Sources/SnapGeometry.swift \
		-framework Cocoa -framework Carbon -framework ApplicationServices -o /tmp/sizer-screenshots
	@/tmp/sizer-screenshots docs/app-store/screenshots/en-US
	@rm -f /tmp/sizer-screenshots

# Push the App Store listing (docs/app-store/metadata + docs/app-store/screenshots) to App Store
# Connect, and submit a processed build for review. Needs fastlane and the
# APP_STORE_CONNECT_API_KEY_* variables described at the top of fastlane/Fastfile.
# The App Store workflows run these for you on a tag push and on manual dispatch.
#   make metadata VERSION=1.5.2
#   make submit VERSION=1.5.2 [BUILD_NUMBER=42]
metadata:
	@[ -n "$(VERSION)" ] || { echo "Set VERSION (e.g. 1.5.2)"; exit 1; }
	fastlane mac metadata version:$(VERSION)

submit:
	@[ -n "$(VERSION)" ] || { echo "Set VERSION (e.g. 1.5.2)"; exit 1; }
	fastlane mac submit version:$(VERSION) $(if $(BUILD_NUMBER),build:$(BUILD_NUMBER),)

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
	@swiftc -typecheck -D APPSTORE $(SRC)
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
	if git rev-parse -q --verify "refs/tags/$$new" >/dev/null; then echo "Tag $$new already exists"; exit 1; fi; \
	echo "→ $$cur -> $$new"; \
	$(PLIST_BUDDY) -c "Set :CFBundleShortVersionString $$new" Info.plist; \
	git add -A; \
	msg="$(MSG)"; [ -n "$$msg" ] || msg="Bump version to $$new"; \
	git commit -m "$$msg"; \
	git tag "$$new"; \
	git push origin HEAD "$$new"; \
	echo "✓ Released $$new"
