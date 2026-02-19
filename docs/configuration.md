# Configuration Reference

This document describes CLI flags and environment variables supported by `ralph.sh`.

## CLI Usage

```bash
./ralph.sh [N] \
  [--mode audit|linting|fixing] \
  [--tool codex] \
  [--search|--no-search] \
  [--model-preflight|--no-model-preflight] \
  [--security-preflight|--no-security-preflight] \
  [--auto-archive|--no-auto-archive] \
  [--require-learning-entry|--no-require-learning-entry] \
  [--sync-branch|--no-sync-branch] \
  [--model <model-id>] \
  [--reasoning-effort <low|medium|high>] \
  [--timeout-seconds <seconds>] \
  [--strict-report-dir|--no-strict-report-dir] \
  [-q|--quiet] [-v|--verbose] \
  [--validate-prd] [--list-stories]
```

## Resolution Order

### Mode

1. `--mode`
2. `MODE`
3. `prd.json.defaults.mode_default`
4. fallback `audit`

### Model

1. `--model`
2. `RALPH_MODEL`
3. `CODEX_MODEL`
4. `prd.json.defaults.model_default`
5. fallback `gpt-5.3`

### Reasoning effort

1. `--reasoning-effort`
2. `RALPH_REASONING_EFFORT`
3. `CODEX_REASONING_EFFORT`
4. `prd.json.defaults.reasoning_effort_default`
5. fallback `high`

## Environment Variables

### Execution and tooling

- `MODE`: `audit|linting|fixing`
- `RALPH_TOOL`: currently `codex` (alias `codex-cli` accepted)
- `RALPH_REPO_ROOT`: force repository root path
- `CODEX_TIMEOUT_SECONDS`: per-story timeout (`0` disables timeout)
- `RALPH_MAX_ATTEMPTS_PER_STORY`: retry budget per story (`>=1`)

### Search and output contract

- `RALPH_SEARCH_ENABLED_BY_DEFAULT`: `true|false`
- `RALPH_REQUIRE_EXTERNAL_REFERENCES_ON_SEARCH`: `true|false`

### Safety and enforcement

- `RALPH_STRICT_REPORT_DIR`: require report target under `defaults.report_dir`
- `RALPH_FIXING_STATE_METHOD`: `auto|full|git`
- `RALPH_SKIP_AFTER_FAILURES`: skip story after N failed runs (`0` disables)
- `RALPH_STALE_LOCK_NO_PID_SECONDS`: stale lock threshold for lock dirs without valid PID

### Security controls

- `RALPH_SECURITY_PREFLIGHT`: `true|false`
- `RALPH_SECURITY_PREFLIGHT_FAIL_ON_RISK`: `true|false`

### Optional workflow automation

- `RALPH_MODEL_PREFLIGHT`: run model preflight before first story
- `RALPH_AUTO_ARCHIVE_ON_PROJECT_CHANGE`: archive state when PRD project changes
- `RALPH_REQUIRE_LEARNING_ENTRY_FOR_FIXING`: require `learnings.md` update in fixing mode
- `RALPH_SYNC_BRANCH_FROM_PRD`: checkout/create branch from PRD branch field
- `RALPH_AUTO_PROGRESS_LOG_APPEND`: append `progress.log.md` entries automatically
- `RALPH_AUTO_PROGRESS_REFRESH`: refresh `progress.txt` if file exists
- `RALPH_AUTO_SYNC_AGENTS_FROM_LEARNINGS`: sync latest learning note into `AGENTS.md`

### Output and helpers

- `RALPH_VERBOSITY`: `normal|quiet|verbose` (or use `-q` / `-v`). Quiet: only errors and final summary; verbose: more per-story output.
- `--validate-prd`: validate PRD and exit without running stories.
- `--list-stories`: list open stories for the current mode (id, priority, mode, title) and exit.

### Diagnostics

- `RALPH_CAPTURE_CODEX_OUTPUT`: capture redacted tool stdout/stderr into `.runtime/run.log`

## Report directory

- `defaults.report_dir` in `prd.json` defines the default directory for story reports. The runner resolves it at startup and exposes it as `DEFAULT_REPORT_DIR` in config; each story’s report path is taken from its acceptance criterion (`Created <path>.md ...`) and must lie under this directory when strict report dir is enabled.

## Notes on `progress.txt`

`progress.txt` is generated state, not authoritative state.

- Authoritative state: `prd.json`
- Generate explicitly with `scripts/generate_progress.sh`
- Keep it gitignored unless a snapshot commit is intentional
