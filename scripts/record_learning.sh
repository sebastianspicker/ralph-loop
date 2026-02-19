#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/parse_opts.sh
source "$SCRIPT_DIR/lib/parse_opts.sh"

OUT_FILE="$ROOT_DIR/learnings.md"
STORY_ID=""
NOTE=""
FILES=""

usage() {
  cat <<'USAGE'
Usage: ./scripts/record_learning.sh --story <id> --note <text> [--files <csv>] [--out <path>]

Append one structured learning entry to learnings.md.

Options:
  --story <id>    Story identifier (e.g. AUDIT-001, FIX-002)
  --note <text>   Reusable learning note
  --files <csv>   Optional comma-separated related files
  --out <path>    Optional output file path (default: ./learnings.md)
  -h, --help      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --story)
      [[ $# -ge 2 ]] || usage_exit "missing value for --story"
      STORY_ID="$2"
      shift 2
      ;;
    --note)
      [[ $# -ge 2 ]] || usage_exit "missing value for --note"
      NOTE="$2"
      shift 2
      ;;
    --files)
      [[ $# -ge 2 ]] || usage_exit "missing value for --files"
      FILES="$2"
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
[[ -n "$NOTE" ]] || usage_exit "missing required --note"

OUT_DIR="$(dirname "$OUT_FILE")"
mkdir -p "$OUT_DIR"

if [[ ! -f "$OUT_FILE" ]]; then
  cat > "$OUT_FILE" <<'EOF'
# Ralph Learnings (Append-Only)

This file stores durable, reusable learnings across iterations.
Do not rewrite history; append new entries only.

## Codebase Patterns

- Add stable cross-story patterns here (short bullets).

## Learning Log

<!-- Append entries below this line -->
EOF
fi

tmp_file="$(mktemp "${OUT_FILE}.XXXXXX.tmp")"
trap 'rm -f "$tmp_file"' EXIT

cat "$OUT_FILE" > "$tmp_file"
{
  printf '\n### %s UTC | %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$STORY_ID"
  printf -- '- Note: %s\n' "$NOTE"
  if [[ -n "$FILES" ]]; then
    printf -- '- Files: %s\n' "$FILES"
  fi
} >> "$tmp_file"

mv "$tmp_file" "$OUT_FILE"

printf 'Recorded learning in %s\n' "$OUT_FILE"
