# shellcheck shell=bash

usage() {
  cat <<'USAGE'
Usage: ./ralph.sh [N] [--mode audit|linting|fixing] [--search|--no-search]
                 [--tool codex]
                 [--model-preflight|--no-model-preflight]
                 [--security-preflight|--no-security-preflight]
                 [--auto-archive|--no-auto-archive]
                 [--require-learning-entry|--no-require-learning-entry]
                 [--sync-branch|--no-sync-branch]
       ./.codex/ralph-audit/ralph.sh [N] [--mode audit|linting|fixing] [--search|--no-search]
                                     [--tool codex]
                                     [--model-preflight|--no-model-preflight]
                                     [--security-preflight|--no-security-preflight]
                                     [--auto-archive|--no-auto-archive]
                                     [--require-learning-entry|--no-require-learning-entry]
                                     [--sync-branch|--no-sync-branch]

Arguments:
  N                          Maximum number of stories to process
                             If omitted: process all remaining open stories for MODE.

Options:
  --mode <mode>              Override MODE env (audit|linting|fixing)
  --tool <tool>              Runner tool adapter (supported: codex)
  --search                   Enable Codex web search
  --no-search                Disable Codex web search (default)
  --model-preflight          Run lightweight model preflight check before first story
  --no-model-preflight       Disable model preflight check (default)
  --security-preflight       Enable sensitive env-var preflight warning scan (default)
  --no-security-preflight    Disable security preflight warning scan
  --skip-security-check      Alias for --no-security-preflight
  --auto-archive             Auto-archive run state when PRD project value changes
  --no-auto-archive          Disable auto-archive on project change (default)
  --require-learning-entry   Require learnings.md update for successful fixing stories
  --no-require-learning-entry
                             Disable learnings.md enforcement (default)
  --sync-branch              Sync current git branch to PRD branch_name/branchName
  --no-sync-branch           Disable branch sync from PRD (default)
  --model <model>            Override model id (default: gpt-5.3)
  --reasoning-effort <lvl>   Override reasoning effort (default: high)
  --timeout-seconds <secs>   Per-story timeout (default: 900, 0 = disabled)
  --strict-report-dir        Require Created report path under defaults.report_dir (default)
  --no-strict-report-dir     Allow Created report path outside defaults.report_dir for new files
  -q, --quiet                Only errors and final summary
  -v, --verbose              More per-story output
  --validate-prd             Validate PRD only and exit
  --list-stories             List open stories for current mode and exit
  -h, --help                 Show this help

Environment:
  MODE                        Same as --mode
  RALPH_TOOL                  Same as --tool (default: codex)
  RALPH_SEARCH_ENABLED_BY_DEFAULT
                              true|false, default false
  RALPH_REPO_ROOT             Optional explicit repo root override
  RALPH_MODEL / CODEX_MODEL   Optional model override
  RALPH_REASONING_EFFORT      Optional reasoning effort override
  RALPH_MAX_ATTEMPTS_PER_STORY
                              Retry budget for transient tool failures per story (default: 1)
  RALPH_SKIP_AFTER_FAILURES   Persistently skip story after N failed runs (default: 0 disabled)
  RALPH_REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH
                              true|false, require External References section when --search is enabled (default: true)
  RALPH_MODEL_PREFLIGHT       true|false, default false
  RALPH_SECURITY_PREFLIGHT    true|false, default true
  RALPH_SECURITY_PREFLIGHT_FAIL_ON_RISK
                              true|false, fail run when sensitive env-vars are detected (default: false)
  RALPH_AUTO_ARCHIVE_ON_PROJECT_CHANGE
                              true|false, default false
  RALPH_REQUIRE_LEARNING_ENTRY_FOR_FIXING
                              true|false, default false
  RALPH_SYNC_BRANCH_FROM_PRD  true|false, default false
  RALPH_AUTO_PROGRESS_LOG_APPEND
                              true|false, append progress.log.md entries on story completion (default: true)
  RALPH_AUTO_SYNC_AGENTS_FROM_LEARNINGS
                              true|false, sync AGENTS.md from latest learnings after fixing stories (default: false)
  CODEX_TIMEOUT_SECONDS       Optional timeout override
  RALPH_CAPTURE_CODEX_OUTPUT  true|false, default false
  RALPH_STRICT_REPORT_DIR     true|false, default true
  RALPH_FIXING_STATE_METHOD   auto|full|git (default: auto)
  RALPH_AUTO_PROGRESS_REFRESH true|false, default true
  RALPH_STALE_LOCK_NO_PID_SECONDS
                              Seconds before a lock dir without valid pid is considered stale (default: 30)
  RALPH_VERBOSITY             normal|quiet|verbose (default: normal). Use -q/-v for quiet/verbose.

For details and troubleshooting: docs/configuration.md, docs/operations.md
USAGE
}

log() {
  [[ "${RALPH_VERBOSITY:-normal}" == "quiet" ]] && return 0
  printf '[ralph] %s\n' "$*"
}

log_event() {
  local line
  line="$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
  printf '%s\n' "$line" >> "$EVENT_LOG"
}

fail() {
  local msg="$1"
  local hint="${2:-}"
  local red="" reset=""
  if [[ -t 2 ]] && [[ "${RALPH_VERBOSITY:-normal}" != "quiet" ]]; then
    red='\033[0;31m'
    reset='\033[0m'
  fi
  printf '%s[ralph][ERROR] %s%s\n' "$red" "$msg" "$reset" >&2
  if [[ -n "$hint" ]]; then
    printf '[ralph] %s\n' "$hint" >&2
  else
    printf '[ralph] See docs/operations.md for troubleshooting.\n' >&2
  fi
  if [[ -n "${EVENT_LOG:-}" ]]; then
    log_event "ERROR $msg"
  fi
  exit 1
}

register_tmp() {
  TMP_FILES+=("$1")
}

cleanup() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    if [[ -n "$f" && -e "$f" ]]; then
      rm -f "$f" || true
    fi
  done
}

release_run_lock() {
  local owner_pid=""

  if [[ "${LOCK_OWNED:-false}" != "true" ]]; then
    return
  fi

  if [[ -z "${LOCK_DIR:-}" || ! -d "$LOCK_DIR" ]]; then
    LOCK_OWNED="false"
    return
  fi

  if [[ -f "$LOCK_DIR/pid" ]]; then
    owner_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  fi

  # Never release a lock owned by another process.
  if [[ "$owner_pid" != "$$" ]]; then
    LOCK_OWNED="false"
    return
  fi

  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
  LOCK_OWNED="false"
}

on_exit() {
  local rc="$1"
  release_run_lock
  cleanup
  if [[ "$rc" -ne 0 ]]; then
    printf '[ralph] aborted (exit=%s)\n' "$rc" >&2
  fi
}

on_interrupt() {
  printf '[ralph] interrupted\n' >&2
  exit 130
}

trap 'on_exit $?' EXIT
trap on_interrupt INT TERM

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing required dependency: $cmd"
}

is_true() {
  [[ "$1" == "true" || "$1" == "1" || "$1" == "yes" ]]
}

is_supported_mode() {
  case "$1" in
    audit|linting|fixing) return 0 ;;
    *) return 1 ;;
  esac
}
