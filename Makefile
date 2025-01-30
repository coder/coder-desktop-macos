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

.PHONY: setup
setup: \
	$(XCPROJECT) \
	$(PROJECT)/VPNLib/vpn.pb.swift

$(XCPROJECT): $(PROJECT)/project.yml
	cd $(PROJECT); \
		SWIFT_VERSION=$(SWIFT_VERSION) xcodegen

$(PROJECT)/VPNLib/vpn.pb.swift: $(PROJECT)/VPNLib/vpn.proto
	protoc --swift_opt=Visibility=public --swift_out=. 'Coder Desktop/VPNLib/vpn.proto'

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
lint: ## Lint swift files
	swiftlint \
		--strict \
		--quiet $(LINTFLAGS)

.PHONY: clean
clean: ## Clean Xcode project
	xcodebuild clean \
		-project $(XCPROJECT)
	rm -rf $(XCPROJECT)

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
