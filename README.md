# EpubReader

一个便携式的 EPUB 阅读 / 预览工具，绿色免安装。没有主界面——双击 EPUB 文件、把 EPUB 拖到程序上、或右键「打开方式」选择 EpubReader，即可直接阅读书籍内容。

- 单个 exe，无需安装 .NET 运行时（自包含）
- 支持 EPUB 2 / EPUB 3
- 自动解析目录（NCX / nav.xhtml），章节间切换
- 自动提取书籍并渲染，图片、样式正常显示
- 按阅读习惯注入排版样式（自动居中、合适的字号行距）
- 窗口与字号自动适应屏幕与内容显示大小（v1.1.0）
- 窗口高度自动适配章节内容长度，打开即整章尽收眼底（v1.2.0）
- 一键设为默认打开方式（v1.1.0）

## 版本

- **v1.2.0**：窗口高度自动适配当前章节内容（内容多高窗口多高，受限屏内，翻页自动跟随；手动调整窗口后自动停用）。
- **v1.1.0**：界面自动适应内容显示大小（窗口按屏幕自动开合、字号随窗口缩放、记住上次窗口大小）；新增「设为默认打开方式」按钮；程序登记到 Windows「默认应用」列表。
- **v1.0.0**：首个版本，基础阅读与预览能力。

## 使用方法

### 方式一：直接打开

把 `.epub` 文件拖到 `EpubReader.exe` 上，或双击已关联的 EPUB 文件。

### 方式二：命令行

```powershell
(应用包名) 书籍.epub
```

### 方式三：设置为默认打开方式（一键）

点击阅读窗口工具栏上的「设为默认打开方式」
之后双击任意 `.epub` 文件都会默认用 EpubReader 打开。该操作只写入当前用户的注册表，无需管理员权限；同时 EpubReader 会出现在「设置 → 默认应用」的列表中，可随时在系统设置里改回其它程序。

### 方式四：双击程序本身

双击 exe（不带参数）会弹出文件选择框，选择 EPUB 后阅读。

## 阅读操作

| 操作 | 功能 |
| --- | --- |
| `←` / `PageUp` | 上一章 |
| `→` / `PageDown` | 下一章 |
| 工具栏下拉框 | 跳转到任意章节 |
| 拖入新 EPUB | 打开另一本书（新窗口） |
| 窗口缩放 | 正文版心与字号自动适应窗口宽度 |
| 翻页 | 窗口高度自动跟随章节内容长度（未手动调整窗口时） |
| `Esc` | 关闭窗口 |

## 自检模式

```powershell
EpubReader.exe --selftest 书籍.epub
```

输出书籍元信息、章节数与目录，用于排查解析问题。

## 从源码构建

需要 [.NET SDK 8](https://dotnet.microsoft.com/download)。

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o out
```

产物：`out\EpubReader.exe`（约 160 MB，绿色单文件，64 位 Windows 通用）。

## 原理

1. EPUB 本质是 ZIP：解析 `META-INF/container.xml` 找到 OPF 清单。
2. 读取 OPF 的 `manifest` 与 `spine`，得到章节文件顺序。
3. 解析 `toc.ncx`（EPUB 2）或 `nav.xhtml`（EPUB 3）生成目录。
4. 解压整本书到临时目录，用内嵌浏览器按 `file://` 渲染，图片与样式自动生效。
5. 文件关联：写入 `HKCU\Software\Classes\.epub`（每用户默认关联）+ 能力声明，Explorer 会优先按此打开 `.epub`，并在系统「默认应用」中列出 EpubReader。

## 许可证

[GPL](LICENSE)
