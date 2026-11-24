# Ta Da — Ta Da folder v1

## Context
Onboarding offers only Choose Folder…. This plan adds a second choice, a Ta Da folder in iCloud Drive that the app makes and opens, as Obsidian's folder sits at iCloud Drive's top level. It covers the Mac and iPhone.

The folder is the app's own iCloud container, which needs the iCloud capability and so the paid Apple Developer Program (auto-update v1, Part 3).

## Decisions
- **Container**: `iCloud.com.lobrenov.TaDa`, public to iCloud Drive (`NSUbiquitousContainers`: `NSUbiquitousContainerIsDocumentScopePublic` YES, `NSUbiquitousContainerName` "Ta Da", `NSUbiquitousContainerSupportedFolderLevels` Any) in both Info.plists, with the iCloud Documents entitlement on the app (production environment for Developer ID builds). The folder Ta Da opens is the container's `Documents`, which iCloud Drive and Finder show as "Ta Da" with the app's icon.
- **Layout**: the container's `Documents` is the chosen folder, as any other, so Ta Da's own files are in iCloud Drive ▸ Ta Da ▸ Ta Da ▸ tasks (and projects, areas, attachments, logbook). No change to `docs/file-format.md`.
- **Onboarding** (`FolderPickerView`):
  - The text says what each choice is for: the Ta Da folder to keep tasks on their own, or a folder you choose (an Obsidian vault, say) to keep them beside your notes.
  - **Use the Ta Da Folder** (prominent, default) and **Choose Folder…** (bordered) below it.
  - With iCloud off or no account (`FileManager.ubiquityIdentityToken` nil), Use the Ta Da Folder is off, with "Sign in to iCloud to use the Ta Da folder." under it.
  - The same view shows when the saved folder is gone, so both choices are there too.
- **Opening it**: `AppModel.useTaDaFolder()` gets the container with `url(forUbiquityContainerIdentifier:)` off the main actor, makes `Documents` if it's missing, and opens it through `choose(_:)`, so it's remembered and listed with the other folders. An existing Ta Da folder (another device, a reinstall) opens as it is. A new one opens empty, as a new folder does today.
- **Elsewhere**: Settings' folder list and the folder line treat it as any other folder; its name shows as "Ta Da".
- **Version**: the next `y` version (tag `feature`).
- **Not in v1**: starter tasks in a new folder; moving files between the Ta Da folder and another; Settings' own Use the Ta Da Folder (Choose Folder… can pick it in iCloud Drive).

## Steps
1. **Design** (me). Onboarding with both choices, and the iCloud-off state, on the Mac and iPhone, on a new canvas page. Check: you approve the boards.
2. **Capability** (me). The container in the developer account, the entitlement and `NSUbiquitousContainers` (the Info.plists' build number bumped, so iCloud Drive picks up the folder's name). Check: the app builds and runs for Mac and iPhone; `codesign -d --entitlements -` shows the container; `url(forUbiquityContainerIdentifier:)` returns a URL on the device.
3. **Onboarding** (me). `useTaDaFolder()`, the two buttons, the iCloud-off state. Check: `TaDaTests` for `useTaDaFolder` with an injected container URL (makes `Documents`, opens it, remembers it; an existing folder's files are read; no container is the iCloud-off state); on the iPhone and the Mac, a first run with Use the Ta Da Folder, then a new task appears in iCloud Drive ▸ Ta Da ▸ Ta Da ▸ tasks on the other device.
4. **Docs and release** (me). The design framework (onboarding in As built and In the app), `docs/architecture.md`, `docs/releases.md` (the container and its profile), the canvas's reference pages updated from the feature page and that page deleted; release notes. Check: `xcodebuild … test -skip-testing:TaDaUITests` passes; the release's Mac app shows the folder in Finder's iCloud Drive.

No subagents: the steps are short and each needs the one before.

## Risks
- On a second device the folder's files arrive from iCloud after it opens; the folder watcher picks them up as they download, as with any iCloud folder.
- The folder's name and icon show in iCloud Drive only after a build with a new `CFBundleVersion`.
- Obsidian on iPhone opens vaults only in its own folder, so the Ta Da folder suits people who use Ta Da on its own; the onboarding text says so.
