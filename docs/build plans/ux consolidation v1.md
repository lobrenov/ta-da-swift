# Ta Da — UX Consolidation plan

## Context
Lists put the task and its group first, as Things does, rather than a line of information about each task. Design source: direction A on the canvas's **UX Consolidation** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V (`UxA-Mac`, `UxA-MacArea`, `UxA-MacProject`, `UxA-Ios`, `UxA-IosArea`, `UxA-IosProject`). Brief: the vault task `tasks/UX Consolidation.md`.

Starting point, as checked on 2026-10-21 (Build 29):
- `TaskRow` is two lines: the title over a meta line of chips (place, subtasks `n/m`, repeat rule, due and deadline, tag count), drawn by `SelectableRow` in `TaDa/Browser/TaskRow.swift`. `TaskRow.Dates` picks labelled, icons-only or Today's overdue-only dates. `PhoneTaskRow` in `TaDa/iOS/PhoneRows.swift` builds the same chips.
- Group headers: `ProjectGroupHeader`, `AreaGroupHeader` and `CountGroupHeader` in `TaDa/Browser/BrowserChrome.swift`, 12pt `muted`.
- The area page has Projects, Tasks and Completed sections, each foldable; its project rows carry a meta line.
- The project browser's header holds the property chips (`PropertyChipRow`), subtasks and "n of m tasks done".

## Decisions
- **Task row is one line**: checkbox, title (one line, truncated; the full title in the tooltip and accessibility label), then quiet glyphs in `muted`, then one date on the right. Rows are 32pt on the Mac and 46pt on iPhone.
- **Glyphs**, in this order, icon only: a note (`doc.text`, when the file has body text: `Item.summary`), subtasks (`checklist`), repeat (`repeat`), tags (`tag` in `accent`; hovering lists them, as `TagCountChip` does). Counts and rule text move to the tooltip and accessibility label. Contexts stay hidden.
- **One date**, right-aligned in `muted` with its kind's icon in its tint: the deadline when set, else the due date. Closed tasks show none.
  - In the Agenda, a deadline reads as "today", "N days left" or "N days late"; a due date shows only when overdue, as now.
  - Elsewhere, the date (`relativeLabel`, "Fri 30 Oct").
  - An overdue date's text is in `deadline`, as now.
- **Place**: where a list's groups don't show a task's project or area (the Agenda under Status and Open, tag pages), it sits in `muted` before the date and truncates before the title does.
- **Group headers**: a project group is its ring, its name in 15pt bold `strong` and its area in 12pt `muted`, over a hairline. Tasks with no project lead the list without a header. Status, Date and Open headers are the name in 15pt bold `strong` and the count in `muted`, keeping their fold chevron. Completed stays a 12.5pt `muted` foldable header at the foot, folded at first.
- **Area page**: its projects first, one line each (ring, name in 14pt semibold `strong`, deadline, open-task count), then the tasks filed straight to the area after a gap, then Completed. The Projects and Tasks headers and their folds go.
- **Project page**: the header keeps the ring, title, Filter, Group and Open project file. The chips become one `muted` line: status (dot in its tint), deadline, due date, subtasks `n/m` and "n of m done". Each item is a plain button that opens its menu (status, date). Missing keys are set from the project's document pane.
- **iPhone** follows the same rules: one-line `PhoneTaskRow`, `PhoneProjectRow` and `PhoneAreaRow`; project groups as 20pt bold headers; the project screen's chips become the same quiet line, with Group and Filter on the row under it.
- **Unchanged**: the sidebar, the document pane and its property chips, search results (place and matching summary), Logbook rows, note rows, colour tokens.

## Milestones
Each ends with its check passing, then a commit and a review.

### U1 — Mac task row
- `TaskRow` and `SelectableRow` one line; `RowGlyphs` and `RowDate` replace the meta line's chips; `TaskRow.Dates` becomes the date rule above (Agenda or elsewhere).
- Every caller: Agenda day and week lists, Loose tasks, projectBrowser, areaBrowser, tag pages, the project page's linked tasks.
- Check: app builds; `TaDaTests` pass; DesignRenderTests renders compared with the canvas boards.

### U2 — Mac groups and pages
- `ProjectGroupHeader`, `AreaGroupHeader` and `CountGroupHeader` restyled; no header for tasks without a project.
- areaBrowser's project rows and layout; projectBrowser's quiet header line with its menus.
- Check: app builds; `TaDaTests` pass; renders compared.

### U3 — iPhone
- `PhoneTaskRow`, `PhoneProjectRow`, `PhoneAreaRow`, the group headers in `PhoneGrouping.swift`, and `PhoneProjectHeader`'s quiet line.
- Check: iOS build; run on the simulator against the canvas boards.

### U4 — Docs and canvas
- `docs/design/design-framework.md` (In the app, As built: TaskRow meta line, Area page, Project browser), `docs/design/components/TaskRow/`, `docs/architecture.md` if a view moves.
- Canvas: update the macOS, iOS and Menus reference pages' boards (taskRow and every list) to match, then delete the UX Consolidation page.
- `docs/backlog.md`; archive this plan.
