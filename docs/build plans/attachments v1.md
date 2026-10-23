# Ta Da — Attachments plan

## Context
A place to see the images Ta Da saved and clear out the ones nothing open uses. Design source: the canvas's **Attachments** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V (`AttachmentsMac`, `AttachmentsMacPicked`, `AttachmentsMacCleanUp`, `AttachmentsIosOther`, `AttachmentsIos`, `AttachmentsIosPicked`, `AttachmentsIosFile`, `AttachmentsIosCleanUp`).

Starting point, as checked on 2026-10-23 (Build 31):
- `Vault.attachmentPaths()` lists every image in the folder, iCloud placeholders included, newest first. `VaultIndex.embedders(ofAttachment:among:)` gives the items that embed an image; the index holds live and logged files (`Item.isLogged`), and `AppModel.trash` holds the trashed ones.
- Images are renamed and deleted one at a time from the editor: `RenameImageDialog` and `DeleteImageDialog` in `TaDa/Editor/ImageDialogs.swift`, through `AppModel.renameAttachment` and `AppModel.trashAttachment`, which calls `Vault.moveAttachmentsToTrash`.
- The Mac sidebar has Logbook then Trash (`AppModel.Domain`); View has Agenda ⌘1, Loose ⌘2, Trash ⌘3, Logbook ⌘4 (`TaDa/Commands.swift`). iPhone's Other lists Logbook and Trash (`PhoneOtherScreen`).

## Decisions
- **Scope**: the images directly in `Ta Da/attachments/`, iCloud placeholders included. Images elsewhere, and the old layout's `attachments/`, aren't listed.
- **In use**: an image is in use when a live file embeds it: a task, project, area or note outside the Logbook and `.trash/`. An embed counts when it resolves to that image (`Vault.attachmentPath(for:in:)` over every image path), so a same-named image elsewhere that wins resolution doesn't make it in use.
- **Clean-up candidates**: every image not in use, with its reason: only logged files embed it, only trashed files, both, or nothing.
- **Files waiting to download**: while markdown files are still to download from iCloud Drive (`AttachmentGroups.pendingFiles`), Clean Up says so and starts every image unticked (UI in A2/A3).
- **List**: two groups, "Not in open files" (with count and total size) then "In open files", each sorted by name (Finder order: numeric, ignoring case). A row is the thumbnail, the filename, where it's embedded ("In Photograph the Kombi and 1 logged file", "In the Logbook: Replace the tyres", "In Trash: …", "Not embedded anywhere · added Fri 2 Oct") and its size.
- **iCloud**: an image iCloud Drive hasn't downloaded shows a cloud badge and a faded thumbnail; its size comes from the placeholder. Opening it asks iCloud Drive to download it (Download on the Mac's preview).
- **Count**: the sidebar row and Other's row show the folder's total size (`ByteCountFormatter`, `.file`), not a file count.
- **One image** (Mac detail pane, iPhone screen): preview, type, size, dimensions, date added, the files that embed it (open, logged with its month, or in Trash; each opens the file), and Show in Finder (Mac), Share (iPhone), Rename… and Move to Trash, using the existing dialogs.
- **Several images**: ⌘-click, ⇧-click and ⌘A pick on the Mac; "…" ▸ Select and swipe-select on iPhone. The detail pane shows the picked images stacked with their count and size, Show in Finder and Move N to Trash; ⌫ does the same. Moving asks first when a live file embeds any of them, as `DeleteImageDialog` does, listing them.
- **Clean Up…** (header button on the Mac, toolbar on iPhone; disabled with no candidates): a dialog (sheet on iPhone) listing the candidates grouped by reason, each with what embeds it, all ticked. Move N to Trash sends the ticked ones to `.trash/attachments/` in one `moveAttachmentsToTrash` call; embeds aren't rewritten, so logged and trashed files show them as missing until they're restored. A note under the list reports what moved.
- **Navigation**: `AppModel.Domain.attachments`, a sidebar row between Logbook and Trash, and View ▸ Attachments with no shortcut. iPhone: a row in Other between Logbook and Trash.
- **Unchanged**: Trash (cleaned-up images list there on their own, as images deleted alone do), the editor's image menu and dialogs, `attachmentPaths()` for the embed menu.

## Milestones
Each ends with its check passing, then a commit and a review.

### A1 — Core
- `Vault.taDaAttachments()`: the images in `Ta Da/attachments/` with size, date added and whether downloaded (placeholder sizes from the `.icloud` plist's `NSURLFileSizeKey`).
- `AttachmentUse` (in use, or the reason it's a candidate, with the embedding items by state) from the index, the trashed items and every image path.
- Tests: grouping and name order; each reason; a same-named image elsewhere; placeholders; total size.
- Check: `swift test --package-path Packages/TaDaCore`.

### A2 — Mac
- `Domain.attachments`, its sidebar row with the size, View ▸ Attachments.
- `AttachmentsBrowser`: header with Clean Up…, the grouped list with multi-pick, the detail pane (one image, or several).
- `CleanUpDialog`; Move to Trash for several, with the embed warning; refresh after each change.
- Check: app builds; `TaDaTests` pass; run against `SampleVault` with images in each state and compare with the canvas boards.

### A3 — iPhone
- Other's Attachments row with the size; `PhoneAttachmentsScreen` (groups, Select, swipe-select, toolbar), `PhoneAttachmentScreen` (one image), the Clean Up sheet; download on open.
- Check: iOS build; run on the simulator against the canvas boards.

### A4 — Docs and canvas
- `docs/file-format.md` (Attachments: the clean-up rule), `docs/architecture.md` (the domain, views and core types), `docs/design/design-framework.md` (In the app).
- Canvas: move the Attachments boards into the macOS and iOS reference pages (and Other's row into its board), then delete the Attachments page.
- `docs/backlog.md`; archive this plan.
