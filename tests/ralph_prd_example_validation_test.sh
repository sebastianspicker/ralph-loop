#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds jq mktemp

run_example_validation_case() {
  local tmpdir required_defaults_keys required_story_keys
  local allowed_root_keys allowed_story_keys allowed_step_keys
  tmpdir="$(mktemp -d)"

  required_defaults_keys="$(jq -c '.["$defs"].defaults.required // []' "$PRD_SCHEMA_FILE" 2>/dev/null || true)"
  required_story_keys="$(jq -c '.["$defs"].story.required // []' "$PRD_SCHEMA_FILE" 2>/dev/null || true)"
  allowed_root_keys="$(jq -c '.properties | keys // []' "$PRD_SCHEMA_FILE" 2>/dev/null || true)"
  allowed_story_keys="$(jq -c '.["$defs"].story.properties | keys // []' "$PRD_SCHEMA_FILE" 2>/dev/null || true)"
  allowed_step_keys="$(jq -c '.["$defs"].story_step.properties | keys // []' "$PRD_SCHEMA_FILE" 2>/dev/null || true)"

  if [[ -z "$required_defaults_keys" || "$required_defaults_keys" == "null" ]]; then
    fail_case "prd-example-valid" "could not load defaults.required from schema" "" "$tmpdir"
  fi
  if [[ -z "$required_story_keys" || "$required_story_keys" == "null" ]]; then
    fail_case "prd-example-valid" "could not load story.required from schema" "" "$tmpdir"
  fi
  if [[ -z "$allowed_root_keys" || "$allowed_root_keys" == "null" ]]; then
    fail_case "prd-example-valid" "could not load root properties from schema" "" "$tmpdir"
  fi
  if [[ -z "$allowed_story_keys" || "$allowed_story_keys" == "null" ]]; then
    fail_case "prd-example-valid" "could not load story properties from schema" "" "$tmpdir"
  fi
  if [[ -z "$allowed_step_keys" || "$allowed_step_keys" == "null" ]]; then
    fail_case "prd-example-valid" "could not load story_step properties from schema" "" "$tmpdir"
  fi

  if ! jq -e \
    --argjson supported_modes '["audit","linting","fixing"]' \
    --arg created_regex '^Created\s+`?[^`\s]+`?(\s+.*)?$' \
    --argjson required_defaults_keys "$required_defaults_keys" \
    --argjson required_story_keys "$required_story_keys" \
    --argjson allowed_root_keys "$allowed_root_keys" \
    --argjson allowed_story_keys "$allowed_story_keys" \
    --argjson allowed_step_keys "$allowed_step_keys" \
    -f "$PRD_VALIDATE_FILTER_FILE" \
    "$ROOT_DIR/prd.json.example" > "$tmpdir/validate.log" 2>&1; then
    fail_case "prd-example-valid" "prd.json.example failed runtime validation filter" "$tmpdir/validate.log" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [prd-example-valid]\n'
}

run_example_validation_case
printf 'All PRD example validation tests passed.\n'
