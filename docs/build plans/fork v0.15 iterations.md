# Ta Da — Fork v0.15 iterations plan

## Context
Upstream swift-markdown-engine 0.15.0 is merged into the fork's `live` as `0.15.0-live.1` (`FORK.md`, Upstream merges). Two of its changes stop short of the fork's own features:
- **Inline Writing Tools** (`writingToolsBehavior = .complete`) leave code, formulas, links, embeds and tables as written (`NativeTextViewCoordinator+WritingTools.swift`, `writingToolsIgnoredRangesInEnclosingRange`). The fork's tags (#24), task boxes (#1) and callout markers (#16) aren't in that list, so a rewrite or proofread can change `#work`, `[x]` or `[!note]`.
- **Two-way focus** (`NativeTextViewWrapper.isFocused`) is on the Mac wrapper only. The fork's iOS editor (#19) has none.

Ta Da focuses the editor itself: `LiveEditor`'s `takesFocus` task retries `makeFirstResponder` up to 20 times through `SlashCommandProxy.textView`, and the iPhone keyboard bar's Hide Keyboard calls `resignFirstResponder` on it.

## Decisions
- **What Writing Tools leave alone**: a tag (`#` and name), a task box's marker (`[ ]`, `[x]`, the alternative markers; the item's text stays rewritable), and a callout's `[!type]` with its fold sign (the title stays rewritable). Taken from the parse the editor already has: `.tag` tokens, the list items' box ranges, and the `.calloutLine` title parts.
- **`isFocused` on iOS** has the Mac wrapper's meaning: nil leaves focus to UIKit; set, it follows `becomeFirstResponder`/`resignFirstResponder`, and setting it to `true` or `false` gives or drops the keyboard. Writes to the binding are deferred out of view updates as on the Mac (`reportFocusChange`).
- **Ta Da uses `isFocused`** in place of the `takesFocus` retry loop and the Hide Keyboard call. Focus still moves the caret to the start of a newly opened file.
- **Not in this plan**: the code-blocks bridge on iOS (highlight.js runs on JavaScriptCore, but Ta Da doesn't link `MarkdownEngineCodeBlocks`); upstreaming the exclusions (they cover fork syntax only).

## Milestones
Fork milestones run on `live` in `~/Projects/swift-markdown-engine-extended`, per its `CLAUDE.md` (An editor or syntax change). Ta Da milestones run on `feat/fork-v0.15`. Each ends with its check passing, then a commit and a review.

### F1 — Writing Tools leave fork syntax alone (fork)
- `writingToolsIgnoredRangesInEnclosingRange` adds tag tokens, task box markers and callout `[!type]` markers, clipped to the enclosing range. `Fork:` marker; `FORK.md` entry (Conflicts: Upstream's, the fork's ranges added to upstream's list).
- Tests: `WritingToolsIgnoredRangesTests` cases for a tag, each kind of box, a quoted task, a callout title line with and without a fold sign, and a range that cuts one of them.
- Tag `0.15.0-live.2`.
- Check: macOS and iOS fork tests pass (the exclusions are macOS-only; the iOS run shows nothing else moved).

### F2 — `isFocused` on the iOS editor (fork)
- The iOS `NativeTextViewWrapper` takes `isFocused: Binding<Bool>?`. `NativeTextView` (iOS) reports responder changes; `updateUIView` applies a requested change only when it differs from the view's state.
- `FORK.md` #19 names it.
- Tests: `IOSEditorInputTests`: the binding follows a tap and a resign; setting it gives and drops first responder; nil changes nothing.
- Tag `0.15.0-live.3`.
- Check: macOS and iOS fork tests pass.

### F3 — Ta Da on `0.15.0-live.3` (Ta Da)
- Bump the exact pin in the Xcode project and `Packages/TaDaCore/Package.swift`.
- `LiveEditor`: a focus binding passed as `isFocused`, set on `takesFocus` (caret to the start, then `onTookFocus`); the retry loop goes. On iPhone, Hide Keyboard sets it to `false`.
- `docs/architecture.md` (Editors) where it describes focus.
- Check: macOS and iOS builds; app + core tests (`-skip-testing:TaDaUITests`); by hand on the Mac: a new task's editor takes focus, a rewrite and a proofread over a note with tags, tasks and a callout leave those as written, switching files mid-rewrite and ⌘Z mid-rewrite don't crash; on iPhone: opening a new task shows the keyboard and Hide Keyboard drops it.
