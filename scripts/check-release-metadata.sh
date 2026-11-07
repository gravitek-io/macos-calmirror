#!/bin/bash
# Verifies the manually packaged app metadata against the Swift package source.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${PROJECT_DIR}/Sources/CalmMirrorApp/Info.plist"
CORE_VERSION="$(sed -nE 's/.*public static let version = "([^"]+)".*/\1/p' "${PROJECT_DIR}/Sources/CalmMirrorCore/CalmMirrorCore.swift")"
PACKAGE_MAJOR="$(sed -nE 's/.*\.macOS\(\.v([0-9]+)\).*/\1/p' "${PROJECT_DIR}/Package.swift")"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PLIST_MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"

if [[ -z "$CORE_VERSION" || "$PLIST_VERSION" != "$CORE_VERSION" || "$PLIST_BUILD" != "$CORE_VERSION" ]]; then
    echo "error: app bundle versions ($PLIST_VERSION/$PLIST_BUILD) must match Core version ($CORE_VERSION)." >&2
    exit 1
fi
if [[ "$PLIST_MINIMUM" != "${PACKAGE_MAJOR}.0" ]]; then
    echo "error: app minimum macOS ($PLIST_MINIMUM) must match Package.swift (.macOS(.v${PACKAGE_MAJOR}))." >&2
    exit 1
fi
echo "Release metadata is consistent: version ${CORE_VERSION}, macOS ${PLIST_MINIMUM}+"
