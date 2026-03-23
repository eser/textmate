# SW³ TextFellow (sw3t) — Makefile
# Gradual migration from TextMate
# Both Rave and Xcode builds coexist until Xcode is proven identical.
# ─────────────────────────────────────────────

.PHONY: build run test clean configure xcode xcode-run xcode-clean check-deps info deps verify

RAVE_APP = ~/build/textmate/release/Applications/TextMate/TextMate.app
XCODE_APP = build/xcode/Debug/TextFellow.app

# ─────────────────────────────────────────────
# Rave build (original)
# ─────────────────────────────────────────────

## Build TextMate (Rave/Ninja)
build:
	ninja TextMate

## Build and run TextMate (Rave)
run: build
	@xattr -cr $(RAVE_APP) 2>/dev/null || true
	open $(RAVE_APP)

## Build and relaunch (TextMate's native reload)
relaunch:
	ninja TextMate/run

## Configure Rave (first time setup)
configure:
	./configure

## Clean Rave build artifacts
clean:
	ninja -t clean 2>/dev/null || true

# ─────────────────────────────────────────────
# Xcode build (new)
# ─────────────────────────────────────────────

## Generate Xcode project from project.yml
xcode:
	xcodegen generate
	@echo "Generated TextFellow.xcodeproj — open with: open TextFellow.xcodeproj"

## Build TextFellow via Xcode (Debug, arm64)
xcode-build: xcode
	xcodebuild -project TextFellow.xcodeproj \
		-target TextFellow \
		-configuration Debug \
		-arch arm64 \
		SYMROOT=$(CURDIR)/build/xcode \
		build

## Build and run TextFellow (Xcode)
xcode-run: xcode-build
	@xattr -cr $(XCODE_APP) 2>/dev/null || true
	open $(XCODE_APP)

## Clean Xcode build artifacts
xcode-clean:
	rm -rf build/xcode
	rm -rf TextFellow.xcodeproj

# ─────────────────────────────────────────────
# Quality
# ─────────────────────────────────────────────

## Run tests (Rave)
test:
	ninja run_tests

## Check that all required dependencies are installed
check-deps:
	@scripts/check-deps.sh

## Verify both builds produce working apps
verify:
	@scripts/verify-build.sh

# ─────────────────────────────────────────────
# Info
# ─────────────────────────────────────────────

## Show build summary
info:
	@echo "─── Rave build ───"
	@ls -lh $(RAVE_APP)/Contents/MacOS/TextMate 2>/dev/null || echo "  Not built yet (run: make build)"
	@echo ""
	@echo "─── Xcode build ───"
	@ls -lh $(XCODE_APP)/Contents/MacOS/TextFellow 2>/dev/null || echo "  Not built yet (run: make xcode-build)"
	@echo ""
	@echo "─── Source files ───"
	@find Frameworks Applications -name "*.mm" 2>/dev/null | wc -l | xargs echo "  .mm:"
	@find Frameworks Applications -name "*.cc" 2>/dev/null | wc -l | xargs echo "  .cc:"
	@find Frameworks Applications -name "*.h" 2>/dev/null | wc -l | xargs echo "  .h:"

## Install dependencies (macOS, Homebrew)
deps:
	brew install multimarkdown ninja ragel xcodegen
