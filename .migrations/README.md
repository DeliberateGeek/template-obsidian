# .migrations/

Machine-readable per-hop migration files consumed by the `/update-metadata-framework` Skill.

- **One file per adjacent-version hop.** Filename: `<from-version>-to-<to-version>.yaml`. Example: `1.0.0-to-1.1.0.yaml`.
- **No skip-version files.** The Skill walks hops sequentially; every pair of adjacent released versions must have its own file.
- **Schema is defined in `../MIGRATIONS.md`.** See that file for required fields, operations, framework-owned roots, and the release history.
- **Dot-prefixed on purpose.** Obsidian hides dot-prefixed folders. This directory is a `template-obsidian` repo concern — it is not installed into onboarded vaults and should not appear in an Obsidian file explorer.
- **`v1.0.0` has no hop file.** The bootstrap is not a migration; vaults at `1.0.0` start here.

The Skill reads every file matching `<semver>-to-<semver>.yaml` along the chain between the vault's recorded `.template-version` and the target tag. Any other files in this directory (like this README) are ignored.
