# CLAUDE.md — {{WORKSPACE_NAME}}

{{WORKSPACE_DESCRIPTION}}

## Documentation

Vault conventions and AI guidance live in `.claude/Claude Context/` — Obsidian ignores dot-prefixed folders, keeping these invisible in the vault.

- **`.claude/Claude Context/vault-guide.md`** — Vault overview, folder structure, linking conventions
- **`.claude/Claude Context/commit-message-guidelines.md`** — Content commit types and format
- **`.claude/Claude Context/metadata-philosophy.md`** — Metadata framework: tagging philosophy, boundary rules, validation layers
- **`.claude/Claude Context/metadata-examples.md`** — 24 worked classification examples
- **`.claude/Claude Context/metadata-schema.yaml`** — Structural schema for `vault-metadata.yaml`

## Quick Reference

- **Vault type:** Obsidian
- **Commit format:** UPPERCASE Conventional Commits (see `commit-message-guidelines.md`)
- **Branching:** Single `main` branch (no gitflow)
- **Link style:** Wiki-style links only (`[[Note]]`, `[[#Section]]`)
- **Metadata:** Tag by dimension, not by detail — see `metadata-philosophy.md`; canonical list at `🫥 Meta/vault-metadata.yaml`

## Obsidian Conventions

When working in this vault, follow the shared Obsidian conventions:
- **Reference:** `~/.claude/obsidian-conventions.md`
- **Detection:** Presence of `.obsidian/` folder confirms this is an Obsidian vault
- **Key rules:**
  - MUST use wiki-style links `[[#Section]]` for internal navigation, NEVER markdown anchor links `[Text](#anchor)`
  - Use 🫥 emoji prefix for metadata/auxiliary folders
  - Follow Obsidian-specific linking conventions in the reference file

## Folder Structure

| Folder | Purpose |
|--------|---------|
| `📥 Inbox/` | Quick captures, unsorted notes |
| `📦 Archive/` | Completed or retired content |
| `🫥 Attachments/` | Images, PDFs, media files |
| `🫥 Meta/` | Metadata framework: canonical list, audit logs |
| `🫥 Templater/` | Templater community plugin templates (uses `tp.` syntax) |
| `🫥 Templates/` | Obsidian core templates (simple variable substitution) |
