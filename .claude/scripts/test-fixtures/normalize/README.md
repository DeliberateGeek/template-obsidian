# Invoke-MetadataNormalize test fixtures

Scenario fixtures for `Invoke-MetadataNormalize.ps1` covering the behaviour
contract set by `DeliberateGeek/template-obsidian#21` and the canonical
`inline-array-shape` rule from `metadata-schema.yaml`.

## Running

```powershell
pwsh.exe -File .claude/scripts/Test-InvokeMetadataNormalize.ps1
```

The harness copies each `inputs/*.md` to a scratch `.obsidian/`-marked vault,
invokes the script, and diffs the result against `expected/<name>.md`. Exit 0
means every scenario passed; non-zero prints per-scenario diffs and fails.

## Scenarios

| Input | Expected outcome |
|---|---|
| `inline-alias.md` | simple alias → canonical substitution, inline output |
| `inline-collision.md` | canonical already present; alias deduped |
| `block-collision.md` | block shape + collision; shape flips to inline, deduped |
| `to18-regression.md` | `${1}/${2}` leakage scenario; clean substitution |
| `canonical-only.md` | no alias in tags; file untouched |
| `no-tags-key.md` | note without `tags:` key; file untouched |
| `block-no-drift.md` | block shape + no alias; file untouched (shape preserved per option (i) scope) |
