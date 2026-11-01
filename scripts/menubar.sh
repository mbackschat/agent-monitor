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
stage=$(mktemp -d "$root/.build/menubar-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
python3 scripts/macos_bundle.py "$products" "$stage/Agent Monitor.app"
codesign --force --sign - "$stage/Agent Monitor.app"
codesign --verify --deep --strict "$stage/Agent Monitor.app"
rm -rf "$app"
mv "$stage/Agent Monitor.app" "$app"
python3 scripts/clean-build.py check
echo "$app"
if [[ "$mode" == run ]]; then
    open "$app"
fi
