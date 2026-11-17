#!/usr/bin/env bash
set -euo pipefail

# Signs an unsigned "Coder Desktop.app" (see scripts/build.sh) on Linux with
# rcodesign, reproducing what Xcode's Developer ID export used to do. Each
# step was worked out by comparing against the signatures in the v0.8.5 app,
# the last release Xcode signed.
#
# Usage: sign-app.sh "path/to/Coder Desktop.app"
#
# Environment:
#   APP_PROF_PATH, EXT_PROF_PATH  Developer ID provisioning profiles for the
#                                 app and the system extension. They must be
#                                 bound to the signing certificate.
#   RCODESIGN                     rcodesign binary. Default: rcodesign.
#
# The signing key is the Developer ID Application key in Google Cloud KMS,
# reached through the Cloud KMS PKCS#11 library. This needs Google
# credentials that may sign with it.
#   AC_PKCS11_LIBRARY             Path to libkmsp11.so.
#   KMS_PKCS11_CONFIG             The library's configuration, naming the
#                                 key ring.
#   AC_PKCS11_KEY_LABEL           Name of the key in the key ring.
#   AC_CERTIFICATE_FILE           The certificate Apple issued for that key,
#                                 as PEM.
#
# For experiments with a throwaway certificate, instead of AC_PKCS11_LIBRARY:
#   AC_P12_FILE, AC_P12_PASSWORD_FILE
#   AC_TEAM_NAME                  Team ID to record. Only needed when Apple
#                                 did not issue the certificate.

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 \"path/to/Coder Desktop.app\""
  exit 1
fi

APP="$1"
RCODESIGN="${RCODESIGN:-rcodesign}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="$SCRIPT_DIR/entitlements"

SYSEXT="Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension"
SPARKLE="Contents/Frameworks/Sparkle.framework/Versions/B"

: "${APP_PROF_PATH:?APP_PROF_PATH must be set}"
: "${EXT_PROF_PATH:?EXT_PROF_PATH must be set}"

key_args=()
if [[ -n "${AC_PKCS11_LIBRARY:-}" ]]; then
  : "${KMS_PKCS11_CONFIG:?KMS_PKCS11_CONFIG must be set}"
  : "${AC_PKCS11_KEY_LABEL:?AC_PKCS11_KEY_LABEL must be set}"
  : "${AC_CERTIFICATE_FILE:?AC_CERTIFICATE_FILE must be set}"
  key_args+=(
    --pkcs11-library "$AC_PKCS11_LIBRARY"
    --pkcs11-key-label "$AC_PKCS11_KEY_LABEL"
    --pkcs11-certificate-file "$AC_CERTIFICATE_FILE"
  )
else
  : "${AC_P12_FILE:?set AC_PKCS11_LIBRARY or AC_P12_FILE}"
  : "${AC_P12_PASSWORD_FILE:?AC_P12_PASSWORD_FILE must be set}"
  key_args+=(--p12-file "$AC_P12_FILE" --p12-password-file "$AC_P12_PASSWORD_FILE")
fi
if [[ -n "${AC_TEAM_NAME:-}" ]]; then
  key_args+=(--team-name "$AC_TEAM_NAME")
fi

# Xcode embeds the profiles while it signs. They are sealed as resources of
# their bundle, so they have to be in place before anything is signed.
cp "$APP_PROF_PATH" "$APP/Contents/embedded.provisionprofile"
cp "$EXT_PROF_PATH" "$APP/$SYSEXT/Contents/embedded.provisionprofile"

# The agents archive holds two more macOS programs, which mutagen copies to
# the machine at the other end of a file sync. Signing a bundle does not look
# inside an archive, but Apple's notary service does, so sign them here. The
# archive is a sealed resource of the app, so this has to happen before the
# app is signed.
AGENTS="$APP/Contents/Resources/mutagen-agents.tar.gz"
agents_dir="$(mktemp -d)"
trap 'rm -rf "$agents_dir"' EXIT
agents=(darwin_amd64 darwin_arm64)
# The archive comes from the unsigned, credentialless build, so its contents
# are not trusted. The member names are reused below, first as paths under
# $agents_dir and then as tar -c operands, where an absolute or parent path
# would read a host file (a signing key, say) into the published archive.
# Accept only the exact two regular-file members the build is known to
# produce; reject absolute, parent, link, duplicate, or extra entries.
mapfile -t members < <(tar -tzf "$AGENTS")
if [[ "$(printf '%s\n' "${members[@]}" | LC_ALL=C sort)" != "$(printf '%s\n' "${agents[@]}" | LC_ALL=C sort)" ]]; then
  echo "ERROR: unexpected members in mutagen-agents.tar.gz: ${members[*]}"
  exit 1
fi
while IFS= read -r entry; do
  if [[ "$entry" != -* ]]; then
    echo "ERROR: non-regular member in mutagen-agents.tar.gz: $entry"
    exit 1
  fi
done < <(tar -tvzf "$AGENTS")
tar -xpzf "$AGENTS" -C "$agents_dir"
for agent in "${agents[@]}"; do
  # Identified by its name in the archive, which is what it was called
  # before. Nothing is kept from the signature it arrived with.
  "$RCODESIGN" sign "${key_args[@]}" \
    --binary-identifier "$agent" \
    --code-signature-flags runtime \
    "$agents_dir/$agent" 1>&2
done
# Same members, in the same order. "--" keeps a member name from being read as an option.
tar -czf "$AGENTS" -C "$agents_dir" -- "${members[@]}"

args=()

# Code built by Xcode arrives with only a linker signature, which carries no
# hardened runtime flag. Notarization requires the flag. Sparkle's code
# arrives signed with it and keeps it. The mutagen programs are listed so
# that nothing depends on how, or whether, they arrive signed.
runtime=(
  "Contents/MacOS/Coder Desktop"
  "Contents/MacOS/com.coder.Coder-Desktop.Helper"
  "$SYSEXT/Contents/MacOS/com.coder.Coder-Desktop.VPN"
  "$SYSEXT/Contents/Frameworks/VPNLib.framework/Versions/A/VPNLib"
  "$SYSEXT/Contents/Frameworks/CoderSDK.framework/Versions/A/CoderSDK"
  "Contents/Resources/mutagen-darwin-amd64"
  "Contents/Resources/mutagen-darwin-arm64"
)
for path in "${runtime[@]}"; do
  args+=(--code-signature-flags "$path:runtime")
done

# rcodesign names a Mach-O that is not the main executable of a bundle after
# its file name. Xcode keeps the identifier the file arrived with.
keep_identifier=(
  "$SPARKLE/Autoupdate"
  "Contents/Frameworks/libswiftCompatibilitySpan.dylib"
)
for path in "${keep_identifier[@]}"; do
  identifier="$("$RCODESIGN" print-signature-info "$APP/$path" | awk '$1 == "identifier:" { print $2; exit }')"
  if [[ -z "$identifier" ]]; then
    echo "ERROR: $path has no existing signature to take an identifier from"
    exit 1
  fi
  args+=(--binary-identifier "$path:$identifier")
done
# The mutagen programs have always been identified this way, after the names
# of the files mutagen's own build signs.
args+=(
  --binary-identifier "Contents/Resources/mutagen-darwin-amd64:darwin_amd64"
  --binary-identifier "Contents/Resources/mutagen-darwin-arm64:darwin_arm64"
)

# Xcode derives the signed entitlements from the target's entitlements file
# and the provisioning profile: it expands the team prefix, adds the
# application and team identifiers, and drops what the profile does not
# allow. These files are the result, taken from the shipped app.
args+=(
  --entitlements-xml-file "Contents/MacOS/Coder Desktop:$ENTITLEMENTS/app.plist"
  --entitlements-xml-file "Contents/MacOS/com.coder.Coder-Desktop.Helper:$ENTITLEMENTS/helper.plist"
  --entitlements-xml-file "$SYSEXT/Contents/MacOS/com.coder.Coder-Desktop.VPN:$ENTITLEMENTS/vpn.plist"
  # Xcode gives the prebuilt mutagen binaries an empty entitlements
  # dictionary. Having none means the same, but match it anyway.
  --entitlements-xml-file "Contents/Resources/mutagen-darwin-amd64:$ENTITLEMENTS/empty.plist"
  --entitlements-xml-file "Contents/Resources/mutagen-darwin-arm64:$ENTITLEMENTS/empty.plist"
)

"$RCODESIGN" sign "${key_args[@]}" "${args[@]}" "$APP" 1>&2
