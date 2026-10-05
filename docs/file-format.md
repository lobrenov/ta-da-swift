# Ta Da file format

Every task and every project is one markdown file. YAML frontmatter holds the structured data; the body is free markdown. Files must stay readable and editable in Obsidian or any text editor.

## Example

```markdown
---
type: task
status: Doing
area: Personal
contexts:
  - "@computer"
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

- **Kind** comes only from `type: task` or `type: project` (any case). Files without either value are not Ta Da files and are ignored. This lets Ta Da share a folder (or an Obsidian vault) with other notes.
- **Title** is the filename without `.md`. Renaming a task or project renames its file.
- **Location** doesn't matter. The whole chosen folder is scanned recursively; hidden folders, `.obsidian` and `.trash` are skipped. New files are created in `tasks/` and `projects/`.

## Properties

| Key | Applies to | Value | Notes |
|---|---|---|---|
| `type` | both | `task` \| `project` | Required |
| `status` | both | `Not Started` \| `Doing` \| `Done` \| `Blocked` | Read case-insensitively; written in this exact form. Missing or unknown values read as `Not Started`, with a warning |
| `area` | both | text | Optional |
| `contexts` | both | list of text | Optional. Flow (`["@a"]`) and block lists are both accepted. Values starting with `@` must be quoted in YAML |
| `project` | tasks | wikilink `"[[Project title]]"` | Optional. The **only** thing that makes a task belong to a project. If the link doesn't resolve, the task is loose and gets a warning |
| `createdDate` | both | `YYYY-MM-DD` | Set when Ta Da creates the file |
| `completedDate` | both | `YYYY-MM-DD` | Set when completed, cleared when reopened |
| `dueDate` | both | `YYYY-MM-DD` | Optional |
| `deadline` | both | `YYYY-MM-DD` | Optional |
| `repeat` | both | text | Displayed only; no recurrence yet |

- Dates are calendar days in local time, with no times or time zones. They are read as plain strings, never as YAML timestamps.
- Any other keys, plus comments, key order and formatting, are preserved untouched.
- An empty key (`dueDate:`), or an unquoted `~` or `null`, is the same as a missing one.
- Values that can't be read (a bad date, a `project` that isn't a link, a list where text belongs) are treated as missing, with a warning.
- If the frontmatter isn't valid YAML, the file still loads when an unindented `type: task` or `type: project` line is present. Its other properties read as missing and it gets a warning.

## Body

- **Description**: the whole body. Its first paragraph is the summary shown in lists.
- **Checkboxes**: a list item whose marker is followed by `[c]` and a space or tab, where `c` is one character from the [Alternative Checkboxes Reference Set](https://github.com/damiankorcz/Alternative-Checkboxes-Reference-Set). Items inside code blocks don't count, and any other character inside the brackets (e.g. `[y]`) stays plain text.
- **Subtasks** are the checkboxes in these states, anywhere in the body and at any depth, counted as done/total:

  | Marker | State | Counts as |
  |---|---|---|
  | `[ ]` | To do | open |
  | `[/]` | Incomplete | open |
  | `[>]` | Forwarded | open |
  | `[<]` | Scheduling | open |
  | `[x]` `[X]` | Done | done |
  | `[-]` | Cancelled | left out of the total |

  The other reference markers (`[?] [!] [*] ["] [l] [b] [i] [S] [I] [p] [c] [f] [k] [w] [u] [d]`) are icons only. They render as checkboxes but aren't subtasks.
- **Links**: `[[Title]]`, `[[Title|alias]]`, `[[Title#heading]]` and `[[folder/Title]]` resolve to the file with that title, case-insensitively. Body links are links only; they never set project membership.

## Behaviour rules

- **Completing** sets `status: Done` and `completedDate: <today>`. **Reopening** sets `status: Not Started` and clears `completedDate`. `status` is the source of truth; a mismatched `completedDate` is ignored. Ticking every subtask does not complete the task.
- **Today** shows tasks that aren't Done and whose `dueDate` or `deadline` is today or earlier; overdue tasks are flagged. It also shows tasks completed today.
- **Upcoming** starts tomorrow. An open task gets one entry on its `dueDate` and another on its `deadline`.
- Today and Upcoming list tasks only; a project's own dates show on its page.
- **Loose tasks** are open tasks without a resolvable `project`.
- **Projects** in the sidebar are those not Done. Progress is done/total of linked tasks.
- **Deleting** moves the file into `.trash/` in the folder (the folder Obsidian also uses), keeping its filename unless that's taken there. A project takes its linked tasks. The file's contents don't change; the date it was deleted is when it was added to `.trash/`.
- **Restoring** moves a task to `tasks/` and a project to `projects/`, numbering a taken name. A project brings back the trashed tasks that link to it; if its name had to change, their `project:` links are rewritten. Delete Forever and Empty Trash move the Ta Da files in `.trash/` to the system Trash; other notes there are left alone.

## Writing rules (how Ta Da edits files)

- Ta Da never re-serialises YAML or markdown. Each change splices only the lines it affects:
  - a property change replaces that key's line(s) (the unindented `key:` line plus its indented or `- ` continuation lines), appends the key before the closing `---` if it's missing, or creates the frontmatter block if there is none. Clearing a property leaves `key:` with no value; a missing key stays missing;
  - a checkbox change replaces only the one character between its brackets. A click completes an open subtask (`[x]`) and reopens a done or cancelled one (`[ ]`); icon-only markers ignore clicks. Any marker can be chosen from the checkbox's right-click menu.
- Line endings (LF or CRLF) and all other bytes are preserved.
- Written values: dates as `YYYY-MM-DD` (unquoted); links quoted as `"[[Title]]"`; lists in block style with quoted items (`[]` when empty); text plain when it starts with a letter and YAML can't misread it (e.g. as `yes`, a comment or a mapping), otherwise double-quoted.
- Filenames come from titles. Ta Da replaces `/ : \ * ? " < > |` and the Obsidian link-breakers `[ ] # ^ |`: a `:` becomes ` -` (so "Game Jam: Starfall" becomes `Game Jam - Starfall.md`), `/ \ |` become `-`, and the rest are dropped. Leading dots and repeated spaces are removed, names are capped at 200 bytes, and an empty name becomes `Untitled`. If the name is taken (ignoring case), it adds ` 2`, ` 3`, and so on.
- Renaming a project rewrites the `project:` link in each of its tasks as `"[[New title]]"`. Body links aren't changed.
