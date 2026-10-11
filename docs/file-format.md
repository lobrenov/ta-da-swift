# Ta Da file format

Every task, project and area is one markdown file. YAML frontmatter holds the structured data; the body is free markdown. Files must stay readable and editable in Obsidian or any text editor.

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

- **Kind** comes only from `type: task`, `type: project` or `type: area` (any case). Files without either value are not Ta Da files and are ignored. This lets Ta Da share a folder (or an Obsidian vault) with other notes.
- **Title** is the filename without `.md`. Renaming a file renames it.
- **Location** doesn't matter. The whole chosen folder is scanned recursively; hidden folders, `.obsidian` and `.trash` are skipped, except `.logbook` (see Logging). New files are created in `tasks/`, `projects/` and `areas/`.

## Properties

| Key | Applies to | Value | Notes |
|---|---|---|---|
| `type` | all | `task` \| `project` \| `area` | Required |
| `status` | tasks, projects | `Not Started` \| `Doing` \| `Done` \| `Blocked` \| `Cancelled` | Read case-insensitively; written in this exact form. Missing or unknown values read as `Not Started`, with a warning |
| `project` | tasks | wikilink `"[[Project title]]"` | Optional. The **only** thing that makes a task belong to a project. If the link doesn't resolve, the task has no parent and gets a warning |
| `area` | tasks, projects | wikilink `"[[Area title]]"` | Optional. Files a project, or a task with no project, under an area. Plain text (`area: Personal`) reads as the title. If it doesn't resolve, the file has no parent and gets a warning |
| `createdDate` | all | `YYYY-MM-DD` | Set when Ta Da creates the file |
| `completedDate` | both | `YYYY-MM-DD` | Set when completed or cancelled, cleared when reopened |
| `dueDate` | both | `YYYY-MM-DD` | Optional |
| `deadline` | both | `YYYY-MM-DD` | Optional |
| `repeat` | both | text | Displayed only; no recurrence yet |

- An area's frontmatter is `type` and `createdDate`; its body is free markdown. Areas have no status or dates, and Ta Da doesn't write them.
- `contexts` is no longer read. Like any unknown key, it stays in the file untouched.
- Dates are calendar days in local time, with no times or time zones. They are read as plain strings, never as YAML timestamps.
- Any other keys, plus comments, key order and formatting, are preserved untouched.
- An empty key (`dueDate:`), or an unquoted `~` or `null`, is the same as a missing one.
- Values that can't be read (a bad date, a `project` that isn't a link, a list where text belongs) are treated as missing, with a warning.
- If the frontmatter isn't valid YAML, the file still loads when an unindented `type: task`, `type: project` or `type: area` line is present. Its other properties read as missing and it gets a warning.

## Body

- **Description**: the whole body. Search also matches its first paragraph (the summary).
- **Checkboxes**: a list item whose marker is followed by `[c]` and a space or tab (as in GFM, so a bare `- [ ]` is text), where `c` is one character from the [Alternative Checkboxes Reference Set](https://github.com/damiankorcz/Alternative-Checkboxes-Reference-Set). Items inside code blocks don't count, and any other character inside the brackets (e.g. `[y]`) stays plain text.
- **Subtasks** are the checkboxes in these states, anywhere in the body and at any depth, counted as done/total:

  | Marker | State | Counts as |
  |---|---|---|
  | `[ ]` | Not started | open |
  | `[/]` | Doing | open |
  | `[>]` | Forwarded | open |
  | `[<]` | Scheduling | open |
  | `[x]` `[X]` | Done | done |
  | `[-]` | Cancelled | left out of the total |

  The other reference markers (`[?] [!] [*] ["] [l] [b] [i] [S] [I] [p] [c] [f] [k] [w] [u] [d]`) are icons only. They render as checkboxes but aren't subtasks.
- **Links**: `[[Title]]`, `[[Title|alias]]`, `[[Title#heading]]` and `[[folder/Title]]` resolve to the file with that title, case-insensitively. Body links are links only; they never set a parent.
- **Embeds**: the same with a leading `!`, e.g. `![[front.jpg]]` or `![[front.jpg|300]]`. Embeds aren't links, so they aren't backlinks. An embed whose target ends in an image extension (`avif bmp gif heic jpeg jpg png svg tif tiff webp`, any case) shows that attachment.

## Attachments

- An attachment is an image file in the folder. Ta Da saves new ones in `attachments/`, which it creates when needed.
- An embed resolves to its target as a path when that file exists, else to `attachments/<filename>`, else to the first file with that filename by path, ignoring case. Hidden folders, including `.trash`, are skipped. An embed that doesn't resolve is missing. On iOS an image iCloud Drive hasn't downloaded is a hidden `.Name.png.icloud` placeholder; it counts under its real name, and Ta Da asks iCloud Drive to download it.
- A pasted image without a name is saved as `Pasted image <yyyyMMddHHmmss>.png`, in local time.
- **Renaming an attachment** keeps its folder and extension (the same extension typed in the new name is dropped); the name can't be another image's filename anywhere in the folder. Every embed in a file's body that resolved to it is rewritten to the new filename (to the new path where it was written as a path); anything after `|` stays, and embeds in code are left alone.

## Behaviour rules

- **Completing** sets `status: Done` and `completedDate: <today>`; **cancelling** sets `status: Cancelled` and `completedDate: <today>`. Done and Cancelled files are *completed*. **Reopening** sets `status: Not Started` and clears `completedDate`. `status` is the source of truth; a mismatched `completedDate` is ignored. Ticking every subtask does not complete the task. Reopening a task (any status that isn't Done or Cancelled) whose project is Done or Cancelled sets the project to `Doing` and clears its `completedDate`. Completing or cancelling a project that has open tasks asks first whether they're completed or cancelled too, each getting its own `status` and `completedDate`.
- **Parents**: a project names its area. A task names one parent, its project or its area; a task in a project is in that project's area, which isn't written into the task. When a task has both keys and `project` has a value, `area` is ignored, with a warning.
- **Today** shows tasks that aren't completed and whose `dueDate` or `deadline` is today or earlier; overdue tasks are flagged. It also shows tasks completed or cancelled today. Tasks with no parent come first, then each loose project's, then each area's: its own tasks, then its projects'.
- **Upcoming** starts tomorrow. An open task gets one entry on its `dueDate` and another on its `deadline`.
- Today and Upcoming list tasks only; a project's own dates show on its page.
- **Loose tasks** are open tasks with no resolvable `project` and no resolvable `area`. A **loose project** has no resolvable `area`.
- **Projects** in the sidebar are those not completed: loose projects first, then each area with its projects. Progress is Done/total of linked tasks, logged ones included; Cancelled tasks are left out of the total.
- **Deleting** moves the file into `.trash/` in the folder (the folder Obsidian also uses), keeping its filename unless that's taken there. A project takes its linked tasks. An area takes its projects, their tasks and its own tasks, and Ta Da asks first. Logged files stay in `.logbook/`. Files that embed attachments also ask first, listing each attachment once: those ticked go with the files, and an attachment that a file staying in the folder embeds starts unticked. The file's contents don't change; the date it was deleted is when it was added to `.trash/`.
- **Deleting an attachment** moves it into `.trash/attachments/`, keeping its filename unless that's taken there. Attachments go with a deleted file or on their own; embeds of them stay in every file and show as missing.
- A trashed attachment **went with** a trashed file when its filename is the embed's filename, or that name numbered (`front 2.jpg`, when `front.jpg` was taken in `.trash/attachments/`); of those, the one trashed nearest the file.
- **Restoring** moves a task to `tasks/`, a project to `projects/` and an area to `areas/`, numbering a taken name. Restoring brings back parents, never children: a task brings back its project and that project's area, or its area; a project brings back its area; an area comes back alone. A parent that's only in `.logbook/` doesn't count; a parent that isn't in the folder or `.trash/` is created by name. If a parent's name had to change, the restored file's link is rewritten. Each restored file brings back the attachments that went with it, and a trashed attachment can be restored alone; both go to `attachments/`, numbering a taken name. An embed that no longer resolves to its restored attachment (renamed by numbering, or restored to another folder) is rewritten to it.
- **Delete Forever** on a project also removes its trashed tasks; on an area, its trashed projects, their tasks and its own tasks. Each removed file takes the attachments that went with it, except those that a trashed file that stays, or a file outside `.trash/`, embeds. Delete Forever and Empty Trash move the Ta Da files and attachments in `.trash/` to the system Trash (on iOS, deleting them where that isn't supported, outside iCloud Drive; a failure doesn't stop the others); other notes there are left alone.
- **Logging** moves completed tasks and projects into `.logbook/<yyyy-MM>/` (by `completedDate`, else today), numbering a taken name; if a project's name changes, its tasks' `project:` links follow. Ta Da logs once a day, when the folder opens or the day changes, the files completed before that day; Log Now in the Logbook logs every completed file. A completed project with open tasks waits, with its tasks: Log Now asks whether they're completed or cancelled. Areas aren't logged. Logged files keep their contents and their embeds, and links to them still resolve, after a file of the same title outside `.logbook/`; they're left out of Today, Upcoming, Loose tasks, the project and area pages, Search and the link menu.
- **Reopening a logged file** (any status that isn't Done or Cancelled: at once in Ta Da, or at the next day's logging when set in another app) moves it back to `tasks/` or `projects/`, numbering a taken name. A task whose project is logged brings it back too, set to `Doing` with `completedDate` cleared; the project's other logged tasks stay.

## Writing rules (how Ta Da edits files)

- Ta Da never re-serialises YAML or markdown. Each change splices only the lines it affects:
  - a property change replaces that key's line(s) (the unindented `key:` line plus its indented or `- ` continuation lines), appends the key before the closing `---` if it's missing, or creates the frontmatter block if there is none. Clearing a property leaves `key:` with no value; a missing key stays missing;
  - a checkbox change replaces only the one character between its brackets. A click completes an open subtask (`[x]`) and reopens a done or cancelled one (`[ ]`); icon-only markers ignore clicks. Any marker can be chosen from the checkbox's right-click menu.
- Line endings (LF or CRLF) and all other bytes are preserved.
- Written values: dates as `YYYY-MM-DD` (unquoted); links quoted as `"[[Title]]"`; lists in block style with quoted items (`[]` when empty); text plain when it starts with a letter and YAML can't misread it (e.g. as `yes`, a comment or a mapping), otherwise double-quoted.
- Filenames come from titles. Ta Da replaces `/ : \ * ? " < > |` and the Obsidian link-breakers `[ ] # ^ |`: a `:` becomes ` -` (so "Game Jam: Starfall" becomes `Game Jam - Starfall.md`), `/ \ |` become `-`, and the rest are dropped. Leading dots and repeated spaces are removed, names are capped at 200 bytes, and an empty name becomes `Untitled`. If the name is taken (ignoring case), it adds ` 2`, ` 3`, and so on.
- Attachment filenames follow the same rules on the name before the extension, and keep the extension: a taken `front.jpg` becomes `front 2.jpg`.
- Moving a file to another parent writes one key and empties the other, in one write.
- Renaming a project rewrites the `project:` link in each of its tasks (logged ones too) as `"[[New title]]"`, and renaming an area rewrites the `area:` link in its projects and its own tasks (logged ones too), in one coordinated read and write per file and only if the file still links to it. Renaming any file also rewrites the `[[ ]]` links to its title in the bodies of the files that link to it, itself included, keeping each link's folder, `.md`, heading and alias; links in code are left alone, and nothing is rewritten while another `.md` file in the folder, Ta Da's or not, still has the old title.
