#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/parse_opts.sh
source "$SCRIPT_DIR/lib/parse_opts.sh"

ROOT=""

usage() {
  cat <<'USAGE'
Usage: ./scripts/sync_agents_from_learnings.sh [--root <dir>]

Append latest learning note to AGENTS.md under "Learned Patterns" section if missing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || usage_exit "missing value for --root"
      ROOT="$2"
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

if [[ -z "$ROOT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

LEARNINGS="$ROOT/learnings.md"
AGENTS="$ROOT/AGENTS.md"

[[ -f "$LEARNINGS" ]] || exit 0
[[ -f "$AGENTS" ]] || exit 0

latest_note="$(
  awk '
    /^- Note: / { note=$0 }
    END { if (note != "") print note }
  ' "$LEARNINGS"
)"

[[ -n "$latest_note" ]] || exit 0

if awk -v note="$latest_note" '
  $0 == note { found=1; exit }
  END { exit(found ? 0 : 1) }
' "$AGENTS"; then
  exit 0
fi

tmp_file="$(mktemp "${AGENTS}.XXXXXX.tmp")"
trap 'rm -f "$tmp_file"' EXIT

if grep -q '^## Learned Patterns$' "$AGENTS"; then
  awk -v note="$latest_note" '
    { print }
    /^## Learned Patterns$/ { print ""; print note; inserted=1 }
    END {
      if (!inserted) {
        print "";
        print "## Learned Patterns";
        print "";
        print note;
      }
    }
  ' "$AGENTS" > "$tmp_file"
else
  cat "$AGENTS" > "$tmp_file"
  {
    printf '\n## Learned Patterns\n\n'
    printf '%s\n' "$latest_note"
  } >> "$tmp_file"
fi

mv "$tmp_file" "$AGENTS"
