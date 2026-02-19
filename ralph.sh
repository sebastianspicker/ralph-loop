#!/usr/bin/env bash
# shellcheck disable=SC2034
# Ralph Audit Loop (golden reference template)
#
# Usage examples:
#   MODE=audit   ./ralph.sh 20
#   MODE=linting ./ralph.sh 10
#   MODE=fixing  ./ralph.sh 10
#   MODE=audit   ./.codex/ralph-audit/ralph.sh 20  # embedded layout

set -euo pipefail

MODE="${MODE:-}"
TOOL="${RALPH_TOOL:-codex}"
MAX_STORIES=""
MAX_STORIES_EXPLICIT="false"
ENABLE_SEARCH="${RALPH_SEARCH_ENABLED_BY_DEFAULT:-false}"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT_SECONDS:-900}"
REQUESTED_MODEL="${RALPH_MODEL:-${CODEX_MODEL:-}}"
REASONING_EFFORT="${RALPH_REASONING_EFFORT:-${CODEX_REASONING_EFFORT:-}}"
CAPTURE_CODEX_OUTPUT="${RALPH_CAPTURE_CODEX_OUTPUT:-false}"
MAX_ATTEMPTS_PER_STORY="${RALPH_MAX_ATTEMPTS_PER_STORY:-1}"
REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH="${RALPH_REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH:-true}"
MODEL_PREFLIGHT="${RALPH_MODEL_PREFLIGHT:-false}"
AUTO_ARCHIVE_ON_PROJECT_CHANGE="${RALPH_AUTO_ARCHIVE_ON_PROJECT_CHANGE:-false}"
REQUIRE_LEARNING_ENTRY_FOR_FIXING="${RALPH_REQUIRE_LEARNING_ENTRY_FOR_FIXING:-false}"
SKIP_AFTER_FAILURES="${RALPH_SKIP_AFTER_FAILURES:-0}"
SYNC_BRANCH_FROM_PRD="${RALPH_SYNC_BRANCH_FROM_PRD:-false}"
AUTO_PROGRESS_LOG_APPEND="${RALPH_AUTO_PROGRESS_LOG_APPEND:-true}"
AUTO_SYNC_AGENTS_FROM_LEARNINGS="${RALPH_AUTO_SYNC_AGENTS_FROM_LEARNINGS:-false}"
SECURITY_PREFLIGHT="${RALPH_SECURITY_PREFLIGHT:-true}"
SECURITY_PREFLIGHT_FAIL_ON_RISK="${RALPH_SECURITY_PREFLIGHT_FAIL_ON_RISK:-false}"
LOCK_STALE_NO_PID_SECONDS="${RALPH_STALE_LOCK_NO_PID_SECONDS:-30}"
STRICT_REPORT_DIR="${RALPH_STRICT_REPORT_DIR:-true}"
FIXING_STATE_METHOD="${RALPH_FIXING_STATE_METHOD:-auto}"
AUTO_PROGRESS_REFRESH="${RALPH_AUTO_PROGRESS_REFRESH:-true}"
RALPH_VERBOSITY="${RALPH_VERBOSITY:-normal}"
SUPPORTED_MODES_JSON='["audit","linting","fixing"]'
SUPPORTED_MODES_HINT='audit | linting | fixing'
SUPPORTED_TOOLS_HINT='codex'
# shellcheck disable=SC2016
CREATED_AC_REGEX='^Created\s+`?[^`\s]+`?(\s+.*)?$'
DEFAULT_MODE_FALLBACK="audit"
DEFAULT_MODEL_FALLBACK="gpt-5.3"
DEFAULT_REASONING_FALLBACK="high"

SCRIPT_DIR=""
REPO_ROOT=""
REPO_ROOT_REAL=""
PRD_FILE=""
PRD_SCHEMA_FILE=""
PRD_VALIDATE_FILTER_FILE=""
CODEX_FILE=""
STATE_DIR=""
RUN_LOG=""
EVENT_LOG=""
SANDBOX_MODE=""
LOCK_DIR=""
LOCK_OWNED="false"
SCRIPT_REL_IN_REPO=""
STATE_REL_IN_REPO=""
STAT_FLAVOR=""
DEFAULT_REPORT_DIR=""
MAX_STORIES_DEFAULT="all_open"

processed=0
passed=0
VALIDATE_PRD_ONLY="false"
LIST_STORIES_ONLY="false"

TMP_FILES=()
DETECTED_CHECKS=()
DETECTED_CHECKS_READY="false"
STORY_CACHE_ID=""
STORY_CACHE_TITLE=""
STORY_CACHE_NOTES=""
STORY_CACHE_OBJECTIVE=""
STORY_CACHE_CREATED_LINE=""
STORY_CACHE_SCOPE_PATTERNS=()
STORY_CACHE_ACCEPTANCE_LINES=()
STORY_CACHE_STEP_LINES=()
STORY_CACHE_VERIFICATION_LINES=()
STORY_CACHE_OUT_OF_SCOPE_LINES=()
FIXING_BASE_STATE_FILE=""
FIXING_STATE_METHOD_LOGGED="false"


RALPH_ENTRYPOINT="${BASH_SOURCE[0]}"
RALPH_LIB_DIR=""

resolve_lib_dir() {
  local entry_dir
  entry_dir="$(cd "$(dirname "$RALPH_ENTRYPOINT")" && pwd)"

  if [[ -d "$entry_dir/lib/ralph" ]]; then
    RALPH_LIB_DIR="$entry_dir/lib/ralph"
    return
  fi

  printf '[ralph][ERROR] Could not locate local lib/ralph modules next to entrypoint: %s/lib/ralph\n' "$entry_dir" >&2
  exit 1
}

source_module() {
  local module="$1"
  local path="$RALPH_LIB_DIR/$module"
  if [[ ! -f "$path" ]]; then
    printf '[ralph][ERROR] Missing module: %s\n' "$path" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$path"
}

resolve_lib_dir
source_module core.sh
source_module config.sh
source_module tool.sh
source_module prd.sh
source_module prompt.sh
source_module runner.sh

main() {
  parse_args "$@"
  validate_runtime_config

  resolve_script_dir
  resolve_repo_root
  REPO_ROOT_REAL="$(cd "$REPO_ROOT" && pwd -P)"
  resolve_paths

  if [[ "$VALIDATE_PRD_ONLY" == "true" ]]; then
    validate_prd_structure
    log "PRD validation passed."
    exit 0
  fi

  if [[ "$LIST_STORIES_ONLY" == "true" ]]; then
    validate_prd_structure
    load_default_report_dir
    apply_prd_runtime_defaults
    finalize_runtime_config
    jq -r --arg mode "$MODE" '
      [.stories[] | select(.mode == $mode and ((.passes // false) == false) and ((.skipped // false) == false))]
      | sort_by(.priority, .id)
      | .[] | "\(.id)\t\(.priority)\t\(.mode)\t\(.title)"
    ' "$PRD_FILE" 2>/dev/null
    exit 0
  fi

  detect_stat_flavor
  acquire_run_lock
  run_security_preflight_check

  require_cmd jq
  require_cmd mktemp
  if command -v git >/dev/null 2>&1; then
    log_event "INFO git detected"
  else
    log_event "INFO git not detected"
  fi

  validate_prd_structure
  maybe_sync_branch_from_prd
  maybe_auto_archive_on_project_change
  load_default_report_dir
  apply_prd_runtime_defaults
  finalize_runtime_config
  mode_to_sandbox

  if [[ "$MAX_STORIES_EXPLICIT" != "true" ]]; then
    if [[ "$MAX_STORIES_DEFAULT" == "all_open" ]]; then
      MAX_STORIES="$(remaining_count)"
      log "no N provided; processing all remaining open stories for mode=$MODE (count=$MAX_STORIES)"
    else
      MAX_STORIES="$MAX_STORIES_DEFAULT"
      log "no N provided; using defaults.max_stories_default=$MAX_STORIES for mode=$MODE"
    fi
  fi

  if [[ "$MAX_STORIES" -gt 0 ]]; then
    require_selected_tool_cmd
    maybe_run_model_preflight_check
  else
    log_event "INFO tool dependency check skipped (max_stories=0 tool=$TOOL)"
  fi

  log "start mode=$MODE tool=$TOOL max_stories=$MAX_STORIES sandbox=$SANDBOX_MODE"
  log_event "RUN_START mode=$MODE tool=$TOOL max_stories=$MAX_STORIES sandbox=$SANDBOX_MODE search=$ENABLE_SEARCH"

  while [[ "$processed" -lt "$MAX_STORIES" ]]; do
    local story_id
    local story_rc=0
    story_id="$(select_next_open_story)"

    if [[ -z "$story_id" ]]; then
      break
    fi

    processed=$((processed + 1))
    if [[ "${RALPH_VERBOSITY:-normal}" != "quiet" ]]; then
      log "Processing story $processed/$MAX_STORIES ($story_id)"
    fi
    if process_story "$story_id"; then
      passed=$((passed + 1))
    else
      story_rc=$?
      handle_story_failure "$story_id" "$story_rc"
    fi
  done

  local remaining
  remaining="$(remaining_count)"

  log "summary processed=$processed passed=$passed remaining=$remaining mode=$MODE tool=$TOOL"
  log_event "RUN_END processed=$processed passed=$passed remaining=$remaining mode=$MODE tool=$TOOL"
  if [[ "$remaining" -eq 0 ]]; then
    printf '<promise>COMPLETE</promise>\n'
    if [[ "${RALPH_VERBOSITY:-normal}" != "quiet" ]]; then
      log "All stories complete."
    fi
  fi
}

main "$@"
