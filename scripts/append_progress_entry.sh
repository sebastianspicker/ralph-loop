#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
      [[ $# -ge 2 ]] || { printf 'missing value for --story\n' >&2; exit 1; }
      STORY_ID="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || { printf 'missing value for --mode\n' >&2; exit 1; }
      MODE="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || { printf 'missing value for --title\n' >&2; exit 1; }
      TITLE="$2"
      shift 2
      ;;
    --report)
      [[ $# -ge 2 ]] || { printf 'missing value for --report\n' >&2; exit 1; }
      REPORT="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || { printf 'missing value for --out\n' >&2; exit 1; }
      OUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$STORY_ID" ]] || { printf 'missing required --story\n' >&2; exit 1; }
[[ -n "$MODE" ]] || { printf 'missing required --mode\n' >&2; exit 1; }
[[ -n "$TITLE" ]] || { printf 'missing required --title\n' >&2; exit 1; }
[[ -n "$REPORT" ]] || { printf 'missing required --report\n' >&2; exit 1; }

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
