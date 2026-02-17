# shellcheck shell=bash

run_with_timeout() {
  local -a cmd=("$@")

  if [[ "$CODEX_TIMEOUT_SECONDS" -eq 0 ]]; then
    "${cmd[@]}"
    return
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=INT --kill-after=15 "$CODEX_TIMEOUT_SECONDS" "${cmd[@]}"
    return
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --signal=INT --kill-after=15 "$CODEX_TIMEOUT_SECONDS" "${cmd[@]}"
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$CODEX_TIMEOUT_SECONDS" "${cmd[@]}"
    return
  fi

  log "timeout tool not found; running without timeout"
  "${cmd[@]}"
}

append_redacted_log() {
  local raw_log_file="$1"
  redact_stream < "$raw_log_file" >> "$RUN_LOG"
}

redact_stream() {
  sed -E \
    -e 's/((([A-Za-z_][A-Za-z0-9_]*)?(TOKEN|SECRET|PASSWORD|API_KEY|ACCESS_KEY|PRIVATE_KEY)[A-Za-z0-9_]*)=)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/(Authorization:[[:space:]]*Bearer[[:space:]])[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/(AKIA[0-9A-Z]{16})/[REDACTED]/g' \
    -e 's/\b(sk|rk|pk)-[A-Za-z0-9_-]{10,}\b/[REDACTED]/g'
}

emit_redacted_codex_excerpt() {
  local raw_log_file="$1"
  local line_count="${2:-25}"
  local excerpt
  excerpt="$(redact_stream < "$raw_log_file" | tail -n "$line_count" || true)"
  [[ -n "$excerpt" ]] || return

  printf '[ralph] codex failure excerpt (redacted, last %s lines):\n' "$line_count" >&2
  while IFS= read -r line; do
    printf '[ralph][codex] %s\n' "$line" >&2
  done <<< "$excerpt"
}

validate_external_references_contract() {
  local story_id="$1"
  local last_message_file="$2"

  if [[ "$story_id" == "MODEL_PREFLIGHT" ]]; then
    return 0
  fi
  if [[ "$ENABLE_SEARCH" != "true" ]] || ! is_true "$REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH"; then
    return 0
  fi

  if ! grep -Eq '^##[[:space:]]+External References([[:space:]]*)$' "$last_message_file"; then
    log_event "WARN story=$story_id missing_external_references_section"
    return 41
  fi
  if ! grep -Eq '\[[^][]+\]\(https?://[^)]+\)|https?://[^[:space:])]+|www\.[^[:space:])]+' "$last_message_file"; then
    log_event "WARN story=$story_id missing_external_reference_links"
    return 42
  fi
  if ! grep -Eq '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$last_message_file"; then
    log_event "WARN story=$story_id missing_external_reference_dates"
    return 43
  fi

  return 0
}

run_codex_once() {
  local story_id="$1"
  local prompt_file="$2"
  local last_message_file="$3"
  local -a cmd
  local raw_codex_log
  local codex_rc
  local attempt=1
  local contract_rc

  cmd=(env "CODEX_INTERNAL_ORIGINATOR_OVERRIDE=${CODEX_INTERNAL_ORIGINATOR_OVERRIDE:-codex_cli_rs}" codex -a never)
  if [[ "$ENABLE_SEARCH" == "true" ]]; then
    cmd+=(--search)
  fi

  cmd+=(exec -C "$REPO_ROOT" -s "$SANDBOX_MODE")

  if [[ -n "$REQUESTED_MODEL" ]]; then
    cmd+=(-m "$REQUESTED_MODEL")
  fi

  if [[ -n "$REASONING_EFFORT" ]]; then
    cmd+=(-c "model_reasoning_effort=\"$REASONING_EFFORT\"")
  fi

  cmd+=(--output-last-message "$last_message_file")

  while [[ "$attempt" -le "$MAX_ATTEMPTS_PER_STORY" ]]; do
    rm -f "$last_message_file"
    raw_codex_log="$(mktemp "$STATE_DIR/.codex-output.${story_id}.attempt${attempt}.XXXXXX")"
    register_tmp "$raw_codex_log"

    if run_with_timeout "${cmd[@]}" < "$prompt_file" > "$raw_codex_log" 2>&1; then
      codex_rc=0
    else
      codex_rc=$?
    fi

    if [[ "$codex_rc" -eq 0 ]] && [[ -s "$last_message_file" ]]; then
      contract_rc=0
      validate_external_references_contract "$story_id" "$last_message_file" || contract_rc=$?
      if [[ "$contract_rc" -eq 0 ]]; then
        if is_true "$CAPTURE_CODEX_OUTPUT"; then
          append_redacted_log "$raw_codex_log"
        fi
        if [[ "$attempt" -gt 1 ]]; then
          log_event "INFO story=$story_id tool_retry_recovered attempt=$attempt max=$MAX_ATTEMPTS_PER_STORY"
        fi
        return 0
      fi
      codex_rc="$contract_rc"
    fi

    append_redacted_log "$raw_codex_log"
    if [[ "$codex_rc" -eq 0 ]] && [[ ! -s "$last_message_file" ]]; then
      codex_rc=44
      log_event "WARN story=$story_id empty_last_message attempt=$attempt max=$MAX_ATTEMPTS_PER_STORY"
    fi

    if [[ "$attempt" -lt "$MAX_ATTEMPTS_PER_STORY" ]]; then
      log_event "WARN story=$story_id tool_attempt_failed rc=$codex_rc attempt=$attempt max=$MAX_ATTEMPTS_PER_STORY"
      attempt=$((attempt + 1))
      sleep 1
      continue
    fi

    emit_redacted_codex_excerpt "$raw_codex_log" 25
    return "$codex_rc"
  done
}

run_tool_once() {
  local story_id="$1"
  local prompt_file="$2"
  local last_message_file="$3"

  case "$TOOL" in
    codex)
      run_codex_once "$story_id" "$prompt_file" "$last_message_file"
      ;;
    *)
      fail "Unsupported tool selected: $TOOL"
      ;;
  esac
}

maybe_run_model_preflight_check() {
  local prompt_file
  local last_message_file
  local codex_rc=0

  if ! is_true "$MODEL_PREFLIGHT"; then
    return
  fi

  prompt_file="$(mktemp "$STATE_DIR/.model-preflight.XXXXXX.md")"
  last_message_file="$(mktemp "$STATE_DIR/.model-preflight-last.XXXXXX.txt")"
  register_tmp "$prompt_file"
  register_tmp "$last_message_file"

  cat > "$prompt_file" <<'EOF'
Reply with exactly:
MODEL_PREFLIGHT_OK
EOF

  run_tool_once "MODEL_PREFLIGHT" "$prompt_file" "$last_message_file" || codex_rc=$?
  if [[ "$codex_rc" -ne 0 ]]; then
    fail "Model preflight check failed (tool=$TOOL model=$REQUESTED_MODEL rc=$codex_rc)"
  fi
  if ! grep -qx 'MODEL_PREFLIGHT_OK' "$last_message_file"; then
    fail "Model preflight check returned unexpected output for model=$REQUESTED_MODEL"
  fi

  log_event "INFO model_preflight_ok tool=$TOOL model=$REQUESTED_MODEL"
}

file_signature_or_missing() {
  local path="$1"
  local signature
  if [[ -f "$path" ]]; then
    if ! signature="$(file_state_signature "$path")"; then
      fail "Could not read file metadata for: $path"
    fi
    printf '%s' "$signature"
  else
    printf '__missing__'
  fi
}

maybe_require_learning_entry_update() {
  local story_id="$1"
  local baseline_signature="$2"
  local learnings_file="$SCRIPT_DIR/learnings.md"
  local current_signature

  if [[ "$MODE" != "fixing" ]] || ! is_true "$REQUIRE_LEARNING_ENTRY_FOR_FIXING"; then
    return
  fi

  if [[ ! -f "$learnings_file" ]]; then
    fail "fixing story $story_id requires learnings.md update, but file is missing: $learnings_file"
  fi

  current_signature="$(file_signature_or_missing "$learnings_file")"
  if [[ "$current_signature" == "$baseline_signature" ]]; then
    fail "fixing story $story_id requires at least one new learnings.md entry (see scripts/record_learning.sh)"
  fi
}

file_state_signature() {
  local abs_path="$1"
  local signature

  case "${STAT_FLAVOR:-}" in
    gnu)
      if signature="$(stat -c '%Y:%Z:%s' "$abs_path" 2>/dev/null)"; then
        printf '%s' "$signature"
        return 0
      fi
      ;;
    bsd|*)
      if signature="$(stat -f '%m:%c:%z' "$abs_path" 2>/dev/null)"; then
        printf '%s' "$signature"
        return 0
      fi
      ;;
  esac

  return 1
}

capture_worktree_state() {
  local out_file="$1"
  local method="full"

  if should_use_git_state_fast_path; then
    if capture_worktree_state_git "$out_file"; then
      method="git"
    else
      capture_worktree_state_full "$out_file"
      method="full"
    fi
  else
    capture_worktree_state_full "$out_file"
    method="full"
  fi

  if [[ "$MODE" == "fixing" && "$FIXING_STATE_METHOD_LOGGED" != "true" ]]; then
    log_event "INFO fixing_state_method=$method requested=$FIXING_STATE_METHOD"
    FIXING_STATE_METHOD_LOGGED="true"
  fi
}

capture_worktree_state_full() {
  local out_file="$1"
  local rel abs_path signature
  local entries_file tmp_unsorted

  : > "$out_file"
  entries_file="$(mktemp "$STATE_DIR/.state-entries.full.XXXXXX")"
  tmp_unsorted="$(mktemp "$STATE_DIR/.state-raw.full.XXXXXX")"
  register_tmp "$entries_file"
  register_tmp "$tmp_unsorted"
  : > "$tmp_unsorted"

  (
    cd "$REPO_ROOT" || exit 1
    find . \( -path './.git' -o -path './.git/*' \) -prune -o \( -type f -o -type l \) -print0
  ) > "$entries_file" || fail "Could not enumerate repository files for state snapshot"

  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    if is_runner_internal_path "$rel"; then
      continue
    fi

    abs_path="$REPO_ROOT/$rel"
    if [[ ! -e "$abs_path" && ! -L "$abs_path" ]]; then
      continue
    fi

    if ! signature="$(file_state_signature "$abs_path")"; then
      fail "Could not read file metadata for: $abs_path"
    fi
    printf '%s\t%s\n' "$rel" "$signature" >> "$tmp_unsorted"
  done < "$entries_file"

  LC_ALL=C sort -u "$tmp_unsorted" > "$out_file"
}

capture_worktree_state_git() {
  local out_file="$1"
  local rel abs_path signature
  local entries_file tmp_unsorted

  : > "$out_file"
  entries_file="$(mktemp "$STATE_DIR/.state-entries.git.XXXXXX")"
  tmp_unsorted="$(mktemp "$STATE_DIR/.state-raw.git.XXXXXX")"
  register_tmp "$entries_file"
  register_tmp "$tmp_unsorted"
  : > "$tmp_unsorted"

  if ! (
    cd "$REPO_ROOT" || exit 1
    git ls-files -z --cached --others --exclude-standard
  ) > "$entries_file"; then
    return 1
  fi

  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] || continue
    if is_runner_internal_path "$rel"; then
      continue
    fi

    abs_path="$REPO_ROOT/$rel"
    if [[ ! -e "$abs_path" && ! -L "$abs_path" ]]; then
      continue
    fi

    if ! signature="$(file_state_signature "$abs_path")"; then
      fail "Could not read file metadata for: $abs_path"
    fi
    printf '%s\t%s\n' "$rel" "$signature" >> "$tmp_unsorted"
  done < "$entries_file"

  LC_ALL=C sort -u "$tmp_unsorted" > "$out_file"
}

git_repo_has_ignored_paths() {
  local ignored_count
  ignored_count="$(
    git -C "$REPO_ROOT" ls-files --others -i --exclude-standard --directory --no-empty-directory -z 2>/dev/null \
    | wc -c \
    | tr -d '[:space:]'
  )"
  [[ "${ignored_count:-0}" -gt 0 ]]
}

should_use_git_state_fast_path() {
  case "$FIXING_STATE_METHOD" in
    full)
      return 1
      ;;
    auto|git)
      ;;
    *)
      return 1
      ;;
  esac

  command -v git >/dev/null 2>&1 || return 1
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

  if git_repo_has_ignored_paths; then
    if [[ "$FIXING_STATE_METHOD" == "git" ]]; then
      fail "RALPH_FIXING_STATE_METHOD=git is unsafe with ignored paths; use auto or full"
    fi
    # Preserve correctness when ignored files exist; ignored-path changes are
    # not represented by git ls-files --exclude-standard snapshots.
    if [[ "$FIXING_STATE_METHOD" == "auto" ]]; then
      return 1
    fi
  fi

  return 0
}

diff_worktree_states() {
  local before_file="$1"
  local after_file="$2"
  local out_file="$3"

  awk -F '\t' '
    NR==FNR {
      before[$1] = $2
      next
    }
    {
      after[$1] = $2
    }
    END {
      for (path in before) {
        if (!(path in after) || before[path] != after[path]) {
          print path
        }
      }
      for (path in after) {
        if (!(path in before)) {
          print path
        }
      }
    }
  ' "$before_file" "$after_file" | LC_ALL=C sort -u > "$out_file"
}

enforce_fixing_scope() {
  local story_id="$1"
  local before_state_file="$2"
  local after_state_file="$3"
  local changed_paths_file
  local path
  local violations=()

  changed_paths_file="$(mktemp "$STATE_DIR/.state-diff.${story_id}.XXXXXX.txt")"
  register_tmp "$changed_paths_file"

  diff_worktree_states "$before_state_file" "$after_state_file" "$changed_paths_file"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if is_runner_internal_path "$path"; then
      continue
    fi
    if ! path_matches_story_scope "$story_id" "$path"; then
      violations+=("$path")
    fi
  done < "$changed_paths_file"

  if [[ "${#violations[@]}" -gt 0 ]]; then
    local details=""
    for path in "${violations[@]}"; do
      details+=$'\n- '"$path"
    done
    fail "Story $story_id modified files outside scope:$details"
  fi
}

repo_relative_dir() {
  local abs_dir="$1"
  if [[ "$abs_dir" == "$REPO_ROOT" ]]; then
    printf '.'
    return
  fi
  if [[ "$abs_dir" == "$REPO_ROOT/"* ]]; then
    printf '%s' "${abs_dir#"$REPO_ROOT"/}"
    return
  fi
  printf ''
}

cache_internal_paths() {
  SCRIPT_REL_IN_REPO="$(repo_relative_dir "$SCRIPT_DIR")"
  STATE_REL_IN_REPO="$(repo_relative_dir "$STATE_DIR")"
}

is_runner_internal_path() {
  local path="$1"
  if [[ -n "$STATE_REL_IN_REPO" ]]; then
    case "$path" in
      "$STATE_REL_IN_REPO"/*) return 0 ;;
    esac
  fi

  if [[ -n "$SCRIPT_REL_IN_REPO" ]]; then
    if [[ "$SCRIPT_REL_IN_REPO" == "." ]]; then
      case "$path" in
        .prompt.*|.last-message.*|.prd.*.tmp|progress.log.md) return 0 ;;
      esac
    else
      case "$path" in
        "$SCRIPT_REL_IN_REPO"/.prompt.*|"$SCRIPT_REL_IN_REPO"/.last-message.*|"$SCRIPT_REL_IN_REPO"/.prd.*.tmp|"$SCRIPT_REL_IN_REPO"/progress.log.md) return 0 ;;
      esac
    fi
  fi

  return 1
}

write_report_atomically() {
  local last_message_file="$1"
  local report_rel="$2"
  local report_abs="$REPO_ROOT/$report_rel"
  local report_dir
  local tmp_report

  report_dir="$(dirname "$report_abs")"
  enforce_report_target_confinement "$report_abs" "$report_rel"
  mkdir -p "$report_dir"
  enforce_report_target_confinement "$report_abs" "$report_rel"

  tmp_report="$(mktemp "$report_dir/.ralph-report.XXXXXX.tmp")"
  register_tmp "$tmp_report"

  cp "$last_message_file" "$tmp_report"
  mv "$tmp_report" "$report_abs"
}

mark_story_passed() {
  local story_id="$1"
  local report_rel="$2"
  local now_iso
  local tmp_prd

  now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp_prd="$(mktemp "$SCRIPT_DIR/.prd.XXXXXX.tmp")"
  register_tmp "$tmp_prd"

  jq --arg id "$story_id" --arg now "$now_iso" --arg report "$report_rel" '
    if ([.stories[] | select(.id == $id)] | length) != 1 then
      error("story id not found uniquely")
    else
      .stories = (
        .stories
        | map(
            if .id == $id then
              (
                . + {
                  passes: true,
                  skipped: false,
                  completed_at: $now,
                  report_path: $report
                }
                | del(.skip_reason, .skipped_at)
              )
            else
              .
            end
          )
      )
    end
  ' "$PRD_FILE" > "$tmp_prd"

  mv "$tmp_prd" "$PRD_FILE"
}

story_failure_state_file() {
  printf '%s/.story-failures.tsv' "$STATE_DIR"
}

ensure_story_failure_state_file() {
  local failures_file
  failures_file="$(story_failure_state_file)"
  if [[ ! -f "$failures_file" ]]; then
    : > "$failures_file"
  fi
}

get_story_failure_count() {
  local story_id="$1"
  local failures_file

  failures_file="$(story_failure_state_file)"
  if [[ ! -f "$failures_file" ]]; then
    printf '0'
    return
  fi

  awk -F '\t' -v id="$story_id" '
    $1 == id { print $2; found=1; exit }
    END { if (!found) print 0 }
  ' "$failures_file"
}

set_story_failure_count() {
  local story_id="$1"
  local count="$2"
  local failures_file tmp_file

  ensure_story_failure_state_file
  failures_file="$(story_failure_state_file)"
  tmp_file="$(mktemp "$STATE_DIR/.story-failures.XXXXXX.tmp")"
  register_tmp "$tmp_file"

  awk -F '\t' -v id="$story_id" -v count="$count" '
    BEGIN { written=0 }
    $1 == id {
      if (count > 0) {
        print id "\t" count
      }
      written=1
      next
    }
    { print $0 }
    END {
      if (!written && count > 0) {
        print id "\t" count
      }
    }
  ' "$failures_file" > "$tmp_file"

  mv "$tmp_file" "$failures_file"
}

increment_story_failure_count() {
  local story_id="$1"
  local current next

  current="$(get_story_failure_count "$story_id")"
  next=$((current + 1))
  set_story_failure_count "$story_id" "$next"
  printf '%s' "$next"
}

clear_story_failure_count() {
  local story_id="$1"
  set_story_failure_count "$story_id" 0
}

mark_story_skipped() {
  local story_id="$1"
  local reason="$2"
  local now_iso tmp_prd

  now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp_prd="$(mktemp "$SCRIPT_DIR/.prd.skip.XXXXXX.tmp")"
  register_tmp "$tmp_prd"

  jq --arg id "$story_id" --arg now "$now_iso" --arg reason "$reason" '
    if ([.stories[] | select(.id == $id)] | length) != 1 then
      error("story id not found uniquely")
    else
      .stories = (
        .stories
        | map(
            if .id == $id then
              (
                . + {
                  passes: false,
                  skipped: true,
                  skip_reason: $reason,
                  skipped_at: $now
                }
                | del(.report_path, .completed_at)
              )
            else
              .
            end
          )
      )
    end
  ' "$PRD_FILE" > "$tmp_prd"

  mv "$tmp_prd" "$PRD_FILE"
}

append_progress_log_best_effort() {
  local story_id="$1"
  local report_rel="$2"
  local logger="$SCRIPT_DIR/scripts/append_progress_entry.sh"
  local title

  if ! is_true "$AUTO_PROGRESS_LOG_APPEND"; then
    return
  fi
  if [[ ! -x "$logger" ]]; then
    return
  fi

  title="$(story_title "$story_id")"
  if "$logger" --story "$story_id" --mode "$MODE" --title "$title" --report "$report_rel" >/dev/null 2>&1; then
    log_event "INFO progress_log_appended story=$story_id"
  else
    log_event "WARN progress_log_append_failed story=$story_id"
  fi
}

sync_agents_from_learnings_best_effort() {
  local story_id="$1"
  local sync_script="$SCRIPT_DIR/scripts/sync_agents_from_learnings.sh"

  if ! is_true "$AUTO_SYNC_AGENTS_FROM_LEARNINGS"; then
    return
  fi
  if [[ "$MODE" != "fixing" ]]; then
    return
  fi
  if [[ ! -x "$sync_script" ]]; then
    return
  fi
  if ! path_matches_story_scope "$story_id" "AGENTS.md"; then
    log_event "WARN agents_sync_skipped_out_of_scope story=$story_id path=AGENTS.md"
    return
  fi

  if "$sync_script" --root "$SCRIPT_DIR" >/dev/null 2>&1; then
    log_event "INFO agents_synced_from_learnings"
  else
    log_event "WARN agents_sync_from_learnings_failed"
  fi
}

handle_story_failure() {
  local story_id="$1"
  local rc="$2"
  local failures reason

  log_event "STORY_FAIL id=$story_id mode=$MODE rc=$rc"

  if [[ "$SKIP_AFTER_FAILURES" -le 0 ]]; then
    fail "$TOOL exec failed for story $story_id (rc=$rc, see $RUN_LOG for redacted details)"
  fi

  failures="$(increment_story_failure_count "$story_id")"
  if [[ "$failures" -ge "$SKIP_AFTER_FAILURES" ]]; then
    reason="Skipped after $failures failed runs (last_rc=$rc)"
    mark_story_skipped "$story_id" "$reason"
    clear_story_failure_count "$story_id"
    refresh_progress_snapshot_best_effort
    if [[ "$MODE" == "fixing" && -n "${FIXING_BASE_STATE_FILE:-}" ]]; then
      capture_worktree_state "$FIXING_BASE_STATE_FILE"
    fi
    log_event "STORY_SKIPPED id=$story_id reason=$reason"
    log "story=$story_id skipped after repeated failures (count=$failures rc=$rc)"
    return 0
  fi

  fail "$TOOL exec failed for story $story_id (rc=$rc, failure_count=$failures skip_after=$SKIP_AFTER_FAILURES)"
}

select_next_open_story() {
  next_story_id
}

execute_story_run() {
  local story_id="$1"
  local prompt_file="$2"
  local last_message_file="$3"
  local after_state_file=""
  local codex_rc=0

  if [[ "$MODE" == "fixing" ]]; then
    if [[ -z "$FIXING_BASE_STATE_FILE" ]]; then
      FIXING_BASE_STATE_FILE="$(mktemp "$STATE_DIR/.state-base.XXXXXX.tsv")"
      register_tmp "$FIXING_BASE_STATE_FILE"
      capture_worktree_state "$FIXING_BASE_STATE_FILE"
    fi
  fi

  run_tool_once "$story_id" "$prompt_file" "$last_message_file" || codex_rc=$?

  if [[ "$MODE" == "fixing" ]]; then
    after_state_file="$(mktemp "$STATE_DIR/.state-after.${story_id}.XXXXXX.tsv")"
    register_tmp "$after_state_file"
    capture_worktree_state "$after_state_file"
    enforce_fixing_scope "$story_id" "$FIXING_BASE_STATE_FILE" "$after_state_file"
    cp "$after_state_file" "$FIXING_BASE_STATE_FILE"
  fi

  if [[ "$codex_rc" -ne 0 ]]; then
    return "$codex_rc"
  fi
}

persist_story_result() {
  local story_id="$1"
  local report_rel="$2"
  local last_message_file="$3"
  local learnings_baseline_signature="${4:-__missing__}"

  maybe_require_learning_entry_update "$story_id" "$learnings_baseline_signature"
  write_report_atomically "$last_message_file" "$report_rel"
  mark_story_passed "$story_id" "$report_rel"
  clear_story_failure_count "$story_id"
  refresh_progress_snapshot_best_effort
  append_progress_log_best_effort "$story_id" "$report_rel"
  sync_agents_from_learnings_best_effort "$story_id"
  if [[ "$MODE" == "fixing" && -n "${FIXING_BASE_STATE_FILE:-}" ]]; then
    capture_worktree_state "$FIXING_BASE_STATE_FILE"
  fi
  log_event "STORY_COMPLETE id=$story_id report=$report_rel"
}

refresh_progress_snapshot_best_effort() {
  local generator="$SCRIPT_DIR/scripts/generate_progress.sh"
  local progress_file="$SCRIPT_DIR/progress.txt"

  if ! is_true "$AUTO_PROGRESS_REFRESH"; then
    return
  fi
  if [[ ! -f "$generator" ]]; then
    return
  fi
  if [[ ! -f "$progress_file" ]]; then
    return
  fi

  if "$generator" "$PRD_FILE" "$progress_file" >/dev/null 2>&1; then
    log_event "INFO progress_snapshot_refreshed path=$progress_file"
  else
    log_event "WARN progress_snapshot_refresh_failed path=$progress_file"
  fi
}

process_story() {
  local story_id="$1"
  local created_line
  local report_rel
  local report_rel_file
  local prompt_file
  local last_message_file
  local learnings_baseline_signature="__missing__"

  if ! created_line="$(extract_created_line "$story_id")"; then
    return 1
  fi
  if [[ -z "$created_line" ]]; then
    fail "Story $story_id is missing a valid Created acceptance criterion"
  fi
  report_rel_file="$(mktemp "$STATE_DIR/.report-path.${story_id}.XXXXXX.txt")"
  register_tmp "$report_rel_file"
  extract_report_path "$created_line" > "$report_rel_file"
  report_rel="$(cat "$report_rel_file")"

  if [[ "$MODE" == "fixing" ]]; then
    invalidate_detected_checks_cache
    if is_true "$REQUIRE_LEARNING_ENTRY_FOR_FIXING"; then
      learnings_baseline_signature="$(file_signature_or_missing "$SCRIPT_DIR/learnings.md")"
    fi
  fi

  prompt_file="$(mktemp "$STATE_DIR/.prompt.${story_id}.XXXXXX.md")"
  last_message_file="$(mktemp "$STATE_DIR/.last-message.${story_id}.XXXXXX.md")"
  register_tmp "$prompt_file"
  register_tmp "$last_message_file"

  build_prompt "$story_id" "$report_rel" "$prompt_file"

  log_event "STORY_START id=$story_id mode=$MODE report=$report_rel"
  log "story=$story_id mode=$MODE"

  execute_story_run "$story_id" "$prompt_file" "$last_message_file" || return $?
  persist_story_result "$story_id" "$report_rel" "$last_message_file" "$learnings_baseline_signature"
}
