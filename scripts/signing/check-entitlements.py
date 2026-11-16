#!/usr/bin/env python3
"""Checks that the entitlements the app is signed with still match the project.

Xcode used to derive the signed entitlements while it signed. Now that the
app is signed on Linux, they are kept in scripts/signing/entitlements, and a
change to the entitlements in project.yml would not reach a release unless
those files change too. This fails the build when they have drifted apart.

It applies what Xcode's Developer ID export does to a target's generated
entitlements file, and compares the result with the file used for signing:
  - $(TeamIdentifierPrefix) becomes the team ID and a dot;
  - the application identifier and the team identifier are added;
  - aps-environment is dropped, because the provisioning profile does not
    grant it. No release has carried it.

Usage: check-entitlements.py GENERATED.entitlements SIGNED.plist BUNDLE_ID
"""

import plistlib
import sys

TEAM_ID = "4399GN35BJ"
DROPPED = {"aps-environment"}


def expand(value):
    if isinstance(value, str):
        return value.replace("$(TeamIdentifierPrefix)", TEAM_ID + ".")
    if isinstance(value, list):
        return [expand(item) for item in value]
    return value


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    generated_path, signed_path, bundle_id = sys.argv[1:4]
    with open(generated_path, "rb") as f:
        generated = plistlib.load(f)
    with open(signed_path, "rb") as f:
        signed = plistlib.load(f)

    expected = {key: expand(value) for key, value in generated.items() if key not in DROPPED}
    expected["com.apple.application-identifier"] = f"{TEAM_ID}.{bundle_id}"
    expected["com.apple.developer.team-identifier"] = TEAM_ID

    problems = []
    for key in sorted(set(expected) | set(signed)):
        if key not in signed:
            problems.append(f"  {key}: in the project, missing from {signed_path}")
        elif key not in expected:
            problems.append(f"  {key}: in {signed_path}, not in the project")
        elif expected[key] != signed[key]:
            problems.append(f"  {key}: project has {expected[key]!r}, {signed_path} has {signed[key]!r}")
    if problems:
        print(f"ERROR: the entitlements for {bundle_id} have changed in the project.")
        print("\n".join(problems))
        print(f"Update {signed_path} to match, and check that the provisioning profile grants them.")
        sys.exit(1)
    print(f"OK: {signed_path} matches the project's entitlements for {bundle_id}")


if __name__ == "__main__":
    main()
