#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds mktemp grep

make_fake_codex() {
  local fake_codex="$1"
  cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [[ "$arg" == "--output-last-message" ]]; then
    j=$((i + 1))
    out="${!j}"
  fi
done
: "${out:?missing --output-last-message}"
cat >/dev/null
printf '# progress log report\n' > "$out"
EOF
  chmod +x "$fake_codex"
}

prepare_repo() {
  local repo_dir="$1"
  prepare_runner_and_codex "$repo_dir"
  mkdir -p "$repo_dir/scripts"
  cp "$ROOT_DIR/scripts/append_progress_entry.sh" "$repo_dir/scripts/append_progress_entry.sh"
  chmod +x "$repo_dir/scripts/append_progress_entry.sh"
  cp "$ROOT_DIR/progress.log.md" "$repo_dir/progress.log.md"
  cat > "$repo_dir/prd.json" <<'EOF'
{
  "schema_version": "1.0.0",
  "project": "progress-log-autappend-test",
  "defaults": {
    "mode_default": "audit",
    "max_stories_default": "all_open",
    "model_default": "gpt-5.3",
    "reasoning_effort_default": "high",
    "report_dir": ".codex/ralph-audit/audit",
    "sandbox_by_mode": {
      "audit": "read-only",
      "linting": "read-only",
      "fixing": "workspace-write"
    },
    "lint_detection_order": ["package.json scripts (lint/test)"]
  },
  "stories": [
    {
      "id": "AUDIT-001",
      "title": "Progress Log Append",
      "priority": 1,
      "mode": "audit",
      "scope": ["**/*"],
      "acceptance_criteria": ["Created .codex/ralph-audit/audit/AUDIT-001.md with report"],
      "passes": false
    }
  ]
}
EOF
}

run_case() {
  local tmpdir bindir rc
  tmpdir="$(mktemp -d)"
  bindir="$tmpdir/bin"
  mkdir -p "$bindir" "$tmpdir/repo"
  make_fake_codex "$bindir/codex"
  prepare_repo "$tmpdir/repo"

  set +e
  (
    cd "$tmpdir/repo"
    PATH="$bindir:$PATH" ./ralph.sh 1
  ) > "$tmpdir/out.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    fail_case "progress-log-autappend" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi
  if ! grep -q 'AUDIT-001' "$tmpdir/repo/progress.log.md"; then
    fail_case "progress-log-autappend" "expected appended progress log entry" "$tmpdir/repo/progress.log.md" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [progress-log-autappend]\n'
}

run_case
printf 'All progress log auto-append tests passed.\n'
