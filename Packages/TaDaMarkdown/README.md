# TaDaMarkdown

Ta Da's live markdown editor: a TextKit 2 editor view bridged to SwiftUI, with live styling, Obsidian wikilinks and callouts, alternative checkboxes, inline bubbles, slash commands and auto-closed pairs. macOS today; iOS is in progress (`docs/iOS-Plan.md` in the Ta Da repo). No external dependencies.

- Entry point: `NativeTextViewWrapper` (SwiftUI). Ta Da embeds it in `TaDa/Editor/LiveEditor.swift`, the only file that imports `TaDaMarkdown`.
- Internals: `ARCHITECTURE.md`. API overview: the DocC catalog in `Sources/TaDaMarkdown/TaDaMarkdown.docc`.
- Origin and changes from swift-markdown-engine 0.13.0: `ORIGIN.md`.
- Tests: `swift test --package-path Packages/TaDaMarkdown` from the repo root.

Licensed under the Apache License, Version 2.0 (`LICENSE`); see `NOTICE`.
