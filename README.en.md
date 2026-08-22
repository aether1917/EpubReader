# EpubReader

[中文](README.md) | English

A portable EPUB reading / preview tool. No installer needed — just double-click an EPUB file, drag it onto the program, or right-click "Open with" to start reading.

- Single exe, no .NET runtime required (self-contained)
- Supports EPUB 2 / EPUB 3
- Auto-parses table of contents (NCX / nav.xhtml), chapter navigation
- Extracts and renders books with images and styles intact
- Injects reading-friendly typography (centered layout, optimized font size & line height)
- Window and font size auto-adapt to screen and content (v1.1.0)
- Window height auto-fits chapter content length (v1.2.0)
- Content always auto-adapts to window size, even after manual resize (v26.3)
- E-Ink/Paper style interface and reading typography (v26.4.0beta)
- Content fits the window exactly; window follows late-loading images (v26.4.1beta)
- One-click set as default opener (v1.1.0)

## Changelog

- **v26.0.1**: Stable release. Consolidates all improvements since v26.0.0-beta — E-Ink/Paper interface, content fitting the window exactly and following late-loading images, toolbar blended into the page.
- **v26.4.1beta**: Fixed content overflowing the window — exact document-height measurement with auto-converging refit (window stays in sync with async-loaded images); box-sizing on code blocks/quotes prevents horizontal overflow, long words wrap; removed the divider between toolbar and content so the UI blends into the page.
- **v26.4.0beta**: Full UI redesign in E-Ink/Paper style — paper-white background, ink-black text, zero animation, high contrast; toolbar replaced by a self-drawn minimal header (chapter nav, TOC dropdown, chapter title, position indicator); reading typography upgraded (serif body, underlined links, paper-styled quotes/code/tables); hover feedback and keyboard focus rings on all buttons, tooltips everywhere, accessibility improvements.
- **v26.3.1beta**: Content always auto-adapts to window size — height remains auto-fitted even after manual resize, window and content always stay in perfect sync.
- **v1.2.0**: Window height auto-fits current chapter content (content height = window height, capped at screen; auto-follows on page turn; disabled after manual resize).
- **v1.1.0**: Adaptive UI (window auto-sizes to screen, font scales with window, remembers last size); added "Set as default opener" button; registered in Windows "Default apps" list.
- **v1.0.0**: First release with basic reading and preview.

## Usage

### Option 1: Direct Open

Drag an `.epub` file onto `EpubReader.exe`, or double-click an associated EPUB file.

### Option 2: Command Line

```powershell
EpubReader.exe book.epub
```

### Option 3: Set as Default Opener (One-click)

Click "Set as default opener" in the toolbar.
After that, double-clicking any `.epub` file will open it with EpubReader. This only writes to the current user's registry (no admin rights needed). EpubReader will also appear in Settings → Default Apps, where you can switch back anytime.

### Option 4: Double-click the Program

Double-click the exe (no arguments) to open a file picker, then select an EPUB to read.

## Reading Controls

| Action | Function |
| --- | --- |
| `←` / `PageUp` | Previous chapter |
| `→` / `PageDown` | Next chapter |
| Toolbar dropdown | Jump to any chapter |
| Drag in a new EPUB | Open another book (new window) |
| Resize window | Content width & font auto-adapt |
| Page turn | Window height auto-follows chapter length |
| `Esc` | Close window |

## Build from Source

Requires [.NET SDK 8](https://dotnet.microsoft.com/download).

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o out
```

Output: `out\EpubReader.exe` (~160 MB, portable single file, 64-bit Windows).

## License

[GPL](LICENSE)
