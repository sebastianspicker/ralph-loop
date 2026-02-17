#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds jq mktemp

run_case() {
  local tmpdir total expected_total expected_passed expected_remaining
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo/scripts"

  cp "$PRD_FILE" "$tmpdir/repo/prd.json"
  cp "$ROOT_DIR/scripts/generate_progress.sh" "$tmpdir/repo/scripts/generate_progress.sh"
  chmod +x "$tmpdir/repo/scripts/generate_progress.sh"

  (
    cd "$tmpdir/repo"
    ./scripts/generate_progress.sh ./prd.json ./progress.txt
  ) > "$tmpdir/out.log" 2>&1

  if [[ ! -f "$tmpdir/repo/progress.txt" ]]; then
    fail_case "progress-generation" "progress file not generated" "$tmpdir/out.log" "$tmpdir"
  fi

  expected_total="$(jq '[.stories[]] | length' "$tmpdir/repo/prd.json")"
  expected_passed="$(jq '[.stories[] | select(.passes == true)] | length' "$tmpdir/repo/prd.json")"
  expected_remaining=$((expected_total - expected_passed))

  total="$(awk -F'`' '/^- Stories passed: `/ {print $2}' "$tmpdir/repo/progress.txt")"
  if [[ "$total" != "$expected_passed/$expected_total" ]]; then
    fail_case "progress-generation" "stories passed snapshot mismatch: got=$total expected=$expected_passed/$expected_total" "$tmpdir/repo/progress.txt" "$tmpdir"
  fi
  if ! grep -q "^- Remaining: \`$expected_remaining\`$" "$tmpdir/repo/progress.txt"; then
    fail_case "progress-generation" "remaining snapshot mismatch" "$tmpdir/repo/progress.txt" "$tmpdir"
  fi

  if grep -q '^Last updated:' "$tmpdir/repo/progress.txt"; then
    fail_case "progress-generation" "found stale manual Last updated marker" "$tmpdir/repo/progress.txt" "$tmpdir"
  fi
  if grep -q '^## Template Upgrade Progress' "$tmpdir/repo/progress.txt"; then
    fail_case "progress-generation" "manual checklist section should not be in generated progress file" "$tmpdir/repo/progress.txt" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [progress-generation]\n'
}

run_custom_paths_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo/scripts" "$tmpdir/repo/data"

  cp "$PRD_FILE" "$tmpdir/repo/data/prd.copy.json"
  cp "$ROOT_DIR/scripts/generate_progress.sh" "$tmpdir/repo/scripts/generate_progress.sh"
  chmod +x "$tmpdir/repo/scripts/generate_progress.sh"

  set +e
  (
    cd "$tmpdir/repo"
    ./scripts/generate_progress.sh ./data/prd.copy.json ./state/progress/progress.txt
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "progress-generation-custom-paths" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi

  if [[ ! -f "$tmpdir/repo/state/progress/progress.txt" ]]; then
    fail_case "progress-generation-custom-paths" "progress file not generated in nested output dir" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q "^Source of truth: \`./data/prd.copy.json\` (\`stories\\[\\].passes\`).$" "$tmpdir/repo/state/progress/progress.txt"; then
    fail_case "progress-generation-custom-paths" "source-of-truth path label mismatch" "$tmpdir/repo/state/progress/progress.txt" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [progress-generation-custom-paths]\n'
}

run_case
run_custom_paths_case
printf 'All progress generation tests passed.\n'
