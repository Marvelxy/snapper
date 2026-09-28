.PHONY: app run open clean install

CONFIGURATION ?= release

## Build the universal Snapper.app into ./build
app:
	Scripts/build-app.sh $(CONFIGURATION)

## Build and launch the app bundle
run: app
	open build/Snapper.app

## Launch the already-built bundle WITHOUT rebuilding.
## Rebuilding re-signs ad-hoc, which changes the binary hash and makes macOS
## revoke the Screen Recording grant. Use this to relaunch after granting.
open:
	open build/Snapper.app

## Launch the raw executable (no bundle: screen recording will not persist)
run-raw:
	swift run -c $(CONFIGURATION) Snapper

## Copy the built bundle into /Applications
install: app
	rm -rf /Applications/Snapper.app
	cp -R build/Snapper.app /Applications/Snapper.app
	@echo "Installed /Applications/Snapper.app"

clean:
	swift package clean
	rm -rf build
