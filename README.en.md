# EpubReader

[中文](README.md) | English

A portable EPUB reading / preview tool. No installer needed — just double-click an EPUB file, drag it onto the program, or right-click "Open with" to start reading.

> **Since v26.1.0-alpha the app has been rebuilt from C#/WinForms to Flutter + Material Design 3**: a full MD3 component system (dynamic color, menus, dialogs, progress indicator), light/dark themes following the system, with serif reading typography preserved. This is a preview release; the legacy C# implementation remains at the repository root.

- Single program bundle, no runtime installation required
- Supports EPUB 2 / EPUB 3
- Auto-parses table of contents (NCX / nav.xhtml), chapter navigation
- Pure Flutter-native chapter rendering (headings/paragraphs/quotes/lists/tables/code blocks/images), no WebView involved
- Material Design 3 interface, light/dark theme follows the system (v26.1.0-alpha)
- Serif reading typography; font size auto-scales with window width (v26.1.0-alpha)
- Window height auto-fits chapter content and follows late-loading images (since v1.2.0, kept in v26.1.0-alpha)
- Selectable/copyable text, tappable in-book and external links (v26.1.0-alpha)
- One-click set as default opener (v1.1.0)
- Keyboard: `←`/`→`/`PageUp`/`PageDown` for chapters, `Ctrl+O` to open, `Esc` to close

## Changelog

- **v26.1.0-alpha**: Flutter + Material Design 3 rebuild preview. Brand-new MD3 interface (dynamic color seed, light/dark themes, componentized menus/dialogs/progress bar); chapter content now renders natively in Flutter (no embedded browser) with text selection/copy and in-book anchor jumps; keeps existing features — window height auto-fit, width-adaptive font size, remembered window bounds, one-click file association.
- **v26.0.1**: Stable release (C#/WinForms). Consolidates all improvements since v26.0.0-beta — E-Ink/Paper interface, content fitting the window exactly and following late-loading images, toolbar blended into the page.
- **v26.0.1-beta3**: Fixed content overflowing the window — exact document-height measurement with auto-converging refit (window stays in sync with async-loaded images); box-sizing on code blocks/quotes prevents horizontal overflow, long words wrap; removed the divider between toolbar and content so the UI blends into the page.
- **v26.0.1-beta.2**: Full UI redesign in E-Ink/Paper style — paper-white background, ink-black text, zero animation, high contrast; toolbar replaced by a self-drawn minimal header (chapter nav, TOC dropdown, chapter title, position indicator); reading typography upgraded (serif body, underlined links, paper-styled quotes/code/tables); hover feedback and keyboard focus rings on all buttons, tooltips everywhere, accessibility improvements.
- **v26.0.0-beta**: Content always auto-adapts to window size — height remains auto-fitted even after manual resize, window and content always stay in perfect sync.
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

Click "Set as default opener" (pin icon) in the header bar.
After that, double-clicking any `.epub` file will open it with EpubReader. This only writes to the current user's registry (no admin rights needed). EpubReader will also appear in Settings → Default Apps, where you can switch back anytime.

### Option 4: Double-click the Program

Double-click the exe (no arguments) to open a file picker, then select an EPUB to read.

## Reading Controls

| Action | Function |
| --- | --- |
| `←` / `PageUp` | Previous chapter |
| `→` / `PageDown` | Next chapter |
| "TOC" menu in the header | Jump to any chapter |
| Drag in a new EPUB | Opens another book in the same window |
| `Ctrl+O` | Open another EPUB file |
| Resize window | Content width & font auto-adapt |
| Page turn | Window height auto-follows chapter length (disabled after manual resize) |
| Select text with mouse | Copy body text |
| `Esc` | Close window |

## Build from Source

### Flutter version (v26.1.0-alpha onwards, the main version)

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (stable channel with Windows desktop support) and Visual Studio with the "Desktop development with C++" workload.

```powershell
cd flutter
flutter test
flutter build windows --release
```

Output is in `flutter\build\windows\x64\runner\Release\` (`EpubReader.exe` + runtime files).

> If your repository disk is exFAT (no symlink support) and you have no admin rights, use the staged build script shipped in the repo (stages the project to drive C, copies artifacts back to out\):
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1
> ```
>
> You can also just push to GitHub and let the Actions workflow (`.github/workflows/build.yml`) build on `windows-latest`.

### Legacy C# version (v26.0.1)

Requires [.NET SDK 8](https://dotnet.microsoft.com/download).

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o out
```

Output: `out\EpubReader.exe` (~160 MB, portable single file, 64-bit Windows).

## License

[GPL](LICENSE)
