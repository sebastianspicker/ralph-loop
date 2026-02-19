# shellcheck shell=bash
# shellcheck disable=SC2034

_ralph_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ralph/validate_prd.sh
source "$_ralph_lib/validate_prd.sh"
# shellcheck source=lib/ralph/config_parse.sh
source "$_ralph_lib/config_parse.sh"

resolve_script_dir() {
  local entry="${RALPH_ENTRYPOINT:-${BASH_SOURCE[0]}}"
  SCRIPT_DIR="$(cd "$(dirname "$entry")" && pwd)"
}

resolve_repo_root() {
  local candidate

  if [[ -n "${RALPH_REPO_ROOT:-}" ]]; then
    [[ -d "$RALPH_REPO_ROOT" ]] || fail "RALPH_REPO_ROOT does not exist: $RALPH_REPO_ROOT"
    REPO_ROOT="$(cd "$RALPH_REPO_ROOT" && pwd)"
    return
  fi

  # Embedded layout marker: <repo>/.codex/ralph-audit
  if [[ "$(basename "$SCRIPT_DIR")" == "ralph-audit" && "$(basename "$(dirname "$SCRIPT_DIR")")" == ".codex" ]]; then
    candidate="$(cd "$SCRIPT_DIR/../.." && pwd)"
    if [[ -f "$candidate/.codex/ralph-audit/prd.json" && -f "$candidate/.codex/ralph-audit/CODEX.md" ]]; then
      REPO_ROOT="$candidate"
      return
    fi
  fi

  # Standalone template layout: script lives at repository root.
  if [[ -f "$SCRIPT_DIR/prd.json" && -f "$SCRIPT_DIR/CODEX.md" ]]; then
    REPO_ROOT="$SCRIPT_DIR"
    return
  fi

  if command -v git >/dev/null 2>&1; then
    if candidate="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
      REPO_ROOT="$candidate"
      return
    fi
  fi

  fail "Could not resolve repository root. Set RALPH_REPO_ROOT explicitly."
}

resolve_paths() {
  PRD_FILE="$SCRIPT_DIR/prd.json"
  PRD_SCHEMA_FILE="$SCRIPT_DIR/prd.schema.json"
  PRD_VALIDATE_FILTER_FILE="$SCRIPT_DIR/prd.validate.jq"
  CODEX_FILE="$SCRIPT_DIR/CODEX.md"
  STATE_DIR="$SCRIPT_DIR/.runtime"
  mkdir -p "$STATE_DIR"
  RUN_LOG="$STATE_DIR/run.log"
  EVENT_LOG="$STATE_DIR/events.log"
  touch "$RUN_LOG" "$EVENT_LOG"
  cache_internal_paths
}

run_security_preflight_check() {
  local -a watched_vars=(
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN
    DATABASE_URL
    POSTGRES_URL
    OPENAI_API_KEY
    ANTHROPIC_API_KEY
    STRIPE_SECRET_KEY
    GITHUB_TOKEN
    GOOGLE_APPLICATION_CREDENTIALS
  )
  local -a detected=()
  local var_name joined

  if ! is_true "$SECURITY_PREFLIGHT"; then
    log_event "INFO security_preflight=disabled"
    return
  fi

  for var_name in "${watched_vars[@]}"; do
    if [[ -n "${!var_name:-}" ]]; then
      detected+=("$var_name")
    fi
  done

  if [[ "${#detected[@]}" -eq 0 ]]; then
    log_event "INFO security_preflight=clean"
    return
  fi

  joined="$(IFS=,; printf '%s' "${detected[*]}")"
  log_event "WARN security_preflight=detected vars=$joined"
  printf '[ralph][WARN] Security preflight detected sensitive environment variables: %s\n' "$joined" >&2
  printf '[ralph][WARN] Use least privilege and unset unneeded secrets for autonomous runs.\n' >&2

  if is_true "$SECURITY_PREFLIGHT_FAIL_ON_RISK"; then
    fail "Security preflight blocked run due sensitive environment variables (vars=$joined)"
  fi
}

mode_to_sandbox() {
  local configured_sandbox
  configured_sandbox="$(jq -r --arg mode "$MODE" '.defaults.sandbox_by_mode[$mode] // ""' "$PRD_FILE" 2>/dev/null || true)"
  case "$configured_sandbox" in
    read-only|workspace-write)
      SANDBOX_MODE="$configured_sandbox"
      ;;
    *)
      fail "Invalid sandbox_by_mode mapping for mode=$MODE in $PRD_FILE"
      ;;
  esac
}

apply_prd_runtime_defaults() {
  local prd_mode prd_model prd_reason prd_max

  prd_mode="$(jq -r '.defaults.mode_default // ""' "$PRD_FILE")"
  prd_model="$(jq -r '.defaults.model_default // ""' "$PRD_FILE")"
  prd_reason="$(jq -r '.defaults.reasoning_effort_default // ""' "$PRD_FILE")"
  prd_max="$(jq -r '
    if .defaults.max_stories_default == "all_open" then
      "all_open"
    elif (.defaults.max_stories_default | type) == "number" then
      (.defaults.max_stories_default | floor | tostring)
    else
      ""
    end
  ' "$PRD_FILE")"

  if [[ -z "$MODE" ]]; then
    MODE="$prd_mode"
  fi
  if [[ -z "$REQUESTED_MODEL" ]]; then
    REQUESTED_MODEL="$prd_model"
  fi
  if [[ -z "$REASONING_EFFORT" ]]; then
    REASONING_EFFORT="$prd_reason"
  fi

  [[ -n "$MODE" ]] || MODE="$DEFAULT_MODE_FALLBACK"
  [[ -n "$REQUESTED_MODEL" ]] || REQUESTED_MODEL="$DEFAULT_MODEL_FALLBACK"
  [[ -n "$REASONING_EFFORT" ]] || REASONING_EFFORT="$DEFAULT_REASONING_FALLBACK"

  if [[ -n "$prd_max" ]]; then
    MAX_STORIES_DEFAULT="$prd_max"
  else
    MAX_STORIES_DEFAULT="all_open"
  fi
}

finalize_runtime_config() {
  is_supported_mode "$MODE" || fail "MODE must be one of: $SUPPORTED_MODES_HINT"
  [[ -n "$REQUESTED_MODEL" ]] || fail "Model must not be empty"
  case "$REASONING_EFFORT" in
    low|medium|high) ;;
    *) fail "Reasoning effort must be one of: low|medium|high" ;;
  esac

  if [[ "$MAX_STORIES_DEFAULT" == "all_open" ]]; then
    :
  elif [[ "$MAX_STORIES_DEFAULT" =~ ^[0-9]+$ ]]; then
    :
  else
    fail "defaults.max_stories_default resolved to invalid value: $MAX_STORIES_DEFAULT"
  fi
}

validate_prd_structure() {
  [[ -f "$PRD_FILE" ]] || fail "Missing PRD file: $PRD_FILE"
  [[ -f "$CODEX_FILE" ]] || fail "Missing CODEX file: $CODEX_FILE"
  [[ -f "$PRD_SCHEMA_FILE" ]] || fail "Missing PRD schema file: $PRD_SCHEMA_FILE"
  [[ -f "$PRD_VALIDATE_FILTER_FILE" ]] || fail "Missing PRD validation filter: $PRD_VALIDATE_FILTER_FILE"

  # SUPPORTED_MODES_JSON and CREATED_AC_REGEX are set by ralph.sh before sourcing this file
  # shellcheck disable=SC2153
  validate_prd_with_jq "$PRD_FILE" "$PRD_SCHEMA_FILE" "$PRD_VALIDATE_FILTER_FILE" \
    "$SUPPORTED_MODES_JSON" "$CREATED_AC_REGEX" || fail "Invalid prd.json structure or story constraints"

  validate_prd_text_hygiene
}

validate_prd_text_hygiene() {
  local bad_paths

  bad_paths="$(jq -r '
    def bad_text:
      test("[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u202A-\u202E\u2066-\u2069]");
    [
      paths(strings) as $p
      | getpath($p) as $v
      | select($v | bad_text)
      | ($p | map(tostring) | join("."))
    ]
    | .[:5]
    | .[]
  ' "$PRD_FILE" 2>/dev/null || true)"

  if [[ -n "$bad_paths" ]]; then
    fail "PRD contains disallowed hidden/control/bidi characters (first paths): $bad_paths"
  fi
}

maybe_auto_archive_on_project_change() {
  local track_file current_project previous_project archive_script

  track_file="$STATE_DIR/.last-project"
  current_project="$(jq -r '.project // ""' "$PRD_FILE" 2>/dev/null || true)"
  if [[ -z "$current_project" || "$current_project" == "null" ]]; then
    current_project="unknown-project"
  fi
  if [[ -f "$track_file" ]]; then
    previous_project="$(cat "$track_file" 2>/dev/null || true)"
  else
    previous_project=""
  fi

  if is_true "$AUTO_ARCHIVE_ON_PROJECT_CHANGE" \
    && [[ -n "$previous_project" ]] \
    && [[ "$previous_project" != "$current_project" ]]; then
    archive_script="$SCRIPT_DIR/scripts/archive_run_state.sh"
    if [[ ! -x "$archive_script" ]]; then
      fail "Auto archive enabled but missing executable script: $archive_script"
    fi
    if "$archive_script" \
      --source-root "$SCRIPT_DIR" \
      --label "$previous_project" \
      --reason "auto-archive on project change ($previous_project -> $current_project)" \
      >/dev/null 2>&1; then
      log_event "INFO auto_archive_on_project_change previous=$previous_project current=$current_project"
    else
      fail "Auto archive on project change failed (previous=$previous_project current=$current_project)"
    fi
  fi

  printf '%s\n' "$current_project" > "$track_file"
}

extract_prd_branch_target() {
  jq -r '
    if (.branch_name | type) == "string" and (.branch_name | length) > 0 then
      .branch_name
    elif (.branchName | type) == "string" and (.branchName | length) > 0 then
      .branchName
    else
      ""
    end
  ' "$PRD_FILE" 2>/dev/null || true
}

resolve_default_base_branch() {
  local candidate
  for candidate in main master; do
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s' "$candidate"
      return
    fi
  done

  candidate="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$candidate" && "$candidate" != "HEAD" ]]; then
    printf '%s' "$candidate"
    return
  fi

  printf ''
}

maybe_sync_branch_from_prd() {
  local target_branch current_branch base_branch

  if ! is_true "$SYNC_BRANCH_FROM_PRD"; then
    return
  fi
  command -v git >/dev/null 2>&1 || fail "Branch sync requested but git is not available"
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Branch sync requested outside git worktree"

  target_branch="$(extract_prd_branch_target)"
  if [[ -z "$target_branch" ]]; then
    log_event "INFO branch_sync_requested_but_no_prd_branch"
    return
  fi

  current_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$current_branch" == "$target_branch" ]]; then
    log_event "INFO branch_sync_already_on_target branch=$target_branch"
    return
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$target_branch"; then
    git -C "$REPO_ROOT" checkout "$target_branch" >/dev/null 2>&1 || fail "Failed to checkout branch from PRD: $target_branch"
    log_event "INFO branch_sync_checked_out_existing branch=$target_branch"
    return
  fi

  base_branch="$(resolve_default_base_branch)"
  if [[ -n "$base_branch" && "$base_branch" != "$target_branch" ]]; then
    git -C "$REPO_ROOT" checkout -b "$target_branch" "$base_branch" >/dev/null 2>&1 || fail "Failed to create branch $target_branch from $base_branch"
    log_event "INFO branch_sync_created branch=$target_branch base=$base_branch"
  else
    git -C "$REPO_ROOT" checkout -b "$target_branch" >/dev/null 2>&1 || fail "Failed to create branch from PRD: $target_branch"
    log_event "INFO branch_sync_created branch=$target_branch"
  fi
}

load_default_report_dir() {
  DEFAULT_REPORT_DIR="$(jq -r '.defaults.report_dir // ""' "$PRD_FILE" 2>/dev/null || true)"
  if [[ "$DEFAULT_REPORT_DIR" == "null" ]]; then
    DEFAULT_REPORT_DIR=""
  fi
  DEFAULT_REPORT_DIR="${DEFAULT_REPORT_DIR#./}"
  DEFAULT_REPORT_DIR="${DEFAULT_REPORT_DIR%/}"
}

path_mtime_epoch() {
  local path="$1"
  local mtime

  case "${STAT_FLAVOR:-}" in
    gnu)
      if mtime="$(stat -c '%Y' "$path" 2>/dev/null)"; then
        printf '%s' "$mtime"
        return
      fi
      ;;
    bsd|*)
      if mtime="$(stat -f '%m' "$path" 2>/dev/null)"; then
        printf '%s' "$mtime"
        return
      fi
      ;;
  esac

  fail "Could not read modification time for: $path"
}

detect_stat_flavor() {
  local probe_path
  probe_path="${SCRIPT_DIR:-.}"
  if stat -c '%Y' "$probe_path" >/dev/null 2>&1; then
    STAT_FLAVOR="gnu"
    return
  fi
  if stat -f '%m' "$probe_path" >/dev/null 2>&1; then
    STAT_FLAVOR="bsd"
    return
  fi
  fail "Could not detect compatible stat flavor (need stat -c or stat -f support)"
}

acquire_run_lock() {
  local lock_dir="$STATE_DIR/.run.lock"
  local attempts=0
  local holder_pid=""
  local lock_dir_mtime=0
  local lock_age=0
  local now_epoch=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    holder_pid=""
    if [[ -f "$lock_dir/pid" ]]; then
      holder_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    fi

    # Recover stale lock when holder process no longer exists.
    if [[ "$holder_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
      rm -f "$lock_dir/pid" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
      continue
    fi

    if [[ "$holder_pid" =~ ^[0-9]+$ ]]; then
      :
    else
      if [[ ! -d "$lock_dir" ]]; then
        continue
      fi
      # A lock directory without a valid pid may be a crash artifact or a
      # process that has created the lock dir but not yet written metadata.
      # Recover only if the lock directory is old enough to avoid stealing a
      # fresh lock.
      if ! lock_dir_mtime="$(path_mtime_epoch "$lock_dir")"; then
        fail "Could not evaluate lock age for lock directory: $lock_dir"
      fi
      now_epoch="$(date +%s)"
      if [[ "$now_epoch" -lt "$lock_dir_mtime" ]]; then
        lock_age=0
      else
        lock_age=$((now_epoch - lock_dir_mtime))
      fi
      if [[ "$lock_age" -ge "$LOCK_STALE_NO_PID_SECONDS" ]]; then
        rm -f "$lock_dir/pid" 2>/dev/null || true
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi

    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 300 ]]; then
      fail "Another ralph run holds lock at $lock_dir (pid=${holder_pid:-unknown})"
    fi
    sleep 1
  done

  printf '%s\n' "$$" > "$lock_dir/pid"
  LOCK_DIR="$lock_dir"
  LOCK_OWNED="true"
}
