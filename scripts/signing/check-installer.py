#!/usr/bin/env python3
"""Checks an installer package after rcodesign has signed it.

It checks that the installer carries both signatures an Apple-signed
installer has, that they carry the expected certificate, that the signature
macOS checks was really made by that certificate's key, and that signing
left the contents alone.

The key check matters because rcodesign embeds whichever certificate it is
given, even if the key it signs with belongs to another one.

Usage: check-installer.py UNSIGNED.pkg SIGNED.pkg [CERTIFICATE_PEM]

Needs openssl.
"""

import base64
import hashlib
import os
import ssl
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib

DSIG = "{http://www.w3.org/2000/09/xmldsig#}"


def read(path):
    """What a xar archive's table of contents says, and the data it points at."""
    with open(path, "rb") as f:
        magic, header_size, _, toc_length = struct.unpack(">4sHHQ", f.read(16))
        if magic != b"xar!":
            sys.exit(f"ERROR: {path} is not an installer package")
        f.seek(header_size)
        compressed_toc = f.read(toc_length)
        heap = f.read()
    toc = ET.fromstring(zlib.decompress(compressed_toc))

    def blob(element):
        offset, size = int(element.findtext("offset")), int(element.findtext("size"))
        return heap[offset : offset + size]

    signatures = {}
    for tag in ("signature", "x-signature"):
        element = toc.find(f"toc/{tag}")
        if element is not None:
            certificates = [base64.b64decode(c.text) for c in element.iter(f"{DSIG}X509Certificate")]
            signatures[element.get("style")] = (certificates, blob(element))
    files = {
        entry.findtext("name"): entry.findtext("data/archived-checksum")
        for entry in toc.iter("file")
        if entry.find("data") is not None
    }
    # The signatures cover this checksum of the table of contents, which in
    # turn holds a checksum of every file.
    checksum = toc.find("toc/checksum")
    stored = blob(checksum)
    if hashlib.new(checksum.get("style"), compressed_toc).digest() != stored:
        sys.exit(f"ERROR: {path}: the table of contents does not match its checksum")
    return signatures, files, stored


def verifies(cms, content):
    """Whether the CMS signature over `content` was made by the key of the
    signer's certificate inside it. The certificate chain is not judged
    here: Apple's notary service and macOS do that."""
    with tempfile.NamedTemporaryFile() as cms_file, tempfile.NamedTemporaryFile() as content_file:
        cms_file.write(cms)
        cms_file.flush()
        content_file.write(content)
        content_file.flush()
        result = subprocess.run(
            [
                "openssl", "cms", "-verify", "-noverify", "-binary", "-inform", "DER",
                "-in", cms_file.name, "-content", content_file.name, "-out", os.devnull,
            ],
            capture_output=True,
            check=False,
        )
    return result.returncode == 0


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    unsigned_signatures, unsigned_files, _ = read(sys.argv[1])
    signatures, files, checksum = read(sys.argv[2])

    if unsigned_signatures:
        sys.exit(f"ERROR: {sys.argv[1]} is already signed")
    for style in ("RSA", "CMS"):
        if style not in signatures or not signatures[style][0]:
            sys.exit(f"ERROR: {sys.argv[2]} has no {style} signature with a certificate")
    if files != unsigned_files:
        sys.exit("ERROR: signing changed the installer's contents")

    note = "certificate not compared"
    if len(sys.argv) == 4:
        with open(sys.argv[3], encoding="ascii") as f:
            pem = f.read()
        begin, end = "-----BEGIN CERTIFICATE-----", "-----END CERTIFICATE-----"
        expected = ssl.PEM_cert_to_DER_cert(pem[pem.index(begin) : pem.index(end) + len(end)])
        for style, (certificates, _) in signatures.items():
            if certificates[0] != expected:
                sys.exit(f"ERROR: the {style} signature does not carry the expected certificate")
        note = "carrying the expected certificate"

    certificates, cms = signatures["CMS"]
    if not verifies(cms, checksum):
        sys.exit(
            "ERROR: the installer's signature was not made by the key of the certificate it carries. "
            "Is the key the one this certificate was issued for?"
        )
    print(
        f"OK: RSA and CMS signatures present, {note}, signature verifies, "
        f"{len(certificates)} certificate(s) in the chain, contents unchanged"
    )


if __name__ == "__main__":
    main()
