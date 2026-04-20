---
name: init-vault-metadata-framework
description: Produce the first real vault-metadata.yaml for an Obsidian vault that has the framework files installed — supports brand-new vaults from /new-workspace, new-with-imported-content, long-standing vaults post-onboard, and a re-init path for reconsidering an existing canonical structure
---

# /init-vault-metadata-framework — Initial Canonical List Author

**Purpose:** Produce the first real `🫥 Meta/vault-metadata.yaml` for an Obsidian vault whose framework files are already installed. Fills the gap between framework install (`/onboard-vault-metadata-framework` or `/new-workspace`) and ongoing drift management (`/audit-metadata`, `/update-metadata-framework`).

This Skill does NOT install framework files. If the framework is missing, halt and point the user to the installer.

**Usage:**

```
/init-vault-metadata-framework
/init-vault-metadata-framework --description "a homelab ops vault"
/init-vault-metadata-framework --interactive
/init-vault-metadata-framework --force-reinit
/init-vault-metadata-framework --skip-audit-suggestion
```

## When to invoke

- Directly after `/onboard-vault-metadata-framework` completes on a long-standing vault (auto-invoked unless `--no-init` was passed to onboard)
- Directly after `/new-workspace` provisions a fresh Obsidian vault (auto-invoked)
- Manually, to reconsider an existing canonical structure (re-init mode)

## When NOT to invoke

- To install framework files into a long-standing vault — use `/onboard-vault-metadata-framework` (global)
- To sync framework-file changes from a newer `template-obsidian` release — use `/update-metadata-framework`
- To audit drift or surface cleanup opportunities against an existing canonical list — use `/audit-metadata`

Re-init mode exists for deliberate restructuring, not for drift cleanup. If the user describes their intent as "clean up tag sprawl" or "fix stale notes," redirect them to `/audit-metadata`.

## Inputs

| Flag | Default | Purpose |
|------|---------|---------|
| `--description <one-liner>` | (prompt) | Short vault description; skips the description prompt in default mode |
| `--interactive` | off | Opt into the structured interview instead of the one-liner path |
| `--skip-audit-suggestion` | off | Suppress the trailing "consider running `/audit-metadata`" reminder |
| `--force-reinit` | off | Bypass the "already has real `vault-metadata.yaml`" confirmation and proceed straight to re-init |

If no flag is passed and `--description` is not supplied, the Skill asks: "default (one-liner) mode or `--interactive` structured interview?" before proceeding.

## Required source files

Read these at start. If any is missing, halt with guidance to run `/onboard-vault-metadata-framework` or `/new-workspace`.

| File | Purpose |
|------|---------|
| `🫥 Meta/.template-version` | Confirms framework is installed; records the semver tag |
| `🫥 Meta/vault-metadata.yaml` | Mode detection target (stub vs. real) |
| `.claude/Claude Context/metadata-schema.yaml` | Structural schema the generated YAML must conform to |
| `.claude/Claude Context/metadata-philosophy.md` | Grounding reference for every proposal — every recommendation cites its source |

## Mode detection

Run on entry, before any prompts or interviews. The result routes the rest of the run.

1. **Framework not installed** — if `🫥 Meta/.template-version` is missing, or the file exists but contains the `.template` placeholder text (e.g., `ReplaceWith...`), halt:
   - *"Framework files are missing or incomplete. Long-standing vault? Run `/onboard-vault-metadata-framework`. New vault? Use `/new-workspace` with the template-obsidian template."*
2. **Legacy `v`-prefixed version format** — if `.template-version` contents match `^v\d+\.\d+\.\d+$` (starts with `v`), halt:
   - *"`.template-version` uses the legacy `v`-prefixed format (e.g., `v1.0.0`). Canonical form is bare semver (e.g., `1.0.0`); `v` is reserved for git tag names only. Edit the file to strip the leading `v`, commit the change (suggested message: `META(metadata): normalize .template-version to canonical bare-semver form`), then re-run this Skill."*
3. **Invalid version format** — if `.template-version` contents are not the stub placeholder and do not match `^\d+\.\d+\.\d+$`, halt:
   - *"`.template-version` is not valid bare semver. Expected form: `MAJOR.MINOR.PATCH` (e.g., `1.0.0`). Fix the file contents and re-run."*
4. **Vault is not a git repo** — halt. Framework work requires git.
5. **Stub `vault-metadata.yaml`** — if `🫥 Meta/vault-metadata.yaml` is missing OR its `vault.name` field equals `ReplaceWithVaultName` (the template stub value), route to **initialize mode**.
6. **Real `vault-metadata.yaml`** — if the file exists with real content (`vault.name` is not the stub value):
   - If `--force-reinit` passed → route to **re-initialize mode**
   - Otherwise, prompt: *"Vault already has a real `vault-metadata.yaml`. Did you mean to invoke `/audit-metadata` (drift cleanup) or do you want to re-initialize (full restructure)?"* — abort cleanly on "audit" or "cancel"; on "re-init" confirmation, route to **re-initialize mode**.

After mode is set, run initialize mode's content scan to distinguish **brand-new** (no substantive content) from **new-with-content** (scan found something). Re-init is always "with content" by definition.

## Pre-flight checks

Run after mode detection, before any interview or write.

1. **Vault git state** — run `git status --porcelain` at vault root.
   - **Clean** → proceed.
   - **Dirty** → prompt: `(a)` stash and pop at end, `(b)` separate pre-init commit first, `(c)` abort, `(d)` proceed with dirty state (user reconciles).
2. **Framework files present per allow-list** — confirm every framework-owned file expected at the recorded `.template-version` exists (`metadata-philosophy.md`, `metadata-schema.yaml`, `metadata-examples.md`, `framework-scripts-reference.md`, the four PowerShell scripts — `Invoke-MetadataNormalize.ps1`, `Invoke-MetadataValidate.ps1`, `Remove-MetadataAuditLogs.ps1`, `Set-MetadataDefer.ps1` — and `🫥 Meta/Audit Logs/`). If any is missing, halt: *"Framework incomplete. Run `/onboard-vault-metadata-framework --force-reinstall` to repair, or investigate manually."*

## Content scan

Run for new-with-content and re-initialize modes. Skip for brand-new (no-content) mode.

**Walk the vault, excluding:**
- `.obsidian/`
- `.git/`
- `📦 Archive/`
- `🫥 Attachments/`
- Anything matched by the vault's `.gitignore`
- Framework-owned files themselves (`.claude/Claude Context/`, `.claude/scripts/`, `🫥 Meta/`)

**Aggregate:**

- **Tags** — unique tags from every note's frontmatter (`tags: [...]`) and inline body (`#tag`). Record usage count per tag.
- **Frontmatter properties** — unique property names across all notes. For each property, collect observed value types (string, date-parseable, wiki-link, number, boolean, list) and sample values.
- **Wiki-link targets** — referenced notes, including detection of broken targets (referenced but missing).
- **Folder structure** — top-level folders (especially emoji-prefixed ones, per Obsidian convention).
- **Pre-existing metadata docs** — read and reconcile any of: `Tag System.md`, `Canonical Metadata.md`, `vault-guide.md`. Use their content as declarative intent to compare against actual usage.

**Classification step:**

- **Property-naming variants** — any property name that differs from a schema-standard name by case, hyphenation, or spelling (e.g., `date-created` vs `created`, `Status` vs `status`, `CreatedDate` vs `created`). Surface as a dedicated finding category — never silently rename.
- **Likely content-type tags** — tags whose names plausibly describe KIND of note (reference, learning, session-log, recipe, etc.). Use philosophy boundary rules: tags that answer "what kind of container?" are content-type candidates.
- **Likely topic tags** — tags whose names describe WHAT a note is about (homelab, docker, python). Content-type candidates AND topic candidates require user classification; don't guess at the boundary.
- **Proper-noun-as-tag flags** — tags whose names look like proper nouns (mixed-case in source, singular capitalized-style words, names of specific entities). Per philosophy: proper nouns are properties, not tags. Surface for user review; propose moving to a property.
- **Malformed tags** — uppercase, underscore/camelCase, leading non-letter, <2 chars, contains `/` or punctuation, >30 chars. Auto-fix on approval (lowercase / kebab-case); reject others for user correction.

## Interviews

### Default mode — one-liner description

Minimal friction. Right for simple vaults or when the user just wants a valid starter.

1. Prompt (unless `--description` supplied): *"One-line description of this vault? e.g., 'a homelab ops vault', 'D&D campaign for the Cipher PC', 'recipes and meal planning'."*
2. Translate description into a minimal content-type set and topic seeds using philosophy rules:
   - "ops" / "reference" / "docs" / "knowledge" → seed `reference` content type
   - "learning" / "course" / "study" → seed `learning` content type
   - "campaign" / "D&D" / "RPG" / "lore" → seed a lore-like content type with `lifecycle.applicable: false`
   - Domain keywords (homelab, recipes, travel) → seed 2-4 related topic candidates
   - **Every translation cites `metadata-philosophy.md` grounding in inline comments.**
3. Present draft `vault-metadata.yaml` for review. User may edit in place before approval.
4. Approval gate → commit.

### Interactive mode — structured interview

Right for content-rich vaults, re-init runs, or when the user wants elaborated starters.

Sequence the interview as:

1. **Vault purpose** — open-ended "what is this vault for?" to ground translation decisions.
2. **Content types expected** — present likely candidates from scan (or from vault-purpose answer if brand-new). User confirms/edits. For each confirmed type, ask:
   - Folder? Tag? Both? (belt-and-suspenders allowed per philosophy § Content Type Redundancy)
   - Required properties? (start broad; specialize under pressure)
   - Lifecycle applicable? If yes: values, staleness thresholds per value.
3. **Topic dimensions** — present tag candidates from scan classified as likely-topics. User confirms, adds, removes, merges (alias proposal per philosophy § Declared aliases vs undeclared near-matches).
4. **Property conventions** — present property names found in scan. For each:
   - Keep as-is / rename to a schema-standard / declare as a new vault-specific canonical.
   - Property-naming variants get explicit choice: rename to standard, declare variant as canonical, or alias it.
5. **Lifecycle expectations** — defaults for any content type that opted in; tune thresholds based on user expectations.

Throughout: each proposal displays its philosophy-grounding reference inline. User can always say "skip" or "come back to this" — skipped sections get `metadata_review: pending` stamps in the draft or stay as sensible defaults.

Close with a review-loop: *"Here's the full draft — edit in place, approve, or start over."*

### Re-initialize mode

Only reachable via `--force-reinit` or explicit confirmation after the "already has real `vault-metadata.yaml`" prompt.

1. **Confirm intent** — *"Re-init replaces the current canonical structure. Old `vault-metadata.yaml` stays in git history. Proceed?"* Abort on anything other than explicit yes.
2. **Conduct interactive interview** informed by BOTH the current canonical list and the content scan. Show side-by-side deltas:
   - Content types: added / removed / renamed
   - Topics: added / removed / renamed / re-aliased
   - Properties: added / removed / retyped / re-cardinalitied
3. **Findings report** captures rationale for each non-trivial change.
4. Approval gate → commit separately: `META(metadata): re-initialize vault-metadata (restructure)`.
5. Guidance: *"Consider running `/audit-metadata` now to normalize existing notes against the restructured list."*

## Write draft

After interview completes in any mode:

1. Serialize the draft to `🫥 Meta/vault-metadata.yaml`, overwriting the stub or prior file.
2. Include **inline comments** explaining each content type, topic cluster, and property choice — each comment cites the philosophy rule that grounded the decision. Comments are durable guidance for future edits.
3. Validate the draft against `metadata-schema.yaml` by invoking:

   ```
   pwsh.exe -File .claude/scripts/Invoke-MetadataValidate.ps1 -MetadataPath "🫥 Meta/vault-metadata.yaml"
   ```

   Interpret the exit code per `.claude/Claude Context/framework-scripts-reference.md`:
   - **Exit 0** — zero findings, proceed to the findings report step.
   - **Exit 1** — structural findings present. Surface the script's stdout to the user and offer: revise the draft in place and re-validate, or abort without writing a findings report or committing.
   - **Exit 2** — environment or framework problem (e.g., `powershell-yaml` not installed, schema file missing). Halt with the surfaced message; do not treat as user-correctable. Point the user to `framework-scripts-reference.md` § Prerequisites.

   Do not write a draft that fails validation. Do not proceed to commit until the validator exits 0.
4. If the scan surfaced findings (property-naming variants, proper-noun-as-tag candidates, malformed tags, deprecation candidates), write a findings report to:

   ```
   🫥 Meta/Audit Logs/findings-init-YYYY-MM-DD-HHMMSS.md
   ```

   Filename format matches `/audit-metadata`'s datetime convention. Report includes: mode used, scan statistics, each finding category with dispositions (what was applied, what was deferred), and grounding citations.
5. Brand-new mode produces **no findings report** — nothing was scanned.

## Commit workflow

Follow the global commit-workflow-checklist — meta-Skill discipline: propose → approve → execute.

**Tracked paths** (explicit, no `git add -A`):
- `🫥 Meta/vault-metadata.yaml` (always)
- `🫥 Meta/Audit Logs/findings-init-YYYY-MM-DD-HHMMSS.md` (when scan produced findings)

**Commit message:**
- Initialize mode: `META(metadata): initialize vault-metadata`
- Re-initialize mode: `META(metadata): re-initialize vault-metadata (restructure)`

**Body summarizes:** mode used, content-type and topic counts seeded, any findings deferred. Both attribution lines at the end per global checklist.

**Approval gate** — present proposal, wait for explicit "yes." On approval, execute via Bash heredoc per global Rule 3.

**Push prompt** after commit succeeds. Do not auto-push.

## Post-run guidance

Unless `--skip-audit-suggestion` was passed:

- Initialize mode: *"Next step: run `/audit-metadata` to validate the canonical list against real content usage."*
- Re-initialize mode: *"Run `/audit-metadata` to normalize existing notes against the restructured list — expect more findings than usual for a first pass."*

If the user is in a `/onboard-vault-metadata-framework` auto-handoff, the handoff Skill does the printing — don't double-print.

## Auto-invocation contract

This Skill is called by:

- **`/onboard-vault-metadata-framework`** — after its provisioning commit succeeds, unless `--no-init` was passed to onboard. Expect to run in new-with-content mode for long-standing vaults.
- **`/new-workspace`** (WorkspaceToolkit) — after template application for an Obsidian vault. Expect to run in brand-new mode with a description the user supplied to `/new-workspace` (passed through as `--description`).

Never called by `/audit-metadata` — reconsidering the canonical list is re-init here, not an audit concern.

## Error handling

- **Missing framework files** — halt with guidance to run `/onboard-...` or `/new-workspace`.
- **Vault not a git repo** — halt; framework work requires git.
- **Malformed `metadata-schema.yaml`** — halt with parser error; framework is broken, not a user problem.
- **Draft fails schema validation** — surface the violation, offer revise-or-abort. Never write an invalid file.
- **User aborts at any approval gate** — exit cleanly; no files written, no commit.
- **Scan encounters unreadable files** — skip with a note in the findings report. Don't halt.

## Acceptance checklist

Mirrors the acceptance criteria from DeliberateGeek/WorkspaceToolkit#106.

- [ ] Skill file present in `main`
- [ ] Mode detection correctly routes initialize vs re-initialize (tested with stub, near-empty-but-real, and fully-populated `vault-metadata.yaml` states)
- [ ] Initialize mode produces valid `vault-metadata.yaml` from a one-line description (default path)
- [ ] `--interactive` conducts structured interview and produces a more elaborated starter
- [ ] New-with-content initialize surfaces property-naming variants as a dedicated category
- [ ] Re-initialize mode confirms user intent before proceeding
- [ ] Re-initialize mode produces a delta summary (topics/content types added/removed/renamed) before commit
- [ ] Every proposal in any mode cites grounding in `metadata-philosophy.md`
- [ ] User approval gate honored for every commit (global checklist Step 2 → 3a)
- [ ] Findings report written to `🫥 Meta/Audit Logs/findings-init-<stamp>.md` when scan produced findings
- [ ] Skill halts with clear guidance when framework files are missing

End-to-end verification against fresh clones and a throwaway vault is scope for template-obsidian#6, not this story.
