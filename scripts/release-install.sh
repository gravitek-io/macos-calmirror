#!/bin/bash
# install.sh — Install CalMirror from pre-built release archive
#
# Installs the GUI app, CLI binary, and background sync agent.
# Run from the extracted release directory.
#
# Usage:
#   ./install.sh          # Install everything
#   ./install.sh --app    # Install GUI app only
#   ./install.sh --cli    # Install CLI + launchd agent only
#
# Installed locations:
#   GUI app:       /Applications/CalMirror.app
#   CLI binary:    /usr/local/bin/calmirror
#   launchd agent: ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CalMirror"
APP_DEST="/Applications/${APP_NAME}.app"
CLI_DEST="/usr/local/bin/calmirror"
AGENT_LABEL="com.gravitek.calmirror.sync"
AGENT_DEST="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"

# Verify we're running from the release archive
if [[ ! -d "${SCRIPT_DIR}/CalMirror.app" ]] || [[ ! -f "${SCRIPT_DIR}/calmirror" ]]; then
    echo "error: CalMirror.app or calmirror binary not found in $(pwd)."
    echo "       Run this script from the extracted release directory."
    exit 1
fi

# Determine what to install
INSTALL_APP=true
INSTALL_CLI=true
if [[ "${1:-}" == "--app" ]]; then
    INSTALL_CLI=false
elif [[ "${1:-}" == "--cli" ]]; then
    INSTALL_APP=false
fi

# ---------------------------------------------------------------------------
# GUI App Bundle
# ---------------------------------------------------------------------------
if $INSTALL_APP; then
    echo "==> Installing ${APP_NAME}.app..."

    if [[ -d "$APP_DEST" ]]; then
        echo "    Removing existing ${APP_DEST}..."
        rm -rf "$APP_DEST"
    fi

    cp -R "${SCRIPT_DIR}/CalMirror.app" "$APP_DEST"
    echo "    Installed: ${APP_DEST}"
fi

# ---------------------------------------------------------------------------
# CLI Binary
# ---------------------------------------------------------------------------
if $INSTALL_CLI; then
    echo ""
    echo "==> Installing CLI binary..."

    if [[ ! -d /usr/local/bin ]]; then
        echo "    Creating /usr/local/bin (requires sudo)..."
        sudo mkdir -p /usr/local/bin
    fi

    if [[ -w /usr/local/bin ]]; then
        cp "${SCRIPT_DIR}/calmirror" "$CLI_DEST"
    else
        echo "    Writing to /usr/local/bin requires sudo..."
        sudo cp "${SCRIPT_DIR}/calmirror" "$CLI_DEST"
    fi

    echo "    Installed: ${CLI_DEST}"

    # -------------------------------------------------------------------
    # Launchd Agent
    # -------------------------------------------------------------------
    echo ""
    echo "==> Installing launchd agent..."

    if launchctl list "$AGENT_LABEL" &>/dev/null; then
        echo "    Unloading existing agent..."
        launchctl bootout "gui/$(id -u)/${AGENT_LABEL}" 2>/dev/null || true
    fi

    mkdir -p "$HOME/Library/LaunchAgents"

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
