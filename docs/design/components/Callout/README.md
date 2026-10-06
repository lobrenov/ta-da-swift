# Callout

An Obsidian callout in the Live editor: a tinted panel with an icon and a title, opened by `> [!type] Title`.

## Anatomy

- `td-callout` — `radius-lg`, padding 9px 14px 11px. Fill: the type's colour at 9% (14% on dark schemes) over `bg`; a 1px inset ring of the colour at 24% (30%). No side bar.
- `td-callout-title` — a 16px icon in the type's colour, 8px gap, then the title at 600 in `strong`. Without a title the type's name is used (`[!faq]` shows "Faq"). A long title wraps; the icon stays on its first line.
- `td-callout-body` — the following `>` lines at `body-editor` in `fg`, 3px under the title, 8px between blocks. Any markdown works inside, including another callout (`> > [!quote]`).
- `td-callout-fold` — for `[!type]+` and `[!type]-`: a 14px chevron in `muted` at the right of the title, down when open, right when folded. Clicking the title row folds or opens it on screen; the file keeps its `+` or `-`.

## Types

The thirteen Obsidian types, read case-insensitively, each with a fixed token (`td-callout.is-<type>` sets `--c`): note `accent`, abstract `doing`, info `accent`, todo `accent`, tip `doing`, success `done`, question `due`, warning `blocked`, failure `deadline`, danger `deadline`, bug `deadline`, example `link`, quote `muted`. Aliases take their type's look. An unknown type draws as note with its own name as the title. The full table, with aliases and icons, is in the Callouts section of `docs/design/design-framework.md`.

## States

- `is-folded` — the title row only (also a callout with no body).
- `is-target` — while its menu is open: a 2px `accent` inset ring in place of the tint ring.
- Caret on the title line: the line shows `> [!type]` in `muted` mono on `code` inside the panel; the body stays drawn.

## Callout menu

A right-click (or control-click) on the title line opens the full Menu under the icon, with the callout ringed. Two groups:

- **Type** — the thirteen types with their icons in their colours and `[!type]` on the right. The current type has an `accent` tick and opens highlighted; an alias ticks its type; an unknown type ticks nothing and opens on Note.
- **Fold** — Always open (`[!type]`), Foldable, open (`+`) and Foldable, folded (`-`), with dash and chevron glyphs in `muted` (`accent` when highlighted).

Picking a type replaces only the text between `[!` and `]` with the type's name; the title, fold and body stay. Picking a fold adds, changes or removes the one character after `]`. One undo step each. The menu takes ↑↓, ↵ (Set) and esc.
