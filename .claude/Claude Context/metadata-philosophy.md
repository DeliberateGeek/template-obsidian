# Metadata Philosophy

> **Tag by dimension, not by detail. Proper nouns are properties, not tags — and staleness is declared, not inferred.**

That one sentence resolves ~80% of day-to-day classification questions without looking anything up.

- **Tag by dimension** — one tag per meaningful *axis of discovery* (content type, topic, capability), not one tag per noun in the note.
- **Proper nouns are properties** — `authentik`, `epsilon3`, `katho-thornhill` live in frontmatter as structured fields (often wiki-linked), never as tags.
- **Staleness is declared** — each content type explicitly opts in to lifecycle tracking. Notes without declared lifecycle are never flagged stale.

## Boundary Rules

### Use a TAG when

- The value is a **category or dimension** with many members (`homelab`, `docker`, `reference`)
- You'd **filter a pane of notes** by it
- It's multi-valued and categorical with a bounded, enumerable set of values

### Use a PROPERTY (frontmatter field) when

- The value is a **proper noun** (`authentik`, `epsilon3`)
- The value is a **date or number**
- The value is **single per note** by nature (`status`, `host`, `campaign`)
- You'd **display it as a column** in a dataview table
- It encodes a **relationship to a specific entity that deserves its own note** — use a wiki-link inside the property (`host: "[[epsilon3]]"`)

### Use a FOLDER when

- The value answers "what *kind* of container does this live in?" at a stable top level
- It would be disruptive to change later
- There's exactly **one right answer** per note

### Use a WIKI-LINK when

- The referenced thing **deserves its own note**
- You want **backlinks** to light up retrieval from the other direction
- The value is a **proper noun that recurs** across many notes

## Tag Format Rules

### Hard fail — auto-fix where possible

1. **Lowercase only** — auto-fix (Linter lowercases on save)
2. **Kebab-case for multi-word** — auto-fix (Linter converts underscores/camelCase)
3. **Must start with a letter** — reject + prompt (human decision required)
4. **Minimum 2 characters** — reject + prompt

### Soft flag — surface at session-end, don't block

5. **No punctuation other than `-`** (bans `/` — hierarchical tags rejected)
6. **Maximum ~30 characters**

## Content Type Redundancy

Content type MAY be expressed as **folder and tag together** (belt-and-suspenders), especially when folder count is high. Not required; the redundancy survives drift better than single-source discipline.

Example: a session log note lives in a `Session Logs/` folder AND carries a `session-log` tag. Either alone is sufficient for discovery; together they're resilient against folder renames and tag cleanup errors.

## Property-to-Folder Promotion

Promote a property-value to its own folder when **ALL** of:

1. Count >= `promotion_threshold` (default 8, vault-tunable in `vault-metadata.yaml`)
2. Folder name would be stable (not likely renamed/split within 6 months)
3. You'd navigate to it visually at least weekly

Migration is flagged at session-end; executed by Claude via script on approval.

## Hierarchy

- **Reject** hierarchical tags (`#rpg/ironclaw/session-log`) — invites synonym sprawl
- Hierarchy emerges from **folder path + flat atomic properties + dataview composition** at query time
- If you feel the urge to nest tags, that's a signal to use folder structure or properties instead

## Capture, Defer, and Audit Flow

The framework uses a three-phase approach that keeps capture frictionless while ensuring nothing falls through the cracks.

### At capture (when Claude is engaged)

Claude proposes metadata additions/corrections inline. User responds:

- **Accept** — Claude writes changes, notes in end-of-turn summary
- **Defer** — Claude runs `metadata-defer.ps1` (pre-approved, silent), stamps `metadata_review: pending` plus optional reason, moves on
- **Reject** — Claude flags for canonical-list review

### At session-end (automatic)

- Short-circuits on empty queue ("closed cleanly")
- On populated queue: numbered summary table, categorized findings
- Dispositions: walk-through / mass-accept / defer-all / skip / **hybrid range syntax** ("approve 1, 3, 6-10; interactive rest")
- Writes audit log entry + session-end marker file

### On-demand (`/audit-metadata` Skill)

Full-vault pass covering eight sections (empty sections omitted):

1. Canonical compliance
2. Fuzzy synonym candidates (**always confirmation-required**)
3. Property integrity (broken wiki-links, missing required fields)
4. Staleness report
5. Long-pending review flags (> 30 days)
6. Property-to-folder promotion candidates
7. Retirement candidates: canonical tags with 0 current usages (not time-based)
8. Audit log hygiene

### At session-start (automatic)

Reads last-session-end marker. If prior session ended abruptly, surfaces lingering pending items.

## Alias Normalization

- **Declared aliases** — silently normalized with audit log entry (pre-approved; the mapping is already vouched for)
- **Fuzzy match candidates** — always confirmation-required, never auto-normalized
- **Unknown tags** — accepted at capture without friction; surfaced at session-end for batch classification (alias / new canonical / delete)

## Staleness

**Staleness is declared, not inferred.** The schema supports per-content-type lifecycle opt-in:

```yaml
content_types:
  - id: reference
    lifecycle:
      applicable: true
      property: status
      values: [active, archived]
      staleness: { active: 90d }

  - id: rpg-reference
    lifecycle:
      applicable: false    # never stale
```

Content types that don't opt in are not subject to staleness audits — no false positives. The `staleness` map defines per-status-value thresholds: a note with `status: active` and no edits for 90 days gets flagged; a note with `status: archived` never does (unless the content type declares a threshold for `archived`).

## Validation Layers

Four layers, increasing in cost and judgment required:

| Layer | Mechanism | Trigger | Deterministic? |
|-------|-----------|---------|----------------|
| 1. Canonical | Script / Skill | Automatic | Yes |
| 2. Referential | Dataview queries | Automatic | Yes |
| 3. Semantic | Claude judgment | On-demand + opportunistic | No |

Layers 1-2 catch mechanical errors. Layer 3 catches misclassification, missing dimensions, and over-tagging — things only judgment can evaluate.

## Audit Log

- **Location:** `Meta/Audit Logs/YYYY-MM-DD.md` (daily rotation, in-vault, git-tracked)
- **Scope:** Claude-initiated changes only (user edits already captured by git)
- **Retention:** 90 days (default, vault-tunable; aligns with `status: active` staleness threshold)
- **Cleanup:** Part of `/audit-metadata` Skill, deliberate and logged

## Canonical List Governance

- Accept unknown tags at capture (frictionless) — surface at session-end for classification with confirmation
- Declared aliases are first-class canonical data
- Fuzzy match reserved for `/audit-metadata` Skill
- Retirement is based on 0-usage count, not elapsed time — a tag with even one active note is not a retirement candidate

## Plugin Integration

### Required

- **Dataview** — queryable audit logs, canonical views, staleness, orphan detection

### Recommended

- **Templater** — content-type templates generated from schema populate required/optional frontmatter
- **Tag Wrangler** — bulk rename (enables alias-to-canonical normalization)

### Native (enable)

- **Properties view** — Obsidian's built-in frontmatter editor

### Explicitly not recommended

- **Metadata Menu** — overlaps with canonical schema; creates competing source of truth
- **Breadcrumbs** — unrelated concern, adds surface area
- **Dataview JS** — arbitrary-complexity trap door; DQL is sufficient

### Plugin provisioning rules

- **Additive install, merge-not-overwrite config** — orthogonal plugins untouched
- Config added to existing plugin's data is namespaced where possible; conflicts flagged, never silently overwritten
- `.template-version` marker enables targeted upgrades

## Provisioning Contract

The `.template-version` marker in `Meta/` records which framework version a vault is running. `/migrate-vault --update` diffs local against current template and proposes targeted updates — enables long-term maintenance without re-seeding.

## Commit Conventions

- Commit type: **META** (enumerated in `.gitmessage`)
- Suggested scope: `metadata` (e.g., `META(metadata): seed vault-metadata`)
