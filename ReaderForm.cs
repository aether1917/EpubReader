using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace EpubReader;

public sealed class ReaderForm : Form
{
    private const string ReadingCss = @"
        html,body{margin:0;padding:0;}
        body{max-width:52em;margin:0 auto!important;padding:28px 36px;line-height:1.9;
             font-family:Georgia,'Times New Roman','Songti SC','SimSun',serif;font-size:18px;color:#1a1a1a;background:#fff;}
        img,svg{max-width:100%;height:auto;}
        pre{white-space:pre-wrap;word-wrap:break-word;}
        table{max-width:100%;}
        a{color:#1a6fb5;}
        h1,h2,h3,h4{margin:1.2em 0 .6em;line-height:1.35;}
    ";

    private readonly EpubBook _book;
    private readonly List<string> _spine;
    private readonly List<TocEntry> _toc;
    private int _index = -1;
    private bool _syncingToc;

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
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1100, 820);
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

        var toolbar = new ToolStrip
        {
            GripStyle = ToolStripGripStyle.Hidden,
            BackColor = Color.FromArgb(245, 245, 247)
        };
        toolbar.Items.Add(btnOpen);
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

        Load += (_, _) =>
        {
            BuildTocMenu();
            if (_spine.Count > 0) Go(0);
        };
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
            style.InnerText = ReadingCss;

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
        }
        catch
        {
            // 忽略渲染期异常
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
        _book.Dispose();
        base.OnFormClosed(e);
    }
}