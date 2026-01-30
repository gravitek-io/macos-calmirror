#!/bin/bash
# install.sh — Build and install CalMirror on macOS
#
# Creates a proper .app bundle for the GUI and installs the CLI binary.
# The .app bundle includes Info.plist with a real bundle identifier,
# which resolves focus/window management issues in SPM executables.
#
# Usage:
#   ./scripts/install.sh          # Install everything
#   ./scripts/install.sh --app    # Install GUI app only
#   ./scripts/install.sh --cli    # Install CLI + launchd agent only
#
# Installed locations:
#   GUI app:       /Applications/CalMirror.app
#   CLI binary:    /usr/local/bin/calmirror
#   launchd agent: ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="CalMirror"
BUNDLE_ID="com.gravitek.calmirror"
APP_DEST="/Applications/${APP_NAME}.app"
CLI_DEST="/usr/local/bin/calmirror"
AGENT_LABEL="com.gravitek.calmirror.sync"
AGENT_DEST="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"

# Determine what to install
INSTALL_APP=true
INSTALL_CLI=true
if [[ "${1:-}" == "--app" ]]; then
    INSTALL_CLI=false
elif [[ "${1:-}" == "--cli" ]]; then
    INSTALL_APP=false
fi

echo "==> Building CalMirror in release mode..."
swift build -c release --package-path "$PROJECT_DIR" 2>&1

BUILD_DIR="$(swift build -c release --package-path "$PROJECT_DIR" --show-bin-path)"

# ---------------------------------------------------------------------------
# GUI App Bundle
# ---------------------------------------------------------------------------
if $INSTALL_APP; then
    echo ""
    echo "==> Packaging ${APP_NAME}.app..."

    # Remove existing app if present
    if [[ -d "$APP_DEST" ]]; then
        echo "    Removing existing ${APP_DEST}..."
        rm -rf "$APP_DEST"
    fi

    # Create .app bundle structure
    mkdir -p "${APP_DEST}/Contents/MacOS"
    mkdir -p "${APP_DEST}/Contents/Resources"

    # Copy binary
    cp "${BUILD_DIR}/CalmMirrorApp" "${APP_DEST}/Contents/MacOS/CalmMirrorApp"

    # Copy Info.plist
    cp "${PROJECT_DIR}/Sources/CalmMirrorApp/Info.plist" "${APP_DEST}/Contents/Info.plist"

    # Ad-hoc code sign so macOS accepts the bundle
    codesign --force --sign - "${APP_DEST}"

    echo "    Installed: ${APP_DEST}"
fi

# ---------------------------------------------------------------------------
# CLI Binary
# ---------------------------------------------------------------------------
if $INSTALL_CLI; then
    echo ""
    echo "==> Installing CLI binary..."

    # Ensure /usr/local/bin exists
    if [[ ! -d /usr/local/bin ]]; then
        echo "    Creating /usr/local/bin (requires sudo)..."
        sudo mkdir -p /usr/local/bin
    fi

    # Copy binary (may require sudo depending on permissions)
    if [[ -w /usr/local/bin ]]; then
        cp "${BUILD_DIR}/calmirror" "$CLI_DEST"
    else
        echo "    Writing to /usr/local/bin requires sudo..."
        sudo cp "${BUILD_DIR}/calmirror" "$CLI_DEST"
    fi

    echo "    Installed: ${CLI_DEST}"

    # -----------------------------------------------------------------------
    # Launchd Agent
    # -----------------------------------------------------------------------
    echo ""
    echo "==> Installing launchd agent..."

    # Unload existing agent if loaded
    if launchctl list "$AGENT_LABEL" &>/dev/null; then
        echo "    Unloading existing agent..."
        launchctl bootout "gui/$(id -u)/${AGENT_LABEL}" 2>/dev/null || true
    fi

    # Create agent directory if needed
    mkdir -p "$HOME/Library/LaunchAgents"

    # Write plist with the correct binary path
    cat > "$AGENT_DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${CLI_DEST}</string>
        <string>sync</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>/tmp/calmirror.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/calmirror.stderr.log</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

    # Load the agent
    launchctl bootstrap "gui/$(id -u)" "$AGENT_DEST"

    echo "    Agent loaded: ${AGENT_LABEL} (sync every 15 min)"
fi

echo ""
echo "==> Installation complete!"
if $INSTALL_APP; then
    echo "    Open CalMirror: open /Applications/CalMirror.app"
fi
if $INSTALL_CLI; then
    echo "    Run sync:       calmirror sync"
    echo "    Check agent:    launchctl list | grep calmirror"
fi
