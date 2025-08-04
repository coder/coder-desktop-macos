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

