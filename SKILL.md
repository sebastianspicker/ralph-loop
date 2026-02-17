---
name: ralph-audit
description: Golden template for iterative story-based Ralph audit, linting, and fixing runs.
---

# Ralph Audit Skill (Golden Template)

Use this skill when the user asks for structured repository inspection, lint/test reporting, or controlled fixes through a story loop with deterministic state tracking.

## Modes

- `audit`: read-only findings reports
- `linting`: read-only lint/test/validation reports
- `fixing`: scoped write-enabled fixes for referenced issues

## Execute (Standalone)

```bash
MODE=audit   ./ralph.sh 20
MODE=linting ./ralph.sh 10
MODE=fixing  ./ralph.sh 10
```

## Execute (Embedded)

```bash
MODE=audit   ./.codex/ralph-audit/ralph.sh 20
MODE=linting ./.codex/ralph-audit/ralph.sh 10
MODE=fixing  ./.codex/ralph-audit/ralph.sh 10
```

If `N` is omitted, the runner processes all remaining open stories for active `MODE`.

## Dependency Contract

- required: `bash`, `jq`, `mktemp`
- selected runner tool required only when executing `N > 0` stories (currently `codex`)
- optional: `git` (repo root fallback), `timeout`/`gtimeout`/`perl` (timeout helper chain)

## Runner Contract (Required Behavior)

1. The runner picks the next story in `prd.json` where `mode` matches active `MODE` and `passes:false`, sorted by `priority` then `id`.
2. Prompt = selected story context + `CODEX.md`.
3. Per story, run `codex exec` exactly once and save only the final message via `--output-last-message`.
4. Write the report to the path extracted from exactly one acceptance criterion line starting with `Created ...`.
5. After successful report write, atomically persist `passes:true`, `completed_at`, and `report_path` for that story.
6. Use run lock `.runtime/.run.lock` to prevent concurrent PRD mutation; recover stale/orphaned lock dirs safely.
7. Emit `<promise>COMPLETE</promise>` when no open (non-skipped) stories remain.

## Detailed Story Authoring

For higher-quality execution plans, stories should include optional:

- `objective` (single, concrete goal)
- `steps[]` with `id`, `title`, `actions[]`, `expected_evidence[]`, `done_when[]`
- `verification[]` checkpoints
- `out_of_scope[]` boundaries

Runner behavior:
- Fields are validated when present.
- Fields are injected into the generated story prompt.
- Minimal legacy story format remains supported.

## Scope Semantics (Fixing)

- Scope patterns are evaluated in declared order.
- Positive patterns include paths; negated patterns (`!pattern`) exclude matches.
- `**/foo` also matches `foo` at repository root.
- Pre/post worktree snapshots enforce that changed files remain within effective story scope.
- Runner internals (`.runtime/` and runner temp files) are excluded from scope checks.
- Existing files outside configured report dir are protected from report overwrite.
- PRD may mark stories as `skipped:true` with structured skip metadata after repeated failures.

## Guardrails

- `audit` and `linting` must run with `-s read-only`.
- `fixing` must stay atomic and scoped to reported issues.
- `fixing` scope is enforced from filesystem state diffs against story `scope` patterns.
- Modify only paths inside the current story scope patterns.
- Do not perform broad refactors or architecture/security redesigns unless explicitly required by story acceptance criteria.
- Never output secrets.

## Best-Effort Checks (Linting/Fixing Prompts)

Detection order:

1. `package.json` scripts (`lint`, `test`)
2. `pyproject.toml` / `requirements*.txt` (`ruff`, `pytest`)
3. `go.mod` (`go test ./...`)
4. `Cargo.toml` (`cargo test`)
5. `Makefile` targets (`make lint`, `make test`)

If no checks are detected, reports remain valid and must explicitly state the no-op detection result.
In `fixing`, the runner refreshes detected-check cache per story so prompts track current tooling/files.

## Tracking Artifacts

- Story definitions: `prd.json` (or `./.codex/ralph-audit/prd.json` in embedded layout)
- JSON Schema: `prd.schema.json`
- Mode rules: `CODEX.md`
- Reports: `.codex/ralph-audit/audit/*.md`
- Runtime logs/state: `.runtime/` next to the active `ralph.sh`
- Operator guide: `AGENTS.md`
- Long-term learnings: `learnings.md`
- Starter PRD: `prd.json.example`
- Embed helper: `scripts/bootstrap_embedded.sh`
- Learnings helper: `scripts/record_learning.sh`
- Archive helper: `scripts/archive_run_state.sh`
- Companion skills: `skills/prd/SKILL.md`, `skills/ralph/SKILL.md`

## Runtime Tunables

- `RALPH_STALE_LOCK_NO_PID_SECONDS`: stale lock recovery threshold (default `30`)
- `RALPH_TOOL`: runner tool adapter (default `codex`, `codex-cli` alias accepted)
- `RALPH_MAX_ATTEMPTS_PER_STORY`: retry budget for transient tool/output-contract failures (default `1`)
- `RALPH_SKIP_AFTER_FAILURES`: mark story skipped after N failed runs (default `0`, disabled)
- `RALPH_REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH`: require `## External References` with links + ISO dates when search is enabled (default `true`)
- `RALPH_MODEL_PREFLIGHT`: run preflight model check before first story (default `false`)
- `RALPH_SECURITY_PREFLIGHT`: scan for sensitive env vars and warn (default `true`)
- `RALPH_SECURITY_PREFLIGHT_FAIL_ON_RISK`: fail run when security preflight detects sensitive env vars (default `false`)
- `RALPH_AUTO_ARCHIVE_ON_PROJECT_CHANGE`: auto-archive when `prd.json.project` changes (default `false`)
- `RALPH_REQUIRE_LEARNING_ENTRY_FOR_FIXING`: require `learnings.md` update for successful fixing stories (default `false`)
- `RALPH_SYNC_BRANCH_FROM_PRD`: checkout/create branch from PRD `branch_name`/`branchName` (default `false`)
- `RALPH_AUTO_PROGRESS_LOG_APPEND`: append to `progress.log.md` after successful stories (default `true`)
- `RALPH_AUTO_SYNC_AGENTS_FROM_LEARNINGS`: sync latest learning note into `AGENTS.md` after successful fixing stories (default `false`)
- `CODEX_TIMEOUT_SECONDS`: timeout per story (default `900`, `0` disables timeout)
- `RALPH_MODEL` / `CODEX_MODEL`: model override
- `RALPH_REASONING_EFFORT` / `CODEX_REASONING_EFFORT`: reasoning effort
- `RALPH_CAPTURE_CODEX_OUTPUT`: capture and redact codex stdout/stderr to `.runtime/run.log`

## Regression Suite

```bash
./tests/ralph_validation_test.sh
./tests/ralph_scope_enforcement_test.sh
./tests/ralph_lock_ownership_test.sh
./tests/ralph_detected_checks_cache_test.sh
./tests/ralph_detailed_steps_prompt_test.sh
./tests/ralph_report_path_overwrite_guard_test.sh
./tests/ralph_report_path_dot_slash_test.sh
./tests/ralph_scope_globstar_semantics_test.sh
./tests/ralph_stat_flavor_detection_test.sh
./tests/ralph_no_codex_zero_run_test.sh
./tests/ralph_tool_selection_test.sh
./tests/ralph_prd_example_validation_test.sh
./tests/ralph_bootstrap_embedded_test.sh
./tests/ralph_record_learning_test.sh
./tests/ralph_archive_run_state_test.sh
./tests/ralph_prd_hidden_chars_test.sh
./tests/ralph_retry_budget_test.sh
./tests/ralph_search_references_contract_test.sh
./tests/ralph_auto_archive_on_project_change_test.sh
./tests/ralph_model_preflight_test.sh
./tests/ralph_learning_entry_enforcement_test.sh
./tests/ralph_complete_signal_test.sh
./tests/ralph_skip_after_failures_test.sh
./tests/ralph_branch_sync_from_prd_test.sh
./tests/ralph_append_progress_entry_test.sh
./tests/ralph_progress_log_autappend_test.sh
./tests/ralph_sync_agents_from_learnings_test.sh
./tests/ralph_agents_sync_integration_test.sh
./tests/ralph_security_preflight_test.sh
```
