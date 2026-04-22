---
name: metadata-check
description: Conversational drift-check for an Obsidian vault's tags against the canonical list in vault-metadata.yaml. Surfaces alias drift, shape drift, and unknown tags; applies operator-approved fixes; orchestrates a single closing commit.
---

# /metadata-check — Vault Metadata Drift Check

**Purpose:** Detect and resolve metadata drift against the vault's canonical list. Single lightweight Skill — no modal dispatch, no flags, no persisted findings file. Conversation is the durable record; git diffs are the durable artifact.

**Invocation:** `/metadata-check` — no arguments.

## When to invoke

- Periodic hygiene pass on a vault (weekly, after a bulk import, after a migration)
- When tag drift is suspected ("feels like I've been adding random tags lately")
- During vault onboarding, after the interactive canonical-list shaping step

## When NOT to invoke

- Single-note metadata questions — handle conversationally without running the Skill
- On a vault that is not yet onboarded — this Skill requires `🫥 Meta/vault-metadata.yaml`; if absent, point the operator to `.claude/Claude Context/vault-onboarding-procedure.md`

## Pre-flight

Run in order. Abort on any failure with a clear message.

1. **Vault root detection** — resolve from cwd: walk up until `.obsidian/` is found. If no ancestor has `.obsidian/`, halt: *"Not inside an Obsidian vault (no .obsidian/ found)."*

2. **Canonical list present** — check `<vault-root>/🫥 Meta/vault-metadata.yaml` exists. If absent, halt with: *"Vault is not onboarded to the metadata framework. See `.claude/Claude Context/vault-onboarding-procedure.md` to onboard."* Do NOT attempt onboarding from this Skill.

3. **Canonical list valid** — invoke:
   ```
   pwsh.exe -File .claude/scripts/Invoke-MetadataValidate.ps1 -MetadataPath "🫥 Meta/vault-metadata.yaml"
   ```
   Interpret the exit code per `.claude/Claude Context/framework-scripts-reference.md`:
   - **Exit 0** — proceed
   - **Exit 1** — structural findings; surface them and halt: *"Fix the canonical-list violations above, then re-run `/metadata-check`."* Scanning notes against a malformed canonical list would produce misleading output.
   - **Exit 2** — environment problem; surface and halt

## Core loop

### Step 1 — Scan notes

Invoke:
```
pwsh.exe -File .claude/scripts/Invoke-MetadataScan.ps1 -VaultRoot <vault-root> -Json
```

Capture stdout and parse as JSON. Expected shape:
```json
{
  "alias_drift":  [ { "note": "...", "from": "...", "to": "...", "collision": false } ],
  "shape_drift":  [ { "note": "...", "current_shape": "block" } ],
  "unknown_tags": [ { "tag": "...", "notes": ["..."] } ]
}
```

If all three arrays are empty:
```
✅ No drift detected. Vault metadata is in canonical shape.
```
and exit. No commit. No further prompts.

Otherwise continue to Step 2.

### Step 2 — Converse per category

Present findings in three category passes in this order: **alias drift → shape drift → unknown tags**. Cheap-mechanical first, operator-judgment last.

Each category follows the same conversational pattern:

1. Render a numbered findings table with a **recommended disposition pre-populated** on each row
2. Accept a single disposition block from the operator (ranges + shortcuts, see below)
3. Apply the approved dispositions for that category before moving to the next
4. Report what was applied, then move to the next category

Skip any category whose finding list is empty.

#### Alias drift presentation

```
Alias drift (N findings) — declared aliases that should normalize to their canonical form.

Recommended: approve all. These are mechanical substitutions governed by the canonical alias map.

  #  Note                                   From           To       Notes
  1  Knowledge/Homelab/Frigate.md           containers  -> docker
  2  Knowledge/Auth.md                      k8s         -> kubernetes  [collision — will dedupe]
  ...

Your disposition?
```

**Valid disposition blocks:**
- `approve all` (equivalent: `accept all`) — approve every finding
- `skip all` — take no action on this category, move on
- `approve 1, 3, 5-7` — approve listed indices; un-listed findings default to **skip**
- `approve 1-3; skip rest` — explicit fallback clause (ranges of `skip`, `defer` not applicable here — `defer` was kernel-cut)
- `interactive` — walk through each finding one-by-one
- `interactive 4-6` — walk through listed range, others skip

**Apply:** for each approved finding, add its `from` tag → `to` canonical to an alias map. After parsing all approvals, write the alias map to a temp file and invoke once:
```
pwsh.exe -File .claude/scripts/Invoke-MetadataNormalize.ps1 -Notes "<note1>,<note2>,..." -AliasMapPath "<temp-map>"
```
Report the normalize script's output.

#### Shape drift presentation

```
Shape drift (N findings) — tag arrays not in canonical inline shape.

Recommended: approve all. Shape is governed by the schema's inline-array-shape rule; no content changes, only whitespace.

  #  Note                                   Current shape
  1  Knowledge/Homelab/Node1.md             block
  2  RPG-Player/Session14.md                scalar
  ...

Your disposition?
```

Same disposition block grammar as alias drift. **Apply:** invoke normalize once with the `-ShapeOnly` switch:
```
pwsh.exe -File .claude/scripts/Invoke-MetadataNormalize.ps1 -Notes "<note1>,<note2>,..." -ShapeOnly
```

#### Unknown tag presentation

Unknown tags are grouped per unique tag (the scan already groups this way). Each unique tag gets one finding regardless of how many notes carry it.

```
Unknown tags (N findings) — tags that are neither canonical nor declared aliases.

Recommended: per-tag judgment required. No default — every unknown tag needs an explicit disposition.

  #  Tag             Notes (count)  Recommendation
  1  homelab         3              promote-to-canonical (topic appears frequently)
  2  containers-lab  1              b:docker (alias candidate; similar to existing canonical)
  3  tmp             2              retire (transient; unlikely long-term value)
  ...

Your disposition?
```

**Inline alias syntax:** operator may specify `b:<canonical>` to add the unknown tag as an alias of an existing canonical (e.g., `b:docker`). Claude validates `<canonical>` exists in the canonical list before accepting.

**Per-tag dispositions:**
- `a` — promote to canonical topic in `vault-metadata.yaml` (adds to `topics[]`)
- `b:<canonical>` — add as alias of `<canonical>` in `vault-metadata.yaml` (appends to the matching `topics[].aliases[]`); after canonical-list edit, affected notes are re-normalized via `Invoke-MetadataNormalize.ps1` to substitute the new alias on the spot
- `c` — retire/delete the tag from all listed notes (edit each note's tags region)
- `d` — skip this tag for this run (no-op; surfaces again next run)

**Valid disposition block examples:**
- `a for 1, c for 2-3, b:docker for 4` — per-finding dispositions
- `a for 1; skip rest`
- `interactive` — walk through each finding one-by-one with these options

**Apply order:**
1. Canonical-list edits (dispositions `a` and `b:<canonical>`) — edit `vault-metadata.yaml` in one batch
2. Re-invoke `Invoke-MetadataScan.ps1` briefly to confirm the canonical-list edits dissolved the expected unknowns
3. Tag deletions (disposition `c`) — edit notes in place to remove the tag from each listed note
4. Alias re-normalizations (disposition `b:<canonical>`) — invoke `Invoke-MetadataNormalize.ps1` with the updated alias map covering the newly-declared aliases

### Step 3 — Report what changed

After all three categories are processed, print a concise summary:

```
Applied changes:
  • Alias drift:  N notes normalized
  • Shape drift:  N notes rewritten
  • Unknown tags: N canonical additions, N alias additions, N notes with tag deletions

Notes to be committed:
  <list of touched note paths + vault-metadata.yaml if edited>
```

Proceed to Step 4 if any files changed; exit cleanly if the operator skipped everything (no commit needed).

### Step 4 — Single closing commit

Propose a commit per the global commit workflow (`~/.claude/commit-workflow-checklist.md`). This Skill does not bypass approval.

**Commit type selection** (per vault's `commit-message-guidelines.md`):
- If only notes were touched: `META(metadata)` — note content changed
- If only `vault-metadata.yaml` was touched (no note edits): `META(metadata)`
- If both: still `META(metadata)` — single type covers the commit

**Stage explicit paths only** — do NOT use `git add -A`. Use the tracked list produced in Step 3.

**Propose** the commit message → **wait for explicit "yes"** → **execute via Bash heredoc**. No auto-push. Standard attribution lines per global workflow.

## Disposition parser details

Hybrid range syntax mirrors `/audit-metadata`'s pattern (preserved across the kernel cut as one of the two patterns worth carrying forward).

### Grammar

```
disposition-block  = ranged-clause ( ";" fallback-clause )?
ranged-clause      = shortcut | ( action range-list ( "," action range-list )* )
fallback-clause    = action "rest"
shortcut           = "approve all" | "accept all" | "skip all" | "interactive" | "interactive" range-list
action             = "approve" | "accept" | "skip" | ( "a" | "c" | "d" )     # unknown-tag category adds "a"/"c"/"d"
                   | "b:" canonical-id                                        # unknown-tag alias-of syntax
range-list         = range ( "," range )*
range              = integer | integer "-" integer
```

### Parsing rules

1. **Split on `;`** to separate the ranged clause from the fallback clause. At most one `;` per disposition block.
2. **Ranged clause** — apply each `action range-list` pair to the listed indices. In the unknown-tag category, each action is per-pair (can mix `a`, `c`, `d`, `b:<x>` in one block).
3. **Fallback clause** — applies the named action to every index not covered by the ranged clause. If absent, un-covered indices default to **skip**. Announce this before executing so the operator can correct.
4. **Out-of-range index** — abort parsing; re-prompt with the valid index range. Do not partial-apply.
5. **Invalid `b:<canonical>`** — where `<canonical>` is not in the canonical list — abort parsing; re-prompt.

### Category-specific disposition grammars

| Category | Actions allowed |
|---|---|
| Alias drift | `approve` (or `accept`), `skip`, `interactive` |
| Shape drift | `approve` (or `accept`), `skip`, `interactive` |
| Unknown tags | `a`, `b:<canonical>`, `c`, `d`, `skip`, `interactive` |

## Error handling

- **Scan script exits non-zero** — surface the stderr, halt. Do not attempt to work with partial findings.
- **Operator-provided `<canonical>` in `b:<canonical>` not in canonical list** — re-prompt with the list of valid canonicals.
- **Normalize script exits non-zero during apply** — surface stderr, preserve the disposition record, halt the current category. Already-applied categories stay applied (they were approved and their commits recorded in memory). Operator can re-run the Skill to pick up the remainder.
- **`vault-metadata.yaml` edit fails validation post-edit** — roll back the in-memory edit, report the validation error, let the operator retry or skip.

## Out of scope (explicitly dropped in kernel cut)

- **Fuzzy synonym detection** — Levenshtein / similarity scoring against canonicals. The Skill does not surface "did you mean?" suggestions. Operators decide via `b:<canonical>` inline syntax.
- **Staleness detection** — `lifecycle.applicable` + age-of-modification checks.
- **Promotion candidates** — frontmatter properties that could become folders.
- **Retirement candidates** — canonical topics with zero/low usage.
- **Property integrity checks** — broken wiki-links in properties, missing required fields, enum violations.
- **Daily audit-log writes** — no `🫥 Meta/Audit Logs/YYYY-MM-DD.md` appends.
- **Persisted findings file** — no `audit-report-*.md` artifact. Git diff is the durable record.
- **`--save-findings` or any flag** — single invocation pattern, no CLI surface.
- **Dirty-git-state pre-flight** — the operator is trusted to start from a clean working tree or knowingly mix changes; the closing commit uses explicit paths so unrelated dirty files stay out.
- **Push prompt** — never auto-push; operator pushes when ready.

## Acceptance criteria (for Skill authoring verification)

- [ ] Skill runs from within any vault with `🫥 Meta/vault-metadata.yaml` present and valid
- [ ] Pre-flight correctly halts on missing / invalid canonical list with actionable messages
- [ ] Scan findings rendered as numbered tables with per-category recommendations
- [ ] Disposition parser accepts the documented grammar and rejects out-of-range / invalid inline canonicals
- [ ] Alias drift → normalize; shape drift → normalize `-ShapeOnly`; unknown tags → canonical-list edit + re-scan + note edits + alias re-normalize
- [ ] All edits are staged on explicit paths and committed as a single `META(metadata)` commit after operator approval
- [ ] No auto-push
- [ ] Zero-findings case exits cleanly without a commit
