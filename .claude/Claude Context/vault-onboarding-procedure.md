# Vault Onboarding Procedure

Interactive procedure Claude follows when onboarding an Obsidian vault to the metadata framework. Not a Skill; not a script with flags. When the operator says "onboard PersonalVault" (or similar), Claude reads this procedure and walks through it conversationally.

Context for this procedure lives in WT#95 § "2026-04-21 — Scope cut to kernel."

## Prerequisites

- Target vault exists and is a git repository
- `template-obsidian` is available locally at a known path
- Operator is ready to make judgment calls about the vault's canonical metadata (this is the interactive part)

## Procedure

### Step 1 — Copy framework files

Framework files land in three locations in the vault, mirroring `template-obsidian`'s own layout:

Copy from `template-obsidian/.claude/Claude Context/` into `<vault>/.claude/Claude Context/`:

- `metadata-philosophy.md`
- `metadata-examples.md`
- `metadata-schema.yaml`

Copy from `template-obsidian/🫥 Meta/` into `<vault>/🫥 Meta/`:

- `vault-metadata.yaml.template`
- `Canonical Metadata.md.template`

Copy from `template-obsidian/.claude/scripts/` into `<vault>/.claude/scripts/`:

- `Invoke-MetadataNormalize.ps1`
- `Invoke-MetadataValidate.ps1`

When the `/metadata-check` Skill lands (see `DeliberateGeek/template-obsidian#27`), copy its directory from `template-obsidian/.claude/skills/metadata-check/` into `<vault>/.claude/skills/metadata-check/`. Until then, Step 1 produces a vault that can be validated/normalized via direct script invocation.

### Step 2 — Merge `.gitignore`

Compare the vault's existing `.gitignore` with `template-obsidian/.gitignore`. Append any metadata-framework lines that aren't already present. Present the diff to the operator before writing.

### Step 3 — Seed `vault-metadata.yaml`

Copy `🫥 Meta/vault-metadata.yaml.template` to `🫥 Meta/vault-metadata.yaml` (if not already present from a prior step).

### Step 4 — Scan existing tag/property usage

Run a discovery scan against the vault's notes. Extract:

- All unique tags with usage counts
- All unique frontmatter properties with usage counts
- Any shape irregularities (block vs. inline tag arrays, etc.)

Present a frequency table to the operator. `Invoke-MetadataValidate.ps1` can produce this directly if run with no canonical list, or it can be done as an inline grep/parse pass — either is fine.

### Step 5 — Interactive canonical-list shaping

With the frequency table in view, converse with the operator:

- Which observed tags become canonical topics in `vault-metadata.yaml`?
- Which are aliases for other canonical topics?
- Which values belong as frontmatter properties, not tags?
- Which are one-off/legacy tags that should be retired?
- What content-types, if any, are relevant to this vault's purpose?

Edit `vault-metadata.yaml` iteratively. The operator drives; Claude proposes based on observed usage and the philosophy document.

### Step 6 — Optional normalize pass

Offer to run `Invoke-MetadataNormalize.ps1` over the vault with the alias map the operator just defined. Preview changes note-by-note before applying. Apply on approval.

### Step 7 — Commit

Stage the onboarding changes as a single commit. Propose a message reflecting what actually happened — e.g.:

```
CHORE(metadata): Onboard <VaultName> to metadata framework

- Add framework files (philosophy, examples, schema)
- Add framework scripts (normalize, validate)
- Author initial vault-metadata.yaml reflecting <N> canonical topics, <M> aliases
- Normalize <K> notes against the new canonical list
```

Wait for operator approval per the standard commit workflow.

## Notes

- Every vault's canonical list diverges from the template's starter. The template is a starting point, not a universal standard.
- If the vault is brand-new (no existing notes), Step 4 surfaces nothing; Step 5 becomes "start from template defaults, tailor to purpose."
- Re-running this procedure on an already-onboarded vault is not supported. For drift over time, use `/metadata-check` (once it lands). For a ground-up reconsideration, manually edit `vault-metadata.yaml` or delete-and-re-onboard.
