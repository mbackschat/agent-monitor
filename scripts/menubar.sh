#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-build}
case "$mode" in
    build|run) ;;
    *) echo 'Usage: bash scripts/menubar.sh [build|run]' >&2; exit 2 ;;
esac

cd "$root"
swift build --disable-sandbox --product agent-monitor-menubar
products=$(swift build --disable-sandbox --show-bin-path)
app="$root/.build/Agent Monitor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/agent-monitor-menubar" "$app/Contents/MacOS/agent-monitor-menubar"
cp -R "$products/AgentMonitor_AgentMonitorPresentation.bundle" "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/LICENSE"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as output:
    plistlib.dump({
        "CFBundleExecutable": "agent-monitor-menubar",
        "CFBundleIdentifier": "de.mbackschat.agent-monitor.menubar",
        "CFBundleName": "Agent Monitor",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.0.1",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "27.0",
        "LSUIElement": True,
        "NSAppleEventsUsageDescription": "Select the terminal tab hosting the agent session you choose.",
    }, output)
PY
codesign --force --sign - "$app"
echo "$app"
if [[ "$mode" == run ]]; then
    # Provider transports use /usr/bin/env; Finder's PATH need not contain the user's CLIs.
    open --env "PATH=$PATH" "$app"
fi
