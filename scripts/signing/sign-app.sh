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
#
# The Windows programs in the agents archive are signed with jsign.
#   JSIGN_PATH                    Path to the jsign jar.
#   JAVA                          java binary. Default: java.
#
# With AC_PKCS11_LIBRARY, their key is the Authenticode key in Google Cloud
# KMS.
#   EV_KEYSTORE                   Resource name of the key ring.
#   EV_KEY                        Name of the key in the key ring.
#   EV_CERTIFICATE_PATH           The certificate chain for that key, as PEM.
#   EV_TSA_URL                    URL of the timestamp server.
#   GCLOUD_ACCESS_TOKEN           Google access token for the key.
#
# With AC_P12_FILE, their key is the one in that file and the signatures carry
# no timestamp. JSIGN_PATH is optional: without it the Windows programs are
# left as they are.

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 \"path/to/Coder Desktop.app\""
  exit 1
fi

APP="$1"
RCODESIGN="${RCODESIGN:-rcodesign}"
JAVA="${JAVA:-java}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="$SCRIPT_DIR/entitlements"

SYSEXT="Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension"
SPARKLE="Contents/Frameworks/Sparkle.framework/Versions/B"

: "${APP_PROF_PATH:?APP_PROF_PATH must be set}"
: "${EXT_PROF_PATH:?EXT_PROF_PATH must be set}"

key_args=()
jsign_args=()
if [[ -n "${AC_PKCS11_LIBRARY:-}" ]]; then
  : "${KMS_PKCS11_CONFIG:?KMS_PKCS11_CONFIG must be set}"
  : "${AC_PKCS11_KEY_LABEL:?AC_PKCS11_KEY_LABEL must be set}"
  : "${AC_CERTIFICATE_FILE:?AC_CERTIFICATE_FILE must be set}"
  key_args+=(
    --pkcs11-library "$AC_PKCS11_LIBRARY"
    --pkcs11-key-label "$AC_PKCS11_KEY_LABEL"
    --pkcs11-certificate-file "$AC_CERTIFICATE_FILE"
  )
  : "${JSIGN_PATH:?JSIGN_PATH must be set}"
  : "${EV_KEYSTORE:?EV_KEYSTORE must be set}"
  : "${EV_KEY:?EV_KEY must be set}"
  : "${EV_CERTIFICATE_PATH:?EV_CERTIFICATE_PATH must be set}"
  : "${EV_TSA_URL:?EV_TSA_URL must be set}"
  : "${GCLOUD_ACCESS_TOKEN:?GCLOUD_ACCESS_TOKEN must be set}"
  jsign_args+=(
    --storetype GOOGLECLOUD
    --storepass "$GCLOUD_ACCESS_TOKEN"
    --keystore "$EV_KEYSTORE"
    --alias "$EV_KEY"
    --certfile "$EV_CERTIFICATE_PATH"
    --tsmode RFC3161
    --tsaurl "$EV_TSA_URL"
  )
else
  : "${AC_P12_FILE:?set AC_PKCS11_LIBRARY or AC_P12_FILE}"
  : "${AC_P12_PASSWORD_FILE:?AC_P12_PASSWORD_FILE must be set}"
  key_args+=(--p12-file "$AC_P12_FILE" --p12-password-file "$AC_P12_PASSWORD_FILE")
  if [[ -n "${JSIGN_PATH:-}" ]]; then
    jsign_args+=(
      --storetype PKCS12
      --keystore "$AC_P12_FILE"
      --storepass "$(head -n 1 "$AC_P12_PASSWORD_FILE")"
    )
  fi
fi
if [[ -n "${AC_TEAM_NAME:-}" ]]; then
  key_args+=(--team-name "$AC_TEAM_NAME")
fi

# Prints the size of the certificate table of a PE file, which holds its
# signatures.
pe_certificate_table_size() {
  local file="$1" header magic directories
  header="$(od -An -tu4 -j 60 -N 4 "$file")"
  magic="$(od -An -tu2 -j "$((header + 24))" -N 2 "$file")"
  case "$((magic))" in
    267) directories="$((header + 120))" ;; # PE32
    523) directories="$((header + 136))" ;; # PE32+
    *)
      echo "ERROR: $file is not a PE file" 1>&2
      return 1
      ;;
  esac
  od -An -tu4 -j "$((directories + 36))" -N 4 "$file"
}

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
# The archive holds one agent for every platform mutagen supports, so the
# platforms are not listed here. Every member must be a regular file with a
# plain <os>_<arch> name that appears once, which rejects absolute, parent,
# link and duplicate entries.
mapfile -t members < <(tar -tzf "$AGENTS")
for member in "${members[@]}"; do
  if [[ ! "$member" =~ ^[a-z0-9]+_[a-z0-9]+$ ]]; then
    echo "ERROR: unexpected member in mutagen-agents.tar.gz: $member"
    exit 1
  fi
done
if [[ -n "$(printf '%s\n' "${members[@]}" | LC_ALL=C sort | uniq -d)" ]]; then
  echo "ERROR: duplicate members in mutagen-agents.tar.gz: ${members[*]}"
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
  # Identified by its name in the archive.
  "$RCODESIGN" sign "${key_args[@]}" \
    --binary-identifier "$agent" \
    --code-signature-flags runtime \
    "$agents_dir/$agent" 1>&2
done
# The Windows programs in the archive. A signature a program already has is
# replaced.
windows_agents=(windows_amd64 windows_arm64)
if [[ "${#jsign_args[@]}" -gt 0 ]]; then
  for agent in "${windows_agents[@]}"; do
    "$JAVA" -jar "$JSIGN_PATH" "${jsign_args[@]}" --replace "$agents_dir/$agent" 1>&2
    size="$(pe_certificate_table_size "$agents_dir/$agent")"
    if [[ "$size" -eq 0 ]]; then
      echo "ERROR: $agent has no signature after signing"
      exit 1
    fi
  done
else
  echo "JSIGN_PATH is not set: the Windows programs in the agents archive are left as they are" 1>&2
fi
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
# The identifiers of the mutagen programs.
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
