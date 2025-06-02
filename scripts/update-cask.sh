#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--version <version>] [--assignee <github handle>]"
  echo "  --version  <version>        Set the VERSION variable to fetch and generate the cask file for"
  echo "  --assignee <github handle>  Set the ASSIGNEE variable to assign the PR to (optional)"
  echo "  -h, --help                  Display this help message"
}

VERSION=""
ASSIGNEE=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --version)
    VERSION="$2"
    shift 2
    ;;
  --assignee)
    ASSIGNEE="$2"
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
[[ "$VERSION" =~ ^v ]] || {
  echo "Error: VERSION must start with a 'v'"
  exit 1
}

# Download the Coder-Desktop pkg
GH_RELEASE_FOLDER=$(mktemp -d)

gh release download "$VERSION" \
  --repo coder/coder-desktop-macos \
  --dir "$GH_RELEASE_FOLDER" \
  --pattern 'Coder-Desktop.pkg'

HASH=$(shasum -a 256 "$GH_RELEASE_FOLDER"/Coder-Desktop.pkg | awk '{print $1}' | tr -d '\n')

# Check out the homebrew tap repo
TAP_CHECKOUT_FOLDER=$(mktemp -d)

gh repo clone "coder/homebrew-coder" "$TAP_CHECKOUT_FOLDER"

cd "$TAP_CHECKOUT_FOLDER"

BREW_BRANCH="auto-release/desktop-$VERSION"

# Check if a PR already exists.
# Continue on a main branch release, as the sha256 will change.
pr_count="$(gh pr list --search "head:$BREW_BRANCH" --json id,closed | jq -r ".[] | select(.closed == false) | .id" | wc -l)"
if [[ "$pr_count" -gt 0 ]]; then
  echo "Bailing out as PR already exists" 2>&1
  exit 0
fi

git checkout -b "$BREW_BRANCH"

mkdir -p "$TAP_CHECKOUT_FOLDER"/Casks

# Overwrite the cask file
cat >"$TAP_CHECKOUT_FOLDER"/Casks/coder-desktop.rb <<EOF
cask "coder-desktop" do
  version "${VERSION#v}"
  sha256 "${HASH}"

  url "https://github.com/coder/coder-desktop-macos/releases/download/v#{version}/Coder-Desktop.pkg"
  name "Coder Desktop"
  desc "Native desktop client for Coder"
  homepage "https://github.com/coder/coder-desktop-macos"
  auto_updates true

  depends_on macos: ">= :sonoma"

  pkg "Coder-Desktop.pkg"

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
    ${ASSIGNEE:+ --assignee "$ASSIGNEE" --reviewer "$ASSIGNEE"}
fi
