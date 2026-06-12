#!/usr/bin/env bash
set -euo pipefail

# Builds the Coder Connect Go tunnel (./libtunnel) into a static xcframework
# consumed by the iOS Network Extension (VPN-iOS). Unlike macOS, which
# downloads the deployment's `coder` binary at runtime, iOS forbids executing
# downloaded code, so the tunnel is compiled in at build time.
#
# Requires macOS with Xcode and Go installed.

cd "$(dirname "$0")/.."

OUT="Coder-Desktop/CoderVPN.xcframework"
BUILD_DIR="build/libtunnel"
IOS_MIN_VERSION="17.0"

rm -rf "$OUT" "$BUILD_DIR"

build_slice() {
	local sdk="$1" target="$2" outdir="$3"
	local sdk_path clang
	sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
	clang="$(xcrun --sdk "$sdk" -f clang)"
	mkdir -p "$outdir/include"
	(
		cd libtunnel
		CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
			CC="$clang" \
			CGO_CFLAGS="-isysroot $sdk_path -target $target" \
			CGO_LDFLAGS="-isysroot $sdk_path -target $target" \
			go build -buildmode=c-archive -tags ios -trimpath -ldflags="-s -w" \
			-o "../$outdir/libcodervpn.a" .
	)
	mv "$outdir/libcodervpn.h" "$outdir/include/libcodervpn.h"
	cat >"$outdir/include/module.modulemap" <<-EOF
		module CoderVPNGo {
		    header "libcodervpn.h"
		    export *
		}
	EOF
}

build_slice iphoneos "arm64-apple-ios$IOS_MIN_VERSION" "$BUILD_DIR/ios-arm64"
# The Network Extension can't run in the simulator, but the simulator slice
# lets the project compile and unit-test there.
build_slice iphonesimulator "arm64-apple-ios$IOS_MIN_VERSION-simulator" "$BUILD_DIR/ios-arm64-simulator"

xcodebuild -create-xcframework \
	-library "$BUILD_DIR/ios-arm64/libcodervpn.a" -headers "$BUILD_DIR/ios-arm64/include" \
	-library "$BUILD_DIR/ios-arm64-simulator/libcodervpn.a" -headers "$BUILD_DIR/ios-arm64-simulator/include" \
	-output "$OUT"

echo "Built $OUT"
