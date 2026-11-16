#!/usr/bin/env python3
"""Checks something about the app bundle that signing and notarization do not,
but that macOS enforces when the system extension is activated.

The Network Extension subsystem requires the extension's Mach service name
(NEMachServiceName in the Info.plist) to start with one of the app groups in
the entitlements. Xcode builds that name from $(TeamIdentifierPrefix), which
it takes from the signing identity, so a build made with signing disabled
loses the prefix unless it is passed in. Activation then fails with
"Extension category returned error".

Usage: check-bundle.py "path/to/Coder Desktop.app" ENTITLEMENTS_DIR
"""

import plistlib
import sys

SYSEXT = "Contents/Library/SystemExtensions/com.coder.Coder-Desktop.VPN.systemextension"
GROUPS_KEY = "com.apple.security.application-groups"


def load(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    app, entitlements = sys.argv[1:3]
    names = []
    for label, info, ents in (
        ("app", f"{app}/Contents/Info.plist", f"{entitlements}/app.plist"),
        ("system extension", f"{app}/{SYSEXT}/Contents/Info.plist", f"{entitlements}/vpn.plist"),
    ):
        name = load(info)["NetworkExtension"]["NEMachServiceName"]
        groups = load(ents)[GROUPS_KEY]
        if not any(name.startswith(group + ".") for group in groups):
            sys.exit(
                f"ERROR: the {label}'s NEMachServiceName is '{name}', which does not start "
                f"with an app group from its entitlements ({', '.join(groups)}). macOS would "
                "refuse to activate the system extension. Was the app built without "
                "TeamIdentifierPrefix?"
            )
        names.append(name)
    if names[0] != names[1]:
        sys.exit(f"ERROR: the app and the system extension disagree on NEMachServiceName: {names}")
    print(f"OK: NEMachServiceName '{names[0]}' starts with an app group")


if __name__ == "__main__":
    main()
