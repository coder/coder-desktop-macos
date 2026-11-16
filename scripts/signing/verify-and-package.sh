#!/usr/bin/env bash
set -uo pipefail

# Runs on macOS against an app that was signed and notarized on Linux by
# sign-app.sh. This is where Apple's own tools judge the signature, so every
# check runs even if an earlier one fails, and the results are written to a
# report. It then builds the installer package.
#
# The installer comes out unsigned. sign-installer.sh signs it, back on
# Linux, with the Developer ID Installer key.
#
# Usage: verify-and-package.sh "path/to/Coder Desktop.app" output-directory
#
# Outputs, in the output directory:
#   verification.txt    What each check printed.
#   Coder-Desktop.pkg   The unsigned installer.

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 \"path/to/Coder Desktop.app\" output-directory"
  exit 1
fi

APP="$1"
OUT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSEXT="$APP/Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension"
REPORT="$OUT/verification.txt"
mkdir -p "$OUT"
: >"$REPORT"

failed=0
check() {
  local name="$1"
  shift
  {
    echo "## $name"
    echo "\$ $*"
  } >>"$REPORT"
  if "$@" >>"$REPORT" 2>&1; then
    echo "PASS  $name" | tee -a "$REPORT"
  else
    echo "FAIL  $name" | tee -a "$REPORT"
    failed=1
  fi
  echo >>"$REPORT"
}

# The seal and every nested signature, with the strictest rules. At this
# verbosity codesign also reports whether the designated requirement holds.
check "codesign verify, deep and strict" codesign --verify --deep --strict --verbose=2 "$APP"
check "codesign verify, system extension" codesign --verify --deep --strict --verbose=2 "$SYSEXT"
# What the app itself demands of its helper and extension over XPC. The
# option takes "=" followed by the requirement text, so -R="text" is right
# and a second "=" is a syntax error.
XPC_REQUIREMENT='anchor apple generic and certificate leaf[subject.OU] = "4399GN35BJ"'
check "XPC peer requirement, helper" codesign --verify --verbose=2 \
  -R="$XPC_REQUIREMENT" "$APP/Contents/MacOS/com.coder.Coder-Desktop.Helper"
check "XPC peer requirement, system extension" codesign --verify --verbose=2 \
  -R="$XPC_REQUIREMENT" "$SYSEXT"
# Apple's own test for a notarization ticket.
check "notarized requirement" codesign --verify --verbose=2 -R="notarized" "$APP"
check "stapled notarization ticket" xcrun stapler validate "$APP"
# Gatekeeper. CI runners have assessment switched off, which spctl reports as
# "override=security disabled", so its exit status alone is not evidence. The
# line that means something is the source it found.
gatekeeper() {
  local out
  out="$(spctl --assess --type execute -vvv "$APP" 2>&1)" || true
  echo "$out"
  grep -q "^source=Notarized Developer ID$" <<<"$out"
}
check "Gatekeeper source is Notarized Developer ID" gatekeeper

# The macOS agents inside the agents archive. The checks above do not reach
# into an archive, so check these on their own.
agents_dir="$(mktemp -d)"
tar -xzf "$APP/Contents/Resources/mutagen-agents.tar.gz" -C "$agents_dir" darwin_amd64 darwin_arm64
for agent in darwin_amd64 darwin_arm64; do
  check "agent $agent, signature and team" codesign --verify --strict --verbose=2 \
    -R="$XPC_REQUIREMENT" "$agents_dir/$agent"
done
{
  for agent in darwin_amd64 darwin_arm64; do
    echo "## signature details, agent $agent"
    codesign -dvv "$agents_dir/$agent" 2>&1
    echo
  done
} >>"$REPORT"

# Not a verdict: this tool's behaviour on CI runners is unverified, so its
# output is recorded without affecting the result.
{
  echo "## syspolicy_check distribution (informational)"
  if command -v syspolicy_check >/dev/null 2>&1; then
    syspolicy_check distribution "$APP" 2>&1 || true
  else
    echo "syspolicy_check is not available on this runner"
  fi
  echo
} >>"$REPORT"

{
  echo "## signature details, app"
  codesign -dvvv --entitlements - "$APP" 2>&1
  echo
  echo "## signature details, system extension"
  codesign -dvvv --entitlements - "$SYSEXT" 2>&1
  echo
  echo "## embedded profiles"
  for profile in "$APP/Contents/embedded.provisionprofile" "$SYSEXT/Contents/embedded.provisionprofile"; do
    security cms -D -i "$profile" 2>/dev/null | plutil -extract Name raw - 2>&1
  done
} >>"$REPORT"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
if pkgbuild --component "$APP" \
  --scripts "$SCRIPT_DIR/../../pkgbuild/scripts/" \
  --identifier "com.coder.Coder-Desktop" \
  --version "$VERSION" \
  --install-location "/Applications/" \
  "$OUT/Coder-Desktop.pkg" >>"$REPORT" 2>&1; then
  echo "PASS  installer built" | tee -a "$REPORT"
else
  echo "FAIL  installer built" | tee -a "$REPORT"
  failed=1
fi

exit "$failed"
