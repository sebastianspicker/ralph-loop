#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds mktemp grep

RECORD_SCRIPT="$ROOT_DIR/scripts/record_learning.sh"

run_create_and_append_case() {
  local tmpdir out_file rc
  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/state/learnings.md"

  set +e
  "$RECORD_SCRIPT" --out "$out_file" --story AUDIT-001 --note "Prefer deterministic sorting" --files "lib/ralph/prd.sh,tests/ralph_validation_test.sh" > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "record-learning-create" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if [[ ! -f "$out_file" ]]; then
    fail_case "record-learning-create" "expected learnings file to be created" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q '^### .* UTC | AUDIT-001$' "$out_file"; then
    fail_case "record-learning-create" "missing first entry header" "$out_file" "$tmpdir"
  fi
  if ! grep -q -- '- Note: Prefer deterministic sorting' "$out_file"; then
    fail_case "record-learning-create" "missing first entry note" "$out_file" "$tmpdir"
  fi

  set +e
  "$RECORD_SCRIPT" --out "$out_file" --story FIX-002 --note "Guard report path overwrite" > "$tmpdir/out2.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "record-learning-create" "expected second append success, got rc=$rc" "$tmpdir/out2.log" "$tmpdir"
  fi
  if [[ "$(grep -c '^### .* UTC | ' "$out_file")" -ne 2 ]]; then
    fail_case "record-learning-create" "expected two learning entries after append" "$out_file" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [record-learning-create]\n'
}

run_validation_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"

  set +e
  "$RECORD_SCRIPT" --note "Missing story should fail" > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    fail_case "record-learning-validation" "expected failure for missing --story" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'missing required --story' "$tmpdir/out.log"; then
    fail_case "record-learning-validation" "expected missing story error" "$tmpdir/out.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [record-learning-validation]\n'
}

run_create_and_append_case
run_validation_case
printf 'All record learning tests passed.\n'
