#!/usr/bin/env python3
"""Checks a Developer ID provisioning profile before it is embedded in the app.

A profile that does not match is not rejected by signing or by notarization.
macOS rejects it when the system extension loads, so check up front that the
profile:
  - is a Developer ID profile for the Coder team,
  - is for the code it will be embedded in,
  - has not expired, and
  - names the signing certificate. A profile is bound to the certificate
    selected when it was created.

Usage: check-profile.py PROFILE ENTITLEMENTS [CERTIFICATE_PEM]

ENTITLEMENTS is the entitlements file of the code the profile goes with.
Without CERTIFICATE_PEM the certificate binding is not checked.
"""

import datetime
import plistlib
import ssl
import subprocess
import sys

TEAM_ID = "4399GN35BJ"
APP_ID_KEY = "com.apple.application-identifier"


def fail(message):
    sys.exit(f"ERROR: {message}")


def describe(der):
    """Serial number and expiry of a DER certificate, for messages."""
    try:
        out = subprocess.run(
            ["openssl", "x509", "-inform", "der", "-noout", "-serial", "-enddate"],
            input=der,
            capture_output=True,
            check=True,
        ).stdout.decode()
    except (OSError, subprocess.CalledProcessError):
        return "details unavailable"
    return ", ".join(line for line in out.splitlines() if line)


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    profile_path, entitlements_path = sys.argv[1:3]
    certificate_path = sys.argv[3] if len(sys.argv) == 4 else ""

    with open(profile_path, "rb") as f:
        blob = f.read()
    if not blob:
        fail(f"{profile_path} is empty. Is the secret set?")
    # A profile is a signed CMS message that wraps an XML property list.
    start, end = blob.find(b"<?xml"), blob.find(b"</plist>")
    if start < 0 or end < start:
        fail(
            f"{profile_path} is not a provisioning profile. The secret must be "
            "the base64 of the .provisionprofile file, encoded once."
        )
    try:
        profile = plistlib.loads(blob[start : end + len(b"</plist>")])
        name = profile["Name"]
        granted = profile["Entitlements"][APP_ID_KEY]
        certificates = profile["DeveloperCertificates"]
        expires = profile["ExpirationDate"]
    except Exception as e:  # pylint: disable=broad-except
        fail(f"{profile_path} could not be read as a provisioning profile: {e!r}")

    if profile.get("TeamIdentifier") != [TEAM_ID]:
        fail(f"profile '{name}' belongs to team {profile.get('TeamIdentifier')}, not {TEAM_ID}")
    if not profile.get("ProvisionsAllDevices"):
        fail(
            f"profile '{name}' is not a Developer ID profile. Development and "
            "App Store profiles do not work for software distributed outside the store."
        )
    with open(entitlements_path, "rb") as f:
        wanted = plistlib.load(f)[APP_ID_KEY]
    if granted != wanted:
        fail(f"profile '{name}' is for {granted}, but would be embedded in {wanted}")
    if expires < datetime.datetime.now():
        fail(f"profile '{name}' expired on {expires:%Y-%m-%d}")

    bound = "certificate binding not checked"
    if certificate_path:
        with open(certificate_path, encoding="ascii") as f:
            pem = f.read()
        begin, finish = "-----BEGIN CERTIFICATE-----", "-----END CERTIFICATE-----"
        if begin not in pem or finish not in pem:
            fail(f"{certificate_path} is not a PEM certificate")
        certificate = ssl.PEM_cert_to_DER_cert(pem[pem.index(begin) : pem.index(finish) + len(finish)])
        if certificate not in certificates:
            names = "; ".join(describe(c) for c in certificates)
            fail(
                f"profile '{name}' is not bound to the signing certificate "
                f"({describe(certificate)}). It is bound to: {names}. In the "
                "Apple Developer portal, create a Developer ID profile that "
                "selects the signing certificate."
            )
        bound = "bound to the signing certificate"

    print(f"OK: profile '{name}' ({profile.get('UUID')}) for {granted}, {bound}, expires {expires:%Y-%m-%d}")


if __name__ == "__main__":
    main()
