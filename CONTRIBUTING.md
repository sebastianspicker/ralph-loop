# Contributing

Thank you for contributing to the Ralph Audit Loop template.

## Scope of This Repository

This repository is a reusable golden template. Changes should improve one or more of these areas:

- loop correctness
- safety and containment
- deterministic behavior
- portability
- documentation clarity
- regression coverage

## Local Setup

Required tools:

- `bash`
- `jq`
- `mktemp`
- `shellcheck`

Optional but useful:

- `git`
- `codex` (needed only for execution flows, not for most tests)

## Development Rules

- Keep shell scripts POSIX-aware where practical, but this project targets `bash`.
- Prefer explicit failure handling over silent fallback.
- Avoid broad refactors mixed with behavior changes.
- Preserve deterministic behavior of the story loop.
- Keep security-sensitive behavior conservative by default.

## Testing Requirements

Before opening a PR:

1. Run shell linting:

```bash
shellcheck -x ralph.sh lib/ralph/*.sh scripts/*.sh tests/*.sh tests/lib/*.sh
```

2. Run full regression suite:

```bash
for t in tests/*.sh; do bash "$t"; done
```

3. If behavior changes, add or update tests in `tests/`.

## Documentation Requirements

For non-trivial behavior changes:

- Update `README.md`.
- Update relevant files in `docs/`.
- Keep examples consistent with actual CLI/env behavior.

## Commit and PR Guidance

Use focused commits with clear intent.

Suggested commit style:

- `fix(runner): fail hard on metadata snapshot errors`
- `docs(readme): clarify progress snapshot source of truth`
- `test(scope): add regression for failing tool run path`

In PR description include:

- problem statement
- root cause
- implemented fix
- test evidence
- any backward compatibility impact

## Backward Compatibility

This template is consumed by embedded copies in other repositories.

Avoid breaking changes unless necessary. If breaking behavior is required:

- document migration steps
- update `prd.json.example`
- add explicit test coverage
