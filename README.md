# paper

A minimalist writing app for macOS. Just your text and a cursor.

- Monospace, spacious, nothing on screen but the words
- Write in Markdown; it stays plain text until you ask to see it rendered
- Focus mode fades everything except the sentence you're writing
- Every document is a plain `.md` file in `~/Documents/Paper`

## Build

Requires macOS 11+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh --install     # builds and copies Paper.app to /Applications
```

Or `./build.sh` and open `build/Paper.app`.

## Keys

| Key   | Action                                 |
|-------|----------------------------------------|
| ⌘O    | documents — type to filter, ↑↓, Enter  |
| ⌘N    | new document                           |
| ⌘.    | focus mode                             |
| ⌘E    | render markdown (Esc or type to return)|
| ⌘S    | save now (it also saves as you type)   |
| ⌘/    | show shortcuts                         |
| ⌘⌫    | in the document list: delete (press twice; goes to Trash) |

In the document list, typing a name that doesn't exist and pressing Enter starts a new document with that title.

**File → Show Documents Folder** opens `~/Documents/Paper` in Finder. Any `.md` file you drop there shows up in the list.

## Layout

```
web/index.html   the editor (also runs in a plain browser, saving to localStorage)
app/main.swift   native shell: window, menus, file storage
app/Info.plist
build.sh
```
