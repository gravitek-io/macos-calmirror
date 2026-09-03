#!/bin/bash
# package-release.sh — Build and package a CalMirror release archive
#
# Produces the same artifact published on GitHub Releases:
#   dist/calmirror-<version>-macos-arm64.tar.gz
# containing:
#   calmirror-<version>/
#     CalMirror.app   (ad-hoc code-signed GUI bundle)
#     calmirror       (CLI binary)
#     install.sh      (prebuilt installer, from scripts/release-install.sh)
#
# Usage:
#   ./scripts/package-release.sh             # version inferred from current git tag
#   ./scripts/package-release.sh 1.1.0       # explicit version
#
# The script does NOT create the GitHub release; it only builds the archive.
# The Release workflow (.github/workflows/release.yml) runs it on every vX.Y.Z
# tag and attaches the archive to a draft release. See docs/RELEASING.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="CalMirror"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    # Strip a leading "v" from the most recent tag pointing at HEAD.
    TAG="$(git -C "$PROJECT_DIR" describe --tags --exact-match 2>/dev/null || true)"
    if [[ -z "$TAG" ]]; then
        echo "error: no version given and HEAD is not tagged."
        echo "       Pass a version explicitly: ./scripts/package-release.sh 1.1.0"
        exit 1
    fi
    VERSION="${TAG#v}"
fi

echo "==> Packaging ${APP_NAME} ${VERSION}"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "==> Building in release mode..."
swift build -c release --package-path "$PROJECT_DIR"
BUILD_DIR="$(swift build -c release --package-path "$PROJECT_DIR" --show-bin-path)"

# Guard: the shipped CLI must report the version we are packaging.
CLI_VERSION_OUTPUT="$("${BUILD_DIR}/calmirror" version)"
if [[ "$CLI_VERSION_OUTPUT" != "calmirror ${VERSION}" ]]; then
    echo "error: CLI reports '${CLI_VERSION_OUTPUT}' but packaging '${VERSION}'."
    echo "       Bump the version in source before packaging (see docs/RELEASING.md)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Stage artifacts
# ---------------------------------------------------------------------------
DIST_DIR="${PROJECT_DIR}/dist"
STAGE="${DIST_DIR}/calmirror-${VERSION}"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# GUI app bundle (mirrors scripts/install.sh packaging)
APP="${STAGE}/${APP_NAME}.app"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BUILD_DIR}/CalmMirrorApp" "${APP}/Contents/MacOS/CalmMirrorApp"
cp "${PROJECT_DIR}/Sources/CalmMirrorApp/Info.plist" "${APP}/Contents/Info.plist"
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

# CLI binary
cp "${BUILD_DIR}/calmirror" "${STAGE}/calmirror"

# Prebuilt installer
cp "${SCRIPT_DIR}/release-install.sh" "${STAGE}/install.sh"
chmod +x "${STAGE}/install.sh"

# ---------------------------------------------------------------------------
# Archive
# ---------------------------------------------------------------------------
ARCHIVE="${DIST_DIR}/calmirror-${VERSION}-macos-arm64.tar.gz"
tar czf "$ARCHIVE" -C "$DIST_DIR" "calmirror-${VERSION}"

echo ""
echo "==> Done: ${ARCHIVE}"
echo "    Contents:"
tar tzf "$ARCHIVE" | sed 's/^/      /'
echo ""
echo "    Pushing tag v${VERSION} on main lets the Release workflow publish this"
echo "    archive as a draft release (see docs/RELEASING.md)."
