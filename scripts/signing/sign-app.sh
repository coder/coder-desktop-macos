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
TEAM_ID="4399GN35BJ"

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

# Neither a wrong profile nor a Mach service name without its team prefix is
# rejected here or by notarization. macOS rejects both when the system
# extension is activated, so check before signing.
"$SCRIPT_DIR/check-bundle.py" "$APP" "$ENTITLEMENTS"
"$SCRIPT_DIR/check-profile.py" "$APP_PROF_PATH" "$ENTITLEMENTS/app.plist" ${AC_CERTIFICATE_FILE:+"$AC_CERTIFICATE_FILE"}
"$SCRIPT_DIR/check-profile.py" "$EXT_PROF_PATH" "$ENTITLEMENTS/vpn.plist" ${AC_CERTIFICATE_FILE:+"$AC_CERTIFICATE_FILE"}

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
mapfile -t agents < <("$SCRIPT_DIR/archive-members.py" list "$AGENTS")
if [[ "${#agents[@]}" -eq 0 ]]; then
  echo "ERROR: found no macOS programs in $AGENTS"
  exit 1
fi
tar -xzf "$AGENTS" -C "$agents_dir" "${agents[@]}"
for agent in "${agents[@]}"; do
  # Identified by its name in the archive, which is what it was called
  # before. Nothing is kept from the signature it arrived with.
  "$RCODESIGN" sign "${key_args[@]}" \
    --binary-identifier "$agent" \
    --code-signature-flags runtime \
    "$agents_dir/$agent" 1>&2
done
"$SCRIPT_DIR/archive-members.py" replace "$AGENTS" "$agents_dir" "${agents[@]}"

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

# Report what was signed, and fail on the two mistakes that are easy to make
# when a binary is added to the app: a missing team, or a missing hardened
# runtime flag on code Xcode built.
echo "Signed code in $APP:"
failed=0
while IFS= read -r -d '' file; do
  info="$("$RCODESIGN" print-signature-info "$file" 2>/dev/null || true)"
  if [[ "$info" != *"code_directory:"* ]]; then
    continue
  fi
  rel="${file#"$APP"/}"
  identifier="$(awk '$1 == "identifier:" { print $2; exit }' <<<"$info")"
  flags="$(awk '$1 == "flags:" { print $2; exit }' <<<"$info")"
  slices="$(grep -c "^ *identifier:" <<<"$info")"
  teamed="$(grep -c "^ *team_name: $TEAM_ID\$" <<<"$info" || true)"
  # Count keys in the first slice's entitlements only. Other parts of the
  # output contain plists too.
  entitlements="$(awk '
    /^ *entitlements_plist:/ { inside = 1; next }
    inside && /^ *- / { if ($0 ~ /<key>/) n++; next }
    inside { exit }
    END { print n + 0 }' <<<"$info")"
  echo "  $rel: id=$identifier flags=$flags slices=$slices entitlements=$entitlements"
  if [[ "$slices" != "$teamed" ]]; then
    echo "ERROR: $rel: $teamed of $slices slices carry team $TEAM_ID"
    failed=1
  fi
  for path in "${runtime[@]}"; do
    if [[ "$rel" == "$path" && "$flags" != *RUNTIME* ]]; then
      echo "ERROR: $rel is missing the hardened runtime flag"
      failed=1
    fi
  done
done < <(find "$APP" -type f -print0)
for agent in "${agents[@]}"; do
  info="$("$RCODESIGN" print-signature-info "$agents_dir/$agent")"
  identifier="$(awk '$1 == "identifier:" { print $2; exit }' <<<"$info")"
  flags="$(awk '$1 == "flags:" { print $2; exit }' <<<"$info")"
  echo "  Contents/Resources/mutagen-agents.tar.gz/$agent: id=$identifier flags=$flags"
  if [[ "$flags" != *RUNTIME* || "$info" != *"team_name: $TEAM_ID"* ]]; then
    echo "ERROR: agent $agent is missing the hardened runtime flag or the team"
    failed=1
  fi
done

# Every program, including those inside archives, must carry the signing
# certificate and no other Developer ID Application certificate.
if [[ -n "${AC_CERTIFICATE_FILE:-}" ]]; then
  "$SCRIPT_DIR/check-signers.py" "$APP" "$AC_CERTIFICATE_FILE" || failed=1
fi
exit "$failed"
