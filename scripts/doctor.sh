#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
status=0
fail() { printf 'FAIL: %s\n' "$*"; status=1; }

if command -v sw_vers >/dev/null; then
    version=$(sw_vers -productVersion)
    if [ "${version%%.*}" -ge 27 ]; then
        printf 'OK: macOS %s\n' "$version"
    else
        fail 'macOS 27 or later is required.'
    fi
else
    fail 'Development requires macOS 27 or later.'
fi

if version=$(swift --version 2>/dev/null) && [[ "$version" =~ Swift\ version\ ([0-9]+)\.([0-9]+) ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    if (( major > 6 || (major == 6 && minor >= 4) )); then
        printf 'OK: Swift %s.%s\n' "$major" "$minor"
    else
        fail 'Swift 6.4 or later is required; select the Xcode 27 toolchain.'
    fi
else
    fail 'Swift is unavailable; install/select Xcode 27.'
fi

if sdk=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null) && [ "${sdk%%.*}" -ge 27 ]; then
    printf 'OK: macOS SDK %s\n' "$sdk"
else
    fail 'The active toolchain needs the macOS 27 SDK or later.'
fi

if command -v git >/dev/null; then
    echo 'OK: Git is available.'
else
    fail 'Git is required to resolve package dependencies and install optional skills.'
fi

if [ -L "$root/AGENTS.md" ] && [ "$root/AGENTS.md" -ef "$root/CLAUDE.md" ]; then
    echo 'OK: AGENTS.md links to CLAUDE.md.'
else
    fail 'Restore the tracked AGENTS.md symlink to CLAUDE.md.'
fi

if [ -d "$root/.skill-sources" ]; then
    if ! bash "$root/scripts/skills.sh" check; then
        fail 'Optional agent skills need attention; see docs/development.md.'
    fi
else
    echo 'OPTIONAL: Agent skills are absent. To use them, run bash scripts/skills.sh install.'
fi

echo 'Preview generation uses Swift only; no image converter or font installation is needed.'
exit "$status"
