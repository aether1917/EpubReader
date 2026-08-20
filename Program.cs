using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace EpubReader;

internal static class Program
{
    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int processId);

    [DllImport("kernel32.dll")]
    private static extern bool FreeConsole();

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0)
        {
            switch (args[0].ToLowerInvariant())
            {
                case "--register":
                    RegisterFileAssociation();
                    return 0;

                case "--selftest" when args.Length > 1 && File.Exists(args[1]):
                    AttachConsole(-1);
                    try
                    {
                        RunSelfTest(args[1]);
                    }
                    finally
                    {
                        FreeConsole();
                    }
                    return 0;
            }
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        SetBrowserEmulation();

        var file = args.FirstOrDefault(a =>
            a.EndsWith(".epub", StringComparison.OrdinalIgnoreCase) && File.Exists(a));

        if (file != null)
        {
            Application.Run(new ReaderForm(file));
            return 0;
        }

        using (var ofd = new OpenFileDialog
        {
            Filter = "EPUB 文件 (*.epub)|*.epub|所有文件 (*.*)|*.*",
            Title = "打开 EPUB 文件",
            Multiselect = false
        })
        {
            if (ofd.ShowDialog() == DialogResult.OK)
                Application.Run(new ReaderForm(ofd.FileName));
        }

        return 0;
    }

    private static void SetBrowserEmulation()
    {
        try
        {
            var exeName = Path.GetFileName(Environment.ProcessPath);
            using var key = Registry.CurrentUser.CreateSubKey(
                @"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION");
            key?.SetValue(exeName, 11001, RegistryValueKind.DWord);
        }
        catch
        {
            // 非致命：只是影响渲染引擎版本
        }
    }

    private static void RegisterFileAssociation()
    {
        try
        {
            var exePath = Environment.ProcessPath;
            using (var root = Registry.CurrentUser.CreateSubKey(@"Software\Classes\.epub"))
                root?.SetValue("", "EpubReader.Document");

            using (var prog = Registry.CurrentUser.CreateSubKey(@"Software\Classes\EpubReader.Document"))
                prog?.SetValue("", "EPUB 电子书");

            using (var shell = Registry.CurrentUser.CreateSubKey(
                @"Software\Classes\EpubReader.Document\shell\open\command"))
                shell?.SetValue("", $"\"{exePath}\" \"%1\"");

            Console.WriteLine("已在当前用户下注册 .epub 文件关联，双击 EPUB 即可用 EpubReader 打开。");
        }
        catch (Exception ex)
        {
            Console.WriteLine("注册失败：" + ex.Message);
        }
    }

    private static void RunSelfTest(string epubPath)
    {
        Console.WriteLine("=== EpubReader 自检 ===");
        try
        {
            using var book = new EpubBook(epubPath);
            Console.WriteLine("书名     : " + (string.IsNullOrEmpty(book.Title) ? "(未设置)" : book.Title));
            Console.WriteLine("章节数   : " + book.SpineItems.Count);
            Console.WriteLine("目录条数 : " + book.Toc.Count);

            foreach (var t in book.Toc.Take(20))
                Console.WriteLine($"  [{'　'.ToString().PadLeft(t.Level, '　')}] {t.Title} -> {t.Href}");

            if (book.SpineItems.Count == 0)
            {
                Console.WriteLine("失败：spine 为空，EPUB 无内容章节。");
                return;
            }

            var first = book.GetContentPath(book.SpineItems[0]);
            Console.WriteLine("首章文件 : " + first + "  存在=" + File.Exists(first));
            Console.WriteLine("OK");
        }
        catch (Exception ex)
        {
            Console.WriteLine("失败：" + ex.Message);
        }
    }
}