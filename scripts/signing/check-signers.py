#!/usr/bin/env python3
"""Checks that every macOS program in the app was signed with the expected
Developer ID Application certificate, and with no other.

It also looks inside .tar.gz files. Signing a bundle does not reach into an
archive, so a program there keeps whatever signature it arrived with unless
it is signed separately.

For each program, and each architecture in it, this reads the certificates
out of the code signature. The expected certificate must be among them, and
every other certificate there must be a certificate authority. It then
verifies the signature itself against the code directory it covers, because
a signature can carry a certificate whose key did not make it: rcodesign
embeds whichever certificate it is given.

Usage: check-signers.py "path/to/Coder Desktop.app" CERTIFICATE_PEM

Needs openssl.
"""

import os
import re
import ssl
import struct
import subprocess
import sys
import tarfile
import tempfile

FAT_MAGIC = 0xCAFEBABE
MACH_O_32 = 0xFEEDFACE
MACH_O_64 = 0xFEEDFACF
LC_CODE_SIGNATURE = 0x1D
SUPERBLOB_MAGIC = 0xFADE0CC0
CODE_DIRECTORY_SLOT = 0
CMS_SLOT = 0x10000
CMS_MAGIC = 0xFADE0B01

PEM = re.compile(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", re.S)


def is_program(head):
    if len(head) < 4:
        return False
    return struct.unpack(">I", head[:4])[0] == FAT_MAGIC or struct.unpack("<I", head[:4])[0] in (MACH_O_32, MACH_O_64)


def slices(data):
    """Offsets of each single-architecture Mach-O in a file."""
    if struct.unpack(">I", data[:4])[0] == FAT_MAGIC:
        (count,) = struct.unpack(">I", data[4:8])
        return [struct.unpack(">I", data[16 + 20 * i : 20 + 20 * i])[0] for i in range(count)]
    return [0]


def signature(data, start):
    """The CMS signature of the Mach-O at `start` and the code directory it
    covers, or None if it has no such signature."""
    (magic,) = struct.unpack("<I", data[start : start + 4])
    header = 32 if magic == MACH_O_64 else 28
    (commands,) = struct.unpack("<I", data[start + 16 : start + 20])
    at = start + header
    for _ in range(commands):
        command, size = struct.unpack("<II", data[at : at + 8])
        if command == LC_CODE_SIGNATURE:
            (offset,) = struct.unpack("<I", data[at + 8 : at + 12])
            blob = start + offset
            magic, _, count = struct.unpack(">III", data[blob : blob + 12])
            if magic != SUPERBLOB_MAGIC:
                return None
            cms = code_directory = None
            for i in range(count):
                slot, where = struct.unpack(">II", data[blob + 12 + 8 * i : blob + 20 + 8 * i])
                magic, length = struct.unpack(">II", data[blob + where : blob + where + 8])
                if slot == CODE_DIRECTORY_SLOT:
                    # The signature covers the whole blob, header included.
                    code_directory = data[blob + where : blob + where + length]
                elif slot == CMS_SLOT and magic == CMS_MAGIC and length > 8:
                    cms = data[blob + where + 8 : blob + where + length]
            if cms is None or code_directory is None:
                return None
            return cms, code_directory
        at += size
    return None


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


def certificates(cms):
    """The certificates in a CMS signature, in DER."""
    out = subprocess.run(
        ["openssl", "pkcs7", "-inform", "DER", "-print_certs"], input=cms, capture_output=True, check=True
    ).stdout.decode()
    return [ssl.PEM_cert_to_DER_cert(pem) for pem in PEM.findall(out)]


def describe(der):
    out = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-serial", "-subject", "-text"],
        input=der,
        capture_output=True,
        check=True,
    ).stdout.decode()
    serial = re.search(r"^serial=(\S+)", out, re.M).group(1)
    name = re.search(r"CN ?= ?([^,\n]+)", out)
    return "CA:TRUE" in out, f"{name.group(1) if name else 'unnamed'}, serial {serial}"


def problem(data, expected):
    """What is wrong with one program's signature, or None."""
    for start in slices(data):
        signed = signature(data, start)
        if signed is None:
            return "is not signed with a certificate"
        cms, code_directory = signed
        found = certificates(cms)
        for der in found:
            if der == expected:
                continue
            authority, text = describe(der)
            if not authority:
                return f"is signed with a different certificate ({text})"
        if expected not in found:
            return "is not signed with the expected certificate"
        if not verifies(cms, code_directory):
            return "carries the expected certificate, but its signature was not made by that certificate's key"
    return None


def programs(app):
    """Yields (name, bytes) for every Mach-O in the app, archives included."""
    for directory, _, files in os.walk(app):
        for name in sorted(files):
            path = os.path.join(directory, name)
            if os.path.islink(path):
                continue
            relative = os.path.relpath(path, app)
            if name.endswith((".tar.gz", ".tgz", ".tar")):
                with tarfile.open(path) as tar:
                    for member in tar:
                        if not member.isfile():
                            continue
                        data = tar.extractfile(member).read()
                        if is_program(data[:4]):
                            yield f"{relative}/{member.name}", data
                continue
            with open(path, "rb") as f:
                if not is_program(f.read(4)):
                    continue
                f.seek(0)
                yield relative, f.read()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    app, certificate_path = sys.argv[1:3]
    with open(certificate_path, encoding="ascii") as f:
        expected = ssl.PEM_cert_to_DER_cert(PEM.search(f.read()).group(0))

    total = archived = 0
    failures = []
    for name, data in programs(app):
        total += 1
        archived += ".tar" in name
        if (what := problem(data, expected)) is not None:
            failures.append(f"ERROR: {name} {what}")
    for failure in failures:
        print(failure)
    if failures:
        sys.exit(1)
    if not total:
        sys.exit(f"ERROR: found no macOS programs in {app}")
    print(f"OK: all {total} macOS programs ({archived} inside archives) are signed with the expected certificate and no other")


if __name__ == "__main__":
    main()
