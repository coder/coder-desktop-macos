#!/usr/bin/env bash
set -euo pipefail

# Signs an installer for Sparkle, the app's updater, on Linux with OpenSSL.
# Sparkle only accepts an update whose Ed25519 signature verifies against the
# SUPublicEDKey built into the app.
#
# Sparkle's own sign_update only runs on macOS. Its signature is a plain
# Ed25519 signature over the file, so OpenSSL produces the same bytes. The
# signature covers the file as it is after notarization: sign last.
#
# Usage: sign-sparkle.sh installer.pkg installer.pkg.sig
#
# The output is the line sign_update prints, which scripts/update-appcast
# reads: sparkle:edSignature="..." length="..."
#
# Environment:
#   SPARKLE_PRIVATE_KEY   The key as Sparkle's generate_keys -x exports it:
#                         base64 of the 32-byte Ed25519 seed.
#   SPARKLE_INFO_PLIST    Info.plist holding SUPublicEDKey. Default: the
#                         app's, in this repository.
#   OPENSSL               openssl binary, 3.0 or later. Default: openssl.

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 installer.pkg installer.pkg.sig"
  exit 1
fi

PKG="$1"
SIG="$2"
OPENSSL="${OPENSSL:-openssl}"
INFO_PLIST="${SPARKLE_INFO_PLIST:-$(dirname "$0")/../../Coder-Desktop/Coder-Desktop/Info.plist}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY must be set}"

# mktemp -d makes the directory readable by its owner only.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Whitespace is dropped first: base64 rejects the stray line break or space
# that a pasted value often carries.
if ! tr -d '[:space:]' <<<"$SPARKLE_PRIVATE_KEY" | base64 -d >"$work/seed"; then
  echo "SPARKLE_PRIVATE_KEY is not valid base64." >&2
  exit 1
fi
size="$(wc -c <"$work/seed" | tr -d ' ')"
if [[ "$size" -eq 96 ]]; then
  # Older keys hold a hashed seed that only Sparkle's own Ed25519 code can
  # sign with.
  echo "SPARKLE_PRIVATE_KEY is in Sparkle's old 96-byte format, which only sign_update on macOS can use." >&2
  exit 1
elif [[ "$size" -ne 32 ]]; then
  echo "SPARKLE_PRIVATE_KEY decodes to $size bytes. It must be the base64 of a 32-byte Ed25519 seed." >&2
  exit 1
fi

# OpenSSL reads a private key as PKCS#8: for Ed25519, a fixed 16-byte header
# and then the seed (RFC 8410).
{
  printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'
  cat "$work/seed"
} >"$work/key.der"
"$OPENSSL" pkey -inform DER -in "$work/key.der" -pubout -out "$work/pub.pem"

# The public key is the last 32 bytes of its DER form. A key that does not
# match the app's would publish an update that no installed app accepts.
public_key="$("$OPENSSL" pkey -pubin -in "$work/pub.pem" -outform DER | tail -c 32 | base64)"
expected_key="$(sed -n '/<key>SUPublicEDKey<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$INFO_PLIST")"
if [[ -z "$expected_key" ]]; then
  echo "No SUPublicEDKey in $INFO_PLIST." >&2
  exit 1
fi
if [[ "$public_key" != "$expected_key" ]]; then
  echo "SPARKLE_PRIVATE_KEY belongs to public key $public_key, but the app expects $expected_key (SUPublicEDKey)." >&2
  exit 1
fi

"$OPENSSL" pkeyutl -sign -rawin -inkey "$work/key.der" -keyform DER \
  -in "$PKG" -out "$work/sig"
"$OPENSSL" pkeyutl -verify -rawin -pubin -inkey "$work/pub.pem" \
  -in "$PKG" -sigfile "$work/sig" 1>&2

printf 'sparkle:edSignature="%s" length="%s"\n' \
  "$(base64 <"$work/sig" | tr -d '\n')" \
  "$(wc -c <"$PKG" | tr -d ' ')" >"$SIG"
