# shellcheck shell=bash
# Shared PRD schema + jq filter validation. Used by lib/ralph/config.sh and tests.
# Call validate_prd_with_jq with: prd_file, schema_file, filter_file, supported_modes_json, created_regex.
# Returns 0 on success, 1 on failure (caller is responsible for fail/exit).

validate_prd_with_jq() {
  local prd_file="$1"
  local schema_file="$2"
  local filter_file="$3"
  local supported_modes_json="$4"
  local created_regex="$5"
  local required_defaults_keys required_story_keys
  local allowed_root_keys allowed_story_keys allowed_step_keys

  [[ -f "$prd_file" ]] || return 1
  [[ -f "$schema_file" ]] || return 1
  [[ -f "$filter_file" ]] || return 1

  required_defaults_keys="$(jq -c '."$defs".defaults.required // []' "$schema_file" 2>/dev/null || true)"
  required_story_keys="$(jq -c '."$defs".story.required // []' "$schema_file" 2>/dev/null || true)"
  allowed_root_keys="$(jq -c '.properties | keys // []' "$schema_file" 2>/dev/null || true)"
  allowed_story_keys="$(jq -c '."$defs".story.properties | keys // []' "$schema_file" 2>/dev/null || true)"
  allowed_step_keys="$(jq -c '."$defs".story_step.properties | keys // []' "$schema_file" 2>/dev/null || true)"

  [[ -n "$required_defaults_keys" && "$required_defaults_keys" != "null" ]] || return 1
  [[ -n "$required_story_keys" && "$required_story_keys" != "null" ]] || return 1
  [[ -n "$allowed_root_keys" && "$allowed_root_keys" != "null" ]] || return 1
  [[ -n "$allowed_story_keys" && "$allowed_story_keys" != "null" ]] || return 1
  [[ -n "$allowed_step_keys" && "$allowed_step_keys" != "null" ]] || return 1

  jq -e \
    --argjson supported_modes "$supported_modes_json" \
    --arg created_regex "$created_regex" \
    --argjson required_defaults_keys "$required_defaults_keys" \
    --argjson required_story_keys "$required_story_keys" \
    --argjson allowed_root_keys "$allowed_root_keys" \
    --argjson allowed_story_keys "$allowed_story_keys" \
    --argjson allowed_step_keys "$allowed_step_keys" \
    -f "$filter_file" \
    "$prd_file" >/dev/null
}
