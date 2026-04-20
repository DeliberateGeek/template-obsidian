# Migration Registry

Human-readable history of every `template-obsidian` release that changes framework-owned files. Paired with machine-readable per-hop migration files in `.migrations/<from>-to-<to>.yaml`, consumed by the `/update-metadata-framework` Skill.

> **Why `.migrations/` is dot-prefixed:** Obsidian hides dot-prefixed folders from the file explorer. The migration registry is a concern of the *template repo*, not of onboarded vaults — hiding it keeps Obsidian users who clone the template as a starting point from seeing (and potentially deleting) an empty-looking folder full of YAML.

## Contract

- **Who writes here:** every release that modifies a framework-owned file (the allow-list installed into `🫥 Meta/`, `.claude/Claude Context/`, `.claude/scripts/`, and `.claude/skills/`). Release authors add an entry to this file *and* a per-hop YAML in `.migrations/` before tagging.
- **Who reads here:** humans reviewing release history. The Skill reads the per-hop YAML, not this document.
- **Scope:** framework-owned paths only. Template-vault content (`Home.md`, `README.md`, `📥 Inbox/`, etc.) is out of scope — those files land via `/onboard-vault-metadata-framework` and are not re-synced on update.
- **Versioning:** semver tags on `main`. Registered vaults record their current tag in `🫥 Meta/.template-version`.
- **Walking policy:** hops are applied in sequence, oldest first, with an approval gate between each. No skip-version YAMLs — the chain is authoritative.
- **Bootstrap is not a migration.** `v1.0.0` has no `.migrations/*.yaml` file. A vault at `1.0.0` is the earliest state the Skill can start from; vaults with missing or stub `.template-version` are redirected to `/onboard-vault-metadata-framework` or `/init-vault-metadata-framework`.

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

### v1.0.0 — 2026-04-16

**Initial release.** Establishes the framework-file baseline. No prior version to migrate from — vaults entering the update flow at `1.0.0` are at the earliest supported state.

Framework files shipped:

- `.claude/Claude Context/metadata-schema.yaml` — structural schema for `vault-metadata.yaml`.
- `.claude/Claude Context/metadata-philosophy.md` — narrative design reference.
- `.claude/Claude Context/metadata-examples.md` — worked classification examples.
- `.claude/Claude Context/commit-message-guidelines.md` — vault-local commit conventions.
- `.claude/Claude Context/vault-guide.md` — vault-level guidance.
- `.claude/skills/audit-metadata/SKILL.md` — on-demand audit Skill (ships with the template so onboarded vaults inherit it).
- `.claude/skills/init-vault-metadata-framework/SKILL.md` — first-run canonical-list authoring Skill.
- `🫥 Meta/.template-version` — records `1.0.0`.
- `🫥 Meta/vault-metadata.yaml.template` — stub consumed by `/init-vault-metadata-framework`.
- `🫥 Meta/Canonical Metadata.md.template` — stub rendered view.
- `🫥 Meta/Audit Logs/` — directory for daily audit logs (created at install; populated by the framework scripts and Skills).

Because `1.0.0` is the bootstrap, there is no `.migrations/` entry for it. The next release (`1.1.0` or similar) will be the first hop file (`.migrations/1.0.0-to-1.1.0.yaml`).
