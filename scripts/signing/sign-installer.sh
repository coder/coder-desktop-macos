#!/usr/bin/env bash
set -euo pipefail

# Signs an installer package on Linux with rcodesign. An installer needs a
# Developer ID Installer certificate, which is a different certificate and
# key from the one that signs the app inside it.
#
# rcodesign signs with SHA-256 where Apple's tools use SHA-1. macOS validates
# the result: checked on macOS 26 with pkgutil, including against copies with
# a corrupted signature.
#
# Usage: sign-installer.sh unsigned.pkg signed.pkg
#
# Environment:
#   RCODESIGN                     rcodesign binary. Default: rcodesign.
#
# The signing key is the Developer ID Installer key in Google Cloud KMS,
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

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 unsigned.pkg signed.pkg"
  exit 1
fi

UNSIGNED="$1"
SIGNED="$2"
RCODESIGN="${RCODESIGN:-rcodesign}"

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

"$RCODESIGN" sign "${key_args[@]}" "$UNSIGNED" "$SIGNED" 1>&2
