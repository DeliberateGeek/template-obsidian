# Vault Guide — {{WORKSPACE_NAME}}

## Overview

This is an Obsidian vault workspace managed with git. Content is organized in markdown files with wiki-style linking.

## Vault Structure

| Path | Purpose |
|------|---------|
| `📥 Inbox/` | Quick captures and unsorted notes |
| `📦 Archive/` | Completed or retired content |
| `🫥 Attachments/` | Images, PDFs, media files |
| `🫥 Meta/` | Metadata framework: canonical list, audit logs |
| `🫥 Templater/` | Templater community plugin templates (uses `tp.` syntax) |
| `🫥 Templates/` | Obsidian core templates (simple variable substitution) |
| `Home.md` | Vault home page and navigation hub |
| `Decision Rules.md` | Vault-specific conventions |

## Conventions

### Links

- **Internal links:** Always use wiki-style: `[[Note Name]]`, `[[#Section]]`, `[[Note#Section]]`
- **Never** use markdown anchor links (`[text](#anchor)`) — they don't work in Obsidian reading view
- **External links:** Standard markdown: `[Display Text](https://url.com)`
- **Full reference:** `~/.claude/obsidian-conventions.md`

### Folder Naming

- Content folders use descriptive names with optional emoji prefixes for categorization
- Metadata/auxiliary folders use the 🫥 emoji prefix (sorts to bottom, signals "infrastructure")
- The `.claude/` folder is invisible to Obsidian (dot-prefix exclusion)

### File Naming

- Use descriptive names with spaces (Obsidian handles spaces natively)
- No special prefix conventions required unless defined in Decision Rules

## Metadata Framework

This vault uses a structured metadata framework for tagging, properties, and classification. The one-sentence philosophy:

> *Tag by dimension, not by detail. Proper nouns are properties, not tags — and staleness is declared, not inferred.*

### Key references

- **Philosophy & boundary rules:** `.claude/Claude Context/metadata-philosophy.md`
- **Worked examples:** `.claude/Claude Context/metadata-examples.md`
- **Structural schema:** `.claude/Claude Context/metadata-schema.yaml`

### Canonical list

The vault's metadata configuration lives at `🫥 Meta/vault-metadata.yaml` — content types, topics (with aliases), properties vocabulary, and lifecycle settings. This is the single source of truth for what tags, properties, and content types are recognized.

A rendered view is available at `🫥 Meta/Canonical Metadata.md` (auto-generated with dataview queries).

### Audit logs

Metadata changes made by Claude are logged to `🫥 Meta/Audit Logs/YYYY-MM-DD.md` (daily rotation, git-tracked). User edits are captured by git itself. Audit logs are retained for 90 days by default (vault-tunable).

### Boundary rules (quick reference)

| Use a... | When... |
|----------|---------|
| **Tag** | Category/dimension with many members; you'd filter a pane by it |
| **Property** | Proper noun, date, number, or single-valued field; you'd display it as a column |
| **Folder** | Stable top-level container; exactly one right answer per note |
| **Wiki-link** | Referenced thing deserves its own note; you want backlinks |

### Tag format rules

- Lowercase only (auto-fixed at capture/audit)
- Kebab-case for multi-word (auto-fixed at capture/audit)
- Must start with a letter (rejected, requires human decision)
- Minimum 2 characters (rejected, requires human decision)

## Git Workflow

- **Branch:** Single `main` branch — commit directly, no PRs needed
- **Commit format:** UPPERCASE Conventional Commits (see `.gitmessage`)
- **Commit types:** CONTENT, DOCS, FIX, REFACTOR, CHORE, META, STYLE

## Obsidian Configuration

- `.obsidian/` contains committed vault settings (app, appearance, plugins, templates)
- Device-specific files (workspace, hotkeys) are gitignored
- Plugin files (including `data.json`) are tracked in git for cross-device sync — disable auto-updates in Obsidian to prevent version drift
- **Templater** is the only pre-configured community plugin — templates folder is `🫥 Templater/`

## AI Editing Guidelines

When editing vault content:
- Preserve existing wiki-style links
- Maintain frontmatter tags if present
- Don't add files to `.obsidian/` without explicit request
- Place new notes in `📥 Inbox/` unless a specific location is indicated
- Use the vault's Decision Rules for organization guidance
- Follow the metadata framework boundary rules when classifying notes
