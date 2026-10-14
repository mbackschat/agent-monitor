#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-check}
case "$mode" in
    update|check) ;;
    *) echo 'Usage: bash scripts/preview.sh [update|check]' >&2; exit 2 ;;
esac

cd "$root"
swift run monitor-preview "$mode" "$root/docs/assets/tui-preview.svg"
