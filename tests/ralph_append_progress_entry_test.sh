#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds mktemp grep

APPEND_SCRIPT="$ROOT_DIR/scripts/append_progress_entry.sh"

run_case() {
  local tmpdir out_file rc
  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/progress.log.md"

  set +e
  "$APPEND_SCRIPT" --out "$out_file" --story AUDIT-001 --mode audit --title "Audit Title" --report ".codex/ralph-audit/audit/AUDIT-001.md" > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "append-progress-entry" "first append should succeed, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if [[ ! -f "$out_file" ]]; then
    fail_case "append-progress-entry" "expected output file to be created" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'AUDIT-001' "$out_file"; then
    fail_case "append-progress-entry" "missing first story entry" "$out_file" "$tmpdir"
  fi

  set +e
  "$APPEND_SCRIPT" --out "$out_file" --story FIX-001 --mode fixing --title "Fix Title" --report ".codex/ralph-audit/audit/FIX-001.md" > "$tmpdir/out2.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "append-progress-entry" "second append should succeed, got rc=$rc" "$tmpdir/out2.log" "$tmpdir"
  fi
  if [[ "$(grep -c '^### .* UTC | ' "$out_file")" -ne 2 ]]; then
    fail_case "append-progress-entry" "expected two appended entries" "$out_file" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [append-progress-entry]\n'
}

run_case
printf 'All append progress entry tests passed.\n'
