#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--short] [--hash]"
    echo "  --short     Output a CFBundleShortVersionString compatible version (X.Y.Z)"
    echo "  --hash      Output only the commit hash"
    echo "  -h, --help  Display this help message"
    echo ""
    echo "With no flags, outputs: X.Y.Z[.N]"
}

SHORT=false
HASH_ONLY=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --short)
            SHORT=true
            shift
            ;;
        --hash)
            HASH_ONLY=true
            shift
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

if [[ "$HASH_ONLY" == true ]]; then
    current_hash=$(git rev-parse --short=7 HEAD)
    echo "$current_hash"
    exit 0
fi

describe_output=$(git describe --tags)

# Of the form `vX.Y.Z-N-gHASH`
if [[ $describe_output =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-([0-9]+)-g[a-f0-9]+)?$ ]]; then
    version=${BASH_REMATCH[1]}  # X.Y.Z
    commits=${BASH_REMATCH[3]}  # number of commits since tag

    # If we're producing a short version string, or this is a release version
    # (no commits since tag)
    if [[ "$SHORT" == true ]] || [[ -z "$commits" ]]; then
        echo "$version"
        exit 0
    fi

    echo "${version}.${commits}"
else
    echo "Error: Could not parse git describe output: $describe_output" >&2
    exit 1
fi