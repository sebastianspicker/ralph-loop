#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FORCE="false"
WITH_TESTS="false"
TARGET_REPO=""

usage() {
  cat <<'USAGE'
Usage: ./scripts/bootstrap_embedded.sh [--force] [--with-tests] <target-repo>

Copies the golden ralph-audit template into:
  <target-repo>/.codex/ralph-audit

Options:
  --force       Overwrite existing destination contents.
  --with-tests  Also copy template regression tests.
  -h, --help    Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE="true"
      shift
      ;;
    --with-tests)
      WITH_TESTS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$TARGET_REPO" ]]; then
        TARGET_REPO="$1"
        shift
      else
        printf 'unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$TARGET_REPO" ]]; then
  usage >&2
  exit 1
fi
if [[ ! -d "$TARGET_REPO" ]]; then
  printf 'target repo does not exist: %s\n' "$TARGET_REPO" >&2
  exit 1
fi

TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"
DEST="$TARGET_REPO/.codex/ralph-audit"

if [[ -e "$DEST" && "$FORCE" != "true" ]]; then
  printf 'destination already exists: %s (use --force to overwrite)\n' "$DEST" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/lib/ralph" "$DEST/scripts" "$DEST/docs" "$DEST/skills/prd" "$DEST/skills/ralph"

copy_file() {
  local rel="$1"
  local src="$TEMPLATE_ROOT/$rel"
  local dst="$DEST/$rel"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

copy_file "ralph.sh"
copy_file "CODEX.md"
copy_file "AGENTS.md"
copy_file "README.md"
copy_file "CONTRIBUTING.md"
copy_file "SECURITY.md"
copy_file "SKILL.md"
copy_file "LICENSE"
copy_file "learnings.md"
copy_file "progress.log.md"
copy_file "prd.json.example"
copy_file "prd.schema.json"
copy_file "prd.validate.jq"
copy_file "scripts/generate_progress.sh"
copy_file "scripts/record_learning.sh"
copy_file "scripts/archive_run_state.sh"
copy_file "scripts/append_progress_entry.sh"
copy_file "scripts/sync_agents_from_learnings.sh"
copy_file "skills/prd/SKILL.md"
copy_file "skills/ralph/SKILL.md"

for doc in "$TEMPLATE_ROOT"/docs/*.md; do
  copy_file "docs/$(basename "$doc")"
done

for mod in "$TEMPLATE_ROOT"/lib/ralph/*.sh; do
  cp "$mod" "$DEST/lib/ralph/"
done

if [[ "$WITH_TESTS" == "true" ]]; then
  mkdir -p "$DEST/tests/lib"
  cp "$TEMPLATE_ROOT"/tests/*.sh "$DEST/tests/"
  cp "$TEMPLATE_ROOT"/tests/lib/*.sh "$DEST/tests/lib/"
fi

chmod +x "$DEST/ralph.sh" "$DEST/scripts/generate_progress.sh" "$DEST/scripts/record_learning.sh" "$DEST/scripts/archive_run_state.sh" "$DEST/scripts/append_progress_entry.sh" "$DEST/scripts/sync_agents_from_learnings.sh"
if [[ "$WITH_TESTS" == "true" ]]; then
  chmod +x "$DEST"/tests/*.sh
fi

printf 'Bootstrapped template to %s\n' "$DEST"
