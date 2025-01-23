ifdef CI
LINTFLAGS := --reporter github-actions-logging
FMTFLAGS := --lint --reporter github-actions-log
else
LINTFLAGS :=
FMTFLAGS :=
endif

PROJECT := "Coder Desktop/Coder Desktop.xcodeproj"
SCHEME := "Coder Desktop"

fmt:
	swiftformat \
		--exclude '**.pb.swift' \
		$(FMTFLAGS) .

test:
	set -o pipefail && xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-testPlan $(SCHEME) \
		-skipPackagePluginValidation \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO | xcbeautify

lint:
	swiftlint \
		--strict \
		--quiet $(LINTFLAGS)

clean:
	xcodebuild clean \
		-project $(PROJECT)

proto:
	protoc --swift_opt=Visibility=public --swift_out=. 'Coder Desktop/VPNLib/vpn.proto'
