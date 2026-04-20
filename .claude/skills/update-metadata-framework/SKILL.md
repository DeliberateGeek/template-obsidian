---
name: update-metadata-framework
description: Sync an onboarded Obsidian vault's framework files with a newer template-obsidian release by walking the versioned migration registry — one approval-gated hop at a time, never writing outside the registry-declared allow-list
---

# /update-metadata-framework — Framework-File Version Sync

**Purpose:** Keep an already-onboarded vault's `template-obsidian` framework files in sync with newer releases. Walks the versioned migration registry (`MIGRATIONS.md` + `.migrations/<from>-to-<to>.yaml`) hop by hop, with an approval gate between each hop. Updates `🫥 Meta/.template-version` after every successful hop.

This Skill does NOT install framework files into a new vault, does NOT author the first `vault-metadata.yaml`, and does NOT audit drift against the canonical list.

**Usage:**

```
/update-metadata-framework
/update-metadata-framework --target-version 1.3.0
/update-metadata-framework --dry-run
/update-metadata-framework --dry-run --target-version 1.3.0
```

## When to invoke

- After `template-obsidian` ships a new release and the user wants to pick up framework improvements.
- Periodic catch-up for a long-lived vault that has fallen behind several versions.
- Before running `/audit-metadata` when the user wants the newest schema and Skill versions to inform the audit.

## When NOT to invoke

- Fresh vault with no `🫥 Meta/.template-version` — use `/onboard-vault-metadata-framework` (global).
- Stub `vault-metadata.yaml` — run `/init-vault-metadata-framework` first.
- Drift cleanup / tag sprawl / staleness — use `/audit-metadata`.
- Restructuring the canonical list — use `/init-vault-metadata-framework --force-reinit`.

## Inputs

| Flag | Default | Purpose |
|------|---------|---------|
| `--target-version <tag>` | latest tag on `template-obsidian/main` | Pin the walk to a specific semver tag. |
| `--dry-run` | off | Report the planned hops and file changes without cloning-to-apply or writing to the vault. The target-tag clone still happens (required to read the registry); nothing in the vault is modified. |

## Required source files

Read these at start. If any is missing or malformed, halt with a specific error.

| File | Purpose |
|------|---------|
| `🫥 Meta/.template-version` | Records the vault's current framework version. Required for mode detection. |
| `.claude/Claude Context/metadata-schema.yaml` | Used by schema-change reconciliation prompts. |
| `.claude/Claude Context/metadata-philosophy.md` | Grounding reference for any `post_apply_notes` guidance. |

## Mode detection

Run on entry, before clone or interview.

1. **Framework not installed** — if `🫥 Meta/.template-version` is missing, halt:
   - *"Framework files are missing. Long-standing vault? Run `/onboard-vault-metadata-framework`. New vault from template? Use `/new-workspace` with the `template-obsidian` template."*
2. **Stub version** — if `.template-version` contains the `.template` placeholder text (starts with `ReplaceWith`), halt:
   - *"`.template-version` is a stub. Run `/init-vault-metadata-framework` to complete first-run setup before updating."*
3. **Legacy `v`-prefixed format** — if `.template-version` contents match `^v\d+\.\d+\.\d+$` (starts with `v`), halt:
   - *"`.template-version` uses the legacy `v`-prefixed format (e.g., `v1.0.0`). Canonical form is bare semver (e.g., `1.0.0`); `v` is reserved for git tag names only. Edit the file to strip the leading `v`, commit the change (suggested message: `META(metadata): normalize .template-version to canonical bare-semver form`), then re-run this Skill."*
4. **Invalid format** — if `.template-version` contents do not match `^\d+\.\d+\.\d+$`, halt:
   - *"`.template-version` is not valid bare semver. Expected form: `MAJOR.MINOR.PATCH` (e.g., `1.0.0`). Fix the file contents and re-run."*
5. **Vault is not a git repo** — halt. Framework work requires git.
6. **Resolve target** — if `--target-version` was passed, validate it is bare semver (`^\d+\.\d+\.\d+$`). Otherwise determine the latest tag from `DeliberateGeek/template-obsidian` (ls-remote against the repo; no checkout) and **strip the leading `v`** before using or comparing. Cache the bare form in a variable for the rest of the run.
7. **Compare current vs target:**
   - **Equal** → no-op. Print *"Vault is already at `template-obsidian` X.Y.Z — nothing to do."* and exit.
   - **Current newer than target** → halt. *"Vault is at X.Y.Z; target A.B.C is older. Downgrade is not supported."*
   - **Current older than target** → proceed to registry walk.

## Pre-flight checks

Run after mode detection, before shallow clone.

1. **Vault git state** — run `git status --porcelain` at vault root.
   - **Clean** → proceed.
   - **Dirty** → prompt the user:
     - `(a)` Stash pending changes, run update, pop stash at end
     - `(b)` Commit pending changes separately first (prompts for message using vault's `commit-message-guidelines.md`)
     - `(c)` Abort — let the user resolve manually
     - `(d)` Proceed with dirty state — per-hop commits will still use explicit paths; user is responsible for reconciling
2. **Framework allow-list present** — confirm the framework files expected at the recorded `.template-version` exist in the vault. The expected list comes from the union of `file_changes[].path` across all prior hops that landed on this vault (equivalently: every path this Skill would treat as framework-owned during the walk). If any non-`copy-if-missing` file is absent, halt:
   - *"Framework incomplete — `<path>` is missing. Run `/onboard-vault-metadata-framework --force-reinstall` to repair, or investigate manually."*
3. **Network reachable** — the shallow-clone step requires GitHub. On failure, surface the git error verbatim and halt; do not fall back to a partial run.

## Shallow clone of the target

Fetch `DeliberateGeek/template-obsidian` at the target tag into a tempdir. Shallow-clone (`--depth 1 --branch <tag>`) to minimize transfer. Register a cleanup hook so the tempdir is removed on every exit path (success, error, user abort).

The clone is the source of truth for both the registry files and for any file contents that `file_changes[]` operations will copy into the vault.

## Registry walk

1. **Enumerate hops.** Walk the chain of adjacent-version hops between current and target. For each expected hop, load `<tempdir>/.migrations/<from>-to-<to>.yaml`.
2. **Missing hop → halt.** If any expected hop file is absent, halt with *"Migration registry is missing hop `<from>-to-<to>.yaml`. Registry is authoritative — cannot proceed."* Do not attempt to infer the missing hop from file diffs.
3. **Adjacency check.** Verify each loaded hop's `from_version` equals the previous hop's `to_version` (or the vault's current version for the first hop), and the final hop's `to_version` equals the overall target. Any mismatch → halt.
4. **Schema validation per hop.** Validate each YAML against the schema documented in `MIGRATIONS.md`. A malformed hop file halts the entire run — partial application across a broken chain is not acceptable.
5. **Allow-list construction.** For the walk as a whole, the allow-list is the union of `file_changes[].path` across loaded hops. During per-hop apply, the effective allow-list is the current hop's own `file_changes[]` paths. The Skill NEVER writes to a path outside the current hop's `file_changes[]`.
6. **Framework-owned root enforcement.** For every `file_changes[].path` in every hop, verify the path resolves inside a framework-owned root (see `MIGRATIONS.md` § Framework-owned roots). Any path outside → halt; this is a registry-authoring error and should surface loudly.

## Per-hop apply

For each hop in sequence:

1. **Present the hop summary:**
   - From → to version
   - `summary` line
   - `breaking` flag (elevated warning if true: *"⚠️ Breaking change: <summary>. Review carefully before approving."*)
   - `file_changes[]` list: path, operation, rationale — one row each
   - `schema_changes[]` if present: kind, path, from/notes
   - `post_apply_notes[]` preview (will be displayed after commit)
2. **Approval gate.** Wait for explicit "yes." On anything else:
   - `no` / `abort` → exit. Vault is left at the last successful hop's version; already-applied hops stay committed.
   - `stop here` → same as abort, but print *"Stopped at v<last-applied>. Re-run `/update-metadata-framework` to resume."*
3. **Apply each `file_changes[]` entry per its operation:**
   - `copy` / `overwrite` — copy the file from `<tempdir>/<path>` to `<vault>/<path>`. Create parent directories as needed. Record the vault path in the tracked-paths list.
   - `copy-if-missing` — if `<vault>/<path>` exists, skip. Otherwise copy from tempdir. Never overwrites an existing file.
   - `diff-prompt` — compute a unified diff between `<vault>/<path>` and `<tempdir>/<path>`. Present the diff. Prompt per file: `(a)` accept (overwrite), `(b)` keep local, `(c)` abort hop. Keep-local records a note in the post-apply summary so the user knows that file will drift further on the next update.
   - `additive-merge` — inspect the target file for new sections/anchors not present locally. Insert additions at the declared anchor. If anchor ambiguity is detected, downgrade to `diff-prompt` for that file.
   - `object-merge` — structured YAML/JSON merge. Add keys present in target-but-not-local. Do NOT remove keys present in local-but-not-target unless `schema_changes[]` marks them `kind: removed` with a matching path. Write the merged result back.
4. **Schema-change reconciliation.** If the hop has `schema_changes[]`, after the file operations complete, prompt the user per entry: surface the schema change and ask whether `🫥 Meta/vault-metadata.yaml` needs a manual reconciliation. Offer: `(a)` edit now (open-ended — user edits), `(b)` defer (stamp a note to run `/audit-metadata` after), `(c)` acknowledge only (no change needed). Vault-metadata edits go in the same hop commit.
5. **Update `.template-version`.** Overwrite `🫥 Meta/.template-version` with `<to_version>` (plain text, no newline sensitivity — match the existing format). Add to tracked paths.
6. **Commit per hop.** Stage only the tracked paths (explicit — no `git add -A`). Commit message:
   - Type: `META(metadata)`
   - Subject: `update framework from template-obsidian <to_version>`
   - Body: hop summary, list of files changed with their operations, any deferred schema-change notes. Attribution lines per global `commit-workflow-checklist.md`.
7. **Approval gate on the commit message.** Present the proposed message and wait for explicit "yes" per global Rule 2. On approval, execute via Bash heredoc per global Rule 3. On rejection, offer revise / abort (changes stay staged) / reset (unstage, leave files in place).
8. **Push prompt.** After the commit succeeds, prompt *"Push to origin? (y/n)."* Do not auto-push.
9. **Display `post_apply_notes[]`** after the push decision.
10. **Offer continue or stop** before moving to the next hop. Default is continue; user may stop at any boundary. If the user stops, print the same resume message as in the approval-gate abort path.

## `--dry-run` mode

When `--dry-run` is passed:

- All mode detection, pre-flight checks, and the shallow clone run normally.
- Hops are loaded, validated, and summarized.
- For each hop, print the summary + planned file operations + schema changes + post-apply notes, but NEVER:
  - Copy files into the vault
  - Edit `.template-version`
  - Stage or commit
  - Prompt for approval
- After the full chain is reported, exit cleanly with *"Dry run complete. No changes written."*

Dry-run is the recommended first pass for any multi-hop walk.

## Tracked paths

Maintain a list of every vault file the Skill modifies or creates during each hop. The list resets between hops (each hop commits its own paths).

**Expected entries per hop:**
- Every vault path from `file_changes[]` that was actually written (respecting `copy-if-missing` skips and `diff-prompt` keep-local).
- `🫥 Meta/.template-version` (always, on success).
- `🫥 Meta/vault-metadata.yaml` if the user edited it during schema-change reconciliation.

**Never use `git add -A`.** The user may have unrelated unstaged work (especially if they chose dirty-state `(d)` in pre-flight).

## Error handling

- **Missing `.template-version`** — halt with guidance to run `/onboard-vault-metadata-framework`.
- **Stub `.template-version`** — halt with guidance to run `/init-vault-metadata-framework`.
- **Invalid `--target-version` (not semver, or tag does not exist)** — halt with the git error and a note that targets must be existing template-obsidian tags.
- **Missing hop file in the registry** — halt with the specific missing filename. Do not attempt diff-based fallback.
- **Malformed hop YAML** — halt with parser error, file path, and offending line.
- **`file_changes[].path` outside framework-owned roots** — halt with the offending entry; this is a registry-authoring bug.
- **File copy failure mid-hop** — roll back the hop: revert any files already copied in this hop using git (`git checkout -- <path>` for tracked paths; delete untracked-new files), do not update `.template-version`, do not commit. Surface the error and exit.
- **Shallow-clone failure** — surface the git stderr and halt. Cleanup hook removes the (likely-empty) tempdir.
- **User aborts at any approval gate** — exit cleanly. Previously-committed hops remain committed; the vault is at the last successful `to_version`.
- **Clone tempdir cleanup** — cleanup hook runs on every exit path including unhandled errors.

## Post-run guidance

After the final hop commits successfully (or dry-run completes):

- Summarize: *"Vault updated from v<start> → v<end>. <N> hop(s) applied, <M> commit(s) made."*
- If any `diff-prompt` files were kept-local, list them with a note that they will diverge further on the next update.
- If any schema-change reconciliation was deferred, remind: *"Run `/audit-metadata` soon to surface schema-driven findings."*
- If `post_apply_notes[]` from the final hop suggested an audit, echo that suggestion.

## Acceptance checklist

Mirrors the acceptance criteria from DeliberateGeek/template-obsidian#5.

**Registry**

- [ ] `MIGRATIONS.md` present at repo root with a `1.0.0` retroactive entry.
- [ ] `.migrations/` directory present.
- [ ] Per-hop YAML schema documented (in `MIGRATIONS.md`).
- [ ] Schema handles `copy` / `copy-if-missing` / `overwrite` / `diff-prompt` / `additive-merge` / `object-merge` operations.
- [ ] Breaking-change flag is surfaced per hop with elevated warning.

**Skill**

- [ ] Skill file present in `main`.
- [ ] Mode detection halts cleanly on missing `.template-version` (directs to `/onboard-...`).
- [ ] Mode detection halts cleanly on stub `.template-version` (directs to `/init-...`).
- [ ] Skill walks adjacent-version hops in order; halts on missing hop file.
- [ ] Adjacency check rejects broken chains.
- [ ] Each hop has its own approval gate; user can stop between hops.
- [ ] `🫥 Meta/.template-version` updated after each successful hop.
- [ ] Framework-owned path allow-list enforced — no writes outside current hop's `file_changes[]`.
- [ ] `--dry-run` reports planned hops and file changes without applying.
- [ ] `--target-version` pins to a specific tag; default is latest tag.
- [ ] Downgrade attempts halt with clear message.
- [ ] Explicit-path commit staging (no `git add -A`).
- [ ] Push prompt after each hop commit.

End-to-end verification against a real multi-version registry is scope for template-obsidian#6, not this story.
