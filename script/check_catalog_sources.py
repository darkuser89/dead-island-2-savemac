#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Verify catalog provenance against temporary exports of the user's own game assets."""
import argparse
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mas', required=True, type=Path, help='MAS legacy export root containing DeadIsland/Content')
parser.add_argument('--steam', required=True, type=Path, help='Steam legacy export root containing DeadIsland/Content')
args = parser.parse_args()
resources = root / 'macOS/SaveMac/Resources'
collections = json.loads((resources / 'CollectionCatalog.json').read_text())
rewards = json.loads((resources / 'QuestRewards.json').read_text())
checks = {}
for entry in collections['provenance']:
    checks[entry['packagePath']] = {'mas': entry['masExportSHA256'], 'steam': entry['steamExportSHA256']}
for entry in rewards['definitions']:
    for package, digest in [(entry['questPath'], entry['questExportSHA256']), (entry['rewardPath'], entry['exportSHA256'])]:
        if package:
            expected = {'mas': digest, 'steam': digest}
            if package in checks and checks[package] != expected:
                raise SystemExit(f'Conflicting provenance: {package}')
            checks[package] = expected
for package, expected in checks.items():
    relative = package.removeprefix('/Game/')
    if not package.startswith('/Game/DI2/') or '..' in Path(relative).parts:
        raise SystemExit('Invalid catalog package path')
    for platform in ['mas', 'steam']:
        path = (getattr(args, platform) / 'DeadIsland/Content' / relative).with_suffix('.uexp')
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected[platform]:
            raise SystemExit(f'Hash mismatch: {platform}: {package}')
print(f'Verified {len(checks)} package exports in both installations; source files were only read.')
