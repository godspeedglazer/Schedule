#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "verify-1.0.3.sh must run on macOS because Sched imports AppKit." >&2
  exit 2
fi

expected_version="$(cat VERSION)"
expected_build="$(cat BUILD_NUMBER)"
[[ "$expected_version" == "1.0.3" ]] || { echo "VERSION must be 1.0.3" >&2; exit 1; }
[[ "$expected_build" == "103" ]] || { echo "BUILD_NUMBER must be 103" >&2; exit 1; }

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist)"
[[ "$plist_version" == "$expected_version" ]] || { echo "Info.plist version is $plist_version, expected $expected_version" >&2; exit 1; }
[[ "$plist_build" == "$expected_build" ]] || { echo "Info.plist build is $plist_build, expected $expected_build" >&2; exit 1; }

echo "==> remove stale products"
rm -rf .build dist

echo "==> validate package"
swift package dump-package >/dev/null

echo "==> compile"
swift build --product Sched

echo "==> tests"
swift test

echo "==> build app bundle"
./script/build_and_run.sh --build

plutil -lint dist/Sched.app/Contents/Info.plist >/dev/null
test -x dist/Sched.app/Contents/MacOS/Sched

echo "==> launch smoke test"
./script/build_and_run.sh --verify

echo "Sched 1.0.3 build gate passed."
