using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace EpubReader;

public sealed class ReaderForm : Form
{
    // ——— E-Ink / Paper 设计体系 ———
    // 纸面白、墨黑、铅笔灰，零动画、高对比，界面细节只留极简描边。
    private static readonly Color Paper = Color.FromArgb(0xFD, 0xFB, 0xF7);   // 纸面
    private static readonly Color Ink = Color.FromArgb(0x1A, 0x1A, 0x1A);     // 墨色
    private static readonly Color Pencil = Color.FromArgb(0x4A, 0x4A, 0x4A);  // 铅笔灰（二级文字）
    private static readonly Color Border = Color.FromArgb(0xE0, 0xE0, 0xE0);  // 细描边
    private static readonly Color Hover = Color.FromArgb(0xF4, 0xF1, 0xE9);   // 悬停纸色
    private static readonly Color Pressed = Color.FromArgb(0xEA, 0xE6, 0xDB); // 按下纸色
    private static readonly Color DisabledText = Color.FromArgb(0x9C, 0x98, 0x90);

    private const int HeaderHeight = 46;
    private const int CtrlHeight = 32;
    private static readonly Font UiFont = new("Segoe UI", 9.5f);
    private static readonly Font ChevronFont = new("Segoe UI", 16f);

    private readonly EpubBook _book;
    private readonly List<string> _spine;
    private readonly List<TocEntry> _toc;
    private int _index = -1;
    private bool _syncingToc;
    private HtmlElement? _styleEl;
    private readonly System.Windows.Forms.Timer _resizeTimer;
    private readonly System.Windows.Forms.Timer _fitTimer = new() { Interval = 300 };
    private int _lastMeasuredH = -1;
    private int _fitPolls;
    private readonly Panel _header;
    private bool _applyingAutoFit;

    private readonly WebBrowser _browser = new()
    {
        Dock = DockStyle.Fill,
        ScriptErrorsSuppressed = true
    };

    private readonly PaperButton _btnPrev;
    private readonly PaperButton _btnNext;
    private readonly ComboBox _tocBox;
    private readonly Label _titleLabel;
    private readonly Label _posLabel;
    private readonly PaperButton _btnOpen;
    private readonly PaperButton _btnDefault;
    private readonly ToolTip _tip = new()
    {
        InitialDelay = 350,
        ReshowDelay = 100,
        ShowAlways = true,
        UseAnimation = false,
        UseFading = false
    };

    public ReaderForm(string epubPath)
    {
        _book = new EpubBook(epubPath);
        _spine = new List<string>(_book.SpineItems);
        _toc = new List<TocEntry>(_book.Toc);

        Text = "EpubReader — " + Path.GetFileName(epubPath);
        StartPosition = FormStartPosition.Manual;
        BackColor = Paper;
        ForeColor = Ink;
        Font = UiFont;
        ApplySavedBounds();
        AllowDrop = true;
        KeyPreview = true;
        _browser.BackColor = Paper;

        _btnPrev = new PaperButton { Text = "‹", Width = 34, Padding = new Padding(0), Font = ChevronFont };
        _btnPrev.AccessibleName = "上一章";
        _btnPrev.AccessibleDescription = "跳转到上一章";
        _btnPrev.Enabled = false;
        _btnPrev.Click += (_, _) => Go(_index - 1);

        _btnNext = new PaperButton { Text = "›", Width = 34, Padding = new Padding(0), Font = ChevronFont };
        _btnNext.AccessibleName = "下一章";
        _btnNext.AccessibleDescription = "跳转到下一章";
        _btnNext.Enabled = false;
        _btnNext.Click += (_, _) => Go(_index + 1);

        _tocBox = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            FlatStyle = FlatStyle.Flat,
            BackColor = Paper,
            ForeColor = Ink,
            Font = UiFont,
            Width = 300,
            DropDownHeight = 320,
            IntegralHeight = false
        };
        _tocBox.SelectedIndexChanged += OnTocSelected;

        _titleLabel = new Label
        {
            Text = "",
            AutoSize = false,
            AutoEllipsis = true,
            TextAlign = ContentAlignment.MiddleRight,
            ForeColor = Pencil,
            Font = UiFont,
            UseMnemonic = false
        };

        _posLabel = new Label
        {
            Text = "",
            AutoSize = true,
            TextAlign = ContentAlignment.MiddleCenter,
            ForeColor = Pencil,
            Font = UiFont,
            UseMnemonic = false
        };

        _btnOpen = new PaperButton { Text = "打开…", Width = 72 };
        _btnOpen.Click += (_, _) => OpenAnother();

        _btnDefault = new PaperButton { Text = "设为默认打开方式", Width = 152 };
        _btnDefault.Click += (_, _) =>
        {
            var msg = FileAssociation.SetAsDefault();
            var goSettings = MessageBox.Show(this, msg + "\n\n是否打开系统「默认应用」设置页确认？",
                "默认打开方式", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (goSettings == DialogResult.Yes)
                FileAssociation.OpenDefaultAppsSettings();
        };

        _tip.SetToolTip(_btnPrev, "上一章（← / PageUp）");
        _tip.SetToolTip(_btnNext, "下一章（→ / PageDown）");
        _tip.SetToolTip(_tocBox, "目录：选择章节跳转");
        _tip.SetToolTip(_btnOpen, "打开其他 EPUB 文件");
        _tip.SetToolTip(_btnDefault, "将 EpubReader 设为 .epub 文件的默认打开方式");

        _header = new Panel
        {
            Dock = DockStyle.Top,
            Height = HeaderHeight,
            BackColor = Paper
        };
        _header.Resize += (_, _) => LayoutHeader();
        _header.Controls.AddRange(new Control[]
        {
            _btnPrev, _btnNext, _tocBox, _titleLabel, _posLabel, _btnOpen, _btnDefault
        });

        Controls.Add(_browser);
        Controls.Add(_header);

        _browser.DocumentCompleted += OnDocumentCompleted;
        DragEnter += OnDragEnter;
        DragDrop += OnDragDrop;
        KeyDown += OnKeyDown;

        // 窗口尺寸变化时，自动调整内容的字号与版心宽度（防抖）
        _resizeTimer = new System.Windows.Forms.Timer { Interval = 200 };
        _resizeTimer.Tick += (_, _) =>
        {
            _resizeTimer.Stop();
            UpdateContentCss();
            AutoFitToContent();
        };
        Resize += (_, _) => _resizeTimer.Start();

        // 内容加载完成后收敛轮询：图片等异步资源就位、或滚动条消失引起回流时，
        // 窗口高度持续贴合内容，直到测量值稳定（或达到轮询上限）。
        _fitTimer.Tick += (_, _) =>
        {
            _fitTimer.Stop();
            var h = MeasureContentHeight();
            if (h <= 0 || h == _lastMeasuredH) return;
            _lastMeasuredH = h;
            AutoFitToContent();
            if (++_fitPolls < 20) _fitTimer.Start();
        };

        Load += (_, _) =>
        {
            LayoutHeader();
            BuildTocMenu();
            if (_spine.Count > 0) Go(0);
        };
    }

    private static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "EpubReader", "settings.ini");

    private void ApplySavedBounds()
    {
        var area = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1600, 900);
        var w = Math.Max(800, (int)(area.Width * 0.7));
        var h = Math.Max(600, (int)(area.Height * 0.8));
        var bounds = new Rectangle(
            area.X + (area.Width - w) / 2,
            area.Y + (area.Height - h) / 2, w, h);

        var saved = LoadBounds();
        if (saved.HasValue && IsOnScreen(saved.Value))
            bounds = saved.Value;

        Bounds = bounds;
    }

    private static Rectangle? LoadBounds()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return null;
            var lines = File.ReadAllLines(SettingsPath);
            int Get(string key) => lines
                .Where(l => l.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase))
                .Select(l => int.TryParse(l.Substring(key.Length + 1), out var v) ? v : -1)
                .FirstOrDefault(v => v >= 0);

            var x = Get("x");
            var y = Get("y");
            var w = Get("width");
            var h = Get("height");
            if (x < 0 || y < 0 || w < 0 || h < 0) return null;
            return new Rectangle(x, y, w, h);
        }
        catch
        {
            return null;
        }
    }

    private static bool IsOnScreen(Rectangle r)
    {
        foreach (var s in Screen.AllScreens)
        {
            if (s.WorkingArea.IntersectsWith(r)) return true;
        }
        return false;
    }

    private void SaveBounds()
    {
        try
        {
            if (WindowState != FormWindowState.Normal) return;
            var dir = Path.GetDirectoryName(SettingsPath);
            if (string.IsNullOrEmpty(dir)) return;
            Directory.CreateDirectory(dir);
            File.WriteAllLines(SettingsPath, new[]
            {
                "x=" + Bounds.X,
                "y=" + Bounds.Y,
                "width=" + Bounds.Width,
                "height=" + Bounds.Height
            });
        }
        catch
        {
            // 保存失败不影响阅读
        }
    }

    /// <summary>顶栏布局：左侧章节导航，右侧章节名与操作，全部采用纸面/墨色。</summary>
    private void LayoutHeader()
    {
        var w = _header.ClientSize.Width;
        var y = (HeaderHeight - CtrlHeight) / 2;

        var right = w - 10;
        PlaceRight(_btnDefault, ref right, y);
        PlaceRight(_btnOpen, ref right, y);
        PlaceRight(_posLabel, ref right, y + (CtrlHeight - _posLabel.Height) / 2);

        const int gap = 4;
        var left = 10;
        _btnPrev.SetBounds(left, y, 34, CtrlHeight);
        _btnNext.SetBounds(left + 34 + gap, y, 34, CtrlHeight);
        _tocBox.SetBounds(left + 34 + gap + 34 + gap, y + 4, 300, _tocBox.Height);

        var titleLeft = left + 34 + gap + 34 + gap + 300 + 20;
        var titleRight = Math.Max(_posLabel.Left - 16, titleLeft);
        _titleLabel.SetBounds(titleLeft, 0, titleRight - titleLeft, _header.ClientSize.Height);
    }

    private static void PlaceRight(Control c, ref int right, int y)
    {
        c.SetBounds(right - c.Width, y, c.Width, c.Height);
        right -= c.Width + 8;
    }

    /// <summary>根据当前窗口宽度生成自适应排版样式：纸面配色、衬线正文、字号随窗口缩放。</summary>
    private string BuildReadingCss()
    {
        var size = Math.Clamp(12 + ClientSize.Width / 110, 14, 26);
        return $@"
            html,body{{margin:0;padding:0;}}
            html{{background:#FDFBF7;}}
            body{{max-width:calc(100% - 48px);margin:0 auto!important;padding:28px 36px;line-height:1.9;
                 font-family:Georgia,'Times New Roman','Songti SC','SimSun',serif;font-size:{size}px;color:#1A1A1A;background:#FDFBF7;
                 word-wrap:break-word;}}
            h1,h2,h3,h4{{margin:1.2em 0 .6em;line-height:1.35;color:#1A1A1A;}}
            a{{color:#1A1A1A;text-decoration:underline;}}
            a:hover{{color:#4A4A4A;}}
            img,svg,video,iframe{{max-width:100%;height:auto;}}
            pre{{box-sizing:border-box;white-space:pre-wrap;word-wrap:break-word;background:#F5F2EA;padding:12px 16px;}}
            pre code{{background:transparent;padding:0;}}
            code{{background:#F5F2EA;padding:1px 5px;}}
            blockquote{{box-sizing:border-box;margin:1em 0;padding:.2em 0 .2em 16px;border-left:3px solid #D8D2C4;color:#4A4A4A;}}
            hr{{border:none;border-top:1px solid #D8D2C4;margin:1.6em 0;}}
            table{{max-width:100%;border-collapse:collapse;}}
            th,td{{box-sizing:border-box;padding:6px 10px;border:1px solid #E0E0E0;}}
            ::selection{{background:#EDE7D8;}}
        ";
    }

    private void UpdateContentCss()
    {
        try
        {
            if (_styleEl == null) return;
            _styleEl.InnerText = BuildReadingCss();
        }
        catch
        {
            // 页面未就绪时忽略
        }
    }

    private void BuildTocMenu()
    {
        _syncingToc = true;
        _tocBox.Items.Clear();
        if (_toc.Count == 0)
        {
            _tocBox.Items.Add("（无目录）");
        }
        else
        {
            foreach (var t in _toc)
                _tocBox.Items.Add(new string('\u3000', t.Level) + t.Title);
        }
        _tocBox.SelectedIndex = -1;
        _syncingToc = false;
    }

    private void Go(int index)
    {
        if (index < 0 || index >= _spine.Count) return;
        _index = index;
        _btnPrev.Enabled = index > 0;
        _btnNext.Enabled = index < _spine.Count - 1;
        _posLabel.Text = $"{_index + 1} / {_spine.Count}";
        LayoutHeader();
        _browser.Navigate(new Uri(_book.GetContentPath(_spine[index])));
        SyncTocSelection();
    }

    private void NavigateTo(string href)
    {
        var plain = href.Split('#')[0];
        var i = _spine.FindIndex(s => string.Equals(s, plain, StringComparison.OrdinalIgnoreCase));
        if (i >= 0) _index = i;
        _posLabel.Text = $"{_index + 1} / {_spine.Count}";
        LayoutHeader();
        _browser.Navigate(new Uri(_book.GetContentPath(href.Replace('/', Path.DirectorySeparatorChar))));
        SyncTocSelection();
    }

    private void SyncTocSelection()
    {
        if (_toc.Count == 0 || _index < 0) return;
        var current = _spine[_index];
        var i = _toc.FindIndex(t =>
            string.Equals(t.Href.Split('#')[0], current, StringComparison.OrdinalIgnoreCase));
        _syncingToc = true;
        _tocBox.SelectedIndex = i >= 0 ? i : -1;
        _syncingToc = false;
    }

    private void OnTocSelected(object? sender, EventArgs e)
    {
        if (_syncingToc || _tocBox.SelectedIndex < 0 || _tocBox.SelectedIndex >= _toc.Count) return;
        NavigateTo(_toc[_tocBox.SelectedIndex].Href);
    }

    private void OnDocumentCompleted(object? sender, WebBrowserDocumentCompletedEventArgs e)
    {
        try
        {
            if (_browser.Url == null || e.Url == null) return;
            if (e.Url.ToString() != _browser.Url.ToString()) return;

            var current = _index >= 0 ? _spine[_index] : "";
            var tocTitle = _toc.FirstOrDefault(t =>
                string.Equals(t.Href.Split('#')[0], current, StringComparison.OrdinalIgnoreCase))?.Title;
            _titleLabel.Text = tocTitle ?? Path.GetFileName(current);
            LayoutHeader();

            var doc = _browser.Document;
            if (doc == null) return;
            var style = doc.CreateElement("style")!;
            style.SetAttribute("type", "text/css");
            style.InnerText = BuildReadingCss();

            HtmlElement? head = null;
            foreach (HtmlElement el in doc.All)
            {
                if (el.TagName.Equals("HEAD", StringComparison.OrdinalIgnoreCase))
                {
                    head = el;
                    break;
                }
            }
            var target = head ?? doc.Body?.Parent ?? doc.Body;
            target?.AppendChild(style);
            _styleEl = style;

            _lastMeasuredH = -1;
            _fitPolls = 0;
            AutoFitToContent();
            _fitTimer.Start();
        }
        catch
        {
            // 忽略渲染期异常
        }
    }

    /// <summary>
    /// 让窗口高度自动适配当前章节的内容高度，内容恰好完整显示：
    /// 内容多高，窗口就多高（受限屏内），图片等异步资源加载后自动跟随；用户手动调整过窗口后自动停用。
    /// </summary>
    private void AutoFitToContent()
    {
        if (_applyingAutoFit) return;
        try
        {
            var contentH = MeasureContentHeight();
            if (contentH <= 0) return;

            var area = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1600, 900);
            var titleBar = Height - ClientSize.Height; // 标题栏 + 边框高度
            var desiredH = contentH + titleBar + _browser.Top + 24; // 24px 底部留白
            desiredH = Math.Clamp(desiredH, 480, area.Height);

            if (Math.Abs(desiredH - Height) < 8) return; // 尺寸接近时不再抖动

            _applyingAutoFit = true;
            try
            {
                var y = Top;
                if (y + desiredH > area.Bottom) y = Math.Max(area.Top, area.Bottom - desiredH);
                SetBounds(Left, y, Width, (int)desiredH);
            }
            finally
            {
                _applyingAutoFit = false;
            }
        }
        catch
        {
            // 自动适配失败时忽略，保持现状
        }
    }

    /// <summary>
    /// 精确测量整页内容高度（含 body 内边距与图片等异步资源），
    /// 取文档根元素 / body 滚动高度 / body 盒模型底边的最大值。
    /// </summary>
    private int MeasureContentHeight()
    {
        try
        {
            var doc = _browser.Document;
            if (doc == null) return 0;
            var result = doc.InvokeScript("eval", new object[]
            {
                "Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, " +
                "Math.ceil(document.body.getBoundingClientRect().bottom + document.documentElement.scrollTop))"
            });
            if (result != null &&
                int.TryParse(Convert.ToString(result, System.Globalization.CultureInfo.InvariantCulture), out var h))
                return h;
        }
        catch
        {
            // 脚本不可用时回退到 DOM 测量
        }
        return _browser.Document?.Body?.ScrollRectangle.Height ?? 0;
    }

    private void OpenAnother()
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "EPUB 文件 (*.epub)|*.epub|所有文件 (*.*)|*.*",
            Title = "打开 EPUB 文件"
        };
        if (ofd.ShowDialog(this) == DialogResult.OK)
            new ReaderForm(ofd.FileName).Show();
    }

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        e.Effect = e.Data?.GetDataPresent(DataFormats.FileDrop) == true
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private void OnDragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(DataFormats.FileDrop) is not string[] files) return;
        foreach (var f in files)
        {
            if (Path.GetExtension(f).Equals(".epub", StringComparison.OrdinalIgnoreCase))
                new ReaderForm(f).Show();
        }
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        switch (e.KeyCode)
        {
            case Keys.Left:
            case Keys.PageUp:
                Go(_index - 1);
                e.Handled = true;
                break;
            case Keys.Right:
            case Keys.PageDown:
                Go(_index + 1);
                e.Handled = true;
                break;
            case Keys.Escape:
                Close();
                e.Handled = true;
                break;
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _resizeTimer.Dispose();
        _fitTimer.Dispose();
        _tip.Dispose();
        SaveBounds();
        _book.Dispose();
        base.OnFormClosed(e);
    }

    /// <summary>纸面风格扁平按钮：悬停/按下变色、键盘焦点虚线圈、禁用态灰字。</summary>
    private sealed class PaperButton : Button
    {
        internal PaperButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 1;
            FlatAppearance.BorderColor = Border;
            FlatAppearance.MouseOverBackColor = Hover;
            FlatAppearance.MouseDownBackColor = Pressed;
            BackColor = Paper;
            ForeColor = Ink;
            Cursor = Cursors.Hand;
            Height = CtrlHeight;
            UseVisualStyleBackColor = false;
            Font = UiFont;
            TextAlign = ContentAlignment.MiddleCenter;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (!Enabled)
            {
                using var bg = new SolidBrush(BackColor);
                e.Graphics.FillRectangle(bg, ClientRectangle);
                using var pen = new Pen(Border);
                e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
                TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, DisabledText,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                return;
            }

            base.OnPaint(e);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics,
                    new Rectangle(3, 3, Width - 7, Height - 7), Ink, Color.Transparent);
        }
    }
}
