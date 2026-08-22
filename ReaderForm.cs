using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace EpubReader;

public sealed class ReaderForm : Form
{
    private readonly EpubBook _book;
    private readonly List<string> _spine;
    private readonly List<TocEntry> _toc;
    private int _index = -1;
    private bool _syncingToc;
    private HtmlElement? _styleEl;
    private readonly System.Windows.Forms.Timer _resizeTimer;
    private readonly ToolStrip _toolbar;
    private bool _loaded;
    private bool _applyingAutoFit;

    private readonly WebBrowser _browser = new()
    {
        Dock = DockStyle.Fill,
        ScriptErrorsSuppressed = true
    };

    private readonly ToolStripButton _btnPrev;
    private readonly ToolStripButton _btnNext;
    private readonly ToolStripComboBox _tocBox;
    private readonly ToolStripLabel _titleLabel;

    public ReaderForm(string epubPath)
    {
        _book = new EpubBook(epubPath);
        _spine = new List<string>(_book.SpineItems);
        _toc = new List<TocEntry>(_book.Toc);

        Text = "EpubReader — " + Path.GetFileName(epubPath);
        StartPosition = FormStartPosition.Manual;
        ApplySavedBounds();
        AllowDrop = true;
        KeyPreview = true;

        _btnPrev = new ToolStripButton("◀ 上一章") { Enabled = false };
        _btnNext = new ToolStripButton("下一章 ▶") { Enabled = false };
        _tocBox = new ToolStripComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            AutoSize = false,
            Width = 360
        };
        _titleLabel = new ToolStripLabel("") { Alignment = ToolStripItemAlignment.Right, AutoSize = true };

        var btnOpen = new ToolStripButton("打开…");
        btnOpen.Click += (_, _) => OpenAnother();

        var btnDefault = new ToolStripButton("设为默认打开方式");
        btnDefault.Click += (_, _) =>
        {
            var msg = FileAssociation.SetAsDefault();
            var goSettings = MessageBox.Show(this, msg + "\n\n是否打开系统「默认应用」设置页确认？",
                "默认打开方式", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (goSettings == DialogResult.Yes)
                FileAssociation.OpenDefaultAppsSettings();
        };

        var toolbar = new ToolStrip
        {
            GripStyle = ToolStripGripStyle.Hidden,
            BackColor = Color.FromArgb(245, 245, 247)
        };
        _toolbar = toolbar;
        toolbar.Items.Add(btnOpen);
        toolbar.Items.Add(btnDefault);
        toolbar.Items.Add(new ToolStripSeparator());
        toolbar.Items.Add(_btnPrev);
        toolbar.Items.Add(_tocBox);
        toolbar.Items.Add(_btnNext);
        toolbar.Items.Add(_titleLabel);

        Controls.Add(_browser);
        Controls.Add(toolbar);

        _btnPrev.Click += (_, _) => Go(_index - 1);
        _btnNext.Click += (_, _) => Go(_index + 1);
        _tocBox.SelectedIndexChanged += OnTocSelected;

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

        Load += (_, _) =>
        {
            _loaded = true;
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

    /// <summary>根据当前窗口宽度生成自适应排版样式：字号随窗口自动缩放，版心自适应。</summary>
    private string BuildReadingCss()
    {
        var size = Math.Clamp(12 + ClientSize.Width / 110, 14, 26);
        return $@"
            html,body{{margin:0;padding:0;}}
            body{{max-width:calc(100% - 48px);margin:0 auto!important;padding:28px 36px;line-height:1.9;
                 font-family:Georgia,'Times New Roman','Songti SC','SimSun',serif;font-size:{size}px;color:#1a1a1a;background:#fff;}}
            img,svg{{max-width:100%;height:auto;}}
            pre{{white-space:pre-wrap;word-wrap:break-word;}}
            table{{max-width:100%;}}
            a{{color:#1a6fb5;}}
            h1,h2,h3,h4{{margin:1.2em 0 .6em;line-height:1.35;}}
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
        _browser.Navigate(new Uri(_book.GetContentPath(_spine[index])));
        SyncTocSelection();
    }

    private void NavigateTo(string href)
    {
        var plain = href.Split('#')[0];
        var i = _spine.FindIndex(s => string.Equals(s, plain, StringComparison.OrdinalIgnoreCase));
        if (i >= 0) _index = i;
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
            _titleLabel.Text = (tocTitle ?? Path.GetFileName(current)) + "    ";

            var doc = _browser.Document;
            if (doc == null) return;
            var style = doc.CreateElement("style");
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

            AutoFitToContent();
        }
        catch
        {
            // 忽略渲染期异常
        }
    }

    /// <summary>
    /// 让窗口高度自动适配当前章节的内容高度：
    /// 内容多高，窗口就多高（受限屏内），减少滚动；用户手动调整过窗口后自动停用。
    /// </summary>
    private void AutoFitToContent()
    {
        if (_applyingAutoFit) return;
        try
        {
            var body = _browser.Document?.Body;
            if (body == null) return;
            var contentH = body.ScrollRectangle.Height;
            if (contentH <= 0) return;

            var area = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1600, 900);
            var toolbarH = _toolbar.Height;
            var titleBar = Height - ClientSize.Height; // 标题栏 + 边框高度
            var contentTop = _browser.Top;
            var desiredH = contentH + toolbarH + titleBar + contentTop + 24; // 24px 底部留白
            desiredH = Math.Clamp(desiredH, 480, area.Height);

            if (Math.Abs(desiredH - Height) < 32) return; // 尺寸接近时不再抖动

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
        e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private void OnDragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
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
        SaveBounds();
        _book.Dispose();
        base.OnFormClosed(e);
    }
}