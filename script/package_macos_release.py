#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build, validate and ZIP one universal macOS release outside the source tree."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def output(*args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()


def validate(app, version):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'org.darkuser89.DeadIsland2SaveMac':
        raise SystemExit('Unexpected app identity.')
    if info.get('CFBundleShortVersionString') != version:
        raise SystemExit('Release tag and app version do not match.')
    if info.get('LSMinimumSystemVersion') != '14.0':
        raise SystemExit('Unexpected deployment target.')
    resources = app / 'Contents/Resources'
    for name in ['AppIcon.icns', 'LICENSE', 'ThirdPartyNotices.txt',
                 'UnlockCatalog.json', 'CollectionCatalog.json', 'QuestRewards.json']:
        if not (resources / name).is_file():
            raise SystemExit(f'Missing app resource: {name}')
    binaries = [app / 'Contents/MacOS/DeadIsland2SaveMac',
                app / 'Contents/Frameworks/SaveCore.framework/Versions/A/SaveCore']
    for binary in binaries:
        if set(output('xcrun', 'lipo', '-archs', binary).split()) != {'arm64', 'x86_64'}:
            raise SystemExit(f'Universal architectures missing: {binary.name}')
        for line in output('xcrun', 'otool', '-L', binary).splitlines():
            if ' (compatibility version ' not in line:
                continue
            dependency = line.strip().split(' (compatibility version ')[0]
            if not dependency.startswith(('/System/Library/', '/usr/lib/', '@rpath/', '@loader_path/', '@executable_path/')):
                raise SystemExit(f'External build-machine dependency: {dependency}')
    run('codesign', '--verify', '--deep', '--strict', '--all-architectures', app)
    # Distribution is explicitly ad-hoc; it must not claim a Developer ID identity.
    identity = subprocess.run(['codesign', '-dv', str(app)], text=True, capture_output=True, check=True).stderr
    if 'Signature=adhoc' not in identity:
        raise SystemExit('Unexpected signing identity; review distribution settings.')
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        raise SystemExit('Version must be MAJOR.MINOR.PATCH.')
    build = Path(os.environ.get('DI2_BUILD_DIR', Path.home() / 'Library/Developer/DeadIsland2SaveMac')).expanduser().resolve()
    if build == ROOT or ROOT in build.parents:
        raise SystemExit('Build directory must be outside source.')
    run(ROOT / 'script/build_and_run.sh', '--release')
    app = build / 'DerivedData/Build/Products/Release/DeadIsland2SaveMac.app'
    info = validate(app, args.version)
    destination = build / 'Release'
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f'DeadIsland2SaveMac-{args.version}-macOS-universal.zip'
    # A short-lived replacement ZIP protects the previous checked download on failure.
    with tempfile.TemporaryDirectory(prefix='release-check-', dir=build) as work:
        temporary = Path(work) / archive.name
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, temporary)
        extracted = Path(work) / 'extracted'
        run('ditto', '-x', '-k', temporary, extracted)
        validate(extracted / app.name, args.version)
        with temporary.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        temporary.replace(archive)
    checksum = archive.with_suffix(archive.suffix + '.sha256')
    checksum.write_text(f'{digest}  {archive.name}\n')
    print(f'Release {args.version} ({info["CFBundleVersion"]}): {archive}')
    print(f'SHA-256: {digest}')
    print('arm64 + x86_64; ad-hoc signed; not notarized.')


if __name__ == '__main__':
    main()
