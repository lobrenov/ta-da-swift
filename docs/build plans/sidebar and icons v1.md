# Ta Da — Sidebar and icons v1

## Context
Two changes to the sidebar and the files it lists, on Mac and iPhone.
- Sidebar navigation: the Tags and Notes trees start collapsed, iPhone's trees fold with an expand and collapse in place of a fade, and the Mac's fold chevrons get space before the row's icon.
- Icons: an area, project or folder can be given its own icon, an emoji or an image in the folder, drawn everywhere the cube, the progress pie or the folder is drawn now.

## Decisions
- Fold state is stored as `expandedTags` and `expandedFolders` (UserDefaults, new keys) in place of `foldedTags` and `foldedFolders`. Empty means all collapsed. The old keys aren't read, so every device starts collapsed once.
- iPhone tree rows are identified by their folder or tag path, not their position, and insert and remove with a move and fade inside the card.
- An area's or project's icon is the frontmatter key `icon` (Iconize's field name): an emoji as written (`icon: "🏡"`) or an image as an embed (`icon: "[[home.png]]"`), which resolves as embeds do. Ta Da writes it by splicing; an empty or missing key, or an image that doesn't resolve, draws the default icon.
- A folder's icon is in `Ta Da/settings.json`, as `folderIcons`: folder path to the same value. Renaming, moving, trashing and restoring a folder updates its entry and its subfolders'.
- A project's icon replaces its progress pie, Ongoing included. The open-task count stays in the sidebar; progress stays on the project page.
- `ItemIcon` draws an area's, project's or folder's icon, else its default (`AreaIcon`, `ProgressRing`, `folder`), at each current size. It replaces them at every call site. Images are decoded at the drawn size and cached by path and modification date.
- The icon picker is a popover: Emoji (the system picker), Image… (the folder's images, as the link menu lists them) and Remove. It opens from the file menu, the folder menu and the icon by a page's title, on Mac and iPhone.
- The design framework's "No emoji anywhere" becomes emoji only as an icon chosen for an area, project or folder.
- The Obsidian plugin reads and keeps `icon` and `folderIcons`; it doesn't draw them.
- Versions: step 1 is 0.34.7; steps 3–7 ship together as 0.35.
- Not in v1: icons on notes, tasks or tags; icon colours (Iconize's `iconColor`); reading Iconize's or Iconic's own icons; iPad.

## Steps
1. Sidebar navigation: the new fold keys in `AppModel`, row identity and transition in `PhoneNotes` and `PhoneTags`, the chevron column in `SidebarView`'s tag and folder rows; the SidebarItem guideline. Check: TaDaTests cover the collapsed default and toggling; the folds expand and collapse on Mac and in the iPhone simulator.
2. Design: a feature page on the canvas with emoji and image icons in the sidebar, page titles, chips, menus and iPhone rows, a project with an icon in place of its pie, and the picker. Check: the user signs it off.
3. TaDaCore: `icon` on areas and projects (parse, set, clear), `folderIcons` in the folder settings, and its updates on folder rename, move, trash and restore; `docs/file-format.md`, then the conformance export. Check: core tests, written first, pass.
4. `ItemIcon` and the image cache, in the sidebar and page titles. Check: app tests and design renders pass; an emoji, an image and a missing image draw on Mac and iPhone.
5. `ItemIcon` in chips, pickers and the link menu. Check: design renders.
6. `ItemIcon` in search, trash, the logbook, the quick switcher, quick entry, the convert sheet and the iPhone rows. Check: no `AreaIcon(` or `ProgressRing(` call left outside `ItemIcon`; design renders.
7. The picker on Mac and iPhone. Check: setting, changing and removing an icon writes only the `icon` line, or only the `folderIcons` entry; `git diff SampleVault`.
8. Obsidian plugin: the core port reads and keeps `icon` and `folderIcons`. Check: plugin tests against the new fixtures, `npm run build`.
9. Docs and canvas: the design framework (Iconography, In the app), `docs/architecture.md`, the reference pages updated from the feature page and the feature page deleted. Check: app, core and UI tests (with permission), and a pass on SampleVault on Mac and iPhone.
