---
name: prd
description: "Create a detailed feature PRD in Markdown as input for the Ralph PRD conversion."
user-invocable: true
---

# PRD Generator (Ralph Audit Template)

Erstellt ein präzises Feature-PRD in Markdown. Dieses Dokument ist die Eingabe für den `skills/ralph`-Konverter zu `prd.json`.

## Ziel

1. Feature-Idee aufnehmen.
2. 3-5 kritische Rückfragen mit Antwortoptionen stellen.
3. PRD in klarer, umsetzbarer Struktur schreiben.
4. Datei unter `tasks/prd-<feature>.md` speichern.

Kein Implementieren in diesem Schritt.

## Rückfragen (Pflicht bei Unklarheit)

Fokussiere auf:
- Problem/Outcome
- Zielnutzer
- Scope/Non-Goals
- Constraints/Risiken
- Erfolgskriterien

Nutze nummerierte Fragen mit Antwortoptionen (`A/B/C/D`) für schnelle Antworten.

## Ausgabeformat PRD (Markdown)

1. `# PRD: <Feature>`
2. `## Kontext / Problem`
3. `## Ziele`
4. `## User Stories`
5. `## Funktionale Anforderungen`
6. `## Nicht-Ziele (Out of Scope)`
7. `## Technische Randbedingungen`
8. `## Abnahmekriterien / Erfolgsmessung`
9. `## Offene Fragen`

## Story-Qualitätsregeln

Jede Story muss:
- klein genug für eine fokussierte Iteration sein,
- verifizierbare Akzeptanzkriterien enthalten,
- klare Grenzen (`out of scope`) haben,
- konkrete Evidenzquellen nennen (Dateien/Checks/Outputs).

Wenn UI betroffen ist, fordere explizite Browser-Verifikation als Kriterium.

## Speichern

- Ordner: `tasks/`
- Dateiname: `prd-<feature-kebab-case>.md`

## Checkliste

- [ ] Rückfragen gestellt und beantwortet
- [ ] Stories klein und eindeutig
- [ ] Akzeptanzkriterien testbar
- [ ] Out-of-Scope klar benannt
- [ ] Datei in `tasks/` gespeichert
