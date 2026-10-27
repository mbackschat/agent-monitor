#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
demo_bundle="$PWD/.build/SwiftUI Table Demo.app"
mkdir -p "$demo_bundle/Contents/MacOS" .build/module-cache
swiftc -parse-as-library -swift-version 6 -module-cache-path .build/module-cache \
    Tools/SwiftUITableProbe/Demo.swift -o "$demo_bundle/Contents/MacOS/SwiftUITableDemo"
cat > "$demo_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SwiftUITableDemo</string>
<key>CFBundleIdentifier</key><string>local.agent-monitor.swiftui-table-demo</string>
<key>CFBundleName</key><string>SwiftUI Table Demo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf '%s\n' "$demo_bundle"
