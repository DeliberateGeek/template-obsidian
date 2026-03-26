# Commit Message Guidelines — Content Workspace

## Format

```
TYPE(scope): description

[optional body]

[optional footer(s)]
```

## Approved Types

| Type | When to use |
|------|------------|
| **CONTENT** | New or updated vault content (notes, pages) |
| **DOCS** | Changes to documentation or guides |
| **FIX** | Corrections to existing content (typos, broken links, factual errors) |
| **REFACTOR** | Reorganization without changing meaning (moving notes, renaming, restructuring) |
| **CHORE** | Maintenance tasks (template updates, folder organization, vault config) |
| **META** | Changes to vault infrastructure (`.obsidian/`, `.claude/`, `.gitignore`) |
| **STYLE** | Formatting changes only (whitespace, markdown structure, no content change) |

## Scope

Optional — indicates the area of vault affected:

- `(inbox)` — Inbox notes
- `(templates)` — Templater templates
- `(archive)` — Archived content
- `(config)` — Vault configuration
- Or any domain-specific scope relevant to this vault

## Examples

```
CONTENT: Add meeting notes from 2026-03-26 standup
CONTENT(recipes): Add sourdough bread recipe
FIX: Correct broken wiki-links in Home.md
REFACTOR: Move completed project notes to Archive
CHORE(templates): Update Quick Capture template with date field
META: Add Dataview plugin to community-plugins.json
STYLE: Normalize heading levels across inbox notes
```

## AI Attribution

See `.gitmessage` for full attribution rules. Summary:
- AI wrote message AND content → include both `🤖 Generated with` and `Co-Authored-By`
- AI wrote message only → include `🤖 Generated with` only
- AI wrote content only → include `Co-Authored-By` only
