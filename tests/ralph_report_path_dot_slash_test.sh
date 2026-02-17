#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/lib/test_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test_helpers.sh"

require_cmds jq mktemp

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
printf '# dot slash report\n' > "$out"
EOF
  chmod +x "$fake_codex"
}

prepare_repo() {
  local repo_dir="$1"
  prepare_runner_and_codex "$repo_dir"

  cat > "$repo_dir/prd.json" <<'EOF'
{
  "schema_version": "1.0.0",
  "project": "dot-slash-report-path-test",
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
    "lint_detection_order": [
      "package.json scripts (lint/test)"
    ]
  },
  "stories": [
    {
      "id": "AUDIT-001",
      "title": "Dot slash created path",
      "priority": 1,
      "mode": "audit",
      "scope": ["**/*"],
      "acceptance_criteria": [
        "Created ./.codex/ralph-audit/audit/AUDIT-001.md with report output"
      ],
      "passes": false
    }
  ]
}
EOF
}

run_case() {
  local tmpdir bindir rc report_path
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
    fail_case "report-path-dot-slash" "expected success, got rc=$rc" "$tmpdir/out.log" "$tmpdir"
  fi

  if [[ ! -f "$tmpdir/repo/.codex/ralph-audit/audit/AUDIT-001.md" ]]; then
    fail_case "report-path-dot-slash" "expected normalized report file to exist" "$tmpdir/out.log" "$tmpdir"
  fi

  report_path="$(jq -r '.stories[0].report_path // ""' "$tmpdir/repo/prd.json")"
  if [[ "$report_path" != ".codex/ralph-audit/audit/AUDIT-001.md" ]]; then
    fail_case "report-path-dot-slash" "report_path should be normalized without leading ./, got=$report_path" "$tmpdir/repo/prd.json" "$tmpdir"
  fi

  cleanup_dir "$tmpdir"
  printf 'PASS [report-path-dot-slash]\n'
}

run_case
printf 'All dot slash report path tests passed.\n'
