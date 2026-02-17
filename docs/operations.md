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

If PRD includes `branch_name` (or `branchName`), enable branch sync:

```bash
RALPH_SYNC_BRANCH_FROM_PRD=true ./ralph.sh 0
```

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
