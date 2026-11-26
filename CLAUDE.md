# Paper — handoff notes

Paper is a minimalist macOS writing app. The user (Frank) wants it **spacious and minimal** — on screen there is only the text being written and a cursor. Keep it that way: no toolbars, status bars, word counts, or visible chrome unless he asks.

## Where things stand

The Swift shell builds cleanly (`./build.sh`, Swift 6.1 / `-swift-version 5`, no warnings) and was tested by hand on 2026-11-25 against every item under "Verify" below: all pass. The only compile fix needed was wrapping the top-level entry point in `MainActor.assumeIsolated`.

Repo: `git@github.com:FrankWhoee/paper.git`, branch `main`. `build/` is gitignored. `./build.sh --install` copies the app to /Applications.

## Requirements (from the user)

- Spacious, minimal interface: just the text and a cursor.
- Accepts Markdown but **does not render it while writing**; rendering happens only on request (⌘E).
- Monospace font.
- Focus mode: highlights the current sentence and fades all other text.
- Performant.
- Save and write multiple articles/essays; browse them easily but simply.
- Its own standalone app, separate from the browser.

## Architecture

```
web/index.html   The entire editor UI — HTML/CSS/JS in one file, no dependencies, no build step.
app/main.swift   Native shell: NSWindow + WKWebView, menus, file storage bridge.
app/Info.plist   Bundle metadata (id com.frankwhoee.paper, min macOS 11).
build.sh         swiftc → build/Paper.app; --install copies to /Applications.
```

Why this shape: a thin Swift wrapper over the system WebKit gives a small (few MB), fast-launching native app without Electron. Keep it dependency-free.

### Storage

- Documents are plain `.md` files in `~/Documents/Paper/`. The id is the filename stem (`YYYY-MM-DD-HHMMSS`, set at creation and never renamed). Titles are derived from the first non-empty line (a leading `#`, `>` or `-` is stripped).
- JS talks to Swift through `window.webkit.messageHandlers.paper.postMessage({op, ...})`, which returns a Promise (`WKScriptMessageHandlerWithReply`). Ops: `list`, `read`, `write`, `trash`, `getPref`, `setPref`. Prefs live in `UserDefaults` under `pref.<key>`; the current keys are `last` (the last open doc id) and `focus`.
- When `index.html` is opened in a plain browser (no bridge), it falls back to `localStorage` with the same API. This is handy for quick UI iteration: just open the file in a browser.
- Autosave runs 500ms after typing stops, and also on window blur, before unload, and on quit (`applicationShouldTerminate` awaits `window.paperFlush()` through `callAsyncJavaScript`).
- If you leave a document while it's empty, it is trashed. In the app, a trashed document goes to the macOS Trash.

### Editor rendering (the performance-sensitive part)

- A transparent `<textarea id="ed">` (only its caret is visible) sits exactly on top of `<div id="mirror">`, which draws the text. Both must keep **identical font, line-height, wrapping and padding**, or the caret drifts. The `#mirror, #ed` CSS rule is shared on purpose.
- The mirror has **one `div.l` per hard line**. On input, `syncLines()` diffs the old and new lines by common prefix/suffix and rebuilds only the changed lines. Only the caret's line is split into spans (`.dim` / `.cur` / `#caret`), and the previous caret line is restored from `el._t`. Benchmark: 52 keystrokes on a 275k-character document took ~250ms total, about 5ms per keystroke. Don't regress to re-rendering the whole document per keystroke.
- Focus mode is CSS only: `body.focus .dim { color: var(--dim) }`. With focus on, it also uses typewriter scrolling (caret kept at ~42% of the viewport height) and a larger top padding.
- Sentence detection is `sentenceRange(line, col)`. It works within a line; a sentence ends at `.`, `!`, `?` or `…` (plus any closing quotes/brackets) followed by whitespace. Decimals like `3.14` don't break a sentence.

### Views and keys (handled in JS)

| Key | Action |
|---|---|
| ⌘O | document list (type to filter titles, ↑/↓, Enter opens; Enter on a non-matching query creates a document titled with it; Esc goes back) |
| ⌘N | new document |
| ⌘. | toggle focus mode (persisted) |
| ⌘E | toggle rendered Markdown view (Esc, or typing any character, returns to editing) |
| ⌘I | word count and stats toast (words, characters, sentences, paragraphs, reading time; with a selection, its word count) |
| ⌘S | flush the save now |
| ⌘/ | shortcut hint toast |
| ⌘⌫ | in the list: delete the selected document (press twice to confirm) |

**Important:** don't add these as `NSMenu` key equivalents in Swift. Menu key equivalents swallow the keystroke before WebKit sees it. The Swift menu only defines standard items (Quit, Hide, Close, Undo/Redo/Cut/Copy/Paste/Select All, Full Screen, Minimize). The Edit menu has to exist for copy/paste/undo to work in WKWebView.

The Markdown renderer is a small hand-written one in `index.html` (`markdown()` / `inline()`): headings, emphasis, code, fenced blocks, lists, task lists, quotes, links, images and hr. It escapes HTML, and `javascript:`/`data:` URLs (other than images) are neutralised. Links in the rendered view open in the default browser via `decidePolicyFor`.

## Likely problems when you first build

- **Swift concurrency / SDK signature mismatches.** `AppDelegate` is `@MainActor`, and `build.sh` passes `-swift-version 5`. With newer SDKs the `WKScriptMessageHandlerWithReply` method may need `replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void`, and `decidePolicyFor`'s handler may need `@MainActor @Sendable`. Match whatever the compiler asks for.
- `callAsyncJavaScript(_:arguments:in:in:completionHandler:)` needs macOS 11+. The function body returns `true` so the result isn't nil.
- `web.setValue(false, forKey: "drawsBackground")` is private KVC. If it crashes, remove it, or use `web.underPageBackgroundColor` (macOS 12+).
- `Info.plist` names `CFBundleIconFile AppIcon`, but no icon exists yet. That's harmless, and `build.sh` copies `app/AppIcon.icns` if one is added. Frank may want an icon later.
- The first launch triggers the macOS "access Documents folder" prompt. That's expected.

## Verify

- The window opens with no visible chrome other than the transparent titlebar, and the colours follow light/dark mode.
- Typing shows the caret exactly where the text is, including on soft-wrapped lines and after emoji or CJK text. If it misaligns, check that the font metrics of the textarea and mirror are identical.
- ⌘Z/⇧⌘Z, copy/paste and ⌘A work in the editor. Tab inserts 4 spaces and undo still works afterwards.
- ⌘. fades everything except the current sentence, and moving the caret moves the highlight.
- ⌘E renders the Markdown; Esc returns to the same scroll position.
- ⌘O lists documents newest first, filtering works, and the files appear in `~/Documents/Paper`.
- Quitting right after typing doesn't lose text.
- Pasting a very long document (around 100k+ characters) keeps typing smooth.

## Conventions

- Keep `web/index.html` a single self-contained file: no frameworks, no CDN, no build step.
- The visual language is monospace, a warm off-white or near-black background, low-contrast faint UI text, and transient toasts instead of persistent UI.
- Ask Frank before adding visible UI elements.
