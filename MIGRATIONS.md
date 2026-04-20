# Migration Registry

Human-readable history of every `template-obsidian` release that changes framework-owned files. Paired with machine-readable per-hop migration files in `.migrations/<from>-to-<to>.yaml`, consumed by the `/update-metadata-framework` Skill.

> **Why `.migrations/` is dot-prefixed:** Obsidian hides dot-prefixed folders from the file explorer. The migration registry is a concern of the *template repo*, not of onboarded vaults — hiding it keeps Obsidian users who clone the template as a starting point from seeing (and potentially deleting) an empty-looking folder full of YAML.

## Contract

- **Who writes here:** every release on this repo. Release authors add an entry to this file *and* a per-hop YAML in `.migrations/` before tagging — even when no framework-owned files change (an empty-`file_changes[]` hop). This keeps template version and framework version in sync; walker halts on a missing hop rather than silently drifting.
- **Who reads here:** humans reviewing release history. The Skill reads the per-hop YAML, not this document.
- **Scope of `file_changes[]`:** framework-owned paths only. Template-vault content (`Home.md`, `README.md`, `📥 Inbox/`, etc.) is out of scope — those files land via `/onboard-vault-metadata-framework` or `/new-workspace` and are not re-synced on update. A release that only changes template-vault content gets a registry entry with `file_changes: []`.
- **Versioning:** semver tags on `main`. Registered vaults record their current version in `🫥 Meta/.template-version` (see § Version format below).
- **Walking policy:** hops are applied in sequence, oldest first, with an approval gate between each. No skip-version YAMLs — the chain is authoritative.
- **Bootstrap is not a migration.** `1.0.0` has no `.migrations/*.yaml` file. A vault at `1.0.0` is the earliest state the Skill can start from; vaults with missing or stub `.template-version` are redirected to `/onboard-vault-metadata-framework` or `/init-vault-metadata-framework`.

### Version format

Framework versions are **bare semver** — `1.0.0`, not `v1.0.0`. This follows the canonical semver spec (semver.org §11): the `v`-prefix is reserved for git tag names and does not appear in recorded or referenced versions.

- `🫥 Meta/.template-version` contents: `1.0.0`
- Migration file names: `.migrations/<from>-to-<to>.yaml` (e.g., `.migrations/1.0.0-to-1.1.0.yaml`)
- Registry entries, error messages, and in-spec references: `1.0.0`
- Git tags (only): `v1.0.0`

When Skills call the GitHub tags API (which returns `v1.0.0`), they MUST strip the `v` prefix before recording or comparing the version. Skills MUST halt on a `v`-prefixed value in `.template-version` with a message directing the user to strip the prefix.

## Release discipline

Template version and framework version are kept in sync on this repo. Every git tag has a corresponding `MIGRATIONS.md` entry and `.migrations/<from>-to-<to>.yaml` file. Non-framework releases carry an empty `file_changes[]` hop. This produces a loud failure (walker halts on a missing hop) when discipline lapses, rather than silent drift between template state and recorded framework state.

### What triggers a release

A release is triggered by **closing an associated feature or standalone story** that was implemented in this repo. When such an issue closes, a tag-and-register cycle follows. Unreleased commits on `main` accumulate until the next story closes; multiple commits can land in a single release.

In-progress work, bug fixes without an associated closed story, and untagged commits do NOT constitute a release.

### Version classification

Decide the version increment per standard semver:

- **MAJOR** — breaking change to a framework file consumers depend on (e.g., removing a required field in `metadata-schema.yaml`, renaming an allow-listed path).
- **MINOR** — additive framework capability (new optional field, new framework Skill, new canonical rule).
- **PATCH** — framework bug fix, OR any non-framework change (template-vault content, `README`, `LICENSE`, `.editorconfig`, CI config).

### Release checklist

1. Merge the scope of work to `main`.
2. Decide the new version per classification above.
3. Add a `MIGRATIONS.md` entry under `## Release entries` with a one-line summary.
4. Author `.migrations/<from>-to-<to>.yaml`. If the release touches no framework-owned paths, `file_changes: []` is correct — the hop is a version marker only.
5. Commit both (`MIGRATIONS.md` + migration YAML) with `META(metadata): release <version>` or equivalent scope.
6. Tag `v<version>` on `main` and push (`git tag -a v<version> -m "Release <version>"` + `git push origin v<version>`).

### Recovery path

If `/update-metadata-framework` halts with *"Migration registry is missing hop X-to-Y.yaml"*, release discipline lapsed between some prior tag and the next. Recovery:

- Author the missing hop retroactively (likely `file_changes: []`) and cut a follow-up release that lands the hop file.
- Alternatively, have affected users manually edit `.template-version` to a registered version and re-run the walker (destructive to provenance; prefer retroactive hop).

## Per-hop YAML schema

Each adjacent-version hop is one file: `.migrations/<from-version>-to-<to-version>.yaml`. Example: `.migrations/1.0.0-to-1.1.0.yaml`.

```yaml
# Required
from_version: "1.0.0"          # semver; must match an existing tag
to_version: "1.1.0"             # semver; must match an existing tag
summary: "One-line description; mirrors the MIGRATIONS.md entry."
breaking: false                 # true surfaces a strong warning before the hop's approval gate

# Required. Every framework-owned path touched by this release appears here.
# The Skill's allow-list = union of file_changes[].path across the hops it is applying.
# Any path not enumerated in at least one hop's file_changes[] is NEVER written by the Skill.
file_changes:
  - path: ".claude/Claude Context/metadata-schema.yaml"
    operation: overwrite        # see Operations below
    rationale: "Added promotion_threshold_strict flag to vault.retention."

  - path: ".claude/skills/audit-metadata/SKILL.md"
    operation: diff-prompt
    rationale: "Section 7 retirement logic refined; review the diff before accepting."

  - path: "🫥 Meta/vault-metadata.yaml.template"
    operation: copy-if-missing
    rationale: "Template stub only; never overwrites a real vault-metadata.yaml."

# Optional. Schema-level changes the user may need to reconcile in their vault-metadata.yaml.
schema_changes:
  - kind: added                 # added | removed | renamed | retyped
    path: "vault.retention.promotion_threshold_strict"
    notes: "Optional; defaults to false. Review if you rely on promotion suggestions."

  - kind: renamed
    path: "properties[].values"
    from: "enum_values"
    notes: "Old name was inconsistent with schema conventions."

# Optional. Guidance surfaced to the user AFTER the hop's apply commits.
post_apply_notes:
  - "Consider running `/audit-metadata` — this release tightened promotion thresholds."
```

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `from_version` | semver string | yes | Must be an existing `template-obsidian` tag. |
| `to_version` | semver string | yes | Must be an existing `template-obsidian` tag, adjacent to `from_version` in the release history. |
| `summary` | string | yes | One line; mirrors the `MIGRATIONS.md` entry for this hop. |
| `breaking` | bool | yes | `true` triggers an elevated warning before the approval gate. |
| `file_changes[]` | list | yes | At least one entry. Defines the allow-list for this hop. |
| `file_changes[].path` | vault-relative string | yes | Must resolve inside a framework-owned root (see below). |
| `file_changes[].operation` | enum | yes | One of the operations below. |
| `file_changes[].rationale` | string | yes | Human-readable reason; surfaced during the hop summary. |
| `schema_changes[]` | list | no | Used when `metadata-schema.yaml` is touched; lets the user reconcile `vault-metadata.yaml`. |
| `schema_changes[].kind` | enum | yes if present | `added` / `removed` / `renamed` / `retyped`. |
| `schema_changes[].path` | dotted string | yes if present | Path within the schema. |
| `schema_changes[].from` | string | conditional | Required when `kind: renamed` or `kind: retyped`. |
| `schema_changes[].notes` | string | no | Freeform. |
| `post_apply_notes[]` | list of strings | no | Surfaced after the commit lands. |

### Framework-owned roots

The Skill rejects any `file_changes[].path` outside these roots:

- `.claude/Claude Context/`
- `.claude/scripts/`
- `.claude/skills/` *(only template-shipped Skills; vault-local Skills outside this directory are never touched)*
- `🫥 Meta/` *(stubs and framework-controlled files only — see operation rules)*

### Operations

| Operation | Behavior | Typical use |
|-----------|----------|-------------|
| `copy` | Write the file from the target-tag template, overwriting unconditionally. | Framework files that are not expected to be user-edited (e.g., `metadata-schema.yaml`). |
| `copy-if-missing` | Write only if the vault does not have the file. | Template stubs (`vault-metadata.yaml.template`, `Canonical Metadata.md.template`) — a real vault already has `vault-metadata.yaml`; the stub must not reappear. |
| `overwrite` | Same as `copy`; explicit alias when the intent is to replace an expected-unchanged file. | Rewrites where user edits would be out-of-contract (scripts, Skill files). |
| `diff-prompt` | Present a diff between the vault's file and the target-tag version; prompt the user per-file (accept / keep-local / abort-hop). | Files that have narrative content a user may have locally annotated (e.g., a Skill SKILL.md the user customized). |
| `additive-merge` | Append or insert additions from the target-tag version without removing local content. Requires a deterministic anchor (e.g., a YAML key, a marker comment). | Script libraries or Context files where new sections are added without disturbing existing ones. |
| `object-merge` | Structured YAML/JSON merge. Keys added in target are added locally; keys removed in target are NOT removed locally unless `schema_changes[]` explicitly marks them removed. | `metadata-schema.yaml` when additive, though overwrite is usually preferred for invariants. |

If a release needs an operation not listed here, add it to this table in the same release that introduces it.

## Release entries

Entries are most-recent-first. Each entry mirrors the summary line of its per-hop YAML.

### 1.0.0 — 2026-04-19

**Initial release** (git tag: `v1.0.0`). Establishes the framework-file baseline and the Phase 2 Skill set. No prior version to migrate from — vaults entering the update flow at `1.0.0` are at the earliest supported state.

Framework Context files:

- `.claude/Claude Context/metadata-schema.yaml` — structural schema for `vault-metadata.yaml`.
- `.claude/Claude Context/metadata-philosophy.md` — narrative design reference.
- `.claude/Claude Context/metadata-examples.md` — worked classification examples.
- `.claude/Claude Context/commit-message-guidelines.md` — vault-local commit conventions.
- `.claude/Claude Context/vault-guide.md` — vault-level guidance.

Framework Skills (ship with the template so onboarded vaults inherit them):

- `.claude/skills/audit-metadata/SKILL.md` — on-demand full-vault audit.
- `.claude/skills/init-vault-metadata-framework/SKILL.md` — first-run canonical-list authoring.
- `.claude/skills/update-metadata-framework/SKILL.md` — version-sync walker for this registry.

Vault metadata scaffolding:

- `🫥 Meta/.template-version` — records `1.0.0`.
- `🫥 Meta/vault-metadata.yaml.template` — stub consumed by `/init-vault-metadata-framework`.
- `🫥 Meta/Canonical Metadata.md.template` — stub rendered view.
- `🫥 Meta/Audit Logs/` — directory for daily audit logs (created at install; populated by the framework scripts and Skills).

Registry files (template-repo only; not installed into vaults):

- `MIGRATIONS.md` — this file.
- `.migrations/` — per-hop YAML directory. Empty at `1.0.0` (bootstrap is not a migration).

Because `1.0.0` is the bootstrap, there is no `.migrations/` entry for it. The next release will be the first hop file (e.g., `.migrations/1.0.0-to-1.1.0.yaml`).
