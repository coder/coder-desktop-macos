#!/usr/bin/env bash
# Packages a signed Coder Desktop.app into an unsigned installer. The installer
# is signed afterwards by ./scripts/sign.sh, which runs on Linux because the
# Developer ID keys live in Google Cloud KMS.
#
# Usage: ./scripts/package.sh --app "path/to/Coder Desktop.app" --version <version> --output path/to/Coder-Desktop.pkg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_SCRIPTS="$SCRIPT_DIR/../pkgbuild/scripts/"

APP_PATH=""
VERSION=""
OUTPUT=""

usage() {
  echo "Usage: $0 --app <path> --version <version> --output <path>"
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
  --app)
    APP_PATH="$2"
    shift 2
    ;;
  --version)
    VERSION="$2"
    shift 2
    ;;
  --output)
    OUTPUT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown parameter passed: $1"
    usage
    exit 1
    ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$VERSION" || -z "$OUTPUT" ]]; then
  usage
  exit 1
fi

pkgbuild --component "$APP_PATH" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "com.coder.Coder-Desktop" \
  --version "$VERSION" \
  --install-location "/Applications/" \
  "$OUTPUT"
