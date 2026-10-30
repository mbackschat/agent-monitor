#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-build}
case "$mode" in
    build|run) ;;
    *) echo 'Usage: bash scripts/menubar.sh [build|run]' >&2; exit 2 ;;
esac

cd "$root"
python3 scripts/clean-build.py check
configuration=${AGENT_MONITOR_BUILD_CONFIGURATION:-release}
products_link=$(readlink .build/debug || readlink .build/release || true)
case "$products_link" in
    *-apple-macosx/*) default_build_system=native ;;
    *) default_build_system=swiftbuild ;;
esac
build_system=${AGENT_MONITOR_BUILD_SYSTEM:-$default_build_system}
case "$configuration" in
    debug|release) ;;
    *) echo 'AGENT_MONITOR_BUILD_CONFIGURATION must be debug or release' >&2; exit 2 ;;
esac
build_flags=()
if [[ "$configuration" == release ]]; then build_flags=(-debug-info-format none); fi
swift build --build-system "$build_system" -j "${AGENT_MONITOR_BUILD_JOBS:-2}" --disable-sandbox -c "$configuration" "${build_flags[@]}" --product agent-monitor-menubar
products=$(swift build --build-system "$build_system" --disable-sandbox -c "$configuration" --show-bin-path)
app="$root/.build/Agent Monitor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/agent-monitor-menubar" "$app/Contents/MacOS/agent-monitor-menubar"
cp -R "$products/AgentMonitor_AgentMonitorPresentation.bundle" "$app/Contents/Resources/"
cp -R "$products/AgentMonitor_AgentMonitorMenuBar.bundle" "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
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
python3 scripts/clean-build.py check
echo "$app"
if [[ "$mode" == run ]]; then
    open "$app"
fi
