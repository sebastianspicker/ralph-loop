#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds mktemp grep

setup_repo() {
  local repo_dir="$1"
  prepare_fixture "$repo_dir"
}

run_default_tool_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo"
  setup_repo "$tmpdir/repo"

  set +e
  (
    cd "$tmpdir/repo"
    unset RALPH_TOOL
    ./ralph.sh 0
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "tool-default" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'tool=codex' "$tmpdir/out.log"; then
    fail_case "tool-default" "expected tool=codex in output" "$tmpdir/out.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [tool-default]\n'
}

run_tool_alias_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo"
  setup_repo "$tmpdir/repo"

  set +e
  (
    cd "$tmpdir/repo"
    RALPH_TOOL=codex-cli ./ralph.sh 0
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "tool-alias" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'tool=codex' "$tmpdir/out.log"; then
    fail_case "tool-alias" "expected normalized tool=codex in output" "$tmpdir/out.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [tool-alias]\n'
}

run_cli_overrides_env_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo"
  setup_repo "$tmpdir/repo"

  set +e
  (
    cd "$tmpdir/repo"
    RALPH_TOOL=bad ./ralph.sh --tool codex 0
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "tool-cli-overrides-env" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'tool=codex' "$tmpdir/out.log"; then
    fail_case "tool-cli-overrides-env" "expected tool=codex after CLI override" "$tmpdir/out.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [tool-cli-overrides-env]\n'
}

run_cli_equals_syntax_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo"
  setup_repo "$tmpdir/repo"

  set +e
  (
    cd "$tmpdir/repo"
    ./ralph.sh --tool=codex 0
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "tool-cli-equals" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'tool=codex' "$tmpdir/out.log"; then
    fail_case "tool-cli-equals" "expected tool=codex with --tool=codex syntax" "$tmpdir/out.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [tool-cli-equals]\n'
}

run_invalid_tool_case() {
  local tmpdir rc
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/repo"
  setup_repo "$tmpdir/repo"

  set +e
  (
    cd "$tmpdir/repo"
    RALPH_TOOL=invalid ./ralph.sh 0
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    fail_case "tool-invalid" "expected failure for invalid tool" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'Tool must be one of: codex' "$tmpdir/out.log"; then
    fail_case "tool-invalid" "missing invalid tool error message" "$tmpdir/out.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [tool-invalid]\n'
}

run_default_tool_case
run_tool_alias_case
run_cli_overrides_env_case
run_cli_equals_syntax_case
run_invalid_tool_case
printf 'All tool selection tests passed.\n'
