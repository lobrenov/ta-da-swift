# Ta Da — Data structure v3

## Context
The vault layout as `docs/file-format.md` describes it, with two changes: the Logbook folder is `Ta Da/logbook/`, and the old layout (top-level `tasks/`, `projects/`, `areas/`, `attachments/`, hidden `.logbook/`) is no longer read or moved. The apps and the Obsidian plugin change together.

## Decisions
- New logged files go in `Ta Da/logbook/<yyyy-MM>/`. Reading stays case-insensitive.
- The old layout goes: `MoveIntoHome`, its alert and its Settings ▸ Vault part, `.logbook/`, and the old folders in `Item.reservedFolders`. Top-level `tasks/`, `projects/`, `areas/` and `attachments/` are ordinary folders; a typed file in one still reads by its `type:`.
- DesignVault's folders move into `Ta Da/`; file contents don't change.
- Existing vaults are moved by hand, once: `Ta Da/Logbook` → `Ta Da/logbook` in two steps (case-only renames need a temporary name on macOS and iCloud Drive).

## Steps
1. TaDaCore and the app: the folder name, the removals, DesignVault, tests, and `docs/file-format.md`, `docs/architecture.md`, `CLAUDE.md`. Check: core and app tests pass; design renders unchanged but for paths.
2. Conformance export again; the plugin's core port follows (`item.ts`, `vault.ts`, the unlog and logbook paths). Check: plugin tests pass.
3. SampleVault: `git mv` the Logbook in two steps. The iCloud vault: the same move with the apps closed, then checked on iPhone before either app logs.
