#!/usr/bin/env bash
# Notarizes a signed installer with Apple and staples the ticket to it, using
# rcodesign so it can run on Linux next to ./scripts/sign.sh.
#
# Usage: ./scripts/notarize.sh path/to/Coder-Desktop.pkg
#
# Requires the App Store Connect API key in:
#  - $AC_APIKEY_ISSUER_ID: the key's issuer UUID
#  - $AC_APIKEY_ID: the key ID
#  - $AC_APIKEY_FILE: the path to the key's .p8 file
set -euo pipefail

[[ $# -eq 1 ]] || {
  echo "Usage: $0 path/to/Coder-Desktop.pkg" >&2
  exit 1
}
: "${AC_APIKEY_ISSUER_ID:?}" "${AC_APIKEY_ID:?}" "${AC_APIKEY_FILE:?}"

key_file="$(mktemp)"
chmod 600 "$key_file"
trap 'rm -f "$key_file"' EXIT
rcodesign encode-app-store-connect-api-key \
  "$AC_APIKEY_ISSUER_ID" \
  "$AC_APIKEY_ID" \
  "$AC_APIKEY_FILE" \
  >"$key_file"

# Apple's notary service fails intermittently, so try twice.
attempts=2
for i in $(seq 1 "$attempts"); do
  rc=0
  rcodesign notary-submit \
    --api-key-file "$key_file" \
    --wait \
    --staple \
    "$1" && break || rc=$?
  echo "rcodesign notary-submit exited with $rc" >&2
  if [[ $i -lt $attempts ]]; then
    echo "Retrying in 30 seconds" >&2
    sleep 30
  fi
done
exit "$rc"
