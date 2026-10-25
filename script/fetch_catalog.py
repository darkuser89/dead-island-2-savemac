#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Fetch optional item metadata; never install or execute the foreign editor."""
import argparse
import hashlib
import io
import os
from pathlib import Path
import tarfile
import tempfile
from urllib.request import urlopen

URL = "https://builds.steffenl.com/download/dead-island-2-save-editor/0.12.0/di2se-0.12.0-darwin.universal.tar.gz"
SHA256 = "a213772601b5ba9d6dc2cfbf54164f7fe9e2fce428c492b995652a36c3f1e62c"
MEMBER_ROOT = "di2se-0.12.0-darwin.universal/bin/data/inventory/"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", default=os.getenv("DI2_BUILD_DIR", "~/Library/Developer/DeadIsland2SaveMac"))
    parser.add_argument("--source-file", type=Path, help="Use an already downloaded items.csv")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()
    root = Path(args.build_dir).expanduser().resolve()
    source = Path(__file__).resolve().parents[1]
    if root == source or source in root.parents:
        parser.error("The catalog belongs outside the source checkout")
    files = {}
    if args.source_file:
        files["items.csv"] = args.source_file.read_bytes()
        upgrades = args.source_file.with_name("weapon_upgrades.csv")
        if upgrades.exists():
            files["weapon_upgrades.csv"] = upgrades.read_bytes()
    else:
        with urlopen(URL, timeout=60) as response:
            archive = response.read(10 * 1024 * 1024)
        if hashlib.sha256(archive).hexdigest() != SHA256:
            raise SystemExit("Archive checksum mismatch")
        with tarfile.open(fileobj=io.BytesIO(archive)) as package:
            for name in ["items.csv", "weapon_upgrades.csv"]:
                member = package.getmember(MEMBER_ROOT + name)
                if not member.isfile() or member.size > 4 * 1024 * 1024:
                    raise SystemExit("Invalid catalog archive member")
                files[name] = package.extractfile(member).read()
    for name, data in files.items():
        if not data or len(data) > 4 * 1024 * 1024 or b"archetype" not in data.splitlines()[0]:
            raise SystemExit("Invalid catalog")
        destination = root / "Catalog" / name
        if destination.exists() and destination.read_bytes() != data and not args.replace:
            raise SystemExit("A different catalog exists; use --replace to update it")
    for name, data in files.items():
        destination = root / "Catalog" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and destination.read_bytes() == data:
            print(destination)
            continue
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".catalog-", delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(data)
            os.replace(temporary, destination)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        print(destination)


if __name__ == "__main__":
    main()
