#!/bin/bash
# Check the user-facing CLI help/version snapshots and JSON rule-list shape.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SNAPSHOT_DIR="${PROJECT_DIR}/Tests/CLIContracts/Snapshots"
BINARY="${CALMIRROR_CLI_BINARY:-${PROJECT_DIR}/.build/release/calmirror}"

if [[ ! -x "$BINARY" ]]; then
    echo "Building release CLI for contract checks..."
    swift build -c release --package-path "$PROJECT_DIR"
fi

check_snapshot() {
    local snapshot="$1"
    shift
    local actual
    actual="$(mktemp)"
    if ! "$BINARY" "$@" > "$actual"; then
        rm -f "$actual"
        echo "CLI contract command failed: calmirror $*" >&2
        return 1
    fi
    if ! cmp -s "$SNAPSHOT_DIR/$snapshot" "$actual"; then
        diff -u "$SNAPSHOT_DIR/$snapshot" "$actual" || true
        rm -f "$actual"
        echo "CLI output changed: $snapshot" >&2
        return 1
    fi
    rm -f "$actual"
}

check_snapshot root-help.txt --help
check_snapshot version.txt version
check_snapshot calendars-help.txt calendars --help
check_snapshot rules-help.txt rules --help
check_snapshot sync-help.txt sync --help
check_snapshot logs-help.txt logs --help
check_snapshot status-help.txt status --help
check_snapshot agent-help.txt agent --help

echo "CLI contracts passed (help/version snapshots)."
