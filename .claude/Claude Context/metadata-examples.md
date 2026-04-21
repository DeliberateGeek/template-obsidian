# Metadata Classification Examples

Worked examples demonstrating the boundary rules from `metadata-philosophy.md`. Each example shows a note scenario, the correct classification, and the rationale.

These examples train classification judgment. When you encounter a new note, find the closest example and reason by analogy.

---

## Frontmatter shape

Tags serialize as a single-line inline array:

```yaml
---
tags: [reference, homelab, sso, docker]
---
```

Not as a YAML block list (`tags:\n  - reference`) or a bare scalar. Canonical rule lives in `metadata-schema.yaml → tag_format_rules.hard_fail.inline-array-shape`; scripts that rewrite frontmatter tags (e.g., `Invoke-MetadataNormalize.ps1`) emit inline shape and Claude auto-fixes at capture. The examples below describe tags narratively for readability; actual frontmatter always uses the inline form shown above.

---

## Example 1 — Service operational reference

**Scenario:** A note documenting how Authentik SSO is deployed, configured, and operated on a specific host.

**Classification:**
- **Tags:** `reference`, `homelab`, `sso`, `docker`
- **Properties:** `host: "[[epsilon3]]"`, `service: "[[authentik]]"`, `status: active`
- **Folder:** `Knowledge/Homelab/`

**Rationale:** `reference` is a content type (what kind of note). `homelab`, `sso`, `docker` are topics (what it's about — retrieval dimensions). The service name and host are proper nouns — properties, not tags. You'd search by topic ("show me all SSO notes") but display host/service as table columns.

---

## Example 2 — Learning plan for a programming language

**Scenario:** A structured learning plan for Rust, with goals, resources, and progress tracking.

**Classification:**
- **Tags:** `learning`, `programming`
- **Properties:** `status: active`, `created: 2026-03-15`
- **Folder:** `Learning/`

**Rationale:** `learning` is both folder and tag (belt-and-suspenders). `programming` is a topic. "Rust" is a proper noun — but here it's the *subject* of the entire note, evident from the title and location. If Rust appears as a property, it would be `language: Rust` or similar. Don't tag it `rust` — that's the detail, not the dimension.

---

## Example 3 — RPG session log

**Scenario:** Notes from Session 12 of an Ironclaw campaign, covering combat encounters, NPC interactions, and plot developments.

**Classification:**
- **Tags:** `session-log`, `rpg`
- **Properties:** `campaign: "[[Ironclaw]]"`, `session: 12`, `created: 2026-04-01`
- **Folder:** `RPG/Sessions/`

**Rationale:** `session-log` is the content type. `rpg` is the topic. Campaign name and session number are properties — they're specific identifiers you'd filter/sort by in a dataview table, not search dimensions. Don't tag `ironclaw` — it's a proper noun.

---

## Example 4 — AI prompt template

**Scenario:** A reusable prompt template for generating clarity conversation questions.

**Classification:**
- **Tags:** `prompt`, `ai`
- **Properties:** (none required)
- **Folder:** by vault convention (e.g., `Knowledge/AI/Prompts/`)

**Rationale:** `prompt` is the content type. `ai` is the topic. No lifecycle tracking needed — prompts don't go stale in the way reference docs do. No proper nouns to extract as properties.

---

## Example 5 — Network infrastructure diagram

**Scenario:** A note containing or linking to a VLAN topology diagram for a home network.

**Classification:**
- **Tags:** `reference`, `homelab`, `networking`
- **Properties:** `status: active`
- **Folder:** `Knowledge/Homelab/`

**Rationale:** `networking` is a topic dimension — you'd filter "show me all networking notes." Don't tag individual VLAN IDs or switch models; those are details within the note, not retrieval dimensions.

---

## Example 6 — Proxmox cluster configuration

**Scenario:** Documenting the three-node Proxmox cluster: node inventory, quorum settings, HA config.

**Classification:**
- **Tags:** `reference`, `homelab`, `virtualization`
- **Properties:** `cluster: "[[babylon]]"`, `status: active`
- **Folder:** `Knowledge/Homelab/`

**Rationale:** The cluster name is a proper noun (property, wiki-linked). `virtualization` is the topic, not `proxmox` — Proxmox is a specific product (proper noun). If you have enough Proxmox content to warrant it, `proxmox` could become a topic, but start with the dimension (`virtualization`) and specialize under pressure.

**Edge case — when does a product name become a topic?** When there are 5+ notes about it AND the product name is the retrieval dimension people think in. "Show me all Proxmox notes" is a natural query; "show me all VMware notes" would be too if you had VMware content. The test: would someone type this into a tag search? If yes, it's a topic. If they'd search by host/cluster instead, it's a property.

---

## Example 7 — Quick capture inbox note

**Scenario:** A hastily captured thought: "Look into Tailscale for remote access to homelab."

**Classification:**
- **Tags:** (none yet)
- **Properties:** (none yet)
- **Folder:** `Inbox/`

**Rationale:** Inbox notes get metadata at triage, not at capture. The framework's defer mechanism exists precisely for this: stamp `metadata_review: pending` and move on. Forcing metadata at capture time creates decision fatigue — the anti-pattern this framework is designed to prevent.

---

## Example 8 — Completed learning plan (archived)

**Scenario:** A Python learning plan marked complete, moved to archive.

**Classification:**
- **Tags:** `learning`, `programming`
- **Properties:** `status: completed`, `created: 2025-06-01`, `updated: 2026-01-15`
- **Folder:** `Archive/`

**Rationale:** Folder changed (moved to Archive), but tags and properties persist. The `status: completed` property is how lifecycle tracking knows this note is done. `learning` content type with `lifecycle.applicable: true` would flag an active learning plan untouched for 60 days — but `completed` status has no staleness threshold, so this note rests peacefully.

---

## Example 9 — RPG character reference

**Scenario:** Detailed notes about an NPC: backstory, motivations, relationships, stat block.

**Classification:**
- **Tags:** `rpg-reference`, `rpg`
- **Properties:** `campaign: "[[Ironclaw]]"`, `character: "Katho Thornhill"`
- **Folder:** `RPG/Characters/`

**Rationale:** Character name is a proper noun (property). The NPC's name wouldn't be a tag — you'd never filter "show me all Katho notes" across the vault. Campaign is a relationship property (wiki-linked). `rpg-reference` is the content type if the vault distinguishes it from generic `reference`.

---

## Example 10 — Docker Compose stack reference

**Scenario:** Documentation for a Dockge-managed compose stack: services, environment variables, volumes, networking.

**Classification:**
- **Tags:** `reference`, `homelab`, `docker`
- **Properties:** `host: "[[epsilon3]]"`, `service: "[[dockge]]"`, `status: active`
- **Folder:** `Knowledge/Homelab/`

**Rationale:** Nearly identical to Example 1. `docker` is a topic — it's the technology dimension. Stack name (`dockge`) is a proper noun property. If you had 8+ service reference notes with identical structure (host, service, status, port, url), that's the signal to specialize the content type (see Example 18).

---

## Example 11 — Certificate renewal procedure

**Scenario:** Step-by-step procedure for renewing a wildcard TLS certificate, including where the cert lives and what services consume it.

**Classification:**
- **Tags:** `reference`, `homelab`, `security`
- **Properties:** `status: active`, `certificates: "[[sectigo-wildcard]]"`
- **Folder:** `Knowledge/Homelab/`

**Rationale:** `security` is the topic dimension. The specific certificate is a proper noun property (wiki-linked so backlinks reveal all notes that reference it). Don't tag `tls` or `ssl` — `security` covers the retrieval dimension; `tls` is a detail within that dimension.

---

## Example 12 — Tag vs property: "docker"

**Scenario:** Should `docker` be a tag or a property?

**Classification:** **Tag** (topic).

**Rationale:** `docker` is categorical — many notes are "about docker" as a technology dimension. You'd filter a pane by it. It's not a proper noun in the property sense because it's not a specific instance (unlike `epsilon3` which is *one specific host*). Docker is a technology you think in, not an entity you'd wiki-link.

**Contrast:** `docker-compose` would be an **alias** for `docker`, not a separate tag. Declare it: `aliases: [docker-compose, compose]`.

---

## Example 13 — Tag vs property: "epsilon3"

**Scenario:** Should `epsilon3` (a specific Proxmox host) be a tag or a property?

**Classification:** **Property** (`host: "[[epsilon3]]"`).

**Rationale:** It's a proper noun — one specific entity. You'd display it as a column in a dataview table ("which host runs this?"). You'd want backlinks from the epsilon3 note to show all services running on it. Tags are for dimensions you filter by; properties are for specific instances you relate to.

---

## Example 14 — Folder vs tag: when both is correct

**Scenario:** A session log note. The vault has a `Session Logs/` folder. Should it also have a `session-log` tag?

**Classification:** **Both** (content type redundancy).

**Rationale:** The framework explicitly supports belt-and-suspenders. The folder tells you at a glance where session logs live; the tag enables dataview queries that span folders. If you later reorganize folders (split by campaign), the tag still works. If you later clean up tags, the folder still works.

---

## Example 15 — Rejecting a hierarchical tag

**Scenario:** Someone proposes `#homelab/docker/authentik` to tag a note about the Authentik Docker deployment.

**Classification:** **Reject.** Use flat tags + properties instead.

**Correct approach:**
- Tags: `homelab`, `docker`
- Properties: `service: "[[authentik]]"`

**Rationale:** Hierarchical tags invite synonym sprawl (`#homelab/docker/authentik` vs `#homelab/sso/authentik` vs `#auth/authentik`). The hierarchy this implies is better captured by folder structure (physical hierarchy) and dataview queries (composed hierarchy). Flat tags + properties achieve the same retrieval power without the ambiguity.

---

## Example 16 — Alias normalization in action

**Scenario:** A note uses the tag `#containers`. The vault's canonical topic is `docker` with aliases `[containers, docker-compose, compose]`.

**Classification:** Auto-normalize `#containers` to `#docker`.

**Rationale:** This is a declared alias — the mapping is explicit in `vault-metadata.yaml`. The normalize script silently replaces it and writes an audit log entry. No confirmation needed; the alias declaration is the pre-approval.

**Contrast:** If a note used `#containerization` (not a declared alias), fuzzy matching would flag it as a *candidate* synonym for `docker` — but never auto-normalize. The user must confirm.

---

## Example 17 — Staleness: opted-in vs opted-out

**Scenario:** Two notes untouched for 120 days: a `reference` note with `status: active`, and an `rpg-reference` note about a campaign setting.

**Classification:**
- Reference note: **flagged stale** (lifecycle applicable, active > 90d threshold)
- RPG reference note: **not flagged** (lifecycle not applicable for this content type)

**Rationale:** Staleness is declared per content type. RPG lore doesn't go stale — the Ironclaw setting from 2024 is as valid in 2026. Reference docs about running services *do* go stale — configs drift, versions update, hosts change. The framework respects this distinction rather than applying a one-size-fits-all timer.

---

## Example 18 — Content type specialization (CRITICAL EXAMPLE)

**Scenario:** The vault has a generic `reference` content type. Over time, 10 service operational reference notes accumulate, all sharing the same frontmatter pattern: `host`, `service`, `status`, `port`, `url`, `dependencies`.

**Judgment process:**

1. **Recognition:** During `/audit-metadata` or session-end review, Claude notices that 10 notes in `Knowledge/Homelab/` share `host + service + status` properties that aren't in the `reference` content type's `properties.required`.

2. **Evaluation:** Is this a stable pattern or coincidence?
   - 10 notes (above the default 8 promotion threshold)
   - The shared properties are structural, not incidental
   - "Show me all service references" is a natural retrieval query distinct from "show me all references"

3. **Proposal:** Split `reference` into `reference` (general) and `service-reference` (specialized):

   ```yaml
   - id: service-reference
     description: Operational reference for a running service
     folder: Knowledge/Homelab/Services/
     also_tag: true
     properties:
       required: [host, service, status]
       optional: [port, url, version, dependencies, certificates, container]
     lifecycle:
       applicable: true
       property: status
       values: [active, archived]
       staleness: { active: 90d }
   ```

4. **Outcome:** Existing `reference`-tagged service notes get re-tagged `service-reference`. Their frontmatter already has the properties; the content type just formalizes what emerged organically.

**Key principle:** Content types specialize under pressure from observed data, not from upfront design. Start broad, split when the pattern proves stable.

---

## Example 19 — Property-to-folder promotion

**Scenario:** The property `campaign` appears on 12 RPG notes, all with value `"[[Ironclaw]]"`. Currently they all live in a flat `RPG/` folder.

**Evaluation:**
1. Count (12) exceeds `promotion_threshold` (8) -- yes
2. Folder name "Ironclaw" is stable (campaign won't be renamed) -- yes
3. Navigate to it visually at least weekly (active campaign) -- yes

**Classification:** Promote to `RPG/Ironclaw/` subfolder. The `campaign` property remains (belt-and-suspenders). Notes for other campaigns stay in `RPG/` or get their own folders when they cross the threshold.

---

## Example 20 — When NOT to tag: over-tagging trap

**Scenario:** A note about configuring Traefik reverse proxy for Proxmox. Candidate tags: `reference`, `homelab`, `networking`, `docker`, `security`, `tls`, `reverse-proxy`, `traefik`, `proxmox`.

**Correct tags:** `reference`, `homelab`, `networking`, `docker`

**Rejected:**
- `security`, `tls` — too specific; subsumed by `networking` for retrieval purposes
- `reverse-proxy` — too specific; subsumed by `networking` and `docker`
- `traefik`, `proxmox` — proper nouns; belong as properties if structured data is needed, or simply mentioned in the note body
- `security` — only if the note is *primarily about* security (e.g., TLS hardening guide). If security is incidental to the networking config, it's not a retrieval dimension for this note.

**Principle:** Each tag should represent a dimension someone would independently search by. If two candidate tags would always co-occur on the same notes, keep only the broader one.

---

## Example 21 — Deferred metadata at capture

**Scenario:** Mid-session, Claude creates a new note while working on a homelab task. The user wants to keep moving, not classify right now.

**Flow:**
1. Claude creates the note in `Inbox/`
2. Claude proposes tags — user says "defer"
3. Claude runs `metadata-defer.ps1`, stamps `metadata_review: pending` with reason "created during homelab session, classify later"
4. At session-end, the note appears in the pending queue
5. User can classify then, or defer again

**Rationale:** The framework optimizes for capture velocity. Forcing classification at creation time is where most tag systems fail — decision fatigue at the worst moment. Defer is a first-class operation, not a failure mode.

---

## Example 22 — Retired tag detection

**Scenario:** The tag `training` exists in the canonical list but appears on zero current notes. All former `training` notes were either re-tagged `learning` or archived.

**Classification:** Retirement candidate (flagged in `/audit-metadata` section 7).

**Rationale:** Retirement is based on 0-usage count, not elapsed time. A tag with even one active note is not a retirement candidate. Once flagged, the user confirms retirement — the tag moves to the `deprecated` section. If a new note later needs `training`, the deprecated list catches it and suggests `learning` instead.

---

## Example 23 — Wiki-link vs property: when to link

**Scenario:** A note mentions "epsilon3" in the body text. Should it be a wiki-link?

**Classification:** Yes, **if epsilon3 has its own note** (or should have one).

**Rationale:** Wiki-links create bidirectional discovery via backlinks. If `epsilon3` is a host with its own reference note, linking `[[epsilon3]]` from any note that mentions it means the epsilon3 note's backlinks panel becomes a "what runs on this host" dashboard for free. Properties (`host: "[[epsilon3]]"`) formalize this for structured queries; body links add it for narrative mentions.

---

## Example 24 — Vault-agnostic vs vault-specific

**Scenario:** Which parts of this classification system are the same across all vaults, and which vary?

**Invariant (same everywhere):**
- Boundary rules (tag/property/folder/link)
- Tag format rules (lowercase, kebab-case, etc.)
- Capture/defer/audit flow
- Validation layers
- Audit log format and location

**Per-vault (varies):**
- Which content types exist and their lifecycle settings
- Which topics are canonical and their aliases
- Which properties are recognized
- Promotion threshold
- Audit log retention period
- Specific folder structure beyond the standard set
