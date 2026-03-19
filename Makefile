APP_NAME := MicBar
APP_BUNDLE := build/$(APP_NAME).app
CONFIG := release

build:
	swift build -c $(CONFIG)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp .build/$(CONFIG)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp -r .build/$(CONFIG)/MicBar_MicBar.bundle $(APP_BUNDLE)/Contents/Resources/
	cp MicBar/Info.plist $(APP_BUNDLE)/Contents/
	codesign -s - --force $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	-killall $(APP_NAME) 2>/dev/null; sleep 0.5
	open $(APP_BUNDLE)

install: build
	-killall $(APP_NAME) 2>/dev/null; sleep 0.5
	cp -R $(APP_BUNDLE) /Applications/
	open /Applications/$(APP_NAME).app

clean:
	rm -rf build .build

.PHONY: build run clean install
