#!/usr/bin/env bash
# Signs a Coder Desktop release with rcodesign. CI runs this on Linux: the
# Developer ID Application private key lives in Google Cloud KMS, which Apple's
# codesign can't use.
#
# Usage:
#   ./scripts/sign.sh app "path/to/Coder Desktop.app"
#   ./scripts/sign.sh pkg path/to/Coder-Desktop.pkg
#
# `app` signs, in place, an app built by ./scripts/build.sh (unsigned, with its
# provisioning profiles embedded) with the Developer ID Application
# certificate. Coder's own executables get the hardened runtime and the
# entitlements in signing/entitlements. Prebuilt executables (Sparkle, mutagen,
# the Swift runtime) keep the identifier, flags and entitlements they were
# built with. The key comes from one of:
#  - Google Cloud KMS, through the Cloud KMS PKCS#11 library: set
#    $PKCS11_LIBRARY to libkmsp11.so (rcodesign must be built with the
#    "pkcs11" feature) and $KMS_PKCS11_CONFIG to the library's config naming
#    the apple-codesign key ring. Google credentials that can sign with the
#    developer-id-application key must be available, e.g. via
#    $GOOGLE_APPLICATION_CREDENTIALS. The certificate is
#    signing/developer-id-application.pem.
#  - A PKCS#12 file, to try signing with a throwaway certificate: set
#    $P12_FILE and $P12_PASSWORD_FILE.
#
# `pkg` signs, in place, an installer built by ./scripts/package.sh with the
# Developer ID Installer certificate and key in the PKCS#12 file
# $INSTALLER_P12_FILE, whose password is in $INSTALLER_P12_PASSWORD_FILE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || die "usage: $0 app|pkg PATH"
kind="$1"
target="$2"
command -v rcodesign >/dev/null || die "rcodesign is not installed"

# app_key_args prints the rcodesign arguments selecting the Developer ID
# Application key.
app_key_args() {
  if [[ -n "${PKCS11_LIBRARY:-}" ]]; then
    [[ -n "${KMS_PKCS11_CONFIG:-}" ]] || die "KMS_PKCS11_CONFIG must be set with PKCS11_LIBRARY"
    printf '%s\0' \
      --pkcs11-library "$PKCS11_LIBRARY" \
      --pkcs11-key-label developer-id-application \
      --pkcs11-certificate-file "$ROOT/signing/developer-id-application.pem"
  elif [[ -n "${P12_FILE:-}" ]]; then
    printf '%s\0' --p12-file "$P12_FILE" --p12-password-file "${P12_PASSWORD_FILE:?}"
  else
    die "set PKCS11_LIBRARY or P12_FILE"
  fi
}
# is_macho FILE succeeds if FILE is a Mach-O or universal binary.
is_macho() {
  case "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" in
  cafebabe | feedface | feedfacf | cefaedfe | cffaedfe) return 0 ;;
  *) return 1 ;;
  esac
}

sign_app() {
  local app="$1"
  local vpn="Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension"
  local helper="Contents/MacOS/com.coder.Coder-Desktop.Helper"
  local ent="$ROOT/signing/entitlements"

  [[ -f "$app/Contents/embedded.provisionprofile" ]] || die "$app has no provisioning profile"
  [[ -f "$app/$vpn/Contents/embedded.provisionprofile" ]] || die "$app/$vpn has no provisioning profile"

  local -a args
  mapfile -d '' args < <(app_key_args)

  # Coder's executables. A path scope applies to the bundle or binary at that
  # path; an unscoped setting applies to the app's main executable.
  args+=(
    --code-signature-flags runtime
    --entitlements-xml-file "$ent/app.plist"
    --code-signature-flags "$helper:runtime"
    --entitlements-xml-file "$helper:$ent/helper.plist"
    --code-signature-flags "$vpn:runtime"
    --entitlements-xml-file "$vpn:$ent/vpn.plist"
    --code-signature-flags "$vpn/Contents/Frameworks/VPNLib.framework/Versions/A:runtime"
    --code-signature-flags "$vpn/Contents/Frameworks/CoderSDK.framework/Versions/A:runtime"
  )

  # rcodesign names a bundle's main executable after its CFBundleIdentifier and
  # any other binary after its file name, which would rename prebuilt binaries
  # such as Sparkle's Autoupdate. Keep the identifier of every binary that was
  # already signed by something other than the linker; Xcode did the same.
  local file rel info id
  while IFS= read -r -d '' file; do
    is_macho "$file" || continue
    rel="${file#"$app"/}"
    info="$(rcodesign print-signature-info "$file" 2>/dev/null)" || continue
    grep -q 'LINKER_SIGNED' <<<"$info" && continue
    id="$(grep -m1 -E '^ +identifier: ' <<<"$info" | sed -E 's/^ +identifier: //')" || continue
    args+=(--binary-identifier "$rel:$id")
  done < <(find "$app" -type f -print0 | sort -z)

  rcodesign sign "${args[@]}" "$app"
}

sign_pkg() {
  local pkg="$1" dir
  : "${INSTALLER_P12_FILE:?}" "${INSTALLER_P12_PASSWORD_FILE:?}"
  command -v openssl >/dev/null || die "openssl is not installed"

  # rcodesign only reads PKCS#12 files in the legacy encryption (Keychain
  # Access exports); re-encode whatever we were given into that form.
  dir="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand $dir now
  trap "rm -rf '$dir'" RETURN
  (
    umask 077
    openssl pkcs12 -legacy -in "$INSTALLER_P12_FILE" -passin "file:$INSTALLER_P12_PASSWORD_FILE" -nodes -out "$dir/installer.pem"
    openssl pkcs12 -export -legacy -in "$dir/installer.pem" -out "$dir/installer.p12" -passout "file:$INSTALLER_P12_PASSWORD_FILE"
  )

  rcodesign sign \
    --p12-file "$dir/installer.p12" \
    --p12-password-file "$INSTALLER_P12_PASSWORD_FILE" \
    "$pkg"
}

case "$kind" in
app) sign_app "${target%/}" ;;
pkg) sign_pkg "$target" ;;
*) die "unknown kind $kind (expected app or pkg)" ;;
esac
