#!/usr/bin/env bash
set -euo pipefail

# Builds a release of Coder Desktop with code signing disabled.
#
# The Developer ID keys live in Google Cloud KMS, which Xcode cannot use, so
# the app is signed afterwards, on Linux, by scripts/signing/sign-app.sh. See
# RELEASING.md. Nothing here touches a certificate, a keychain or a secret.
#
# Usage: build.sh [output-directory]
#
# Outputs, in the output directory (default: build/release):
#   coder-desktop-unsigned.tar  The unsigned app. A tarball, because artifact
#                               uploads drop the symlinks frameworks rely on.
#   coder-desktop-dsyms.zip     Debug symbols.

OUT="${1:-build/release}"
TEAM_ID="4399GN35BJ"

# Selects the system extension flavour of the packet tunnel entitlement.
export PTP_SUFFIX="-systemextension"
# Provisioning profiles are embedded when the app is signed.
export APP_PROVISIONING_PROFILE_ID=""
export EXT_PROVISIONING_PROFILE_ID=""

make clean/project clean/build
make

# The app is signed with the entitlements in scripts/signing/entitlements,
# not with the ones in project.yml. Xcode used to derive one from the other
# when it signed. Stop here, before compiling, if a change to project.yml has
# not been copied over.
#
# Usage: check_entitlements GENERATED SIGNED BUNDLE_ID
check_entitlements() {
  local generated="$1" signed="$2" bundle_id="$3" expected
  expected="$(mktemp)"
  # What Xcode's Developer ID export does to a target's entitlements: it
  # expands the team prefix, adds the application and team identifiers, and
  # drops aps-environment, which the provisioning profile does not grant.
  sed "s/[$](TeamIdentifierPrefix)/${TEAM_ID}./g" "$generated" >"$expected"
  /usr/libexec/PlistBuddy -c "Delete :aps-environment" "$expected" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string ${TEAM_ID}.${bundle_id}" \
    -c "Add :com.apple.developer.team-identifier string ${TEAM_ID}" \
    "$expected"
  # Both in the same canonical form, so that only the content is compared.
  if ! diff <(plutil -convert xml1 -o - "$expected") <(plutil -convert xml1 -o - "$signed"); then
    echo "ERROR: $signed is out of date."
    echo "The entitlements for $bundle_id in Coder-Desktop/project.yml have changed."
    echo "Lines marked < are what the project now produces. Update $signed to"
    echo "match, and check that the provisioning profile grants them. See RELEASING.md."
    exit 1
  fi
  rm -f "$expected"
  echo "OK: $signed matches the project's entitlements for $bundle_id"
}
check_entitlements \
  Coder-Desktop/Coder-Desktop/Coder-Desktop.entitlements \
  scripts/signing/entitlements/app.plist \
  com.coder.Coder-Desktop
check_entitlements \
  Coder-Desktop/VPN/VPN.entitlements \
  scripts/signing/entitlements/vpn.plist \
  com.coder.Coder-Desktop.VPN

ARCHIVE_PATH="./build/Coder-Desktop.xcarchive"
mkdir -p build "$OUT"

# Xcode takes $(TeamIdentifierPrefix) from the signing identity, so with
# signing disabled it has to be passed in. The Info.plists build the system
# extension's Mach service name from it.
xcodebuild \
  -project "Coder-Desktop/Coder-Desktop.xcodeproj" \
  -scheme "Coder Desktop" \
  -configuration "Release" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  TeamIdentifierPrefix="${TEAM_ID}." \
  AppIdentifierPrefix="${TEAM_ID}." | xcbeautify

APP_PATH="$(find "$ARCHIVE_PATH/Products" -maxdepth 4 -name "Coder Desktop.app" -type d | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: could not find the app in $ARCHIVE_PATH/Products"
  find "$ARCHIVE_PATH/Products" -maxdepth 4
  exit 1
fi

# macOS refuses to activate a system extension whose Mach service name does
# not start with the team prefix, and neither signing nor notarization
# notices. Make sure the prefix arrived.
for plist in \
  "$APP_PATH/Contents/Info.plist" \
  "$APP_PATH/Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension/Contents/Info.plist"; do
  name="$(/usr/libexec/PlistBuddy -c "Print :NetworkExtension:NEMachServiceName" "$plist")"
  if [[ "$name" != "${TEAM_ID}."* ]]; then
    echo "ERROR: NEMachServiceName in $plist is '$name', without the team prefix."
    echo "The TeamIdentifierPrefix build setting did not take effect."
    exit 1
  fi
done

tar -C "$(dirname "$APP_PATH")" -cf "$OUT/coder-desktop-unsigned.tar" "Coder Desktop.app"

DSYMS="$(cd "$OUT" && pwd)/coder-desktop-dsyms.zip"
rm -f "$DSYMS"
(cd "$ARCHIVE_PATH/dSYMs" && zip -9 -r --symlinks "$DSYMS" ./*)

ls -la "$OUT"
