# Vault Guide — {{WORKSPACE_NAME}}

## Overview

This is an Obsidian vault workspace managed with git. Content is organized in markdown files with wiki-style linking.

## Vault Structure

| Path | Purpose |
|------|---------|
| `📥 Inbox/` | Quick captures and unsorted notes |
| `📦 Archive/` | Completed or retired content |
| `🫥 Attachments/` | Images, PDFs, media files |
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

## Git Workflow

- **Branch:** Single `main` branch — commit directly, no PRs needed
- **Commit format:** UPPERCASE Conventional Commits (see `.gitmessage`)
- **Commit types:** CONTENT, DOCS, FIX, REFACTOR, CHORE, META, STYLE

## Obsidian Configuration

- `.obsidian/` contains committed vault settings (app, appearance, plugins, templates)
- Device-specific files (workspace, hotkeys, plugin data) are gitignored
- **Templater** is the only pre-configured community plugin — templates folder is `🫥 Templater/`

## AI Editing Guidelines

When editing vault content:
- Preserve existing wiki-style links
- Maintain frontmatter tags if present
- Don't add files to `.obsidian/` without explicit request
- Place new notes in `📥 Inbox/` unless a specific location is indicated
- Use the vault's Decision Rules for organization guidance
