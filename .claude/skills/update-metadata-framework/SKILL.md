---
name: update-metadata-framework
description: Vault-local Skill that seeds vault-metadata.yaml on first run and keeps an onboarded Obsidian vault's metadata framework files in sync with newer template-obsidian releases — handles mode detection, framework-owned path allow-list, explicit-path staging, and approval-gated commits
---

# /update-metadata-framework — Vault-Local Framework Sync

**Purpose:** Two jobs, one Skill, auto-routed:

1. **Seed mode** — first-run discovery on a vault that has framework *files* but no real `vault-metadata.yaml` yet. Scans existing content, builds a draft canonical list with a findings report, commits on approval. Runs once per vault.
2. **Update mode** — keeps the framework files themselves in sync with newer `template-obsidian` releases. Fetches the delta between the vault's recorded template tag and a target tag, proposes targeted provisioning updates, commits on approval. Runs whenever the template advances.

**Distinct from:**
- `/setup-vault-metadata` (global, in WorkspaceToolkit) — installs the framework *for the first time* into a vault that has never had it. This Skill assumes the framework is already installed.
- `/audit-metadata` (this repo) — ongoing drift detection against an already-seeded vault. This Skill does not replace it; seed mode suggests it as the next step.

**Usage:**

```
/update-metadata-framework
/update-metadata-framework --force-seed
/update-metadata-framework --target-version v1.2.0
/update-metadata-framework --skip-audit-suggestion
```

## When to invoke

- Immediately after `/new-workspace` creates a vault from `template-obsidian` (routes to seed mode).
- Immediately after `/setup-vault-metadata` retrofits an existing vault (routes to seed mode).
- Whenever `template-obsidian` cuts a new release and you want this vault on it (routes to update mode).
- When the canonical list has been corrupted or drifted so far that a re-bootstrap is cheaper than an audit (use `--force-seed`).

## When NOT to invoke

- The vault has no framework files at all — run `/setup-vault-metadata` first. This Skill halts in that case.
- Routine canonical-list hygiene — use `/audit-metadata`.
- Migrating content between vaults or changing vault structure — out of scope.

## Inputs

| Flag | Default | Purpose |
|------|---------|---------|
| `--force-seed` | off | Re-run seed mode even on a fully-seeded vault. For bootstrapping a corrupted canonical list. Does not touch framework files. |
| `--target-version <tag>` | latest tag on `template-obsidian/main` | Pin update mode to a specific semver tag instead of the newest. Ignored in seed mode. |
| `--skip-audit-suggestion` | off | Suppress the trailing "consider running `/audit-metadata`" reminder at the end of seed mode. |

## Required source files

Read these at start. If any is missing or malformed, halt with a specific error — see [Pre-flight checks](#pre-flight-checks).

| File | Purpose |
|------|---------|
| `🫥 Meta/.template-version` | Records the `template-obsidian` semver tag this vault currently tracks |
| `🫥 Meta/vault-metadata.yaml` | Per-vault canonical list — state of this file drives mode detection |
| `.claude/Claude Context/metadata-schema.yaml` | Schema the seed draft must conform to |
| `.claude/Claude Context/metadata-philosophy.md` | Judgment reference for seed-mode recommendations |

## Pre-flight checks

Run in order. Abort on any failure with a clear message — do not attempt a partial run against a malformed vault.

1. **Vault is a git repo** — `git rev-parse --is-inside-work-tree` must succeed at the vault root.
2. **Framework files present** — every file in the [Framework-owned path allow-list](#framework-owned-path-allow-list) either exists OR is marked as "copy-if-missing" there. If any non-copy-if-missing file is absent, halt: *"Framework incomplete. Run `/setup-vault-metadata` to reinstall the framework."*
3. **`.template-version` present and non-stub** — file exists and contents do not equal the `.template` stub placeholder. If absent or stub, halt: *"Vault has no recorded template version. Run `/setup-vault-metadata` first."*
4. **Vault git state** — `git status --porcelain` at the vault root.
   - **Clean** → proceed.
   - **Dirty** → prompt:
     - `(a)` Stash pending changes, run, pop stash at end
     - `(b)` Commit pending changes separately first (prompts for a commit message per vault guidelines)
     - `(c)` Abort
     - `(d)` Proceed dirty — Skill will still stage only explicit paths; user reconciles afterward

## Mode detection

After pre-flight, route to exactly one mode.

**Seed mode** when any of:
- `--force-seed` was passed, OR
- `🫥 Meta/vault-metadata.yaml` is still the raw `.template` copy (vault name starts with `ReplaceWithVaultName` or the file equals the template byte-for-byte), OR
- `vault-metadata.yaml` has empty `topics` *and* empty `content_types` arrays (near-empty-but-structurally-valid stub).

**Update mode** when none of the above AND:
- `.template-version` records a tag that is older than the resolved target version (latest template tag by default, or `--target-version <tag>` if passed).

**No-op** when neither trigger fires (seeded, up to date, no `--force-seed`). Announce: *"Vault is seeded and on template version `<tag>`. Nothing to do."* and exit zero.

Announce the mode decision before proceeding — the user should see *"Routing to seed mode because `vault-metadata.yaml` is still the template stub"* or *"Routing to update mode: vault is on `v1.0.0`, target is `v1.2.0`"* before any work begins.

## Seed mode

Runs once per vault. Produces a draft canonical list grounded in what the vault already contains.

### Step 1 — Scan existing content

Walk the vault (excluding `.obsidian/`, `.git/`, `📦 Archive/`, `🫥 Attachments/`, and anything matching `.gitignore`). For each note:

- Collect every tag from frontmatter `tags: [...]`.
- Collect every inline `#tag` in body text.
- Collect every frontmatter property name and its value type.
- Collect every wiki-link target (`[[Target]]` and `[[Target#Section]]`).

Aggregate across all notes: unique tags with usage counts, unique property names with observed value types, unique wiki-link targets.

### Step 2 — Read vault-declared tag-system files as seed input

Some vaults maintain human-authored tag/metadata reference notes before onboarding. Look for and parse (if present) as additional seed context:

- `Tag System.md` at vault root
- `Canonical Metadata.md` at vault root
- `🫥 Meta/Canonical Metadata.md` (the framework's template-derived version, if the user has been hand-editing it)
- `.claude/Claude Context/vault-guide.md` — surface any tag or content-type references the user documented

These inform the draft but do not override scan evidence. Note every referenced tag/property in the findings report so the user can reconcile documented-vs-actual.

### Step 3 — Surface property-naming variants as a dedicated finding category

The schema standard uses specific property names (`created`, `updated`, `status`, etc.). Vaults onboarded from scratch frequently use variants (`date-created`, `date-updated`, `state`). Build a finding per variant:

- The variant the vault uses (`date-created`, 47 notes)
- The schema standard it maps to (`created`)
- The recommended action (rename via normalize script at audit time, or declare as alias in `vault-metadata.yaml` if the user prefers to keep the variant)

Surface these in a dedicated section of the findings report — do not quietly fold them into the generic tag/property buckets. They are the single most common friction point in onboarding and deserve explicit surfacing.

### Step 4 — Produce findings report

Write to `🫥 Meta/Audit Logs/findings-seed-YYYY-MM-DD-HHMMSS.md`. Filename uses datetime stamp for the same reason `/audit-metadata` does — a same-day re-run must not overwrite.

Report structure:
- **Front matter** — run timestamp, vault path, flags passed, target schema version.
- **Summary** — total notes scanned, unique tags, unique properties, unique wiki-link targets, count of property-naming variants.
- **Recommended canonical topics** — tag → usage count → recommended `topics[].id` (with any aliases merged in). Sorted by usage count descending.
- **Recommended content types** — observed patterns in notes (by folder, by tag combinations, by shared property sets) that look like content-type candidates. Each with a recommended `content_types[].id`, detected properties, and a lifecycle recommendation.
- **Property-naming variants** — the dedicated section from Step 3.
- **Unmapped tags** — tags the scan couldn't confidently group. Listed for user review.
- **Discovery notes** — anything surprising (very high cardinality properties, tags used only once, wiki-link targets that don't exist as notes).

Every recommendation cites its grounding in `metadata-philosophy.md` — specifically the "tag by dimension, not by detail" and "proper nouns are properties, not tags" rules — so the user can evaluate each judgment call rather than just accepting defaults.

### Step 5 — Write draft `vault-metadata.yaml`

Write `🫥 Meta/vault-metadata.yaml` (overwriting the `.template` stub). The draft includes:

- All recommended canonical topics from Step 4, with inline comments for each (`# from 47 notes, aliases consolidated from: tech, technology, technical`).
- All recommended content types, with inline comments linking back to the folder/tag pattern that surfaced them.
- Property-naming variants listed under `deprecated:` with their canonical targets, so the normalize script can handle them later.
- Thresholds at schema defaults (`promotion_threshold: 8`, `review_pending_threshold_days: 30`, `retention.audit_log_days: 90`) — user can tune post-seed.

The file remains a **draft** until the user approves the commit in Step 6. If rejected, revert the write.

### Step 6 — Approval gate and commit

Present the diff summary:

```
Seed draft prepared:
  Canonical topics recommended:  <N>
  Content types recommended:      <N>
  Property-naming variants:       <N>
  Unmapped tags (require review): <N>

Files to stage:
  - 🫥 Meta/vault-metadata.yaml               (modified)
  - 🫥 Meta/Audit Logs/findings-seed-<stamp>.md (new)

Review findings report / approve commit / revise / abort?
```

On approval, stage the explicit paths and execute via the global commit-workflow approval gate (`commit-workflow-checklist.md`, Step 2 → 3a). Commit message:

```
META(metadata): seed vault-metadata from existing content
```

Body summarizes counts (topics, content types, variants) and notes the findings report path.

### Step 7 — Post-commit guidance

After the seed commit succeeds (unless `--skip-audit-suggestion`):

> Seed complete. Next step: run `/audit-metadata` to walk the full-vault findings and start normalizing drift.

Do **not** auto-invoke `/audit-metadata`. Seed and audit are distinct logical units — the user may want to inspect the findings report, hand-edit `vault-metadata.yaml`, or defer the audit to a later session.

Prompt for push per the global push rule:

> Push to origin? (y/n)

## Update mode

Runs whenever the template advances. Keeps framework files in sync while leaving everything outside the allow-list untouched.

### Step 1 — Fetch target template

Resolve the target version:
- `--target-version <tag>` if passed — verify the tag exists via `gh api repos/DeliberateGeek/template-obsidian/git/refs/tags/<tag>`.
- Otherwise, the latest tag on `template-obsidian/main` via `gh api repos/DeliberateGeek/template-obsidian/releases/latest` (or `tags` list if no release cut).

Shallow-clone the template at the target tag into a temp directory (`git clone --depth 1 --branch <tag> https://github.com/DeliberateGeek/template-obsidian.git <tmpdir>`). Clean up the temp directory on exit (success or abort).

### Step 2 — Inventory the delta

For each path in the [Framework-owned path allow-list](#framework-owned-path-allow-list), classify the vault's copy against the template's copy at the target tag:

- **Missing in vault** → copy (if path is copy-allowed — see allow-list column).
- **Identical** → skip silently.
- **Additive-merge** → merge per the rule for that path (see allow-list).
- **Different** → stage a diff for user review. Never auto-overwrite.

**Inventory the delta only**, not the full framework. If a file is unchanged between the vault's tag and the target tag, it is not considered — even if the vault's copy has drifted from both. Drift detection is `/audit-metadata`'s job; update mode's job is propagating template changes.

### Step 3 — Present delta summary

```
Update: v1.0.0 → v1.2.0

Framework files changed in this delta:  <N>
  Files to copy (new in template):      <N>
  Files to additive-merge:               <N>
  Files with proposed diffs:             <N>

.template-version will be updated to: v1.2.0

Review diffs / approve / revise / abort?
```

Offer per-file diff review on request. Every diff must be individually approved — the user may accept some, reject others. Rejected diffs leave that file untouched; approved diffs are applied.

### Step 4 — Apply and commit

Apply approved changes. Update `🫥 Meta/.template-version` to the target tag. Stage explicit paths only — never `git add -A`.

Commit via the global commit-workflow approval gate:

```
META(metadata): update framework from template-obsidian <target-version>
```

Body lists the files changed and the nature of each change (copy / merge / diff-applied).

### Step 5 — Post-commit

Do not suggest `/audit-metadata` by default — update mode is cheaper and more frequent than seed, and suggesting audit on every update trains the user to ignore the suggestion. Override with the absence of `--skip-audit-suggestion` is intentional: seed suggests, update does not. Users who want an audit after every template bump can invoke it explicitly.

Prompt for push.

## Framework-owned path allow-list

These are the only paths this Skill may create, modify, or merge into. Anything outside this list is **never** touched — not for linting, not for normalization, not for cleanup.

| Path | Update-mode rule | Seed-mode rule |
|------|------------------|----------------|
| `.claude/Claude Context/metadata-philosophy.md` | copy / diff-prompt | read-only |
| `.claude/Claude Context/metadata-examples.md` | copy / diff-prompt | read-only |
| `.claude/Claude Context/metadata-schema.yaml` | copy / diff-prompt | read-only |
| `.claude/scripts/Set-MetadataDefer.ps1` | copy / diff-prompt | read-only |
| `.claude/scripts/Invoke-MetadataNormalize.ps1` | copy / diff-prompt | read-only |
| `.claude/scripts/Remove-MetadataAuditLogs.ps1` | copy / diff-prompt | read-only |
| `.claude/settings.json` | object-level merge of `permissions.allow` array; preserve broader vault rules | untouched |
| `.gitmessage` | additive-merge of framework-owned scope examples; preserve vault-specific lines | untouched |
| `.gitignore` | additive-merge of any new framework-owned ignores | untouched |
| `🫥 Meta/vault-metadata.yaml.template` | copy-if-missing | untouched |
| `🫥 Meta/Canonical Metadata.md.template` | copy-if-missing | untouched |
| `🫥 Meta/Audit Logs/.gitkeep` | copy-if-missing | untouched |
| `🫥 Meta/.template-version` | overwrite with target tag on successful update | untouched |
| `🫥 Meta/vault-metadata.yaml` | untouched (this is vault-owned, not framework-owned) | rewrite from seed draft (approval-gated) |
| `🫥 Meta/Audit Logs/findings-seed-<stamp>.md` | untouched | create (seed findings report) |
| `CLAUDE.md` | diff-prompt ONLY — never overwrite, never merge | untouched |

**Rules:**

- **copy / diff-prompt** — if missing, copy silently; if present and identical, skip; if present and different, show a diff and require per-file user approval.
- **copy-if-missing** — if missing, copy; if present in any form, leave untouched. These are template seeds meant to be customized.
- **additive-merge** — parse both files, compute the set of framework-owned entries absent from the vault's copy, append them. Never remove entries the vault added.
- **object-level merge** — for `settings.json`, parse both as JSON, merge the framework's `permissions.allow` entries into the vault's array (deduped). Preserve all other keys the vault has set.
- **diff-prompt ONLY** — for `CLAUDE.md`, only show the user a diff. Never write. The user hand-applies desired changes.
- **overwrite** — `.template-version` is authoritative and gets rewritten on successful update.

If a path not in this list needs modification to propagate a framework change, **stop** — that is a framework design defect, not a Skill responsibility. Surface it as an error and require human intervention.

## Explicit-path commit staging

Never use `git add -A` or `git add .`. Build an explicit list of modified paths during the run. Stage by enumerated path: `git -C <vault> add <path1> <path2> ...`. Verify staging with `git -C <vault> diff --cached --stat` before proposing the commit. If nothing was staged (no changes applied), skip the commit step.

## Post-commit workflow

Both modes commit via the global `commit-workflow-checklist.md` approval gate:

1. Present proposal (files staged, message drafted).
2. Wait for explicit "yes".
3. Execute via Bash heredoc.
4. Report commit hash and summary.
5. Prompt for push separately — `"Push to origin? (y/n)"`. Do not auto-push.

Attribution follows the global rule: both lines (🤖 line + `Co-Authored-By:`) as the final lines, always.

## Error handling

- **Not a git repo** — halt with *"Vault root is not a git working tree."*
- **Framework incomplete** (missing non-copy-if-missing file) — halt with *"Framework incomplete. Run `/setup-vault-metadata` to reinstall."* and list the missing paths.
- **`.template-version` missing or stub** — halt with *"Vault has no recorded template version. Run `/setup-vault-metadata` first."*
- **Target tag does not exist** — halt with *"Tag `<target>` not found on template-obsidian. Check `gh api repos/DeliberateGeek/template-obsidian/tags` for valid tags."*
- **Target tag is older than current** — halt with *"Target `<target>` is older than current `.template-version` `<current>`. Downgrade not supported; use `--force-seed` if you need to re-bootstrap."*
- **Network failure during template fetch** — halt with the underlying error; leave the vault untouched.
- **Malformed `vault-metadata.yaml` in mode detection** — halt with the parser error. Do not route to seed mode silently; a malformed file is a distinct failure from an un-seeded file.
- **Dirty git state with user abort** — exit cleanly; no files written.
- **Approval rejection on commit** — offer: revise message, abort (seed: revert the yaml rewrite; update: revert the file changes), or leave staged for manual handling.
- **Temp directory cleanup failure** (update mode) — emit a warning with the path; exit non-zero if the primary work succeeded but cleanup didn't, so the user knows to remove it.

## Acceptance checklist

Mirrors the acceptance criteria from template-obsidian#5. Verify before closing the story.

- [ ] Skill file present in `main`
- [ ] Mode detection correctly routes seed vs update (unseeded / partially seeded / fully seeded + outdated)
- [ ] Seed mode produces draft `vault-metadata.yaml` and findings report at `🫥 Meta/Audit Logs/findings-seed-<stamp>.md`
- [ ] Seed mode surfaces property-naming variants as a dedicated finding category
- [ ] Update mode inventories only delta files, not full template
- [ ] `.template-version` updated on successful update
- [ ] User approval gate honored for every commit (global checklist Step 2 → 3a)
- [ ] Framework-owned path allow-list enforced — no writes outside the list
- [ ] `--force-seed` re-runs seed even on seeded vaults
- [ ] Skill halts with clear guidance when `.template-version` is missing (directs user to `/setup-vault-metadata`)
- [ ] Explicit-path staging only — never `git add -A`

End-to-end verification against a real vault is scope for template-obsidian#6, not this story.
