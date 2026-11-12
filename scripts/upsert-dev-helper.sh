#!/usr/bin/env bash
# This script operates like postinstall + preinstall, but for local development
# builds, where the helper is necessary. Instead of looking for
# /Applications/Coder Desktop.app, it looks for
# /Applications/Coder/Coder Desktop.app, which is where the local build is
# installed.

set -euxo pipefail

LAUNCH_DAEMON_PLIST_SRC="/Applications/Coder/Coder Desktop.app/Contents/Library/LaunchDaemons"
LAUNCH_DAEMON_PLIST_DEST="/Library/LaunchDaemons"
LAUNCH_DAEMON_NAME="com.coder.Coder-Desktop.Helper"
LAUNCH_DAEMON_PLIST_NAME="$LAUNCH_DAEMON_NAME.plist"
LAUNCH_DAEMON_BINARY_PATH="/Applications/Coder/Coder Desktop.app/Contents/MacOS/com.coder.Coder-Desktop.Helper"

# Must match `Validator.xpcPeerRequirement` in Coder-Desktop/VPNLib/Validate.swift.
XPC_PEER_REQUIREMENT='anchor apple generic and certificate leaf[subject.OU] = "4399GN35BJ"'

if [ ! -f "$LAUNCH_DAEMON_BINARY_PATH" ]; then
    echo "error: helper binary not found at '$LAUNCH_DAEMON_BINARY_PATH'." >&2
    echo "Build the 'Coder Desktop' app target first so it installs to /Applications/Coder." >&2
    exit 1
fi

# Refuse to install a helper the app will reject over XPC. The app validates
# XPC peers against this requirement; bootstrapping a helper that fails it
# only surfaces later as cryptic 'errSecCSReqFailed' (-67050) connection
# errors. A stale or ad-hoc-signed helper can end up in the installed bundle
# when Xcode skips the "Embed Dependencies" (CodeSignOnCopy) phase, or when a
# build with code signing disabled (e.g. `make test`) writes into it.
if ! codesign --verify --strict -R="$XPC_PEER_REQUIREMENT" "$LAUNCH_DAEMON_BINARY_PATH"; then
    echo "error: '$LAUNCH_DAEMON_BINARY_PATH' does not satisfy the app's XPC peer code signing requirement:" >&2
    echo "    $XPC_PEER_REQUIREMENT" >&2
    codesign --display --verbose=2 "$LAUNCH_DAEMON_BINARY_PATH" >&2 || true
    echo "The installed helper is likely stale or ad-hoc signed. To fix, delete it and rebuild:" >&2
    echo "    rm '$LAUNCH_DAEMON_BINARY_PATH'" >&2
    echo "then rebuild the 'Coder Desktop' target so the embed phase re-copies and re-signs the helper." >&2
    exit 1
fi

# Stop an existing launch daemon, if it exists
sudo launchctl bootout "system/$LAUNCH_DAEMON_NAME" 2>/dev/null || true

# Install daemon
# Copy plist into system dir, with the path corrected to the local build
sed 's|/Applications/Coder Desktop\.app|/Applications/Coder/Coder Desktop.app|g' "$LAUNCH_DAEMON_PLIST_SRC"/"$LAUNCH_DAEMON_PLIST_NAME" | sudo tee "$LAUNCH_DAEMON_PLIST_DEST"/"$LAUNCH_DAEMON_PLIST_NAME" >/dev/null
# Set necessary permissions
sudo chmod 755 "$LAUNCH_DAEMON_BINARY_PATH"
sudo chmod 644 "$LAUNCH_DAEMON_PLIST_DEST"/"$LAUNCH_DAEMON_PLIST_NAME"
sudo chown root:wheel "$LAUNCH_DAEMON_PLIST_DEST"/"$LAUNCH_DAEMON_PLIST_NAME"

# Load daemon
sudo launchctl enable "system/$LAUNCH_DAEMON_NAME" || true # Might already be enabled
sudo launchctl bootstrap system "$LAUNCH_DAEMON_PLIST_DEST/$LAUNCH_DAEMON_PLIST_NAME"
sudo launchctl kickstart -k "system/$LAUNCH_DAEMON_NAME"

