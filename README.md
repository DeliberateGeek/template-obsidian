# {{WORKSPACE_NAME}}

{{WORKSPACE_DESCRIPTION}}

## Getting Started

1. Open this folder as an Obsidian vault: **Open folder as vault** in Obsidian
2. Enable community plugins when prompted (Templater is pre-configured)
3. Start capturing notes in `📥 Inbox/`

## Vault Structure

```
{{WORKSPACE_NAME}}/
├── 📥 Inbox/          # Quick captures, unsorted notes
├── 📦 Archive/        # Completed or retired content
├── 🫥 Attachments/    # Images, PDFs, media files
├── 🫥 Meta/           # Metadata framework: canonical list, audit logs
├── 🫥 Templates/      # Templater templates
├── Home.md            # Vault home page
├── Decision Rules.md  # Vault-specific conventions
└── .gitmessage        # Commit message template
```

## Conventions

- See `.claude/Claude Context/vault-guide.md` for vault conventions
- See `.claude/Claude Context/commit-message-guidelines.md` for commit format
- See `.claude/Claude Context/metadata-philosophy.md` for the metadata framework (tagging, properties, classification)
- See `.claude/Claude Context/framework-scripts-reference.md` for framework-script prerequisites (e.g., `powershell-yaml` module) and exit-code conventions
- Canonical metadata list: `🫥 Meta/vault-metadata.yaml`
- Wiki-style links only: `[[Note Name]]`, `[[#Section]]`

## License

<!-- TODO: Add license information -->
