#!/usr/bin/env bash
set -uo pipefail

# Runs on macOS against an installer that was signed and notarized on Linux
# by sign-installer.sh. Every check runs even if an earlier one fails.
# Nothing is installed.
#
# Usage: verify-installer.sh Coder-Desktop.pkg

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 Coder-Desktop.pkg"
  exit 1
fi

PKG="$1"
failed=0
check() {
  local name="$1"
  shift
  echo "## $name"
  if "$@"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    failed=1
  fi
  echo
}

# Exit status 0 means signed by a certificate macOS trusts.
check "installer signature" pkgutil --check-signature "$PKG"
check "stapled notarization ticket" xcrun stapler validate "$PKG"
# CI runners have Gatekeeper's assessment switched off, which spctl reports as
# "override=security disabled", so its exit status alone is not evidence. The
# line that means something is the source it found.
gatekeeper() {
  local out
  out="$(spctl --assess --type install -vvv "$PKG" 2>&1)" || true
  echo "$out"
  grep -q "^source=Notarized Developer ID$" <<<"$out"
}
check "Gatekeeper source is Notarized Developer ID" gatekeeper
# Reads the archive and its checksums.
expand() {
  local dir
  dir="$(mktemp -d)"
  pkgutil --expand "$PKG" "$dir/expanded" && ls "$dir/expanded"
}
check "archive expands" expand

exit "$failed"
