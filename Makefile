# Use bash, and immediately exit on failure
SHELL := bash
.SHELLFLAGS := -ceu

# This doesn't work on directories.
# See https://stackoverflow.com/questions/25752543/make-delete-on-error-for-directory-targets
.DELETE_ON_ERROR:

ifdef CI
LINTFLAGS := --reporter github-actions-logging
FMTFLAGS := --lint --reporter github-actions-log
# Use the package versions in Package.resolved, and fail if it does not match project.yml.
PACKAGEFLAGS := -disableAutomaticPackageResolution
else
LINTFLAGS :=
FMTFLAGS :=
PACKAGEFLAGS :=
endif

PROJECT := Coder-Desktop
XCPROJECT := Coder-Desktop/Coder-Desktop.xcodeproj
# The package versions the app is built with. Xcode reads them from inside the project, which
# is generated, so the tracked file is copied there whenever the project is generated.
PACKAGE_RESOLVED := $(PROJECT)/Package.resolved
XCPROJECT_PACKAGE_RESOLVED := $(XCPROJECT)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
SCHEME := Coder\ Desktop
TEST_PLAN := Coder-Desktop
SWIFT_VERSION := 6.0


MUTAGEN_RESOURCES := mutagen-agents.tar.gz mutagen-darwin-arm64 mutagen-darwin-amd64
ifndef MUTAGEN_VERSION
MUTAGEN_VERSION:=$(shell grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' $(PROJECT)/Resources/.mutagenversion)
endif
ifeq ($(strip $(MUTAGEN_VERSION)),)
$(error MUTAGEN_VERSION must be a valid version)
endif
# SHA-256 of each mutagen resource at that version. They ship inside the app, so a download that
# does not match is rejected. When changing .mutagenversion, take the new values from SHA256SUMS
# in that coder/mutagen release.
MUTAGEN_SHA256_mutagen-agents.tar.gz := 02e7458b9c6d1436c1fda8151bac86bfb46783b75a10d0fd9202100eb2a16f1d
MUTAGEN_SHA256_mutagen-darwin-arm64 := 2439eafd5b53bdbaa6b36deeea747c4891eda8ca85ffdc7b8984c5de3e2fee62
MUTAGEN_SHA256_mutagen-darwin-amd64 := 2cc67b7bc269a0549355116e05edc0635bb5724f735f9cc354f17a26ad43b41d

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

.PHONY: setup
setup: \
	$(addprefix $(PROJECT)/Resources/,$(MUTAGEN_RESOURCES)) \
	$(XCPROJECT)

# Mutagen resources
$(addprefix $(PROJECT)/Resources/,$(MUTAGEN_RESOURCES)): $(PROJECT)/Resources/.mutagenversion
	curl -sL "https://storage.googleapis.com/coder-desktop/mutagen/$(MUTAGEN_VERSION)/$(notdir $@)" -o "$@"
	echo "$(MUTAGEN_SHA256_$(notdir $@))  $@" | shasum -a 256 -c - || { rm -f "$@"; exit 1; }
	chmod +x "$@"

$(XCPROJECT): $(PROJECT)/project.yml $(PACKAGE_RESOLVED)
	cd $(PROJECT); \
		SWIFT_VERSION=$(SWIFT_VERSION) \
		PTP_SUFFIX=${PTP_SUFFIX} \
		APP_PROVISIONING_PROFILE_ID=${APP_PROVISIONING_PROFILE_ID} \
		EXT_PROVISIONING_PROFILE_ID=${EXT_PROVISIONING_PROFILE_ID} \
		CURRENT_PROJECT_VERSION=$(CURRENT_PROJECT_VERSION) \
		MARKETING_VERSION=$(MARKETING_VERSION) \
		GIT_COMMIT_HASH=$(GIT_COMMIT_HASH) \
		xcodegen
	mkdir -p $(dir $(XCPROJECT_PACKAGE_RESOLVED))
	cp $(PACKAGE_RESOLVED) $(XCPROJECT_PACKAGE_RESOLVED)

.PHONY: release
release: ## Build an unsigned release of Coder Desktop. CI signs it, see RELEASING.md
	./scripts/build.sh

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
		$(PACKAGEFLAGS) \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO | xcbeautify

.PHONY: lockfile
lockfile: $(XCPROJECT) ## Update Package.resolved after changing packages in project.yml
	xcodebuild -resolvePackageDependencies -project $(XCPROJECT)
	cp $(XCPROJECT_PACKAGE_RESOLVED) $(PACKAGE_RESOLVED)

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
clean: clean/project clean/build clean/mutagen ## Clean project and artifacts

.PHONY: clean/project
clean/project:
	@if [ -d $(XCPROJECT) ]; then \
		echo "Cleaning project: '$(XCPROJECT)'"; \
		xcodebuild clean -project $(XCPROJECT); \
		rm -rf $(XCPROJECT); \
	fi
	find . -name "*.entitlements" -type f -delete

.PHONY: clean/build
clean/build:
	rm -rf build/ release/

.PHONY: clean/mutagen
clean/mutagen:
	find $(PROJECT)/Resources -name 'mutagen-*' -delete

.PHONY: help
help: ## Show this help
	@echo "Specify a command. The choices are:"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-20s\033[m %s\n", $$1, $$2}'
	@echo ""

.PHONY: watch-gen
watch-gen: ## Generate Xcode project file and watch for changes
	watchexec -w 'Coder-Desktop/project.yml' make $(XCPROJECT)

print-%: ; @echo $*=$($*)
