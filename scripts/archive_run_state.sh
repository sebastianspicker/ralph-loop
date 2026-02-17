#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ARCHIVE_ROOT="$ROOT_DIR/archive"
REASON=""
LABEL=""
FORCE="false"

usage() {
  cat <<'USAGE'
Usage: ./scripts/archive_run_state.sh [--reason <text>] [--label <slug>] [--source-root <dir>] [--archive-root <dir>] [--force]

Archive current Ralph run state into a timestamped folder.

Archived when present:
  - prd.json
  - progress.txt
  - learnings.md
  - defaults.report_dir from prd.json

Options:
  --reason <text>       Optional reason metadata
  --label <slug>        Optional folder label suffix
  --source-root <dir>   Root containing prd/progress/learnings (default: template root)
  --archive-root <dir>  Archive root directory (default: ./archive)
  --force               Allow writing into an existing target directory
  -h, --help            Show this help
USAGE
}

slugify() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$s" ]] || s="run"
  printf '%s' "$s"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-root)
      [[ $# -ge 2 ]] || { printf 'missing value for --source-root\n' >&2; exit 1; }
      ROOT_DIR="$2"
      shift 2
      ;;
    --reason)
      [[ $# -ge 2 ]] || { printf 'missing value for --reason\n' >&2; exit 1; }
      REASON="$2"
      shift 2
      ;;
    --label)
      [[ $# -ge 2 ]] || { printf 'missing value for --label\n' >&2; exit 1; }
      LABEL="$2"
      shift 2
      ;;
    --archive-root)
      [[ $# -ge 2 ]] || { printf 'missing value for --archive-root\n' >&2; exit 1; }
      ARCHIVE_ROOT="$2"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
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

if [[ ! -d "$ROOT_DIR" ]]; then
  printf 'source root does not exist: %s\n' "$ROOT_DIR" >&2
  exit 1
fi
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
label_slug=""

if [[ -n "$LABEL" ]]; then
  label_slug="$(slugify "$LABEL")"
elif [[ -f "$ROOT_DIR/prd.json" ]] && command -v jq >/dev/null 2>&1; then
  detected_label="$(jq -r '.project // ""' "$ROOT_DIR/prd.json" 2>/dev/null || true)"
  if [[ -n "$detected_label" && "$detected_label" != "null" ]]; then
    label_slug="$(slugify "$detected_label")"
  fi
fi

if [[ -n "$label_slug" ]]; then
  target_dir="$ARCHIVE_ROOT/$timestamp-$label_slug"
else
  target_dir="$ARCHIVE_ROOT/$timestamp-run"
fi

if [[ -e "$target_dir" ]]; then
  if [[ "$FORCE" != "true" ]]; then
    printf 'archive target already exists: %s (use --force)\n' "$target_dir" >&2
    exit 1
  fi
  rm -rf "$target_dir"
fi

mkdir -p "$target_dir"

copy_if_present() {
  local rel="$1"
  local src="$ROOT_DIR/$rel"
  local dst="$target_dir/$rel"
  if [[ -e "$src" || -L "$src" ]]; then
    if [[ -d "$src" && ! -L "$src" ]]; then
      mkdir -p "$dst"
      cp -R "$src/." "$dst"
    else
      mkdir -p "$(dirname "$dst")"
      cp -R "$src" "$dst"
    fi
  fi
}

copy_if_present "prd.json"
copy_if_present "progress.txt"
copy_if_present "learnings.md"

if [[ -f "$ROOT_DIR/prd.json" ]] && command -v jq >/dev/null 2>&1; then
  report_dir="$(jq -r '.defaults.report_dir // ""' "$ROOT_DIR/prd.json" 2>/dev/null || true)"
  report_dir="${report_dir#./}"
  report_dir="${report_dir%/}"
  if [[ -n "$report_dir" && "$report_dir" != "null" ]]; then
    copy_if_present "$report_dir"
  fi
fi

{
  printf 'archived_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [[ -n "$REASON" ]]; then
    printf 'reason=%s\n' "$REASON"
  fi
  printf 'source_root=%s\n' "$ROOT_DIR"
} > "$target_dir/archive.meta"

printf 'Archived run state to %s\n' "$target_dir"
