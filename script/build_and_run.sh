#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
BUILD_ROOT="$(python3 - "$ROOT" "${DI2_BUILD_DIR:-$HOME/Library/Developer/DeadIsland2SaveMac}" <<'PY'
from pathlib import Path
import sys
source,build=map(lambda p:Path(p).expanduser().resolve(),sys.argv[1:])
if source==build or source in build.parents:
    raise SystemExit('DI2_BUILD_DIR must be outside the source directory')
print(build)
PY
)"
APP="$BUILD_ROOT/DerivedData/Build/Products/Debug/DeadIsland2SaveMac.app"
case "$MODE" in
    run|--verify|--debug|--logs|--telemetry|--build-only|--test|--core-test) ;;
    *) printf 'Usage: %s [--build-only|--test|--core-test|--verify|--debug|--logs|--telemetry]\n' "$0"; exit 2 ;;
esac
mkdir -p "$BUILD_ROOT"
if [[ "$MODE" != --core-test ]] && pgrep -x DeadIsland2SaveMac >/dev/null; then
    printf 'Bitte den Editor regulär beenden, bevor die App neu gebaut wird.\n' >&2
    exit 1
fi
if [[ "$MODE" == --test || "$MODE" == --core-test ]]; then
    SCHEME=DeadIsland2SaveMac
    if [[ "$MODE" == --core-test ]]; then SCHEME=SaveCore; fi
    rm -rf "$BUILD_ROOT/TestResults.xcresult"
    xcodebuild -quiet -project "$ROOT/DeadIsland2SaveMac.xcodeproj" \
        -scheme "$SCHEME" -configuration Debug -destination 'platform=macOS' \
        -derivedDataPath "$BUILD_ROOT/DerivedData" \
        -resultBundlePath "$BUILD_ROOT/TestResults.xcresult" test
    exit 0
fi
xcodebuild -quiet -project "$ROOT/DeadIsland2SaveMac.xcodeproj" \
    -scheme DeadIsland2SaveMac -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_ROOT/DerivedData" build
if [[ "$MODE" == --build-only ]]; then printf '%s\n' "$APP"; exit 0; fi
if [[ "$MODE" == --debug ]]; then lldb -- "$APP/Contents/MacOS/DeadIsland2SaveMac"; exit; fi
if [[ -f "$BUILD_ROOT/Catalog/items.csv" ]]; then
    open -n --env "DI2_ITEM_CATALOG=$BUILD_ROOT/Catalog/items.csv" \
        --env "DI2_UPGRADE_CATALOG=$BUILD_ROOT/Catalog/weapon_upgrades.csv" "$APP"
else
    open -n "$APP"
fi
case "$MODE" in
    --verify) sleep 2; pgrep -x DeadIsland2SaveMac >/dev/null ;;
    --logs) log stream --info --style compact --predicate 'process == "DeadIsland2SaveMac"' ;;
    --telemetry) log stream --info --style compact --predicate 'subsystem == "org.darkuser89.DeadIsland2SaveMac"' ;;
esac
