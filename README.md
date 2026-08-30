# EpubReader

[中文](README.md) | [English](README.en.md)

一个便携式的 EPUB 阅读 / 预览工具，绿色免安装。没有主界面——双击 EPUB 文件、把 EPUB 拖到程序上、或右键「打开方式」选择 EpubReader，即可直接阅读书籍内容。

> **自 v26.1.0-alpha 起由 C#/WinForms 重构为 Flutter + Material Design 3，v26.1.0 转正为稳定版**：全新 MD3 组件体系（动态配色、菜单、对话框、进度指示），浅色 / 深色主题跟随系统，正文保留衬线书卷排版。旧版 C# 实现保留在仓库根目录。

- 单一程序包，无需安装任何运行时
- 支持 EPUB 2 / EPUB 3
- 自动解析目录（NCX / nav.xhtml），章节间切换
- 纯 Flutter 原生渲染章节内容（标题/段落/引用/列表/表格/代码块/图片），不依赖 WebView
- Material Design 3 界面，浅色 / 深色主题跟随系统（v26.1.0）
- 性能优化：章节渲染缓存、图片按显示尺寸解码、下一章后台预解析、窗口尺寸事件驱动（v26.1.0）
- 正文衬线排版，字号随窗口宽度自动适配（v26.1.0-alpha）
- 窗口高度自动适配章节内容长度，图片加载后自动跟随（v1.2.0 起，v26.1.0-alpha 保留）
- 内容可选中复制，文内链接与外部链接可点击（v26.1.0-alpha）
- 一键设为默认打开方式（v1.1.0）
- 键盘操作：`←`/`→`/`PageUp`/`PageDown` 翻章，`Ctrl+O` 打开，`Esc` 关闭

## 版本

- **v26.1.0**：稳定版。整合 v26.1.0-alpha 系列全部改进（MD3 界面、纯原生渲染、封面修复），并完成一轮性能优化——章节渲染缓存（窗口缩放/主题切换/翻回上一章不再重复读盘解析构树）、图片按显示尺寸解码（长图/大封面内存占用大幅下降）、翻页时下一章后台预解析、窗口尺寸监听改事件驱动（移除常驻轮询定时器）、滚动重绘隔离。
- **v26.1.0-alpha.1**：修复封面无法正常显示——`<svg><image xlink:href="…"/></svg>` 结构的封面图现可正确渲染（`package:html` 命名空间属性键问题）；顺带修复 nav.xhtml 目录 `epub:type` 识别。
- **v26.1.0-alpha**：Flutter + Material Design 3 重构预览版。全新 MD3 界面（动态配色种子、浅色/深色主题、菜单/对话框/进度条组件化）；章节内容改为纯 Flutter 原生渲染（不再内嵌浏览器），支持文本选中复制、文内锚点跳转；保留窗口高度自适应内容、字号随宽度适配、记忆窗口位置、一键文件关联等既有特性。
- **v26.0.1**：稳定版（C#/WinForms）。整合 v26.0.0-beta 以来的全部改进——纸墨风格界面，内容恰好完整显示于窗口、图片加载后窗口自动跟随，顶栏与正文融为一体。
- **v26.0.1-beta3**：修复内容溢出窗口的问题——正文测量改用精确的文档高度并自动收敛（图片等异步资源加载后窗口自动贴合）；代码块/引用块改用边框盒防止横向溢出，超长单词自动换行；移除顶栏与内容区之间的分割线，界面与正文融为一体。
- **v26.0.1-beta.2**：界面整体重绘为「纸墨」风格——纸面白底、墨黑文字、零动画高对比；工具栏改为自绘极简头部（章节导航、目录下拉、章节名、进度提示）；正文排版同步升级（衬线正文、下划线链接、引用/代码/表格纸张化样式）；所有按钮带悬停反馈与键盘焦点圈，全控件提示气泡，无障碍优化。
- **v26.0.0-beta**：内容始终自动适应窗口大小——手动调整窗口后仍保持高度自适应，窗口与内容始终保持最佳匹配。
- **v1.2.0**：窗口高度自动适配当前章节内容（内容多高窗口多高，受限屏内，翻页自动跟随；手动调整窗口后自动停用）。
- **v1.1.0**：界面自动适应内容显示大小（窗口按屏幕自动开合、字号随窗口缩放、记住上次窗口大小）；新增「设为默认打开方式」按钮；程序登记到 Windows「默认应用」列表。
- **v1.0.0**：首个版本，基础阅读与预览能力。

## 使用方法

### 方式一：直接打开

把 `.epub` 文件拖到 `EpubReader.exe` 上，或双击已关联的 EPUB 文件。

### 方式二：命令行

```powershell
EpubReader.exe 书籍.epub
```

### 方式三：设置为默认打开方式（一键）

点击阅读窗口顶栏的「设为默认打开方式」（图钉图标）。
之后双击任意 `.epub` 文件都会默认用 EpubReader 打开。该操作只写入当前用户的注册表，无需管理员权限；同时 EpubReader 会出现在「设置 → 默认应用」的列表中，可随时在系统设置里改回其它程序。

### 方式四：双击程序本身

双击 exe（不带参数）会弹出文件选择框，选择 EPUB 后阅读。

## 阅读操作

| 操作 | 功能 |
| --- | --- |
| `←` / `PageUp` | 上一章 |
| `→` / `PageDown` | 下一章 |
| 顶栏「目录」菜单 | 跳转到任意章节 |
| 拖入新 EPUB | 在当前窗口打开另一本书 |
| `Ctrl+O` | 打开其他 EPUB 文件 |
| 窗口缩放 | 正文版心与字号自动适应窗口宽度 |
| 翻页 | 窗口高度自动跟随章节内容长度（手动调整窗口后停用） |
| 鼠标选中文本 | 复制正文内容 |
| `Esc` | 关闭窗口 |

## 从源码构建

### Flutter 版（v26.1.0-alpha 起，主版本）

需要 [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)（stable 通道，含 Windows 桌面支持）与 Visual Studio「使用 C++ 的桌面开发」工作负载。

```powershell
cd flutter
flutter test
flutter build windows --release
```

产物在 `flutter\build\windows\x64\runner\Release\`（`EpubReader.exe` + 运行时文件）。

> 仓库磁盘若为 exFAT（不支持符号链接）且无管理员权限，可用仓库自带的暂存构建脚本（把项目暂存到 C 盘构建，产物拷回 out\）：
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1
> ```
>
> 也可以直接推送到 GitHub，由 Actions 工作流（`.github/workflows/build.yml`）在 `windows-latest` 上构建。

### C# 旧版（v26.0.1）

需要 [.NET SDK 8](https://dotnet.microsoft.com/download)。

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o out
```

产物：`out\EpubReader.exe`（约 160 MB，绿色单文件，64 位 Windows 通用）。

## 许可证

[GPL](LICENSE)
