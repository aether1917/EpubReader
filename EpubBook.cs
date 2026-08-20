using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Xml.Linq;

namespace EpubReader;

public sealed class TocEntry
{
    public string Title { get; set; } = "";
    public string Href { get; set; } = "";
    public int Level { get; set; }
}

public sealed class EpubBook : IDisposable
{
    public string TempDir { get; }
    public string OpfDir { get; }
    public string Title { get; private set; } = "";
    public List<string> SpineItems { get; } = new();
    public List<TocEntry> Toc { get; } = new();

    public EpubBook(string path)
    {
        TempDir = Path.Combine(
            Path.GetTempPath(), "EpubReader",
            Path.GetFileNameWithoutExtension(path) + "_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(TempDir);

        try
        {
            ZipFile.ExtractToDirectory(path, TempDir);
        }
        catch
        {
            try { Directory.Delete(TempDir, true); } catch { }
            throw;
        }

        var containerPath = Path.Combine(TempDir, "META-INF", "container.xml");
        if (!File.Exists(containerPath))
            throw new InvalidDataException("不是有效的 EPUB：缺少 META-INF/container.xml");

        var container = XDocument.Load(containerPath);
        var rootfile = Descendant(container.Root, "rootfile");
        var opfPath = rootfile?.Attribute("full-path")?.Value;
        if (string.IsNullOrEmpty(opfPath))
            throw new InvalidDataException("不是有效的 EPUB：container.xml 中缺少 rootfile");

        OpfDir = Path.GetDirectoryName(Path.Combine(TempDir, opfPath.Replace('/', Path.DirectorySeparatorChar)))
                 ?? TempDir;

        var opf = XDocument.Load(Path.Combine(TempDir, opfPath.Replace('/', Path.DirectorySeparatorChar)));

        var titleEl = Descendant(opf.Root, "title");
        if (titleEl != null) Title = titleEl.Value.Trim();

        var items = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in Descendants(opf.Root, "item"))
        {
            var id = item.Attribute("id")?.Value;
            var href = item.Attribute("href")?.Value;
            if (id != null && href != null) items[id] = href;
        }

        var spineEl = Descendant(opf.Root, "spine");
        var ncxId = spineEl?.Attribute("toc")?.Value;
        foreach (var itemref in Descendants(spineEl, "itemref"))
        {
            var idref = itemref.Attribute("idref")?.Value;
            if (idref != null && items.TryGetValue(idref, out var href))
                SpineItems.Add(Normalize(href));
        }

        if (ncxId != null && items.TryGetValue(ncxId, out var ncxHref))
            LoadNcx(Path.Combine(OpfDir, ncxHref.Replace('/', Path.DirectorySeparatorChar)));

        if (Toc.Count == 0)
            LoadNav();
    }

    public string GetContentPath(string spineHref)
        => Path.Combine(OpfDir, spineHref.Replace('/', Path.DirectorySeparatorChar));

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(TempDir))
                Directory.Delete(TempDir, true);
        }
        catch
        {
            // 文件占用等情况：留给系统临时目录清理
        }
    }

    private void LoadNcx(string ncxPath)
    {
        if (!File.Exists(ncxPath)) return;
        try
        {
            var doc = XDocument.Load(ncxPath);
            foreach (var navPoint in Descendants(doc.Root, "navPoint"))
                AddNavPoint(navPoint, 0);
        }
        catch
        {
            // 忽略损坏的 NCX
        }
    }

    private void AddNavPoint(XElement navPoint, int level)
    {
        var label = Descendant(navPoint, "text")?.Value?.Trim();
        var href = Descendant(navPoint, "content")?.Attribute("src")?.Value;
        if (!string.IsNullOrEmpty(label))
            Toc.Add(new TocEntry { Title = label, Href = Normalize(href ?? ""), Level = level });

        foreach (var child in Descendants(navPoint, "navPoint"))
            AddNavPoint(child, level + 1);
    }

    private void LoadNav()
    {
        var candidates = new List<string>
        {
            Path.Combine(OpfDir, "nav.xhtml"),
            Path.Combine(OpfDir, "nav.html")
        };
        candidates.AddRange(SpineItems.Select(s => Path.Combine(OpfDir, s.Replace('/', Path.DirectorySeparatorChar))));

        foreach (var candidate in candidates)
        {
            if (!File.Exists(candidate)) continue;
            try
            {
                var doc = XDocument.Load(candidate);
                foreach (var nav in Descendants(doc.Root, "nav"))
                {
                    foreach (var a in Descendants(nav, "a"))
                    {
                        var href = a.Attribute("href")?.Value;
                        if (string.IsNullOrEmpty(href)) continue;
                        Toc.Add(new TocEntry { Title = a.Value.Trim(), Href = Normalize(href), Level = 0 });
                    }
                }
                if (Toc.Count > 0) return;
            }
            catch
            {
                // 尝试下一个候选
            }
        }
    }

    private static string Normalize(string href)
    {
        var i = href.IndexOf('#');
        var pathPart = i >= 0 ? href.Substring(0, i) : href;
        var anchor = i >= 0 ? href.Substring(i) : "";
        return Uri.UnescapeDataString(pathPart).Replace('\\', '/') + anchor;
    }

    private static XElement? Descendant(XElement? root, string localName)
        => root?.Descendants().FirstOrDefault(e => e.Name.LocalName == localName);

    private static IEnumerable<XElement> Descendants(XElement? root, string localName)
        => root?.Descendants().Where(e => e.Name.LocalName == localName) ?? Enumerable.Empty<XElement>();
}