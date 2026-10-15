#!/bin/bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export GIT_CONFIG_GLOBAL="$scratch/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_ALLOW_PROTOCOL=file
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture
export GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$scratch/project/scripts" "$scratch/upstream"
cp "$project/scripts/skills.sh" "$scratch/project/scripts/skills.sh"
for spec in \
    AvdLee/Swift-Concurrency-Agent-Skill:skills/swift-concurrency \
    AvdLee/Swift-Testing-Agent-Skill:swift-testing-expert \
    steipete/agent-scripts:skills/swiftui-view-refactor,skills/swiftui-performance-audit; do
    upstream=${spec%%:*}
    repo=${upstream##*/}
    IFS=, read -r -a paths <<< "${spec#*:}"
    git init -q -b main "$scratch/upstream/$repo"
    for path in "${paths[@]}"; do
        mkdir -p "$scratch/upstream/$repo/$path/references"
        printf 'fixture\n' > "$scratch/upstream/$repo/$path/SKILL.md"
        printf 'reference\n' > "$scratch/upstream/$repo/$path/references/example.md"
    done
    printf 'license\n' > "$scratch/upstream/$repo/LICENSE"
    git -C "$scratch/upstream/$repo" add .
    git -C "$scratch/upstream/$repo" commit -qm 'test: seed fixture'
    git config --file "$GIT_CONFIG_GLOBAL" "url.file://$scratch/upstream/$repo.insteadOf" "https://github.com/$upstream.git"
done
bash "$scratch/project/scripts/skills.sh" install
bash "$scratch/project/scripts/skills.sh" check
for name in swiftui-view-refactor swiftui-performance-audit; do
    source="$scratch/project/.skill-sources/agent-scripts/skills/$name"
    for host in .agents .claude; do
        link="$scratch/project/$host/skills/$name"
        [ "$link/SKILL.md" -ef "$source/SKILL.md" ] || { echo "FAIL: shared discovery for $name" >&2; exit 1; }
        [ -f "$link/references/example.md" ] || { echo "FAIL: missing references for $name" >&2; exit 1; }
    done
done
[ -f "$scratch/project/.skill-sources/agent-scripts/LICENSE" ] || { echo 'FAIL: missing agent-scripts license' >&2; exit 1; }
[ "$(awk '$1 == "agent-scripts" {count++} END {print count}' "$scratch/project/skills.lock")" = 1 ] || {
    echo 'FAIL: agent-scripts must have one shared revision' >&2; exit 1;
}
# The lock is a tracked, shared file; mktemp's private 0600 mode must not leak into it.
if [ "$(stat -f %Lp "$scratch/project/skills.lock")" != 644 ]; then
    echo 'FAIL: skills.lock is not world-readable (0644)' >&2
    exit 1
fi
cp "$scratch/project/skills.lock" "$scratch/first.lock"
printf 'new revision\n' >> "$scratch/upstream/Swift-Testing-Agent-Skill/swift-testing-expert/SKILL.md"
git -C "$scratch/upstream/Swift-Testing-Agent-Skill" commit -qam 'test: update fixture'
printf 'new revision\n' >> "$scratch/upstream/agent-scripts/skills/swiftui-view-refactor/SKILL.md"
git -C "$scratch/upstream/agent-scripts" commit -qam 'test: update shared skills'
bash "$scratch/project/scripts/skills.sh" install
cmp "$scratch/first.lock" "$scratch/project/skills.lock"
bash "$scratch/project/scripts/skills.sh" update
if cmp -s "$scratch/first.lock" "$scratch/project/skills.lock"; then
    echo 'FAIL: update did not advance the lock' >&2
    exit 1
fi
bash "$scratch/project/scripts/skills.sh" check
expected=$(git -C "$scratch/upstream/agent-scripts" rev-parse HEAD)
[ "$(awk '$1 == "agent-scripts" {print $2}' "$scratch/project/skills.lock")" = "$expected" ] || {
    echo 'FAIL: shared skills did not advance together' >&2; exit 1;
}
printf 'local edit\n' >> "$scratch/project/.skill-sources/swift-testing-expert/swift-testing-expert/SKILL.md"
if bash "$scratch/project/scripts/skills.sh" update; then
    echo 'FAIL: update accepted local edits' >&2
    exit 1
fi
echo 'PASS: local discovery, pinned reinstall, explicit upgrade, and local-edit protection'
