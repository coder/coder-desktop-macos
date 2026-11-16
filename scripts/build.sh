#!/usr/bin/env bash
# Builds an unsigned release of Coder Desktop: "$out/Coder Desktop.app", with
# its provisioning profiles embedded, and "$out/coder-desktop-dsyms.zip".
#
# The app is signed afterwards by ./scripts/sign.sh, which runs on Linux
# because the Developer ID keys live in Google Cloud KMS, and then packaged by
# ./scripts/package.sh.
set -euo pipefail

# Add standard Nix environment variables
out="${out:-release}"

APP_PROF_PATH=${APP_PROF_PATH:-""}
EXT_PROF_PATH=${EXT_PROF_PATH:-""}
VERSION=${VERSION:-""}

usage() {
  echo "Usage: $0 --app-prof-path <path> --ext-prof-path <path> --version <version>"
  echo "  --app-prof-path <path>     Provisioning profile for the app"
  echo "  --ext-prof-path <path>     Provisioning profile for the network extension"
  echo "  --version       <version>  Version being built, without a leading 'v'"
  echo "  -h, --help                 Display this help message"
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  --app-prof-path)
    APP_PROF_PATH="$2"
    shift 2
    ;;
  --ext-prof-path)
    EXT_PROF_PATH="$2"
    shift 2
    ;;
  --version)
    VERSION="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown parameter passed: $1"
    usage
    exit 1
    ;;
  esac
done

if [[ -z "$APP_PROF_PATH" || -z "$EXT_PROF_PATH" ]]; then
  echo "Missing required values"
  echo "APP_PROF_PATH: $APP_PROF_PATH"
  echo "EXT_PROF_PATH: $EXT_PROF_PATH"
  echo
  usage
  exit 1
fi

# Assert version is not empty and starts with a number
[ -z "$VERSION" ] && {
  echo "Error: VERSION cannot be empty"
  echo
  usage
  exit 1
}
[[ "$VERSION" =~ ^[0-9] ]] || {
  echo "ERROR: Version must start with a number."
  echo "Note: VERSION must not start with a 'v'"
  echo
  usage
  exit 1
}

# Populated at `xcodegen` time.
export PTP_SUFFIX="-systemextension"

make clean/project clean/build

make

mkdir -p "$out" build
out="$(cd "$out" && pwd)"

ARCHIVE_PATH="./build/Coder-Desktop.xcarchive"

# Signing happens later, with rcodesign, so Xcode only builds.
xcodebuild \
  -project "Coder-Desktop/Coder-Desktop.xcodeproj" \
  -scheme "Coder Desktop" \
  -configuration "Release" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO | xcbeautify

BUILT_APP_PATH="$(find "$ARCHIVE_PATH/Products" -maxdepth 3 -type d -name "Coder Desktop.app" -print -quit)"
[[ -n "$BUILT_APP_PATH" ]] || {
  echo "Error: no Coder Desktop.app in $ARCHIVE_PATH/Products"
  exit 1
}

APP_PATH="$out/Coder Desktop.app"
DSYM_ZIPPED_PATH="$out/coder-desktop-dsyms.zip"

ditto "$BUILT_APP_PATH" "$APP_PATH"

# Xcode embeds the provisioning profiles when it signs; we don't let it.
cp "$APP_PROF_PATH" "$APP_PATH/Contents/embedded.provisionprofile"
cp "$EXT_PROF_PATH" "$APP_PATH/Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension/Contents/embedded.provisionprofile"

# Add dsym to build artifacts
(cd "$ARCHIVE_PATH/dSYMs" && zip -9 -r --symlinks "$DSYM_ZIPPED_PATH" ./*)
