#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-install}
case "$mode" in
    install|update|check) ;;
    *) echo 'Usage: bash scripts/skills.sh [install|update|check]' >&2; exit 2 ;;
esac

fail() { echo "$*" >&2; exit 1; }
specs=(
    'swift-concurrency:Swift-Concurrency-Agent-Skill:skills/swift-concurrency'
    'swift-testing-expert:Swift-Testing-Agent-Skill:swift-testing-expert'
)

# Preflight both repositories before an upgrade so local skill edits are never discarded.
for spec in "${specs[@]}"; do
    name=${spec%%:*}
    source="$root/.skill-sources/$name"
    if [ -e "$source" ]; then
        [ -d "$source/.git" ] || fail "Not a managed skill checkout: $source"
        [ -z "$(git -C "$source" status --porcelain)" ] || fail "Local edits in $source; preserve them before updating."
    fi
done

if [ "$mode" != check ]; then
    mkdir -p "$root/.skill-sources" "$root/.agents/skills" "$root/.claude/skills"
    pending=$(mktemp "$root/.skill-sources/lock.XXXXXX")
    trap 'rm -f "$pending"' EXIT
fi

for spec in "${specs[@]}"; do
    name=${spec%%:*}
    remainder=${spec#*:}
    repo=${remainder%%:*}
    path=${remainder#*:}
    source="$root/.skill-sources/$name"
    url="https://github.com/AvdLee/$repo.git"
    revision=''
    if [ -f "$root/skills.lock" ]; then
        revision=$(awk -v name="$name" '$1 == name {print $2}' "$root/skills.lock")
    fi
    if [ "$mode" != check ]; then
        if [ ! -d "$source/.git" ]; then
            git clone --quiet --no-checkout "$url" "$source"
        fi
        [ "$(git -C "$source" config --get remote.origin.url)" = "$url" ] || fail "Unexpected origin in $source"
        if [ "$mode" = update ] || [ -z "$revision" ]; then
            git -C "$source" fetch --quiet origin main
            revision=$(git -C "$source" rev-parse FETCH_HEAD)
        elif ! git -C "$source" cat-file -e "$revision^{commit}" 2>/dev/null; then
            git -C "$source" fetch --quiet origin "$revision"
        fi
        git -C "$source" checkout --quiet --detach "$revision"
    fi
    [ -n "$revision" ] || fail "No locked revision for $name; run install."
    [ "$(git -C "$source" rev-parse HEAD)" = "$revision" ] || fail "Revision mismatch for $name"
    [ -f "$source/$path/SKILL.md" ] || fail "Missing SKILL.md for $name"
    for host in .agents .claude; do
        link="$root/$host/skills/$name"
        target="../../.skill-sources/$name/$path"
        if [ -L "$link" ]; then
            [ "$(readlink "$link")" = "$target" ] || fail "Unexpected symlink: $link"
        elif [ -e "$link" ]; then
            fail "Refusing to replace existing skill: $link"
        elif [ "$mode" != check ]; then
            ln -s "$target" "$link"
        fi
        [ "$link/SKILL.md" -ef "$source/$path/SKILL.md" ] || fail "Skill discovery failed: $link"
    done
    if [ "$mode" != check ]; then
        printf '%s %s\n' "$name" "$revision" >> "$pending"
    fi
    printf '%s %s\n' "$name" "$revision"
done

if [ "$mode" != check ]; then
    chmod 644 "$pending"
    mv "$pending" "$root/skills.lock"
fi
