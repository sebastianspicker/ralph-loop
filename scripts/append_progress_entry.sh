#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/parse_opts.sh
source "$SCRIPT_DIR/lib/parse_opts.sh"

OUT_FILE="$ROOT_DIR/progress.log.md"
STORY_ID=""
MODE=""
TITLE=""
REPORT=""

usage() {
  cat <<'USAGE'
Usage: ./scripts/append_progress_entry.sh --story <id> --mode <mode> --title <title> --report <path> [--out <file>]

Append one structured progress entry to progress.log.md.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --story)
      [[ $# -ge 2 ]] || usage_exit "missing value for --story"
      STORY_ID="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || usage_exit "missing value for --mode"
      MODE="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || usage_exit "missing value for --title"
      TITLE="$2"
      shift 2
      ;;
    --report)
      [[ $# -ge 2 ]] || usage_exit "missing value for --report"
      REPORT="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || usage_exit "missing value for --out"
      OUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      unknown_opt "$1"
      ;;
  esac
done

[[ -n "$STORY_ID" ]] || usage_exit "missing required --story"
[[ -n "$MODE" ]] || usage_exit "missing required --mode"
[[ -n "$TITLE" ]] || usage_exit "missing required --title"
[[ -n "$REPORT" ]] || usage_exit "missing required --report"

mkdir -p "$(dirname "$OUT_FILE")"
if [[ ! -f "$OUT_FILE" ]]; then
  cat > "$OUT_FILE" <<'EOF'
# Ralph Progress Log (Append-Only)

## Codebase Patterns

- Add reusable patterns here over time.

## Entries
EOF
fi

tmp_file="$(mktemp "${OUT_FILE}.XXXXXX.tmp")"
trap 'rm -f "$tmp_file"' EXIT

cat "$OUT_FILE" > "$tmp_file"
{
  printf '\n### %s UTC | %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$STORY_ID"
  printf -- '- Mode: %s\n' "$MODE"
  printf -- '- Title: %s\n' "$TITLE"
  printf -- '- Report: %s\n' "$REPORT"
} >> "$tmp_file"

mv "$tmp_file" "$OUT_FILE"
