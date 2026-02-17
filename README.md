# Ralph Audit Loop (Golden Template)

Deterministic, story-driven automation loop for repository auditing, linting, and scoped fixing.

This template is designed for Codex-style agent runs where execution safety, repeatability, and atomic state updates matter more than speed or improvisation.

## What This Repository Provides

- A strict loop runner: `ralph.sh`
- Modular runtime implementation in `lib/ralph/*.sh`
- A schema-validated PRD contract (`prd.json`, `prd.schema.json`, `prd.validate.jq`)
- A mode policy contract for model behavior (`CODEX.md`)
- Operational helper scripts for progress, learning logs, and archiving
- Regression tests for runner safety and behavior

## Core Guarantees

- Deterministic story selection (`priority`, then `id`)
- Exactly one tool execution per story attempt
- Atomic report writes
- Atomic PRD status updates
- Lock-protected state mutation (`.runtime/.run.lock`)
- Repository-constrained report path handling
- Scope enforcement in `fixing` mode using pre/post state snapshots

## Supported Layouts

### Standalone template repository

Run directly from this repository root:

```bash
MODE=audit ./ralph.sh 20
```

### Embedded template in another repository

Run from target repository root:

```bash
MODE=audit ./.codex/ralph-audit/ralph.sh 20
```

The runner auto-detects both layouts. If detection is ambiguous, set:

```bash
export RALPH_REPO_ROOT=/absolute/path/to/repo
```

## Quick Start

### 1) Validate dependencies

Required:

- `bash`
- `jq`
- `mktemp`

Required only when `N > 0` (story execution):

- `codex`

Optional:

- `git` (branch sync + root fallback)
- `timeout` / `gtimeout` / `perl` (timeout helper chain)

### 2) Create or update `prd.json`

Use `prd.json.example` as your starting point.

### 3) Run a mode

```bash
MODE=audit ./ralph.sh 5
MODE=linting ./ralph.sh 5
MODE=fixing ./ralph.sh 3
```

If `N` is omitted, the runner uses `defaults.max_stories_default` from `prd.json`.

## Loop Contract (High Level)

For each iteration:

1. Pick next open story for active mode (`passes=false`, `skipped!=true`)
2. Build prompt from story data + `CODEX.md`
3. Execute tool once
4. Capture final message only (`--output-last-message`)
5. Resolve report target from exactly one `Created ...` acceptance criterion
6. Write report atomically
7. Mark story pass atomically in `prd.json`
8. Continue until `N` is reached or no stories remain

When no open stories remain, the runner emits:

```xml
<promise>COMPLETE</promise>
```

## Modes

- `audit`: read-only findings and risk reports
- `linting`: read-only checks and lint/test result reporting
- `fixing`: workspace-write, but strictly story-scoped

Safety boundaries are enforced in code, not only in prompt text.

## Repository Structure

- `ralph.sh`: entrypoint and runtime wiring
- `lib/ralph/core.sh`: traps, logging, cleanup, shared helpers
- `lib/ralph/config.sh`: argument/env parsing, PRD validation, lock handling, repo resolution
- `lib/ralph/prd.sh`: story extraction, scope/path handling, report-path confinement checks
- `lib/ralph/prompt.sh`: prompt generation + best-effort check detection
- `lib/ralph/runner.sh`: tool execution, retries, redaction, state capture, scope enforcement, persistence
- `prd.json`: active story plan and execution state
- `prd.schema.json`: schema source of truth
- `prd.validate.jq`: runtime contract validation filter
- `CODEX.md`: model behavior contract for each story run
- `AGENTS.md`: concise operator/agent guide
- `scripts/*`: helper automation scripts
- `tests/*`: regression coverage for loop invariants and safety behavior

## PRD Contract Summary

Minimal required story fields:

- `id`
- `title`
- `priority`
- `mode`
- `scope[]`
- `acceptance_criteria[]` (must contain exactly one `Created ...` line)
- `passes`

Recommended optional fields for better execution quality:

- `objective`
- `steps[]`
- `verification[]`
- `out_of_scope[]`
- `notes`

See:

- `prd.json.example`
- `skills/prd/SKILL.md`
- `skills/ralph/SKILL.md`

## Runtime Artifacts and Logs

- `.runtime/events.log`: lifecycle and decision events
- `.runtime/run.log`: optional redacted tool output
- `progress.log.md`: append-only human-readable progress history
- `learnings.md`: append-only reusable implementation learnings

### About `progress.txt`

`progress.txt` is a generated snapshot, not the source of truth.

- Source of truth is always `prd.json` (`stories[].passes`, `stories[].skipped`)
- Regenerate snapshot via `scripts/generate_progress.sh`
- Keep `progress.txt` out of git unless you intentionally want a frozen snapshot

## Helper Scripts

- `scripts/generate_progress.sh`: generate/update `progress.txt`
- `scripts/append_progress_entry.sh`: append one progress event to `progress.log.md`
- `scripts/record_learning.sh`: append a structured entry to `learnings.md`
- `scripts/sync_agents_from_learnings.sh`: sync latest learning note into `AGENTS.md`
- `scripts/archive_run_state.sh`: archive run state to `archive/<timestamp>-<label>/`
- `scripts/bootstrap_embedded.sh`: copy this template into another repository as `.codex/ralph-audit`

## Embedding This Template

```bash
./scripts/bootstrap_embedded.sh /absolute/path/to/target-repo
```

Options:

- `--force`: replace existing `.codex/ralph-audit`
- `--with-tests`: also copy template tests into embedded target

## Configuration Reference

Configuration is documented in detail here:

- [`docs/README.md`](docs/README.md)
- [`docs/configuration.md`](docs/configuration.md)

Operational runbook is documented here:

- [`docs/operations.md`](docs/operations.md)

Loop flow diagram:

- [`docs/loop-flow.md`](docs/loop-flow.md)

## Testing

Run all tests:

```bash
for t in tests/*.sh; do bash "$t"; done
```

Run shell quality checks:

```bash
shellcheck -x ralph.sh lib/ralph/*.sh scripts/*.sh tests/*.sh tests/lib/*.sh
```

## Troubleshooting

### `Invalid prd.json structure or story constraints`

- Validate against `prd.schema.json`
- Check `prd.validate.jq` expectations
- Confirm required defaults and story fields are present

### Story marked skipped unexpectedly

- Check `RALPH_SKIP_AFTER_FAILURES`
- Inspect `.runtime/events.log` for `STORY_FAIL` and `STORY_SKIPPED`

### Scope violation in `fixing`

- Verify story `scope` patterns
- Check ordered include/exclude semantics (`!pattern` exclusions)
- Review changed paths in error output

### Missing tool dependency

- For `N > 0`, ensure `codex` is installed and in `PATH`

## Security Notes

- Never place secrets directly in reports
- Security preflight can warn/fail on sensitive env vars (`RALPH_SECURITY_PREFLIGHT*`)
- Report writes are repository-confined and path-validated

For disclosure process, see [`SECURITY.md`](SECURITY.md).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT-style template license in [`LICENSE`](LICENSE).
