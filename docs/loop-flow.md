# Ralph Loop Flow

This flow documents the deterministic per-story runner contract implemented in `ralph.sh`.

```mermaid
flowchart TD
  A["Start Run"] --> B["Resolve config (mode/tool/N)"]
  B --> C["Validate PRD + schema contract"]
  C --> D["Acquire run lock"]
  D --> E{"Open story exists?"}
  E -- "No" --> Z["Run summary + exit"]
  E -- "Yes" --> F["Pick next story by (priority,id)"]
  F --> G["Build prompt from story + CODEX.md"]
  G --> H["Execute selected tool once"]
  H --> I["Capture last message output"]
  I --> J["Parse Created <path> and validate target"]
  J --> K["Atomic report write"]
  K --> L["Atomic PRD pass update"]
  L --> M["Best-effort progress refresh"]
  M --> N{"Reached N stories?"}
  N -- "No" --> E
  N -- "Yes" --> Z
```

## Invariants

- Exactly one story is processed per loop iteration.
- Exactly one tool execution happens per story.
- Report write and PRD mutation are both atomic.
- `fixing` mode enforces scope based on pre/post worktree state.
- Locking prevents concurrent writers on `prd.json`.
