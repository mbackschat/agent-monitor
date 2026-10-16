#!/bin/bash
# Prepare (default) or publish an Agent Monitor release; see docs/releasing.md.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

usage() {
    echo 'usage: bash scripts/release.sh <version> [--publish]' >&2
    exit 64
}
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
version=$1
mode=${2:-prepare}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[ "$mode" = prepare ] || [ "$mode" = --publish ] || usage

tag="v$version"
name="agent-monitor-$version-macos-arm64"
archive="dist/$name.tar.gz"
notes="dist/notes-$version.md"

source_version=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AgentMonitorCore/Version.swift)
[ "$source_version" = "$version" ] \
    || fail "AgentMonitorVersion.current is $source_version; set it to $version and commit first"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then fail "$tag already exists"; fi
[ "$(git branch --show-current)" = main ] || fail 'release from main'
[ -z "$(git status --porcelain)" ] || fail 'commit or stash all changes first'
previous=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)

if [ "$mode" = prepare ]; then
    [ ! -e "$archive" ] || fail "$archive exists; delete dist/$name* to prepare again"
    bash scripts/doctor.sh
    python3 scripts/docs.py check
    swift format lint --strict --recursive Sources Tests Tools Package.swift
    swift test
    bash scripts/preview.sh check
    swift build -c release -debug-info-format none
    python3 scripts/verify-tui-terminal.py .build/release/agent-monitor
    uv run scripts/package-release.py .build/release
    # The archive is stripped; the unstripped executable is needed to symbolicate crash reports.
    cp .build/release/agent-monitor "dist/$name-unstripped"
    if [ ! -f "$notes" ]; then
        {
            printf '# Agent Monitor %s\n\nTODO: one-sentence summary.\n\n## Changed\n\n' "$version"
            git log --no-merges --format='- %s' "${previous:+$previous..}HEAD" | grep -E '^- (feat|fix|perf)' || true
            # shellcheck disable=SC2016 # the backticks are literal Markdown
            printf '\n## Verification\n\n`bash scripts/release.sh %s` passed on macOS %s with %s: tests, formatting, documentation, preview and release terminal checks, and version/help/schema checks of the extracted archive.\n' \
                "$version" "$(sw_vers -productVersion)" "$(swift --version 2>/dev/null | sed -n 's/.*\(Swift version [0-9.]*\).*/\1/p' | head -1)"
        } >"$notes"
    fi
    echo "Prepared $archive."
    echo "Edit $notes (remove every TODO), then run: bash scripts/release.sh $version --publish"
    exit 0
fi

[ -f "$archive" ] && [ -f "$archive.sha256" ] || fail "run bash scripts/release.sh $version first"
if [ ! -f "$notes" ] || grep -q TODO "$notes"; then fail "finish $notes first"; fi
# A push under the wrong identity cannot be taken back; the previous release's author is the reference.
if [ -n "$previous" ]; then
    expected=$(git log -1 --format=%ae "$previous")
    actual=$(git config user.email)
    [ "$actual" = "$expected" ] || fail "git user.email is $actual; $previous was released as $expected"
fi

git tag -a "$tag" -m "Agent Monitor $version"
git push origin main "$tag"
gh release create "$tag" "$archive" "$archive.sha256" --title "Agent Monitor $version" --notes-file "$notes"

check=$(mktemp -d)
trap 'rm -rf "$check"' EXIT
gh release download "$tag" --dir "$check"
(cd "$check" && shasum -a 256 -c "$name.tar.gz.sha256" && tar -xzf "$name.tar.gz")
[ "$("$check/$name/agent-monitor" --version)" = "$version" ] || fail 'downloaded executable reports the wrong version'
"$check/$name/agent-monitor" --json-schema >/dev/null

echo "Published $tag and verified the downloaded archive."
echo "Homebrew tap: url https://github.com/mbackschat/agent-monitor/releases/download/$tag/$name.tar.gz"
echo "              sha256 $(cut -d ' ' -f 1 "$archive.sha256")"
