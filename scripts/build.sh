#!/usr/bin/env bash
set -euo pipefail

# Add standard Nix environment variables
out="${out:-release}"

# Build Documentation @ https://developer.apple.com/forums/thread/737894
APPLE_TEAM_ID="4399GN35BJ"
CODE_SIGN_IDENTITY="Developer ID Application: Coder Technologies Inc (${APPLE_TEAM_ID})"

# Default values pulled in from env
APP_PROF_PATH=${APP_PROF_PATH:-""}
EXT_PROF_PATH=${EXT_PROF_PATH:-""}
KEYCHAIN=${KEYCHAIN:-""}

# Function to display usage
usage() {
  echo "Usage: $0 [--app-prof-path <path>] [--ext-prof-path <path>] [--keychain <path>]"
  echo "  --app-prof-path <path>  Set the APP_PROF_PATH variable"
  echo "  --ext-prof-path <path>  Set the EXT_PROF_PATH variable"
  echo "  --keychain      <path>  Set the KEYCHAIN variable"
  echo "  -h, --help              Display this help message"
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

xcodebuild \
  -project "Coder Desktop/Coder Desktop.xcodeproj" \
  -scheme "Coder Desktop" \
  -configuration "Release" \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  OTHER_CODE_SIGN_FLAGS='--timestamp' | LC_ALL="en_US.UTF-8" xcpretty

BUILT_APP_PATH="./build/Coder Desktop.app"
DMG_PATH="$out/Coder Desktop.dmg"
DSYM_ZIPPED_PATH="$out/coder-desktop-universal-dsym.zip"
APP_ZIPPED_PATH="$out/coder-desktop-universal.zip"

mkdir -p "$out"
mkdir build

ditto "$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "Coder Desktop.app")" "$BUILT_APP_PATH"

create-dmg \
  --identity="$CODE_SIGN_IDENTITY" \
  "$BUILT_APP_PATH" \
  "$(dirname "$BUILT_APP_PATH")"

mv "$(dirname "$BUILT_APP_PATH")"/Coder\ Desktop*.dmg "$DMG_PATH"

# Notarize
xcrun notarytool store-credentials "notarytool-credentials" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --keychain "$KEYCHAIN"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "notarytool-credentials" \
  --keychain "$KEYCHAIN" \
  --wait

# Staple the notarization to the app and dmg, so they work without internet
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$BUILT_APP_PATH"

# Add dsym to build artifacts
zip -9 -r --symlinks "$DSYM_ZIPPED_PATH" "$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "Coder Desktop.app.dSYM")"

# Add zipped app to build artifacts
zip -9 -r --symlinks "$APP_ZIPPED_PATH" "$BUILT_APP_PATH"
