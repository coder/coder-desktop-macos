#!/usr/bin/env bash
set -euo pipefail

# Add standard Nix environment variables
out="${out:-release}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build Documentation @ https://developer.apple.com/forums/thread/737894
APPLE_TEAM_ID="4399GN35BJ"
CODE_SIGN_IDENTITY="Developer ID Application: Coder Technologies Inc (${APPLE_TEAM_ID})"
CODE_SIGN_INSTALLER_IDENTITY="Developer ID Installer: Coder Technologies Inc (${APPLE_TEAM_ID})"
PKG_SCRIPTS="$SCRIPT_DIR/../pkgbuild/scripts/"

# Default values pulled in from env
APP_PROF_PATH=${APP_PROF_PATH:-""}
EXT_PROF_PATH=${EXT_PROF_PATH:-""}
KEYCHAIN=${KEYCHAIN:-""}
VERSION=${VERSION:-""}

# Function to display usage
usage() {
  echo "Usage: $0 [--app-prof-path <path>] [--ext-prof-path <path>] [--keychain <path>]"
  echo "  --app-prof-path <path>     Set the APP_PROF_PATH variable"
  echo "  --ext-prof-path <path>     Set the EXT_PROF_PATH variable"
  echo "  --keychain      <path>     Set the KEYCHAIN variable"
  echo "  --version       <version>  Set the VERSION variable to fetch and generate the cask file for"
  echo "  -h, --help                 Display this help message"
}

# Parse command line arguments
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
  --keychain)
    KEYCHAIN="$2"
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

# Check if required variables are set
if [[ -z "$APP_PROF_PATH" || -z "$EXT_PROF_PATH" || -z "$KEYCHAIN" ]]; then
  echo "Missing required values"
  echo "APP_PROF_PATH: $APP_PROF_PATH"
  echo "EXT_PROF_PATH: $EXT_PROF_PATH"
  echo "KEYCHAIN: $KEYCHAIN"
  echo
  usage
  exit 1
fi

# Assert version is not empty and starts with v
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

XCODE_PROVISIONING_PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
ALT_PROVISIONING_PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$XCODE_PROVISIONING_PROFILES_DIR"
mkdir -p "$ALT_PROVISIONING_PROFILES_DIR"

get_uuid() {
  strings "$1" | grep -E -o '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'
}

# Extract the ID of each provisioning profile
APP_PROVISIONING_PROFILE_ID=$(get_uuid "$APP_PROF_PATH")
EXT_PROVISIONING_PROFILE_ID=$(get_uuid "$EXT_PROF_PATH")
PTP_SUFFIX="-systemextension"

# Install Provisioning Profiles
cp "$APP_PROF_PATH" "${XCODE_PROVISIONING_PROFILES_DIR}/${APP_PROVISIONING_PROFILE_ID}.provisionprofile"
cp "$APP_PROF_PATH" "${ALT_PROVISIONING_PROFILES_DIR}/${APP_PROVISIONING_PROFILE_ID}.provisionprofile"
cp "$EXT_PROF_PATH" "${XCODE_PROVISIONING_PROFILES_DIR}/${EXT_PROVISIONING_PROFILE_ID}.provisionprofile"
cp "$EXT_PROF_PATH" "${ALT_PROVISIONING_PROFILES_DIR}/${EXT_PROVISIONING_PROFILE_ID}.provisionprofile"

export APP_PROVISIONING_PROFILE_ID
export EXT_PROVISIONING_PROFILE_ID
export PTP_SUFFIX

make clean/project clean/build

make

mkdir -p "$out"
mkdir build

# Archive the app
ARCHIVE_PATH="./build/Coder Desktop.xcarchive"
mkdir -p build

xcodebuild \
  -project "Coder Desktop/Coder Desktop.xcodeproj" \
  -scheme "Coder Desktop" \
  -configuration "Release" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  OTHER_CODE_SIGN_FLAGS='--timestamp' | LC_ALL="en_US.UTF-8" xcpretty

# Create exportOptions.plist
EXPORT_OPTIONS_PATH="./build/exportOptions.plist"
cat >"$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.coder.Coder-Desktop</key>
        <string>${APP_PROVISIONING_PROFILE_ID}</string>
        <key>com.coder.Coder-Desktop.VPN</key>
        <string>${EXT_PROVISIONING_PROFILE_ID}</string>
    </dict>
</dict>
</plist>
EOF

# Export the archive
EXPORT_PATH="./build/export"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
  -exportPath "$EXPORT_PATH"

BUILT_APP_PATH="$EXPORT_PATH/Coder Desktop.app"
PKG_PATH="$out/CoderDesktop.pkg"
DSYM_ZIPPED_PATH="$out/coder-desktop-dsyms.zip"
APP_ZIPPED_PATH="$out/coder-desktop-universal.zip"

pkgbuild --component "$BUILT_APP_PATH" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "com.coder.Coder-Desktop" \
  --version "$VERSION" \
  --install-location "/Applications/" \
  --timestamp \
  --sign "$CODE_SIGN_INSTALLER_IDENTITY" \
  "$PKG_PATH"

# Notarize
xcrun notarytool store-credentials "notarytool-credentials" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --keychain "$KEYCHAIN"

xcrun notarytool submit "$PKG_PATH" \
  --keychain-profile "notarytool-credentials" \
  --keychain "$KEYCHAIN" \
  --wait

# Staple the notarization to the app and pkg, so they work without internet
xcrun stapler staple "$PKG_PATH"
xcrun stapler staple "$BUILT_APP_PATH"

# Add dsym to build artifacts
(cd "$ARCHIVE_PATH/dSYMs" && zip -9 -r --symlinks "$DSYM_ZIPPED_PATH" ./*)

# Add zipped app to build artifacts
zip -9 -r --symlinks "$APP_ZIPPED_PATH" "$BUILT_APP_PATH"
