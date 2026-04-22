---
name: audit-metadata
description: On-demand full-vault metadata audit — canonical compliance, fuzzy synonym detection, property integrity, staleness, promotion and retirement candidates, and audit log hygiene for Obsidian vaults seeded with the metadata framework
---

> **Status: Reference-only (retained for design input to `/metadata-check`).**
>
> This Skill is no longer maintained and is **not expected to execute correctly.** It is retained to preserve lessons from the Phase 1 Skill implementation for use when designing `/metadata-check` (the kernel-scope replacement, tracked in `DeliberateGeek/template-obsidian#27`).
>
> After the kernel scope cut landed (`DeliberateGeek/template-obsidian#26`), several runtime dependencies of this Skill were removed: the daily-rotation `Audit Logs/YYYY-MM-DD.md` file is no longer written by any script (so Section 6 has no input), `Set-MetadataDefer.ps1` was deleted (so deferral flows no longer function), and the `/init-vault-metadata-framework` Skill was deleted (so references to it are dead). The **text** of every section remains intact — the text is the reference value, not the runtime behavior.
>
> **When using this Skill as reference for `/metadata-check` design:** extract patterns worth preserving and anti-patterns to avoid; do NOT ground the new design in this implementation (see `DeliberateGeek/template-obsidian#27` clarification comment for the "how to use / how not to use" framing).
>
> **Removal:** this directory is deleted once `/metadata-check` lands, tracked in a follow-up issue filed as part of `#26`.

---

# /audit-metadata — On-Demand Vault Metadata Audit

**Purpose:** Full-vault validation, drift detection, and fuzzy-synonym discovery for an Obsidian vault that has been seeded with the metadata framework. Distinct from (a) at-capture classification, where Claude proposes tags/properties on a single note in real time, and (b) session-end review, which acts on a queue of deferred items accumulated during the session. This Skill does a comprehensive sweep of the entire vault on demand.

**Usage:**

```
/audit-metadata
/audit-metadata --content-type reference
/audit-metadata --since 2026-01-01
/audit-metadata --skip-retirement --skip-staleness
/audit-metadata --skip-commit
```

## When to invoke

- Quarterly or ad-hoc canonical-list hygiene pass
- After a vault migration or bulk import
- When the user suspects drift ("feels like I've been adding random tags lately")
- Before onboarding a vault to a new canonical standard

## When NOT to invoke

- Routine note creation — use at-capture classification
- End of a working session — use the automatic session-end flow
- Quick lookups of a single tag's usage — use Obsidian's tag pane or a dataview query

## Inputs

| Flag | Default | Purpose |
|------|---------|---------|
| `--content-type <id>` | (all) | Restrict audit to notes of the given content type |
| `--since <YYYY-MM-DD>` | (all-time) | Restrict scans to notes modified on or after this date |
| `--skip-canonical` | off | Skip Section 1 (canonical compliance) |
| `--skip-fuzzy` | off | Skip Section 2 (fuzzy synonym candidates) |
| `--skip-property-integrity` | off | Skip Section 3 |
| `--skip-staleness` | off | Skip Section 4 |
| `--skip-review` | off | Skip Section 5 (long-pending review) |
| `--skip-promotion` | off | Skip Section 6 (promotion candidates) |
| `--skip-retirement` | off | Skip Section 7 (retirement candidates) |
| `--skip-hygiene` | off | Skip Section 8 (audit log hygiene) |
| `--skip-commit` | off | Do not propose a commit at end of run; emit reminder instead |

All section-skip flags are explicit. There is no auto-skip based on vault age or activity. If a section produces no findings, it is still run (so the omission rule can take effect) — skipping is for cases where the user deliberately wants to defer certain kinds of work.

## Required source files

Read these at start. If any is missing or malformed, halt with a specific error.

| File | Purpose |
|------|---------|
| `🫥 Meta/vault-metadata.yaml` | Per-vault canonical list, content types, thresholds, retention |
| `.claude/Claude Context/metadata-schema.yaml` | Structural schema the vault-metadata.yaml must conform to |
| `.claude/Claude Context/metadata-philosophy.md` | Judgment reference for boundary rules and classification |

## Pre-flight checks

Run in order. Abort on any failure with a clear message — do not attempt partial audits against a malformed vault.

1. **Vault seeded** — `🫥 Meta/vault-metadata.yaml` exists and parses as YAML. If the file is still the raw `.template` copy (name starts with `ReplaceWithVaultName`), halt: *"Vault is not yet seeded. Run vault onboarding first."*
2. **Schema match** — `vault-metadata.yaml` structurally conforms to `metadata-schema.yaml`. Invoke:

   ```
   pwsh.exe -File .claude/scripts/Invoke-MetadataValidate.ps1 -MetadataPath "🫥 Meta/vault-metadata.yaml"
   ```

   Interpret the exit code per `.claude/Claude Context/framework-scripts-reference.md`:
   - **Exit 0** — schema conforms; proceed.
   - **Exit 1** — structural findings present. Halt with the surfaced findings and guidance: *"Fix the schema violations above, then re-run `/audit-metadata`. If the violations are non-obvious, run `/init-vault-metadata-framework --force-reinit` to reconstruct a conformant canonical list."* Do not attempt a partial audit against a malformed canonical list.
   - **Exit 2** — environment or framework problem. Halt with the surfaced message; do not treat as user-correctable.
3. **Audit Logs directory** — `🫥 Meta/Audit Logs/` exists (created by template integration). If absent, halt: *"Audit Logs directory missing. Verify template was applied correctly."*
4. **Vault git state** — run `git status --porcelain` at the vault root.
   - **Clean** → proceed.
   - **Dirty** → prompt the user:
     - `(a)` Stash pending changes, run audit, pop stash at end
     - `(b)` Commit pending changes separately first, then run audit (prompts for a pre-audit commit message using the vault's guidelines)
     - `(c)` Abort — let the user resolve manually
     - `(d)` Proceed with dirty state — audit-produced files will still be staged on explicit paths; user is responsible for reconciling

## The eight audit sections

Run every section that is not explicitly skipped. **Empty sections — those with zero findings — are omitted from the final report.** This keeps the output signal-dense without compromising the invariant that every non-skipped section was actually evaluated.

**Section ordering is load-bearing.** Sections run in numerical order, and later sections see the post-normalization state produced by earlier sections. In particular: Section 2 (fuzzy synonyms) re-evaluates the tag state *after* Section 1 has applied its auto-fixes. Running Section 1 in isolation (`--skip-fuzzy`) can therefore leave a note with a format-valid but still-unknown tag (e.g., `home_lab` → `home-lab`, which is valid kebab-case but not in the canonical topics list). In that scenario, the stranded tag waits for the next full audit run to surface as a fuzzy candidate against `homelab`.

### Section 1 — Canonical compliance

**Scan:** Every tag appearing in any note's frontmatter (`tags: [...]`) and any inline `#tag` in body text.

**Classify each unique tag as:**
- **canonical** — appears as a `topics[].id` in `vault-metadata.yaml`, or as a content-type id when that content type has `also_tag: true`
- **declared-alias** — appears in a `topics[].aliases[]` list; normalization target is the corresponding id
- **malformed** — violates a tag format rule (uppercase, underscore/camelCase, leading non-letter, <2 chars, contains `/` or punctuation, >30 chars)
- **unknown** — none of the above

**Auto-fixes** (applied when the user approves the finding):
- Declared-alias → canonical: delegate to `.claude/scripts/Invoke-MetadataNormalize.ps1` with an alias map built from `vault-metadata.yaml`. The script handles the note rewrite and the daily-log audit entry.
- Lowercase / kebab-case malformed → auto-fix in place; prompt for all other malformed tags.

**Unknown tags** are never auto-normalized. Offer the user four dispositions per unknown tag: (a) add as new canonical topic, (b) add as alias to an existing topic, (c) delete from the note, (d) defer (stamps `metadata_review: pending`).

**Worked example — format-fix producing a stranded unknown:** A note carries the tag `home_lab`. Section 1 classifies it as malformed (underscore) and auto-fixes to `home-lab`. `home-lab` is kebab-case-valid but does not appear as a canonical topic id or declared alias — so it is reclassified as unknown. Section 2 then computes fuzzy similarity and surfaces `home-lab` ↔ `homelab` as a candidate for user confirmation. The two-section pipeline resolves the tag; running only Section 1 would leave `home-lab` stranded until the next full audit.

### Section 2 — Fuzzy synonym candidates

**Scan:** All canonical topic ids and all unknown tags surfaced in Section 1.

**Classify pairs:** Compute a similarity score (Levenshtein ratio, or similar) between each unknown tag and each canonical id. Surface pairs scoring above 0.75 as candidates.

**Enforcement:** Fuzzy matches are **always confirmation-required — never auto-normalized.** A pair is a *suggestion*, not a mapping. The user must either accept (in which case the unknown tag gets added as a declared alias to the canonical topic), reject (preserve as-is), or classify the unknown tag independently.

**Rationale:** Declared aliases are vouched-for mappings written into `vault-metadata.yaml` by a human (or by a human approving a Claude proposal). Fuzzy matches are *guesses* — silently applying them would be exactly the synonym-sprawl failure mode the framework is designed to prevent.

### Section 3 — Property integrity

**Scan:** Every note's frontmatter.

**Surface:**
- **Broken wiki-links in properties** — values like `"[[epsilon3]]"` where the target note does not exist (or is unreachable from the vault root). Distinguish from intentionally-forward-linked notes by checking whether the link target has a backlink anywhere in the vault.
- **Missing required fields** — for a note whose content type is known, any property listed in `content_types[].properties.required` that is absent or blank in the note's frontmatter.
- **Type violations** — a property declared `type: enum` in `properties[]` whose value in a note is not in the enum's `values[]` list; a `type: date` property whose value is not parseable as a date; a `type: link` property whose value is not a wiki-link syntax.

**Dispositions:** offer to fix per-note (prompt for each), batch-fix patterns Claude can infer, or defer.

### Section 4 — Staleness report

**Scan:** Only notes whose content type has `lifecycle.applicable: true`. Content types with `applicable: false` are **never** flagged stale — this is not a bug, it's the declared-staleness contract.

**For each applicable note:**
- Determine the note's `status` value (or whatever property is declared in `lifecycle.property`).
- Look up the staleness threshold in `lifecycle.staleness[<status value>]`. If the map has no entry for this status, the note is never stale for this status — do not flag.
- Compute days since last modification (git `log -1 --format=%ct` on the file, or frontmatter `updated` field if present — prefer the more recent of the two).
- If days-since-modified exceeds the threshold, flag the note.

**Dispositions:** for each flagged note, offer: (a) open and review (user action, Skill returns to queue on next run), (b) bump `updated` to today (user affirms the note is still current), (c) change `status` (e.g., `active` → `archived`), (d) defer.

### Section 5 — Long-pending review flags

**Scan:** All notes with frontmatter `metadata_review: pending`.

**Surface:** Any such note whose `metadata_review` was stamped more than 30 days ago. Age is determined from the note's `metadata_review_note` timestamp if available, otherwise from the earliest git history of the `metadata_review: pending` frontmatter.

**Threshold:** 30 days is the default. Vaults that want a different threshold should add `review_pending_threshold_days: <n>` to `vault.` in `vault-metadata.yaml`; honor if present.

**Dispositions:** per-note offer to classify now (walk-through), batch-accept a uniform classification across selected notes, re-defer with a fresh note, or delete the note.

### Section 6 — Promotion candidates

**Scan:** Every property defined in `vault-metadata.yaml` with `cardinality: single` whose values are wiki-links.

**Classify:** For each distinct property-value pair, count the number of notes carrying it. Surface any pair where:
1. Count ≥ `vault.promotion_threshold` (default 8)
2. The value is a wiki-link to a note that could name a folder cleanly (short, stable, no special characters needing escape)
3. Notes sharing the value are not already collocated in a single folder

**Dispositions:** per pair, offer: (a) promote — move matching notes to `<existing parent folder>/<value>/`, (b) keep as-is, (c) defer, (d) suppress (record in `vault-metadata.yaml` that this property-value will not be prompted again).

**Never auto-execute folder moves.** Folder changes ripple through wiki-link integrity — the user must approve and Claude handles the link-rewrite in a follow-up deterministic pass.

### Section 7 — Retirement candidates

**Scan:** Every canonical topic in `vault-metadata.yaml` (`topics[].id`, including topics where `deprecated: true` that still have nonzero usage).

**Classify each canonical topic by current usage count across the vault:**
- **0 usages** → **retirement candidate** (surfaced as actionable)
- **1 usage** → **low-adoption informational flag** (surfaced but not a recommendation; the user may prefer to preserve a rare-but-intentional tag)
- **2+ usages** → not surfaced

**Usage count includes:**
- Direct frontmatter matches (`tags: [...]`) of the canonical id
- Declared-alias matches in frontmatter (a note tagged with any entry from `topics[].aliases[]` is a usage of the parent canonical)
- Inline body `#tag` matches, after tag-format normalization (e.g., `#IaC` in the body normalizes to `iac` and counts toward canonical `iac`)

An alias or post-normalization body match IS a usage — counting it any other way would recommend retiring canonicals with active indirect traffic.

**Worked example — alias and body-inline contributing to count:** Canonical topic `docker` has declared alias `containers`. Note `Frigate NVR.md` carries `tags: [containers]` and nothing else that would match. Canonical topic `iac` has no aliases. Note `Terraform Study Plan.md` has `#IaC` inline in the body and no frontmatter tags matching. Both `docker` and `iac` have zero direct frontmatter matches of their canonical id, but each has one indirect match (alias, body-inline respectively). Both count as **1 usage** — low-adoption flag, not retirement candidate.

**Retirement is count-based, not time-based.** A topic with a single active note is not a retirement candidate regardless of how old the note is.

**Dispositions:** per topic, offer: (a) retire — move the entry to `deprecated.tags[]` in `vault-metadata.yaml`, (b) keep, (c) rename (user supplies a new canonical id; existing usages migrate).

### Section 8 — Audit log hygiene

**Scan:** `🫥 Meta/Audit Logs/*.md` matching the daily-rotation pattern `YYYY-MM-DD.md` (ignore audit-report-*.md files).

**Classify:** Any daily log older than `vault.retention.audit_log_days` (default 90).

**Disposition:** If any are found, offer to delete them — delegate to `.claude/scripts/Remove-MetadataAuditLogs.ps1`, which handles the delete and writes a summary entry to today's daily log.

## Empty-section omission

A section that has zero findings after its scan is omitted from the final report. The section header does not appear, and there is no "no findings" line. This keeps the report dense. An audit run that finds nothing anywhere produces a report containing only the front-matter summary and a one-line "No findings in any section."

## Disposition handling

When the Skill surfaces findings in any section, offer the user batch dispositions. The user may combine strategies.

**Single-section shortcuts:**

- `walk-through` — prompt per finding, in order
- `mass-accept` — accept the default/recommended disposition for every finding in the section
- `defer-all` — stamp `metadata_review: pending` on every affected note and move on
- `skip` — take no action, section finishes

**Hybrid range syntax:** Users may specify ranges and interactive fallback in one line. The parser:

- **Ranges** — `6-10` selects findings 6 through 10 inclusive
- **Individual indices** — `1, 3, 7`
- **Mixed** — `1, 3, 6-10`
- **Disposition per range** — `"approve 1, 3, 6-10"` (or `accept`, `defer`, `reject`)
- **Fallback clause** — `"...; interactive rest"` or `"...; skip rest"` or `"...; defer rest"`

**Parser rules:**
1. Split on `;` to separate the ranged-action clause from the fallback clause.
2. In the ranged clause, the leading verb applies to all listed ranges (`approve 1, 3, 6-10` == approve each of 1, 3, 6, 7, 8, 9, 10).
3. If the fallback clause is absent, un-ranged findings are **skipped**. Announce this explicitly before executing so the user can adjust if they meant interactive.
4. If any index is out of range, abort disposition and re-prompt with the valid index range.

**Whole-section shortcuts are section-scoped.** `mass-accept` in Section 1 does not imply `mass-accept` in Section 2.

## Report output

After all sections complete, write a single markdown report to:

```
🫥 Meta/Audit Logs/audit-report-YYYY-MM-DD-HHMMSS.md
```

- **Filename format:** ISO date + `-` + 24-hour time with seconds, no separators. Example: `audit-report-2026-04-17-214530.md`.
- **Why datetime, not date-only:** a same-day re-run must not overwrite the prior report. This is common when the user fixes an issue surfaced by one audit and immediately re-runs to verify.
- **Contents:** front matter (run timestamp, flags passed, sections evaluated, sections omitted), then numbered findings per non-empty section with their disposition outcomes (what was accepted, what was deferred, what the user rejected).
- **Audience:** the report is archival evidence of what was audited, what was found, and what was resolved. It is git-tracked and durable.

## Daily audit log appends

Every **change applied** during the run (tag normalization, frontmatter repair, folder move, canonical-list edit, log deletion) produces an audit log entry appended to the daily-rotation file:

```
🫥 Meta/Audit Logs/YYYY-MM-DD.md
```

This file is the Phase 1 script contract — `Invoke-MetadataNormalize.ps1`, `Set-MetadataDefer.ps1`, and `Remove-MetadataAuditLogs.ps1` all write here. The Skill appends to the same file for any changes applied directly (not via those scripts).

Format per `metadata-schema.yaml` § audit_log: timestamped entries, one per change.

## Post-run commit workflow

After the report is written and any applied changes have been made, orchestrate a commit — unless `--skip-commit` was passed.

**Rationale for committing:** leaving audit-produced files uncommitted is a bad state. Reports are evidence, applied changes mixed into a later user commit muddle git blame, and the daily audit log becomes misaligned with the vault's git history. The audit is a logical unit of work; it should be one commit.

**Track during the run:** Maintain a list of every file the Skill has modified or created. Do **not** rely on `git add -A` — the user may have pre-existing unstaged changes unrelated to the audit. Explicit paths only.

**Expected files in the list:**
- `🫥 Meta/Audit Logs/audit-report-YYYY-MM-DD-HHMMSS.md` (always — the report)
- `🫥 Meta/Audit Logs/YYYY-MM-DD.md` (when any change was applied)
- `🫥 Meta/vault-metadata.yaml` (when canonical list was edited — new topics, retired topics, new aliases)
- Individual note files (when frontmatter was repaired, tags normalized, or notes moved during promotion)

**Commit proposal:**

1. Stage only the tracked paths: `git -C <vault> add <path1> <path2> ...`
2. Run `git -C <vault> diff --cached --stat` and verify changes were actually staged. If nothing was staged (rare — indicates no changes and no new report file, which shouldn't happen), skip the commit step and emit a reminder.
3. Pick the commit type from the vault's `commit-message-guidelines.md`:
   - If any note files were modified (frontmatter repair, tag changes): `META(metadata)` — vault infrastructure changes
   - If only audit artifacts were produced (report, daily log, metadata.yaml): `CHORE(metadata)` — maintenance
   - When both apply, prefer `META(metadata)` (the stronger type)
4. Draft a commit message following the **global** `commit-workflow-checklist.md`:
   - UPPERCASE Conventional Commits format
   - Body summarizes what the audit found and what was applied (not just "ran audit")
   - Both attribution lines at the end (🤖 line + `Co-Authored-By:`) — always, no exceptions
5. **Present the proposal and wait for explicit "yes"** per the global approval gate. Do not short-circuit this step even though the changes are "just audit output."
6. On approval, execute via Bash heredoc (per global checklist Rule 3).
7. On rejection, offer: revise message, abort (changes stay staged for the user to handle), or reset (unstage the tracked paths and leave the report in place).

**Push prompt:**

After the commit succeeds, prompt:

> Push to origin? (y/n)

Do not auto-push. Push is a shared-state action and the user may want to review, amend, or coordinate with other work before publishing.

**`--skip-commit` mode:**

If the flag was passed, do none of the above. Instead, emit a trailing message:

```
Audit complete. <N> file(s) modified, not committed.
  Run `git status` in the vault to review.
  Run `git add <paths>` and commit using the vault's conventions.
```

## Error handling

- **Missing `vault-metadata.yaml`** — halt with *"Vault is not yet seeded. Run vault onboarding first."*
- **Malformed YAML** — halt with the parser error and the offending file path and line number.
- **Schema violation in `vault-metadata.yaml`** — halt with the first violation, its path, and the expected shape per `metadata-schema.yaml`.
- **Missing `.claude/Claude Context/metadata-philosophy.md` or `metadata-schema.yaml`** — halt with *"Metadata framework files are missing. Is this vault seeded from template-obsidian?"*
- **Missing `🫥 Meta/Audit Logs/` directory** — halt with *"Audit Logs directory missing. Verify template integration commit was applied."*
- **Phase 1 script failure** (non-zero exit from `Invoke-MetadataNormalize.ps1` etc.) — surface the stderr, roll back the section's dispositions, continue with subsequent sections. The report records the partial completion.
- **Dirty git state with user abort** — exit cleanly; no files written.

## Acceptance checklist

Mirrors the eight acceptance criteria from template-obsidian#4. Verify before closing the story.

- [ ] Skill file present in `main`
- [ ] Skill operates without error against a freshly-seeded vault (all findings rendered correctly)
- [ ] Empty sections do not appear in the report
- [ ] Fuzzy matches always require confirmation (never auto-normalized)
- [ ] Retirement logic uses current usage count (0 = retirement candidate), NOT time-based
- [ ] Long-pending flag triggers at 30 days (configurable via `review_pending_threshold_days`)
- [ ] Report saved to `🫥 Meta/Audit Logs/` with correct filename (including datetime stamp)
- [ ] Hybrid range syntax works (tested with `"approve 1-3, 5"`)

End-to-end verification against a real vault is scope for template-obsidian#6, not this story.
