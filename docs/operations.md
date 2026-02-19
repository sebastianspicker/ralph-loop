# Operations Runbook

This runbook covers day-to-day usage and maintenance of the Ralph loop template.

## Daily Workflow

1. Update `prd.json` story set.
2. Run one mode with a small `N`.
3. Inspect generated reports.
4. Review `.runtime/events.log` for execution trace.
5. Repeat iteratively.

## Typical Commands

```bash
MODE=audit ./ralph.sh 3
MODE=linting ./ralph.sh 3
MODE=fixing ./ralph.sh 1
```

## Monitoring Runtime

```bash
tail -n 200 -f .runtime/events.log
```

Optional redacted tool output:

```bash
RALPH_CAPTURE_CODEX_OUTPUT=true MODE=audit ./ralph.sh 1
tail -n 200 -f .runtime/run.log
```

## Progress and Learning Logs

Generate progress snapshot on demand:

```bash
./scripts/generate_progress.sh
```

Append manual progress item:

```bash
./scripts/append_progress_entry.sh \
  --story FIX-001 \
  --mode fixing \
  --title "Fix report path validation" \
  --report "audit/FIX-001.md"
```

Record reusable learning:

```bash
./scripts/record_learning.sh \
  --story FIX-001 \
  --note "Validate report target before atomic write" \
  --files "lib/ralph/prd.sh,lib/ralph/runner.sh"
```

## Safe State Archiving

Archive current run state before major PRD resets:

```bash
./scripts/archive_run_state.sh --reason "before new milestone"
```

Custom label/output path:

```bash
./scripts/archive_run_state.sh \
  --label "milestone-a" \
  --archive-root ./archive
```

## Project Switch Automation

Enable automatic state archival when `prd.json.project` changes:

```bash
RALPH_AUTO_ARCHIVE_ON_PROJECT_CHANGE=true ./ralph.sh 0
```

## Branch Sync From PRD

When `RALPH_SYNC_BRANCH_FROM_PRD=true`, the runner syncs the current git branch to the value in `prd.json` (`branch_name` or `branchName`). If the target branch already exists, the runner checks it out; if it does not exist, the runner creates it (from the default base branch, or from the current HEAD). Use this to keep the working branch aligned with the PRD before running stories.

```bash
RALPH_SYNC_BRANCH_FROM_PRD=true ./ralph.sh 0
```

## Embedding This Template

To embed the Ralph Audit template into another repository:

1. Run the bootstrap script from this template repo:  
   `./scripts/bootstrap_embedded.sh /absolute/path/to/target-repo`  
   Use `--force` to overwrite an existing `.codex/ralph-audit` and `--with-tests` to copy tests.
2. In the target repo, add or adjust `prd.json` (e.g. copy from `.codex/ralph-audit/prd.json.example`). Set `defaults.report_dir` as needed (default: `.codex/ralph-audit/audit`).
3. From the **target repository root**, run the embedded runner:  
   `./.codex/ralph-audit/ralph.sh [N]`  
   with `MODE=audit`, `MODE=linting`, or `MODE=fixing` as required.

Reports and runtime state live under `.codex/ralph-audit/` and `.codex/ralph-audit/.runtime/` in the target repo.

## Incident Triage Checklist

If a run fails unexpectedly:

1. Check `.runtime/events.log` around `STORY_START` and `STORY_FAIL`.
2. Confirm story has exactly one `Created ...` acceptance criterion.
3. Verify report target path and strict report dir policy.
4. For fixing mode, inspect scope patterns and changed files.
5. Re-run with smaller `N` to isolate one story.

## CI Sanity Commands

```bash
shellcheck -x ralph.sh lib/ralph/*.sh scripts/*.sh tests/*.sh tests/lib/*.sh
for t in tests/*.sh; do bash "$t"; done
```
