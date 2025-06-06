# Use bash, and immediately exit on failure
SHELL := bash
.SHELLFLAGS := -ceu

# This doesn't work on directories.
# See https://stackoverflow.com/questions/25752543/make-delete-on-error-for-directory-targets
.DELETE_ON_ERROR:

ifdef CI
LINTFLAGS := --reporter github-actions-logging
FMTFLAGS := --lint --reporter github-actions-log
else
LINTFLAGS :=
FMTFLAGS :=
endif

PROJECT := Coder-Desktop
XCPROJECT := Coder-Desktop/Coder-Desktop.xcodeproj
SCHEME := Coder\ Desktop
TEST_PLAN := Coder-Desktop
SWIFT_VERSION := 6.0

MUTAGEN_PROTO_DEFS := $(shell find $(PROJECT)/VPNLib/FileSync/MutagenSDK -type f -name '*.proto' -print)
MUTAGEN_PROTO_SWIFTS := $(patsubst %.proto,%.pb.swift,$(MUTAGEN_PROTO_DEFS))

MUTAGEN_RESOURCES := mutagen-agents.tar.gz mutagen-darwin-arm64 mutagen-darwin-amd64
ifndef MUTAGEN_VERSION
MUTAGEN_VERSION:=$(shell grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' $(PROJECT)/Resources/.mutagenversion)
endif
ifeq ($(strip $(MUTAGEN_VERSION)),)
$(error MUTAGEN_VERSION must be a valid version)
endif

ifndef CURRENT_PROJECT_VERSION
# Must be X.Y.Z[.N]
CURRENT_PROJECT_VERSION:=$(shell ./scripts/version.sh)
endif
ifeq ($(strip $(CURRENT_PROJECT_VERSION)),)
$(error CURRENT_PROJECT_VERSION cannot be empty)
endif

ifndef MARKETING_VERSION
# Must be X.Y.Z
MARKETING_VERSION:=$(shell ./scripts/version.sh --short)
endif
ifeq ($(strip $(MARKETING_VERSION)),)
$(error MARKETING_VERSION cannot be empty)
endif

ifndef GIT_COMMIT_HASH
# Must be a valid git commit hash
GIT_COMMIT_HASH := $(shell ./scripts/version.sh --hash)
endif
ifeq ($(strip $(GIT_COMMIT_HASH)),)
$(error GIT_COMMIT_HASH cannot be empty)
endif

# Define the keychain file name first
KEYCHAIN_FILE := app-signing.keychain-db
# Use shell to get the absolute path only if the file exists
APP_SIGNING_KEYCHAIN := $(if $(wildcard $(KEYCHAIN_FILE)),$(shell realpath $(KEYCHAIN_FILE)),$(abspath $(KEYCHAIN_FILE)))

.PHONY: setup
setup: \
	$(addprefix $(PROJECT)/Resources/,$(MUTAGEN_RESOURCES)) \
	$(XCPROJECT) \
	$(PROJECT)/VPNLib/vpn.pb.swift \
	$(MUTAGEN_PROTO_SWIFTS)

# Mutagen resources
$(addprefix $(PROJECT)/Resources/,$(MUTAGEN_RESOURCES)): $(PROJECT)/Resources/.mutagenversion
	curl -sL "https://storage.googleapis.com/coder-desktop/mutagen/$(MUTAGEN_VERSION)/$(notdir $@)" -o "$@"
	chmod +x "$@"

$(XCPROJECT): $(PROJECT)/project.yml
	cd $(PROJECT); \
		SWIFT_VERSION=$(SWIFT_VERSION) \
		PTP_SUFFIX=${PTP_SUFFIX} \
		APP_PROVISIONING_PROFILE_ID=${APP_PROVISIONING_PROFILE_ID} \
		EXT_PROVISIONING_PROFILE_ID=${EXT_PROVISIONING_PROFILE_ID} \
		CURRENT_PROJECT_VERSION=$(CURRENT_PROJECT_VERSION) \
		MARKETING_VERSION=$(MARKETING_VERSION) \
		GIT_COMMIT_HASH=$(GIT_COMMIT_HASH) \
		xcodegen

$(PROJECT)/VPNLib/vpn.pb.swift: $(PROJECT)/VPNLib/vpn.proto
	protoc --swift_opt=Visibility=public --swift_out=. 'Coder-Desktop/VPNLib/vpn.proto'

$(MUTAGEN_PROTO_SWIFTS):
	protoc \
	-I=$(PROJECT)/VPNLib/FileSync/MutagenSDK \
	--swift_out=$(PROJECT)/VPNLib/FileSync/MutagenSDK \
	--grpc-swift_out=$(PROJECT)/VPNLib/FileSync/MutagenSDK \
	$(patsubst %.pb.swift,%.proto,$@)

$(KEYCHAIN_FILE):
	security create-keychain -p "" "$(APP_SIGNING_KEYCHAIN)"
	security set-keychain-settings -lut 21600 "$(APP_SIGNING_KEYCHAIN)"
	security unlock-keychain -p "" "$(APP_SIGNING_KEYCHAIN)"
	@tempfile=$$(mktemp); \
	echo "$$APPLE_DEVELOPER_ID_PKCS12_B64" | base64 -d > $$tempfile; \
	security import $$tempfile -P '$(APPLE_DEVELOPER_ID_PKCS12_PASSWORD)' -A -t cert -f pkcs12 -k "$(APP_SIGNING_KEYCHAIN)"; \
	rm $$tempfile
	@tempfile=$$(mktemp); \
	echo "$$APPLE_INSTALLER_PKCS12_B64" | base64 -d > $$tempfile; \
	security import $$tempfile -P '$(APPLE_INSTALLER_PKCS12_PASSWORD)' -A -t cert -f pkcs12 -k "$(APP_SIGNING_KEYCHAIN)"; \
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
		--version $(MARKETING_VERSION) \
		--keychain "$(APP_SIGNING_KEYCHAIN)" \
		--sparkle-private-key "$$SPARKLE_PRIVATE_KEY"; \
	rm "$$APP_PROF_PATH" "$$EXT_PROF_PATH"

.PHONY: fmt
fmt: ## Run Swift file formatter
	swiftformat \
		--swiftversion $(SWIFT_VERSION) \
		$(FMTFLAGS) .

.PHONY: test
test: $(addprefix $(PROJECT)/Resources/,$(MUTAGEN_RESOURCES)) $(XCPROJECT) ## Run all tests
	set -o pipefail && xcodebuild test \
		-project $(XCPROJECT) \
		-scheme $(SCHEME) \
		-testPlan $(TEST_PLAN) \
		-skipMacroValidation \
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
clean: clean/project clean/keychain clean/build clean/mutagen ## Clean project and artifacts

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

.PHONY: clean/mutagen
clean/mutagen:
	find $(PROJECT)/Resources -name 'mutagen-*' -delete

.PHONY: proto
proto: $(PROJECT)/VPNLib/vpn.pb.swift $(MUTAGEN_PROTO_SWIFTS) ## Generate Swift files from protobufs

.PHONY: help
help: ## Show this help
	@echo "Specify a command. The choices are:"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-20s\033[m %s\n", $$1, $$2}'
	@echo ""

.PHONY: watch-gen
watch-gen: ## Generate Xcode project file and watch for changes
	watchexec -w 'Coder-Desktop/project.yml' make $(XCPROJECT)

print-%: ; @echo $*=$($*)
