# shellcheck shell=bash
# shellcheck disable=SC2034
# CLI argument parsing and runtime config validation.
# Sourced by config.sh; variables set here are used by ralph.sh main().
# validate_tool_config is from tool.sh (loaded after config.sh).

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        [[ $# -ge 2 ]] || fail "--mode requires a value"
        MODE="$2"
        shift 2
        ;;
      --tool)
        [[ $# -ge 2 ]] || fail "--tool requires a value"
        TOOL="$2"
        shift 2
        ;;
      --tool=*)
        TOOL="${1#*=}"
        shift
        ;;
      --search)
        ENABLE_SEARCH="true"
        shift
        ;;
      --no-search)
        ENABLE_SEARCH="false"
        shift
        ;;
      --sync-branch)
        SYNC_BRANCH_FROM_PRD="true"
        shift
        ;;
      --no-sync-branch)
        SYNC_BRANCH_FROM_PRD="false"
        shift
        ;;
      --model-preflight)
        MODEL_PREFLIGHT="true"
        shift
        ;;
      --no-model-preflight)
        MODEL_PREFLIGHT="false"
        shift
        ;;
      --security-preflight)
        SECURITY_PREFLIGHT="true"
        shift
        ;;
      --no-security-preflight|--skip-security-check)
        SECURITY_PREFLIGHT="false"
        shift
        ;;
      --auto-archive)
        AUTO_ARCHIVE_ON_PROJECT_CHANGE="true"
        shift
        ;;
      --no-auto-archive)
        AUTO_ARCHIVE_ON_PROJECT_CHANGE="false"
        shift
        ;;
      --require-learning-entry)
        REQUIRE_LEARNING_ENTRY_FOR_FIXING="true"
        shift
        ;;
      --no-require-learning-entry)
        REQUIRE_LEARNING_ENTRY_FOR_FIXING="false"
        shift
        ;;
      --model)
        [[ $# -ge 2 ]] || fail "--model requires a value"
        REQUESTED_MODEL="$2"
        shift 2
        ;;
      --reasoning-effort)
        [[ $# -ge 2 ]] || fail "--reasoning-effort requires a value"
        REASONING_EFFORT="$2"
        shift 2
        ;;
      --timeout-seconds)
        [[ $# -ge 2 ]] || fail "--timeout-seconds requires a value"
        CODEX_TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --strict-report-dir)
        STRICT_REPORT_DIR="true"
        shift
        ;;
      --no-strict-report-dir)
        STRICT_REPORT_DIR="false"
        shift
        ;;
      -q|--quiet)
        RALPH_VERBOSITY="quiet"
        shift
        ;;
      -v|--verbose)
        RALPH_VERBOSITY="verbose"
        shift
        ;;
      --validate-prd)
        VALIDATE_PRD_ONLY="true"
        shift
        ;;
      --list-stories)
        LIST_STORIES_ONLY="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          if [[ "$MAX_STORIES_EXPLICIT" == "true" ]]; then
            fail "Only one positional N argument is allowed"
          fi
          MAX_STORIES="$1"
          MAX_STORIES_EXPLICIT="true"
          shift
        else
          fail "Unknown argument: $1"
        fi
        ;;
    esac
  done
}

validate_runtime_config() {
  if [[ "$MAX_STORIES_EXPLICIT" == "true" ]]; then
    [[ "$MAX_STORIES" =~ ^[0-9]+$ ]] || fail "N must be a non-negative integer"
  fi
  if [[ -n "$MODE" ]]; then
    is_supported_mode "$MODE" || fail "MODE must be one of: $SUPPORTED_MODES_HINT"
  fi
  validate_tool_config
  [[ "$ENABLE_SEARCH" == "true" || "$ENABLE_SEARCH" == "false" ]] || fail "RALPH_SEARCH_ENABLED_BY_DEFAULT must be true|false"
  [[ "$CODEX_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || fail "CODEX_TIMEOUT_SECONDS must be a non-negative integer"
  [[ "$MAX_ATTEMPTS_PER_STORY" =~ ^[0-9]+$ && "$MAX_ATTEMPTS_PER_STORY" -ge 1 ]] || fail "RALPH_MAX_ATTEMPTS_PER_STORY must be an integer >= 1"
  [[ "$SKIP_AFTER_FAILURES" =~ ^[0-9]+$ ]] || fail "RALPH_SKIP_AFTER_FAILURES must be a non-negative integer"
  [[ "$CAPTURE_CODEX_OUTPUT" == "true" || "$CAPTURE_CODEX_OUTPUT" == "false" ]] || fail "RALPH_CAPTURE_CODEX_OUTPUT must be true|false"
  [[ "$REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH" == "true" || "$REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH" == "false" ]] || fail "RALPH_REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH must be true|false"
  [[ "$MODEL_PREFLIGHT" == "true" || "$MODEL_PREFLIGHT" == "false" ]] || fail "RALPH_MODEL_PREFLIGHT must be true|false"
  [[ "$AUTO_ARCHIVE_ON_PROJECT_CHANGE" == "true" || "$AUTO_ARCHIVE_ON_PROJECT_CHANGE" == "false" ]] || fail "RALPH_AUTO_ARCHIVE_ON_PROJECT_CHANGE must be true|false"
  [[ "$REQUIRE_LEARNING_ENTRY_FOR_FIXING" == "true" || "$REQUIRE_LEARNING_ENTRY_FOR_FIXING" == "false" ]] || fail "RALPH_REQUIRE_LEARNING_ENTRY_FOR_FIXING must be true|false"
  [[ "$SECURITY_PREFLIGHT" == "true" || "$SECURITY_PREFLIGHT" == "false" ]] || fail "RALPH_SECURITY_PREFLIGHT must be true|false"
  [[ "$SECURITY_PREFLIGHT_FAIL_ON_RISK" == "true" || "$SECURITY_PREFLIGHT_FAIL_ON_RISK" == "false" ]] || fail "RALPH_SECURITY_PREFLIGHT_FAIL_ON_RISK must be true|false"
  [[ "$SYNC_BRANCH_FROM_PRD" == "true" || "$SYNC_BRANCH_FROM_PRD" == "false" ]] || fail "RALPH_SYNC_BRANCH_FROM_PRD must be true|false"
  [[ "$AUTO_PROGRESS_LOG_APPEND" == "true" || "$AUTO_PROGRESS_LOG_APPEND" == "false" ]] || fail "RALPH_AUTO_PROGRESS_LOG_APPEND must be true|false"
  [[ "$AUTO_SYNC_AGENTS_FROM_LEARNINGS" == "true" || "$AUTO_SYNC_AGENTS_FROM_LEARNINGS" == "false" ]] || fail "RALPH_AUTO_SYNC_AGENTS_FROM_LEARNINGS must be true|false"
  [[ "$STRICT_REPORT_DIR" == "true" || "$STRICT_REPORT_DIR" == "false" ]] || fail "RALPH_STRICT_REPORT_DIR must be true|false"
  [[ "$FIXING_STATE_METHOD" == "auto" || "$FIXING_STATE_METHOD" == "full" || "$FIXING_STATE_METHOD" == "git" ]] || fail "RALPH_FIXING_STATE_METHOD must be auto|full|git"
  [[ "$AUTO_PROGRESS_REFRESH" == "true" || "$AUTO_PROGRESS_REFRESH" == "false" ]] || fail "RALPH_AUTO_PROGRESS_REFRESH must be true|false"
  [[ "$LOCK_STALE_NO_PID_SECONDS" =~ ^[0-9]+$ ]] || fail "RALPH_STALE_LOCK_NO_PID_SECONDS must be a non-negative integer"
}
