#!/usr/bin/env python3
"""Helps sign the macOS programs that sit inside a .tar.gz in the app.

Signing a bundle does not look inside an archive, but Apple's notary service
does, and it expects every macOS program it finds to be signed. The mutagen
agents archive holds two.

Usage:
  archive-members.py list ARCHIVE
      Prints the name of every member that is a macOS (Mach-O) program.
  archive-members.py replace ARCHIVE DIRECTORY NAME...
      Rewrites ARCHIVE in place, taking the content of each NAME from
      DIRECTORY. Every other member, and every member's name, mode, owner
      and time, is kept as it was.
"""

import gzip
import io
import os
import shutil
import sys
import tarfile

# Universal binary, and 64-bit and 32-bit single-architecture binaries.
MACH_O_MAGICS = (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe")


def list_programs(archive):
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            if member.isfile() and tar.extractfile(member).read(4) in MACH_O_MAGICS:
                print(member.name)


def replace(archive, directory, names):
    names = set(names)
    replaced = set()
    temporary = archive + ".tmp"
    with tarfile.open(archive, "r:gz") as source, open(temporary, "wb") as raw:
        # No file name or time in the gzip header, so the result depends only
        # on the contents.
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=source.format) as target:
                for member in source:
                    if member.name in names:
                        with open(os.path.join(directory, member.name), "rb") as f:
                            data = f.read()
                        member.size = len(data)
                        target.addfile(member, io.BytesIO(data))
                        replaced.add(member.name)
                    elif member.isfile():
                        target.addfile(member, source.extractfile(member))
                    else:
                        target.addfile(member)
    if replaced != names:
        os.remove(temporary)
        sys.exit(f"ERROR: {archive} has no member named {', '.join(sorted(names - replaced))}")
    shutil.copymode(archive, temporary)
    os.replace(temporary, archive)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "list":
        list_programs(sys.argv[2])
    elif len(sys.argv) >= 5 and sys.argv[1] == "replace":
        replace(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
