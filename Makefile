APP_NAME := MicBar
APP_BUNDLE := build/$(APP_NAME).app
CONFIG := release

# Stable self-signed code-signing identity. Ad-hoc signing (codesign -s -) mints a
# new cdhash every build, which invalidates all of MicBar's TCC permissions
# (Automation/Microphone/Accessibility) on every install. Signing with a stable
# cert gives a cdhash-independent designated requirement, so grants persist.
# Create the identity once with: make setup-signing
SIGN_ID := MicBar Local Signing
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/micbar-signing.keychain-db
SIGN_KEYCHAIN_PW := micbar-local

build:
	swift build -c $(CONFIG)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp .build/$(CONFIG)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp -r .build/$(CONFIG)/MicBar_MicBar.bundle $(APP_BUNDLE)/Contents/Resources/
	cp MicBar/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp MicBar/Info.plist $(APP_BUNDLE)/Contents/
	-security unlock-keychain -p "$(SIGN_KEYCHAIN_PW)" "$(SIGN_KEYCHAIN)" 2>/dev/null
	codesign -s "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --force $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	-killall $(APP_NAME) 2>/dev/null; sleep 0.5
	open $(APP_BUNDLE)

install: build
	-killall $(APP_NAME) 2>/dev/null; sleep 0.5
	cp -R $(APP_BUNDLE) /Applications/
	open /Applications/$(APP_NAME).app

setup-signing:
	./scripts/setup-signing.sh

clean:
	rm -rf build .build

.PHONY: build run clean install setup-signing
