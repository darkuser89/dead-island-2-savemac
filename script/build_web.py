#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build the browser editor with the same Swift/C/C++ core as the macOS app.
All SDKs, downloads, intermediate files and the deployable site stay outside source.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '6.4.0'
DOWNLOADS = {
    'swift-wasm-sdk.tar.gz': (
        f'https://download.swift.org/swift-{VERSION}-release/wasm-sdk/swift-{VERSION}-RELEASE/swift-{VERSION}-RELEASE_wasm.artifactbundle.tar.gz',
        'f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d'),
    'swift-toolchain.pkg': (
        f'https://download.swift.org/swift-{VERSION}-release/xcode/swift-{VERSION}-RELEASE/swift-{VERSION}-RELEASE-osx.pkg',
        '8fd03185b98fe27f54a54631c2449decf75d5b466ce8e34abbd414141063c6aa'),
    'wasi-shim.tgz': (
        'https://registry.npmjs.org/@bjorn3/browser_wasi_shim/-/browser_wasi_shim-0.4.2.tgz',
        '9c0281520d0e99f027ec7c1c79b4036c0f8168ed9bf98aba19db4737a1333782'),
}

def run(args):
    print('+', Path(str(args[0])).name, *map(str, args[1:3]), flush=True)
    subprocess.run(list(map(str, args)), check=True)

def fetch(name, tools):
    url, expected = DOWNLOADS[name]
    output = tools / name
    if not output.exists():
        partial = output.with_suffix(output.suffix + '.partial')
        try:
            with urllib.request.urlopen(url, timeout=120) as source, partial.open('wb') as target:
                shutil.copyfileobj(source, target)
            partial.replace(output)
        finally:
            partial.unlink(missing_ok=True)
    with output.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != expected:
        raise SystemExit(f'Checksum mismatch: {name}. Remove this download and retry.')
    return output

def setup(tools):
    if os.uname().sysname != 'Darwin':
        raise SystemExit('Automatic toolchain setup currently requires macOS.')
    for name in DOWNLOADS:
        expected_directory = {
            'swift-wasm-sdk.tar.gz': tools / f'swift-{VERSION}-RELEASE_wasm.artifactbundle',
            'swift-toolchain.pkg': tools / 'toolchain-extracted',
            'wasi-shim.tgz': tools / 'wasi-shim/package',
        }[name]
        if expected_directory.exists():
            continue
        archive = fetch(name, tools)
        if name == 'swift-wasm-sdk.tar.gz':
            if not (tools / f'swift-{VERSION}-RELEASE_wasm.artifactbundle').exists():
                run(['tar', '-xzf', archive, '-C', tools])
        elif name == 'swift-toolchain.pkg':
            target = tools / 'toolchain-extracted'
            if not target.exists():
                run(['pkgutil', '--check-signature', archive])
                run(['pkgutil', '--expand-full', archive, target])
        else:
            if not (tools / 'wasi-shim/package').exists():
                with tarfile.open(archive) as package:
                    package.extractall(tools / 'wasi-shim', filter='data')
        # Keep the single extracted toolchain, not a redundant download archive.
        archive.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', action='store_true', help='Build a separate synthetic-fixture generator for web tests')
    parser.add_argument('--setup', action='store_true', help='Download pinned official toolchain/SDK and WASI shim into the build directory')
    parser.add_argument('--build-dir', type=Path)
    args = parser.parse_args()
    build = (args.build_dir or Path(os.environ.get('DI2_BUILD_DIR', Path.home()/'Library/Developer/DeadIsland2SaveMac'))).expanduser().resolve()
    if build == ROOT or ROOT in build.parents:
        raise SystemExit('Build directory must be outside source.')
    web = build / 'Web'
    tools = web / 'Tools'
    tools.mkdir(parents=True, exist_ok=True)
    if args.setup:
        setup(tools)
    toolchain = Path(os.environ.get('DI2_SWIFT_TOOLCHAIN', tools / f'toolchain-extracted/swift-{VERSION}-RELEASE-osx-package.pkg/Payload'))
    sdk = Path(os.environ.get('DI2_WASM_SDK', tools / f'swift-{VERSION}-RELEASE_wasm.artifactbundle/swift-{VERSION}-RELEASE_wasm/wasm32-unknown-wasip1'))
    swift = toolchain / 'usr/bin/swiftc'
    clang = toolchain / 'usr/bin/clang'
    shim = tools / 'wasi-shim/package'
    if not swift.exists() or not sdk.exists() or not shim.exists():
        raise SystemExit('Missing web toolchain. Run with --setup (macOS) or set DI2_SWIFT_TOOLCHAIN and DI2_WASM_SDK.')
    objects = web / 'Objects'
    objects.mkdir(exist_ok=True)
    sysroot = sdk / 'WASI.sdk'
    resources = sdk / 'swift.xctoolchain/usr/lib/swift_static'
    common = ['-target', 'wasm32-unknown-wasip1', '--sysroot=' + str(sysroot), '-O2', '-DZSTD_DISABLE_ASM=1',
              '-I'+str(ROOT/'macOS/ThirdParty/zstd/lib'), '-I'+str(ROOT/'macOS/ThirdParty/cityhash')]
    sources = sorted((ROOT/'macOS/ThirdParty/zstd/lib').glob('*/*.c'))
    sources += [ROOT/'macOS/ThirdParty/cityhash/city.cc', ROOT/'macOS/NativeCodec/NativeCodec.cpp']
    def compile_one(source):
        output = objects / (source.name + '.o')
        # Header edits must invalidate objects as well.
        headers = list((ROOT/'macOS/NativeCodec').glob('*.h')) + list((ROOT/'macOS/ThirdParty').rglob('*.h'))
        newest = max([source.stat().st_mtime] + [h.stat().st_mtime for h in headers])
        if not output.exists() or output.stat().st_mtime < newest:
            flags = ['-std=c++17', '-fno-exceptions', '-fno-rtti'] if source.suffix in ['.cc', '.cpp'] else []
            run([clang, *common, *flags, '-c', source, '-o', output])
        return output
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        compiled = list(executor.map(compile_one, sources))
    site = web / 'Site'
    site.mkdir(exist_ok=True)
    excluded = {'SaveBackup.swift', 'SaveDiscovery.swift', 'SaveFileLoader.swift'}
    swift_sources = sorted(p for p in (ROOT/'macOS/SaveCore').glob('*.swift') if p.name not in excluded)
    swift_flags = [swift, '-target', 'wasm32-unknown-wasip1', '-sdk', sysroot, '-resource-dir', resources,
                   '-static-stdlib', '-O', '-whole-module-optimization',
                   '-Xclang-linker', '-resource-dir=' + str(sdk/'swift.xctoolchain/usr/lib/clang'),
                   '-I', ROOT/'macOS/NativeCodec', '-module-cache-path', web/'ModuleCache']
    linker_flags = ['-Xlinker', '-z', '-Xlinker', 'stack-size=8388608',
                    '-Xlinker', '--max-memory=1073741824', '-Xlinker', '--strip-debug']
    run([*swift_flags, *swift_sources, ROOT/'web/Bridge/main.swift', *compiled, *linker_flags, '-o', site/'SaveCore.wasm'])
    if args.test:
        run([*swift_flags, '-parse-as-library', *swift_sources, ROOT/'web/tests/Fixtures.swift',
             *compiled, *linker_flags, '-o', web/'TestFixtures.wasm'])
    # Only deployment files are copied; Bridge, tests and private saves are never served.
    for name in ['index.html', 'licenses.html', 'style.css', 'app.js', 'worker.js', 'engine.js', 'session.js']:
        shutil.copy2(ROOT/'web'/name, site/name)
    (site/'vendor').mkdir(exist_ok=True)
    for file in (shim/'dist').glob('*.js'):
        shutil.copy2(file, site/'vendor'/file.name)
    (site/'licenses').mkdir(exist_ok=True)
    for source, name in [(ROOT/'LICENSE', 'AGPL-3.0.txt'), (shim/'LICENSE-MIT', 'browser-wasi-shim-MIT.txt'),
                         (ROOT/'macOS/ThirdParty/zstd/LICENSE', 'Zstandard.txt'), (ROOT/'macOS/ThirdParty/cityhash/COPYING', 'CityHash.txt'),
                         (toolchain/'usr/share/swift/LICENSE.txt', 'Swift-Runtime.txt')]:
        shutil.copy2(source, site/'licenses'/name)
    for notice in (ROOT/'web/ThirdParty').glob('*.txt'):
        shutil.copy2(notice, site/'licenses'/notice.name)
    for name in ['CollectionCatalog', 'UnlockCatalog', 'QuestRewards']:
        shutil.copy2(ROOT/f'macOS/SaveMac/Resources/{name}.json', site/f'{name}.json')
    shutil.copy2(ROOT/'macOS/SaveMac/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png', site/'icon.png')
    (site/'.nojekyll').touch()
    (site/'package.json').write_text('{"type":"module"}\n')
    print(f'Web site: {site}\nWasm size: {(site/"SaveCore.wasm").stat().st_size:,} bytes')

if __name__ == '__main__':
    main()
