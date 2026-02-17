---
name: ralph
description: "Convert a Markdown PRD to the Ralph Audit `prd.json` schema (audit/linting/fixing Stories)."
user-invocable: true
---

# PRD -> Ralph JSON Converter

Konvertiert ein PRD (Markdown) in dieses Template-Schema:
- `defaults`-Block (vollständig, schema-konform),
- `stories[]` mit `mode`, `scope`, `acceptance_criteria`, `steps`, `verification`, `out_of_scope`,
- `passes: false` für alle Stories.

## Zielschema (Pflichtfelder)

Top-Level:
- `schema_version`
- `project`
- `defaults`
- `stories`

`defaults`:
- `mode_default`
- `max_stories_default`
- `model_default`
- `reasoning_effort_default`
- `report_dir`
- `sandbox_by_mode`
- `lint_detection_order`

Story:
- `id`, `title`, `priority`, `mode`, `scope`, `acceptance_criteria`, `passes`
- optional: `notes`, `objective`, `steps`, `verification`, `out_of_scope`

## Konvertierungsregeln

1. Erzeuge kleine, iterative Stories mit eindeutiger Reihenfolge.
2. Gruppiere typischerweise in:
  - `audit` (Analyse, read-only),
  - `linting` (Checks, read-only),
  - `fixing` (gezielte Korrekturen, write).
3. Jede Story braucht genau eine AC-Zeile mit:
  - `Created <repo-rel-path>.md ...`
4. `scope` muss restriktiv und realistisch sein.
5. `steps` klein halten (lieber viele kleine Schritte als wenige große).
6. `verification` als explizite Prüfliste ausformulieren.
7. `out_of_scope` für Scope-Containment setzen.

## Deterministische Priorisierung

- Prioritäten streng aufsteigend.
- Abhängigkeiten zuerst.
- Keine Story darf von späteren Stories abhängen.

## Ausgabe

- Ziel: `prd.json` im Ralph-Template-Ordner.
- Anschließend Schema/Runtime-Validierung sicherstellen:
  - `./tests/ralph_validation_test.sh`
  - `./tests/ralph_schema_runtime_contract_test.sh`

## Checkliste

- [ ] Alle Pflichtfelder vorhanden
- [ ] Pro Story genau eine `Created ...`-Zeile
- [ ] Alle Stories mit `passes: false`
- [ ] `mode` nur `audit|linting|fixing`
- [ ] Prioritäten eindeutig und geordnet
- [ ] Scope/Verification/Out-of-Scope klar
