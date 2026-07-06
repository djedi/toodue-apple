# TooDue iOS — build & test automation
#
# Everyday flow:
#   make            # help
#   make run        # build + install + launch in the simulator
#   make test       # run the unit tests

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

PROJECT      := TooDue.xcodeproj
SCHEME       := TooDue
SIM_NAME     ?= iPhone 17 Pro
SIM_OS       ?=
DEVICE_ID    ?= $(shell ./scripts/sim-device-id '$(SIM_NAME)' '$(SIM_OS)')
DESTINATION  := id=$(DEVICE_ID)
DERIVED_DATA := build
BUNDLE_ID    := com.toodue.ios
APP          := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/TooDue.app

# Prettify xcodebuild output when xcbeautify is around; stay plain otherwise.
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
ifdef XCBEAUTIFY
  PRETTY = | xcbeautify
else
  PRETTY =
endif

.DEFAULT_GOAL := help

##@ Setup

.PHONY: bootstrap
bootstrap: ## Install dev tools (xcodegen, xcbeautify) via Homebrew
	@command -v xcodegen  >/dev/null || brew install xcodegen
	@command -v xcbeautify >/dev/null || brew install xcbeautify
	@echo "✓ tools ready"

$(PROJECT): project.yml
	@command -v xcodegen >/dev/null || { echo "xcodegen missing — run 'make bootstrap'"; exit 1; }
	xcodegen generate

.PHONY: generate
generate: ## (Re)generate the Xcode project from project.yml
	@command -v xcodegen >/dev/null || { echo "xcodegen missing — run 'make bootstrap'"; exit 1; }
	xcodegen generate

##@ Build & test

.PHONY: build
build: $(PROJECT) ## Build for the simulator
	xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO $(PRETTY)

.PHONY: test
test: $(PROJECT) ## Run unit tests in the simulator
	xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO $(PRETTY)

##@ Run

.PHONY: run
run: build ## Build, install, and launch in the simulator
	@xcrun simctl boot "$(DEVICE_ID)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(DEVICE_ID)" -b
	open -a Simulator
	xcrun simctl install "$(DEVICE_ID)" "$(APP)"
	xcrun simctl launch "$(DEVICE_ID)" $(BUNDLE_ID)

.PHONY: open
open: $(PROJECT) ## Open the project in Xcode
	open $(PROJECT)

.PHONY: server
server: ## Start a local TooDue backend (needs ../toodue checkout + Docker)
	$(MAKE) -C ../toodue up
	@echo "→ backend on http://localhost:8080 — point the app at http://localhost:8080"

##@ Housekeeping

.PHONY: clean
clean: ## Delete build products and the generated project
	rm -rf $(DERIVED_DATA) $(PROJECT)

.PHONY: nuke
nuke: clean ## Clean + erase the simulator's copy of the app
	@xcrun simctl uninstall "$(DEVICE_ID)" $(BUNDLE_ID) 2>/dev/null || true

.PHONY: sims
sims: ## List available iPhone simulators (set SIM_NAME=… SIM_OS=… to pick one)
	@xcrun simctl list devices available | grep -i iphone

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nTooDue iOS\n\nUsage:\n  make \033[36m<target>\033[0m [SIM_NAME=\"iPhone 17 Pro\"] [SIM_OS=\"26.5\"]\n"} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
