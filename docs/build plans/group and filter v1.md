# Ta Da — Group and Filter plan

## Context
Browsers gain a Group choice and a tag filter. Design source: the canvas's **Group & Filter** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V (`GfToday`, `GfLoose`, `GfProjectBrowser`, `GfProjectFiltered`, `GfArea`, `GfNotes`, `GfSpec`, `IosGfToday`, `IosGfProjectBrowser`, `IosGfLoose`, `IosGfFilterSheet`). Brief: the vault task `tasks/Group By and Filter.md`.

Starting point, as checked on 2026-10-16:
- Today and Loose tasks group by area ▸ project (`VaultIndex.grouped`); projectBrowser has Open and Completed, foldable per project (`AppModel.foldedGroups`).
- projectBrowser's header has a labelled Open project file button; the iPhone project screen has a Project file row.
- Nothing filters a browser by tag.

## Decisions
- **Group** sits on the title line, before the file button. Per list, kept in app settings (never the vault): Today (Project default, Status, Open), Loose tasks (Status default, Date, Open), every project (Status, Date, Open default). Areas and Notes folders have none.
- **Status** order: Doing, Blocked, Not Started, Done, Cancelled; empty groups are left out.
- **Date** merges `dueDate` and `deadline`: Today (either today or past), Upcoming (any later), Someday (neither); Done and Cancelled go to Completed, last.
- **Open**: Open, then Completed. **Project**: Today's area ▸ project groups as before.
- **Folding**: Status, Date and Open groups fold, remembered per list (Today, Loose tasks, each project). Done, Cancelled and Date's Completed start folded; Open's Completed doesn't, as before.
- **Filter pill**: + Tag's dashed chip with a funnel. Shown on Today, Loose tasks, projectBrowser, areaBrowser and Notes folders when a file in the view carries a tag. Its menu lists the tags of the files in the view with counts; picks toggle and the menu stays open. A file shows when it carries any picked tag or a child of one. Picked tags follow as filled chips with ×, then "n of m shown" and Clear. Picks are kept per page for the session, not saved.
- While filtering, Today hides its events and reminders, and rows outside Project grouping show their project or area.
- **Open project file** becomes an icon-only button with a tooltip on the Mac; on iPhone, a file button in the top bar replaces the Project file row.
- **iPhone**: Group is a menu capsule on the title line; the pill opens a sheet (search, tags with counts and ticks, Clear, Done). No Notes folders on iPhone.

## Milestones
Each ends with its check passing, then a commit and a review.

### G1 — Core
- `Grouping` and `ListSection` (`Index/Grouping.swift`): Status, Date and Open sections from a list of tasks.
- `TagFilter`: matching (any picked tag or a child) and the tags of a list with counts.
- Check: `GroupingTests`.

### G2 — Mac
- `AppModel`: the three groupings in settings, the session's filters per domain, section folds.
- Group button and menu, filter pill, menu and chips, the icon-only file button; wired into Today, Loose tasks, projectBrowser, areaBrowser and folderBrowser.
- Check: app builds; `TaDaTests` pass.

### G3 — iPhone
- Group menu capsule, filter pill, chips and sheet on Today, Loose, a project and an area; the project file button in the top bar.
- Check: iOS build.

### G4 — Docs
- `docs/design/design-framework.md` (In the app, As built), `docs/architecture.md`, `docs/backlog.md`; archive this plan.
