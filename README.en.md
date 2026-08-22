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
- One-click set as default opener (v1.1.0)

## Changelog

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
