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

- **Kind** comes only from `type: task` or `type: project`. Files without either value are not Ta Da files and are ignored. This lets Ta Da share a folder (or an Obsidian vault) with other notes.
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
- An empty key (`dueDate:`) is the same as a missing one.

## Body

- **Description**: the whole body. Its first paragraph is the summary shown in lists.
- **Subtasks**: every GFM checklist item (`- [ ]`, `- [x]` or `- [X]`, followed by a space) anywhere in the body, at any depth. They are counted as done/total. Items inside code blocks don't count, and Obsidian's custom statuses such as `[/]` stay plain text.
- **Links**: `[[Title]]`, `[[Title|alias]]`, `[[Title#heading]]` and `[[folder/Title]]` resolve to the file with that title, case-insensitively. Body links are links only; they never set project membership.

## Behaviour rules

- **Completing** sets `status: Done` and `completedDate: <today>`. **Reopening** sets `status: Not Started` and clears `completedDate`. `status` is the source of truth; a mismatched `completedDate` is ignored. Ticking every subtask does not complete the task.
- **Today** shows items that aren't Done and whose `dueDate` or `deadline` is today or earlier; overdue items are flagged. It also shows items completed today.
- **Upcoming** starts tomorrow. An item gets one entry on its `dueDate` and another on its `deadline`.
- **Loose tasks** are open tasks without a resolvable `project`.
- **Projects** in the sidebar are those not Done. Progress is done/total of linked tasks.

## Writing rules (how Ta Da edits files)

- Ta Da never re-serialises YAML or markdown. Each change splices only the lines it affects:
  - a property change replaces that key's line(s), appends the key before the closing `---` if it's missing, or creates the frontmatter block if there is none;
  - a subtask toggle changes only `[ ]` ↔ `[x]` on that line.
- Line endings (LF or CRLF) and all other bytes are preserved.
- Written values: dates as `YYYY-MM-DD` (unquoted); links quoted as `"[[Title]]"`; lists in block style with quoted items.
- Filenames come from titles. Ta Da replaces `/ : \ * ? " < > |` and the Obsidian link-breakers `[ ] # ^ |` (a `:` becomes ` -`, so "Game Jam: Starfall" becomes `Game Jam - Starfall.md`). If the name is taken, it adds ` 2`, ` 3`, and so on.
- Renaming a project rewrites the `project:` link in each of its tasks.
