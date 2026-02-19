# shellcheck shell=bash
# Tool execution: timeout, redaction, codex run, external-refs contract.
# Sourced by runner.sh; expects core.sh and config.sh globals.

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
