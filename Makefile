ifdef CI
LINTFLAGS := --reporter github-actions-logging
FMTFLAGS := --lint --reporter github-actions-log
else
LINTFLAGS :=
FMTFLAGS :=
endif

PROJECT := Coder\ Desktop
XCPROJECT := Coder\ Desktop/Coder\ Desktop.xcodeproj
SCHEME := Coder\ Desktop
SWIFT_VERSION := 6.0

CURRENT_PROJECT_VERSION:=$(shell git describe --match 'v[0-9]*' --dirty='.devel' --always --tags)
ifeq ($(strip $(CURRENT_PROJECT_VERSION)),)
    $(error CURRENT_PROJECT_VERSION cannot be empty)
endif

MARKETING_VERSION:=$(shell git describe --match 'v[0-9]*' --tags --abbrev=0 | sed 's/^v//' | sed 's/-.*$$//')
ifeq ($(strip $(MARKETING_VERSION)),)
    $(error MARKETING_VERSION cannot be empty)
endif

# Define the keychain file name first
KEYCHAIN_FILE := app-signing.keychain-db
# Use shell to get the absolute path only if the file exists
APP_SIGNING_KEYCHAIN := $(if $(wildcard $(KEYCHAIN_FILE)),$(shell realpath $(KEYCHAIN_FILE)),$(abspath $(KEYCHAIN_FILE)))

.PHONY: setup
setup: \
	$(XCPROJECT) \
	$(PROJECT)/VPNLib/vpn.pb.swift

$(XCPROJECT): $(PROJECT)/project.yml
	cd $(PROJECT); \
		SWIFT_VERSION=$(SWIFT_VERSION) \
		PTP_SUFFIX=${PTP_SUFFIX} \
		APP_PROVISIONING_PROFILE_ID=${APP_PROVISIONING_PROFILE_ID} \
		EXT_PROVISIONING_PROFILE_ID=${EXT_PROVISIONING_PROFILE_ID} \
		CURRENT_PROJECT_VERSION=$(CURRENT_PROJECT_VERSION) \
		MARKETING_VERSION=$(MARKETING_VERSION) \
		xcodegen

$(PROJECT)/VPNLib/vpn.pb.swift: $(PROJECT)/VPNLib/vpn.proto
	protoc --swift_opt=Visibility=public --swift_out=. 'Coder Desktop/VPNLib/vpn.proto'

$(KEYCHAIN_FILE):
	security create-keychain -p "" "$(APP_SIGNING_KEYCHAIN)"
	security set-keychain-settings -lut 21600 "$(APP_SIGNING_KEYCHAIN)"
	security unlock-keychain -p "" "$(APP_SIGNING_KEYCHAIN)"
	@tempfile=$$(mktemp); \
	echo "$$APPLE_CERT" | base64 -d > $$tempfile; \
	security import $$tempfile -P '$(CERT_PASSWORD)' -A -t cert -f pkcs12 -k "$(APP_SIGNING_KEYCHAIN)"; \
	rm $$tempfile
	security list-keychains -d user -s $$(security list-keychains -d user | tr -d '\"') "$(APP_SIGNING_KEYCHAIN)"

.PHONY: release
release: $(KEYCHAIN_FILE) ## Create a release build of Coder Desktop
	@APP_PROF_PATH="$$(mktemp)"; \
	EXT_PROF_PATH="$$(mktemp)"; \
	echo -n "$$APP_PROF" | base64 -d > "$$APP_PROF_PATH"; \
	echo -n "$$EXT_PROF" | base64 -d > "$$EXT_PROF_PATH"; \
	./scripts/build.sh \
		--app-prof-path "$$APP_PROF_PATH" \
		--ext-prof-path "$$EXT_PROF_PATH" \
		--keychain "$(APP_SIGNING_KEYCHAIN)"; \
	rm "$$APP_PROF_PATH" "$$EXT_PROF_PATH"

.PHONY: fmt
fmt: ## Run Swift file formatter
	swiftformat \
		--swiftversion $(SWIFT_VERSION) \
		$(FMTFLAGS) .

.PHONY: test
test: $(XCPROJECT) ## Run all tests
	set -o pipefail && xcodebuild test \
		-project $(XCPROJECT) \
		-scheme $(SCHEME) \
		-testPlan $(SCHEME) \
		-skipPackagePluginValidation \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO | xcbeautify

.PHONY: lint
lint: lint/swift lint/actions ## Lint all files in the repo

.PHONY: lint/swift
lint/swift: ## Lint Swift files
	swiftlint \
		--strict \
		--quiet $(LINTFLAGS)

.PHONY: lint/actions
lint/actions: ## Lint GitHub Actions
	actionlint
	zizmor .

.PHONY: clean
clean: clean/project clean/keychain clean/build ## Clean project and artifacts

.PHONY: clean/project
clean/project:
	@if [ -d $(XCPROJECT) ]; then \
		echo "Cleaning project: '$(XCPROJECT)'"; \
		xcodebuild clean -project $(XCPROJECT); \
		rm -rf $(XCPROJECT); \
	fi
	find . -name "*.entitlements" -type f -delete

.PHONY: clean/keychain
clean/keychain:
	@if [ -e "$(APP_SIGNING_KEYCHAIN)" ]; then \
		echo "Cleaning keychain: '$(APP_SIGNING_KEYCHAIN)'"; \
		security delete-keychain "$(APP_SIGNING_KEYCHAIN)"; \
		rm -f "$(APP_SIGNING_KEYCHAIN)"; \
	fi

.PHONY: clean/build
clean/build:
	rm -rf build/ release/ $$out

.PHONY: proto
proto: $(PROJECT)/VPNLib/vpn.pb.swift ## Generate Swift files from protobufs

.PHONY: help
help: ## Show this help
	@echo "Specify a command. The choices are:"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-20s\033[m %s\n", $$1, $$2}'
	@echo ""

.PHONY: watch-gen
watch-gen: ## Generate Xcode project file and watch for changes
	watchexec -w 'Coder Desktop/project.yml' make $(XCPROJECT)

print-%: ; @echo $*=$($*)
