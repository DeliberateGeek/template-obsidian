# Template Repo Guidance (template-obsidian)

**Purpose:** Guidance that applies when working on **this template repo itself** (`DeliberateGeek/template-obsidian`), NOT on Obsidian vaults created from this template. This file is stripped from consumer vaults during `/new-workspace` via the `templateOnlyPaths` mechanism (see `DeliberateGeek/WorkspaceToolkit/manifests/obsidian.json`).

The authoritative source for release discipline is [`MIGRATIONS.md`](../MIGRATIONS.md) § Release discipline. This file summarizes the key rules and signals *when* they apply.

## When a release cycle is expected

A release is triggered by **closing an associated feature or standalone story** that was implemented in this repo. If the current session is closing such an issue, expect to perform a release per the checklist in `MIGRATIONS.md`.

Signals the current work will close a story:
- The session was opened to work on a specific GitHub issue on this repo (or a cross-repo issue with implementation in this repo).
- The final AC on that issue implies "done" after the current commit lands.
- The user explicitly says the issue is closing.

If any of these apply, the release checklist runs before declaring the work complete.

## Release checklist (quick form)

Full detail in `MIGRATIONS.md` § Release checklist. Abbreviated:

1. Decide MAJOR / MINOR / PATCH per the classification rules.
2. Add a `MIGRATIONS.md` entry for the new version.
3. Author `.migrations/<from>-to-<to>.yaml` (empty `file_changes[]` if no framework-owned paths changed — this is still a required step).
4. Commit both files with `META(metadata): release <version>`.
5. Tag `v<version>` on `main` and push.

If the session's story closes without changing framework-owned files (e.g., improved `Home.md`, new README example), the release is still required — it's a PATCH bump with an empty `file_changes[]` hop.

## Pre-release tag discipline

During epic DeliberateGeek/WorkspaceToolkit#95 (in-flight as of 2026-04-20), the `v1.0.0` tag on this repo is force-moved to the latest commit to keep `/onboard-...` and `/update-metadata-framework` testing aligned with current framework state. At epic closure, `v1.0.0` settles on the final commit and stops moving. After closure, new work follows the normal release cycle above.

## Not in scope for this file

- Vault conventions (tagging, metadata framework philosophy, linking) — those live in `.claude/Claude Context/` and propagate to consumer vaults as intended.
- Commit message format — covered by the global `commit-workflow-checklist.md` and the vault-propagated `commit-message-guidelines.md`.
