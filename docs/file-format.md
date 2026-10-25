# Ta Da file format

Every task, project, area and note is one markdown file. YAML frontmatter holds the structured data; the body is free markdown. Files must stay readable and editable in Obsidian or any text editor.

## Example

```markdown
---
type: task
status: Doing
project: "[[Ta Da MVP]]"
createdDate: 2026-09-28
completedDate:
dueDate: 2026-10-02
deadline: 2026-10-06
repeat: Weekly · Fri
---
Bring the project instruction files in line with how I actually work now.

## Subtasks

- [x] Audit the global file
- [ ] Add Swift test conventions
```

## Identity

- **Kind** comes from `type: task`, `type: project` or `type: area` (any case). A `.md` file without one of these is a **note**, unless it sits in a hidden folder or under a reserved top-level folder (any case): `Ta Da/`, where it's ignored. A typed file is never a note, wherever it sits. This lets Ta Da share a folder (or an Obsidian vault) with other notes.
- **Title** is the filename without `.md`. Renaming a file renames it.
- **Location** doesn't matter. The whole chosen folder is scanned recursively; hidden folders, `.obsidian` and `.trash` are skipped. Ta Da keeps what it makes in `Ta Da/` at the top level: new tasks, projects and areas in `Ta Da/tasks/`, `Ta Da/projects/` and `Ta Da/areas/`, attachments in `Ta Da/attachments/` and logged files in `Ta Da/logbook/`. New notes go in the folder they're made in.

## Properties

| Key | Applies to | Value | Notes |
|---|---|---|---|
| `type` | tasks, projects, areas | `task` \| `project` \| `area` | Required; a note has none |
| `status` | tasks, projects | `Not Started` \| `Doing` \| `Ongoing` \| `Done` \| `Blocked` \| `Cancelled` | Read case-insensitively; written in this exact form. Missing or unknown values read as `Not Started`, with a warning. `Ongoing` is for projects: an open project without progress (Ta Da offers it only for projects) |
| `project` | tasks | wikilink `"[[Project title]]"` | Optional. The **only** thing that makes a task belong to a project. If the link doesn't resolve, the task has no parent and gets a warning |
| `area` | tasks, projects | wikilink `"[[Area title]]"` | Optional. Files a project, or a task with no project, under an area. Plain text (`area: Personal`) reads as the title. If it doesn't resolve, the file has no parent and gets a warning |
| `createdDate` | all | `YYYY-MM-DD` | Set when Ta Da creates the file |
| `completedDate` | both | `YYYY-MM-DD` | Set when completed or cancelled, cleared when reopened |
| `dueDate` | both | `YYYY-MM-DD` | Optional |
| `deadline` | both | `YYYY-MM-DD` | Optional |
| `repeat` | both | text | Displayed only; no recurrence yet |
| `tags` | all | list of tags | Optional. A flow list, a block list, or one string split on commas. Items may hold spaces; a leading `#` is dropped. See Tags |

- A note reads only `createdDate` and `tags`. It has no status, parent or dates; any other keys stay untouched and unread. A note's frontmatter that isn't valid YAML reads as empty, with a warning.
- An area's frontmatter is `type`, `createdDate` and optional `tags`; its body is free markdown. Areas have no status or dates, and Ta Da doesn't write them.
- `contexts` is no longer read. Like any unknown key, it stays in the file untouched.
- Dates are calendar days in local time, with no times or time zones. They are read as plain strings, never as YAML timestamps.
- Any other keys, plus comments, key order and formatting, are preserved untouched.
- An empty key (`dueDate:`), or an unquoted `~` or `null`, is the same as a missing one.
- Values that can't be read (a bad date, a `project` that isn't a link, a list where text belongs) are treated as missing, with a warning.
- If the frontmatter isn't valid YAML, the file still loads when an unindented `type: task`, `type: project` or `type: area` line is present. Its other properties read as missing and it gets a warning.

## Body

The body's syntax is the spec in the Live editor's package, at the tag Ta Da pins (`Packages/TaDaCore/Package.swift`): [`spec/`](https://github.com/lobrenov/swift-markdown-engine-extended/tree/0.15.0-live.5/spec) in swift-markdown-engine-extended. Its `README.md` says what each construct is (task markers, links, embeds, tags, callouts, tables) and its `edits/` how a change is written. TaDaCore reads it through the package's `MarkdownEngineSyntax` (`MarkdownFacts`). Ta Da's choices:

- **Description**: the whole body. Search also matches its first paragraph (the summary).
- **Subtasks** are the checkboxes (the spec's task markers; `[y]` is text) in these states, anywhere in the body and at any depth, outside code, counted as done/total:

  | Marker | State | Counts as |
  |---|---|---|
  | `[ ]` | Not started | open |
  | `[/]` | Doing | open |
  | `[>]` | Forwarded | open |
  | `[<]` | Scheduling | open |
  | `[x]` `[X]` | Done | done |
  | `[-]` | Cancelled | left out of the total |

  The other markers (`[?] [!] [*] ["] [l] [b] [i] [S] [I] [p] [c] [f] [k] [w] [u] [d]`) are icons only: they render as checkboxes, aren't subtasks and ignore clicks.
- **Links** (`[[Title]]`, `[[Title|alias]]`, `[[Title#heading]]`, `[[Title#^block]]`, `[[folder/Title]]`) resolve to the file with that title, case-insensitively: a task, project or area first, then a note, then a logged file. A block reference is kept as a heading starting with `^`. A link within the file (`[[#heading]]`) links no file. Body links are links only; they never set a parent.
- **Embeds** (a link with a leading `!`, e.g. `![[front.jpg]]` or `![[front.jpg|300]]`, where a number is the width) aren't links, so they aren't backlinks. An embed whose target ends in one of the spec's image extensions (`avif bmp gif heic jpeg jpg png svg tif tiff webp`, any case) shows that attachment.
- **Callouts** (`> [!type]`, folded with `-` or open with `+`) take their type's look; an unknown type looks like a note.
- **Tables**: Ta Da edits one as the spec's edits say: the table's lines only, columns padded, alignment markers and indentation kept, a line break in a cell as `<br>` and a `|` as `\|`.

## Tags

- A file's tags are its `tags:` items and its inline `#tags`, merged; a tag carried twice counts once.
- **Inline tags** are the spec's (`spec/data/tags.json`): `#` where a tag can start (a paragraph's or line's start, emphasis content's start, or after whitespace), then letters, digits, `_`, `-` and `/`, with at least one character that's neither a digit nor `/` (so `#2026/10` isn't a tag). Any other character, a comma or space included, ends the tag. Code, HTML, link text, URLs and `[[…]]` links hold none, so `[[Note#Heading]]` and a heading's `# ` aren't tags.
- **Identity**: tags match ignoring case, and show as first written in the folder. Empty segments and a trailing `/` are dropped (`home/` is `home`).
- **Nesting**: `/` nests, so `home/garden` is a child of `home`. A parent shows its children's files too, and exists whether or not any file carries it alone.
- An area's or project's tags don't apply to its tasks.
- **Counts**: the areas, projects, tasks and notes, completed or not, carrying the tag or a child of it. Files in `.trash/` and logged files aren't counted. **Untagged** is every area, project, task and note with no tag.

## Notes

- **Folders**: notes are browsed by folder. The Notes tree holds the folders with a note at any depth, the folders that hold no files at all (iCloud Drive placeholders count as files), and their parents, leaving out hidden folders, packages and the reserved top-level folders (`Ta Da/`). A folder is named by its last path segment, sorted by name ignoring case, and counts the notes in it and its subfolders. **Loose** is the folder's top level and counts only its own notes.
- **Subtasks** in a note count as a task's do.
- The Agenda's task lists, Loose tasks, the project and area pages and the Logbook never list notes; tags, Search, links, backlinks and the link menu include them.
- **Making**: a new note is `Untitled.md` in the chosen folder (Loose: the top level), with `createdDate: <today>` and `tags: []`. A new folder is `Untitled folder`. Folder names follow the filename rules, numbering a taken name.
- **Renaming a folder** keeps it in its parent, numbering a taken name, and rewrites body links written with its path (`[[Meetings/Ark]]`).
- **Moving a note** to another folder keeps its filename, numbering a taken one, and rewrites body links written with its path, and links by title when the name changed.
- **Converting** a note to a task, project or area splices `type`, `status` (not for an area), the parent's link (a task's `project` or `area`, a project's `area`) and `createdDate` (only when it has no value) straight after the opening `---`, ahead of the note's keys; keys it already has are set in place, and a `project` or `area` key the parent doesn't name is emptied. A note with no frontmatter gets the block. A Done or Cancelled status also sets `completedDate`; any other empties it. The file then moves to `Ta Da/tasks/`, `Ta Da/projects/` or `Ta Da/areas/`, keeping its filename unless that's taken there (for a project, also by any other project's title, live or logged), and body links written with its path follow it, as do links by title when the name changed. The body is untouched.

## Daily notes

- **Names**: a day's note is `<daily folder>/YYYY-MM-DD.md` and a week's is `<week folder>/GGGG-[W]WW.md`, with the ISO year and week (`Periodic Notes/Daily Notes/2026-10-02.md`, `Periodic Notes/Weekly Notes/2026-W40.md`). The folders default to `Periodic Notes/Daily Notes` and `Periodic Notes/Weekly Notes`, and are set in Settings ▸ Daily notes (kept in the folder, see Settings); they may be the same folder or the top level. The name patterns are fixed.
- **Plain notes**: they have no `type` and the format doesn't change, so they sit in the Notes tree like any note. A folder matches in any case. A note is found by its exact name in its folder, so a note renamed or moved away from it is just a note. A date's ISO week starts on Monday.
- **Making**: a note is created only on request (Start this day's note, or Create in the Agenda's empty editor), never by showing a day. Its folders are created with it, the existing folder's own case is used, and a name that's taken is never numbered. The file is the new note's frontmatter (`createdDate: <today>`, `tags: []`) followed by the body of the template note chosen in Settings (one for daily notes, one for week notes, or none); the template's frontmatter isn't copied.
- **Open boxes**: a daily note's unchecked boxes (`[ ]`, `[/]`, `[>]`, `[<]`) mark its day in the Agenda.

## Settings

The settings that belong to the folder, not the device, are in `Ta Da/settings.json`, shared by Ta Da and the Obsidian plugin. Ta Da never writes in Obsidian's config folder (`.obsidian/`) or the plugin's `data.json`.

```json
{
  "dailyNotes": {
    "dailyFolder": "Periodic Notes/Daily Notes",
    "dailyTemplate": null,
    "weekNotes": true,
    "weekFolder": "Periodic Notes/Weekly Notes",
    "weekTemplate": null
  },
  "theme": {
    "themeSet": "Ayu",
    "usesSchemePerAppearance": false,
    "lightScheme": "Ayu Light",
    "darkScheme": "Ayu Mirage"
  },
  "editor": {
    "autocomplete": { "brackets": true, "formatting": true, "wikiLinks": true, "tags": true }
  }
}
```

- **Groups**: `dailyNotes` (Settings ▸ Daily notes) is read and written by Ta Da and the plugin. `theme` (Settings ▸ Themes, less Appearance) and `editor` (Settings ▸ Editor) are Ta Da's only. Folders and templates are paths from the folder's top level, without surrounding slashes; `""` is the top level. A template is a note's path or `null` for none. Theme and scheme values are names.
- **Reading**: each key is read on its own. A missing key, or a value of the wrong type, takes the device's earlier value (from before the setting moved into the folder), else, for `dailyFolder` and `dailyTemplate` only, Obsidian's Daily notes setting (`folder` and `template` in `.obsidian/daily-notes.json`, `.md` added to a template without it), else the default above. A missing or unreadable file reads as all keys missing. A name that isn't a theme takes the default.
- **Writing**: the file is written only when a setting in it changes, never on opening. A write sets every key of the groups that side owns (Ta Da: all three; the plugin: `dailyNotes`) to its current value and keeps every other key and group as it was, unknown ones included. It's JSON with two-space indents and a final newline; key order doesn't matter.
- **Changes** from another device or app are picked up as the file changes, as other files are.

## Attachments

- An attachment is an image file in the folder. Ta Da saves new ones in `Ta Da/attachments/`, which it creates when needed, numbering a name taken there.
- An embed resolves to its target as a path when that file exists, else to `Ta Da/attachments/<filename>`, else to the first file with that filename by path, ignoring case. Hidden folders, including `.trash`, are skipped. An embed that doesn't resolve is missing. On iOS an image iCloud Drive hasn't downloaded is a hidden `.Name.png.icloud` placeholder; it counts under its real name, and Ta Da asks iCloud Drive to download it.
- A pasted image without a name is saved as `Pasted image <yyyyMMddHHmmss>.png`, in local time.
- **Listing**: Attachments lists the images directly in `Ta Da/attachments/`, iCloud placeholders included (their size is the one the placeholder records). Images elsewhere aren't listed.
- **In use**: an image is in use when a live file embeds it: a task, project, area or note outside `Ta Da/logbook/` and `.trash/`. An embed counts for the image it resolves to, so a same-named image elsewhere that wins resolution doesn't make this one in use.
- **Clean-up reasons**: an image not in use can be cleaned up, for one of four reasons: only logged files embed it, only trashed files, both, or nothing.
- **Clean Up** moves the ticked images not in use to `.trash/attachments/` (as Deleting an attachment does) without rewriting any embed; logged and trashed files show them as missing until they're restored. While markdown files in the folder or `.trash/` are iCloud Drive placeholders, an image they embed can look unused.
- **Renaming an attachment** keeps its folder and extension (the same extension typed in the new name is dropped); the name can't be another image's filename anywhere in the folder. Every embed in a file's body that resolved to it is rewritten to the new filename (to the new path where it was written as a path); anything after `|` stays, and embeds in code are left alone.

## Behaviour rules

- **Completing** sets `status: Done` and `completedDate: <today>`; **cancelling** sets `status: Cancelled` and `completedDate: <today>`. Done and Cancelled files are *completed*. **Reopening** sets `status: Not Started` and clears `completedDate`. `status` is the source of truth; a mismatched `completedDate` is ignored. Ticking every subtask does not complete the task. Ticking a subtask (`[x]`) of a Not Started task in Ta Da sets it to `Doing`; unticking or removing subtasks leaves the status, and ticks made in another app change nothing. Reopening a task (any status that isn't Done or Cancelled) whose project is Done or Cancelled sets the project to `Doing` and clears its `completedDate`. Completing or cancelling a project that has open tasks asks first whether they're completed or cancelled too, each getting its own `status` and `completedDate`.
- **Parents**: a project names its area. A task names one parent, its project or its area; a task in a project is in that project's area, which isn't written into the task. When a task has both keys and `project` has a value, `area` is ignored, with a warning.
- **Agenda** shows one day, or one ISO week, at a time. Today lists tasks that aren't completed and whose `dueDate` or `deadline` is today or earlier; overdue tasks are flagged. It also lists tasks completed or cancelled today. Tasks with no parent come first, then each loose project's, then each area's: its own tasks, then its projects'. Any other day lists the tasks whose `dueDate` or `deadline` is that day, open or Done. A week lists one entry for each `dueDate` and each `deadline` in it, in date order, due before deadline.
- The Agenda lists tasks only; a project's own dates show on its page. Its strip, month and week rows mark a day with an open task due or at its deadline, with unchecked boxes in its daily note, and with an event or reminder.
- **Loose tasks** are open tasks with no resolvable `project` and no resolvable `area`. A **loose project** has no resolvable `area`.
- **Projects** in the sidebar are those not completed: loose projects first, then each area with its projects. Progress is Done/total of linked tasks, logged ones included; Cancelled tasks are left out of the total.
- **Deleting** moves the file into `.trash/` in the folder (the folder Obsidian also uses), keeping its filename unless that's taken there. A project takes its linked tasks. An area takes its projects, their tasks and its own tasks, and Ta Da asks first. Logged files stay in the Logbook. Files that embed attachments also ask first, listing each attachment once: those ticked go with the files, and an attachment that a file staying in the folder embeds starts unticked. The file's contents don't change; the date it was deleted is when it was added to `.trash/`. A note keeps its folder inside `.trash/` (`.trash/Meetings/Ark.md`). **Deleting a folder** asks first, naming how many notes go, then moves it whole to the same path in `.trash/`, merging into a folder already there and numbering taken names; a folder that holds no files is removed instead.
- **Deleting an attachment** moves it into `.trash/attachments/`, keeping its filename unless that's taken there. Attachments go with a deleted file or on their own; embeds of them stay in every file and show as missing.
- A trashed attachment **went with** a trashed file when its filename is the embed's filename, or that name numbered (`front 2.jpg`, when `front.jpg` was taken in `.trash/attachments/`); of those, the one trashed nearest the file.
- **Restoring** moves a task to `Ta Da/tasks/`, a project to `Ta Da/projects/` and an area to `Ta Da/areas/`, numbering a taken name. A note goes back to its folder, which is made again if it's gone (so a deleted folder's notes bring it back), or to the top level when a file has the folder's name. Folders left empty in `.trash/` are removed. Restoring brings back parents, never children: a task brings back its project and that project's area, or its area; a project brings back its area; an area comes back alone. A parent that's only logged doesn't count; a parent that isn't in the folder or `.trash/` is created by name (a project under a title no other project has). If a parent's name had to change, the restored file's link is rewritten. Each restored file brings back the attachments that went with it, and a trashed attachment can be restored alone; both go to `Ta Da/attachments/`, numbering a name taken there. An embed that no longer resolves to its restored attachment (renamed by numbering, or restored to another folder) is rewritten to it.
- **Delete Forever** on a project also removes its trashed tasks; on an area, its trashed projects, their tasks and its own tasks. Each removed file takes the attachments that went with it, except those that a trashed file that stays, or a file outside `.trash/`, embeds. Delete Forever and Empty Trash move the Ta Da files (notes included) and attachments in `.trash/` to the system Trash (on iOS, deleting them where that isn't supported, outside iCloud Drive; a failure doesn't stop the others); other files there are left alone.
- **Logging** moves completed tasks and projects into `Ta Da/logbook/<yyyy-MM>/` (by `completedDate`, else today), numbering a taken name, and for a project any other project's title, live or logged (`Monthly accounts 2`); if a project's name changes, its tasks' `project:` links follow. Ta Da logs each folder once a day, when it opens or the day changes, the files completed before that day (a run that fails is tried again at the next open or day change); Log Now in the Logbook logs every completed file. A completed project with open tasks waits, with its tasks: Log Now asks whether they're completed or cancelled. Areas and notes aren't logged. Logged files keep their contents and their embeds, and links to them still resolve, after a file of the same title that isn't logged; they're left out of the Agenda, Loose tasks, the project and area pages, Search and the link menu.
- **Reopening a logged file** (any status that isn't Done or Cancelled: at once in Ta Da, or at the next day's logging when set in another app) moves it back to `Ta Da/tasks/` or `Ta Da/projects/`, numbering a taken name (for a project, also any other project's title). A task whose project is logged brings it back too, set to `Doing` with `completedDate` cleared; the project's other logged tasks stay. An open task whose project is logged does the same: when its status is set in Ta Da, and at the next day's logging when it's changed in another app.

## Writing rules (how Ta Da edits files)

- Ta Da never re-serialises YAML or markdown. Each change splices only the lines it affects:
  - a property change replaces that key's line(s) (the unindented `key:` line plus its indented or `- ` continuation lines), appends the key before the closing `---` if it's missing, or creates the frontmatter block if there is none. Clearing a property leaves `key:` with no value; a missing key stays missing;
  - a checkbox change replaces only the one character between its brackets. A click completes an open subtask (`[x]`) and reopens a done or cancelled one (`[ ]`); icon-only markers ignore clicks. Any marker can be chosen from the checkbox's right-click menu.
- Line endings (LF or CRLF) and all other bytes are preserved.
- Written values: dates as `YYYY-MM-DD` (unquoted); links quoted as `"[[Title]]"`; lists in block style with quoted items (`[]` when empty); text plain when it starts with a letter and YAML can't misread it (e.g. as `yes`, a comment or a mapping), otherwise double-quoted.
- Filenames come from titles. Ta Da replaces `/ : \ * ? " < > |` and the Obsidian link-breakers `[ ] # ^ |`: a `:` becomes ` -` (so "Game Jam: Starfall" becomes `Game Jam - Starfall.md`), `/ \ |` become `-`, and the rest are dropped. Leading dots and repeated spaces are removed, names are capped at 200 bytes, and an empty name becomes `Untitled`. If the name is taken (ignoring case), it adds ` 2`, ` 3`, and so on. A project's name is also taken by any other project's title, live or logged, when it's created, renamed, restored or logged, so a title never resolves to a logged project's tasks.
- Attachment filenames follow the same rules on the name before the extension, and keep the extension: a taken `front.jpg` becomes `front 2.jpg`.
- **Tags** are written only in `tags:`. Adding one that's already there (ignoring case) does nothing. A flow list stays flow and a block list stays block; an empty key, or a string of comma-separated tags, becomes a flow list. A missing key is added as `tags: [name]` after `createdDate`, or before the closing `---` without one. Removing the last tag leaves `tags:` with no value. A value that can't be spliced safely (a block scalar, or a string or a commented flow list over several lines) is left alone. Inline tags are never rewritten. A task created from a tag gets `tags: [name]`; a file made in Quick Entry gets its tags as a flow list after `createdDate`.
- Moving a file to another parent writes one key and empties the other, in one write.
- Converting a note inserts its keys straight after the opening `---` (see Notes), in the same line style as other writes.
- Renaming a project rewrites the `project:` link in each of its tasks (logged ones too) as `"[[New title]]"`, and renaming an area rewrites the `area:` link in its projects and its own tasks (logged ones too), in one coordinated read and write per file and only if the file still links to it. Renaming any file also rewrites the `[[ ]]` links to its title in the bodies of the files that link to it, itself included, keeping each link's folder, `.md`, heading and alias; links in code are left alone, and nothing is rewritten while another `.md` file in the folder, Ta Da's or not, still has the old title.
