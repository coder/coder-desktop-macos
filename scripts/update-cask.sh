#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--version <version>] [--assignee <github handle>]"
  echo "  --version  <version>        Set the VERSION variable to fetch and generate the cask file for"
  echo "  --assignee <github handle>  Set the ASSIGNE variable to assign the PR to (optional)"
  echo "  -h, --help                  Display this help message"
}

VERSION=""
ASSIGNE=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --version)
    VERSION="$2"
    shift 2
    ;;
  --assignee)
    ASSIGNE="$2"
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

# Assert version is not empty and starts with v
[ -z "$VERSION" ] && {
  echo "Error: VERSION cannot be empty"
  exit 1
}
[[ "$VERSION" =~ ^v || "$VERSION" == "preview" ]] || {
  echo "Error: VERSION must start with a 'v'"
  exit 1
}

# Download the CoderDesktop pkg
GH_RELEASE_FOLDER=$(mktemp -d)

gh release download "$VERSION" \
  --repo coder/coder-desktop-macos \
  --dir "$GH_RELEASE_FOLDER" \
  --pattern 'CoderDesktop.pkg'

HASH=$(shasum -a 256 "$GH_RELEASE_FOLDER"/CoderDesktop.pkg | awk '{print $1}' | tr -d '\n')

IS_PREVIEW=false
if [[ "$VERSION" == "preview" ]]; then
  IS_PREVIEW=true
  VERSION=$(make 'print-CURRENT_PROJECT_VERSION' | sed 's/CURRENT_PROJECT_VERSION=//g')
fi

# Check out the homebrew tap repo
TAP_CHECHOUT_FOLDER=$(mktemp -d)

gh repo clone "coder/homebrew-coder" "$TAP_CHECHOUT_FOLDER"

cd "$TAP_CHECHOUT_FOLDER"

BREW_BRANCH="auto-release/desktop-$VERSION"

# Check if a PR already exists.
# Continue on a main branch release, as the sha256 will change.
pr_count="$(gh pr list --search "head:$BREW_BRANCH" --json id,closed | jq -r ".[] | select(.closed == false) | .id" | wc -l)"
if [[ "$pr_count" -gt 0 && "$IS_PREVIEW" == false ]]; then
  echo "Bailing out as PR already exists" 2>&1
  exit 0
fi

git checkout -b "$BREW_BRANCH"

# If this is a main branch build, append a preview suffix to the cask.
SUFFIX=""
CONFLICTS_WITH="coder-desktop-preview"
TAG=$VERSION
if [[ "$IS_PREVIEW" == true ]]; then
  SUFFIX="-preview"
  CONFLICTS_WITH="coder-desktop"
  TAG="preview"
fi

mkdir -p "$TAP_CHECHOUT_FOLDER"/Casks

# Overwrite the cask file
cat >"$TAP_CHECHOUT_FOLDER"/Casks/coder-desktop${SUFFIX}.rb <<EOF
cask "coder-desktop${SUFFIX}" do
  version "${VERSION#v}"
  sha256 $([ "$IS_PREVIEW" = true ] && echo ":no_check" || echo "\"${HASH}\"")

  url "https://github.com/coder/coder-desktop-macos/releases/download/$([ "$IS_PREVIEW" = true ] && echo "${TAG}" || echo "v#{version}")/CoderDesktop.pkg"
  name "Coder Desktop"
  desc "Coder Desktop client"
  homepage "https://github.com/coder/coder-desktop-macos"

  conflicts_with cask: "coder/coder/${CONFLICTS_WITH}"
  depends_on macos: ">= :sonoma"

  pkg "CoderDesktop.pkg"

  uninstall quit:       [
              "com.coder.Coder-Desktop",
              "com.coder.Coder-Desktop.VPN",
            ],
            login_item: "Coder Desktop"

  zap delete: "/var/root/Library/Containers/com.Coder-Desktop.VPN/Data/Documents/coder-vpn.dylib",
      trash:  [
        "~/Library/Caches/com.coder.Coder-Desktop",
        "~/Library/HTTPStorages/com.coder.Coder-Desktop",
        "~/Library/Preferences/com.coder.Coder-Desktop.plist",
      ]
end
EOF

git add .
git commit -m "Coder Desktop $VERSION"
git push -u origin -f "$BREW_BRANCH"

# Create a PR only if none exists
if [[ "$pr_count" -eq 0 ]]; then
  gh pr create \
    --base master --head "$BREW_BRANCH" \
    --title "Coder Desktop $VERSION" \
    --body "This automatic PR was triggered by the release of Coder Desktop $VERSION" \
    ${ASSIGNE:+ --assignee "$ASSIGNE" --reviewer "$ASSIGNE"}
fi
