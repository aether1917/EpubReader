using System;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

namespace EpubReader;

internal static class FileAssociation
{
    private const string ProgId = "EpubReader.Document";
    private const string Ext = ".epub";

    /// <summary>
    /// 注册当前用户的 .epub 文件关联：
    /// 双击 EPUB 默认由 EpubReader 打开（无需管理员权限）。
    /// 同时把 EpubReader 登记到 Windows「默认应用」列表，可随时在系统设置中调整。
    /// </summary>
    public static string SetAsDefault()
    {
        try
        {
            var exePath = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exePath)) return "无法定位程序路径。";

            // 1. 扩展名 → ProgId（HKCU 每用户关联，Explorer 优先于此解析）
            using (var root = Registry.CurrentUser.CreateSubKey(@"Software\Classes\.epub"))
                root?.SetValue("", ProgId);

            // 2. ProgId 描述、打开命令、图标
            using (var prog = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + ProgId))
                prog?.SetValue("", "EPUB 电子书");

            using (var shell = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ProgId}\shell\open\command"))
                shell?.SetValue("", $"\"{exePath}\" \"%1\"");

            using (var icon = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ProgId}\DefaultIcon"))
                icon?.SetValue("", $"\"{exePath}\",0");

            // 3. 能力声明，让程序出现在「设置 → 默认应用」的列表中
            using (var caps = Registry.CurrentUser.CreateSubKey(@"Software\EpubReader\Capabilities"))
            {
                caps?.SetValue("ApplicationName", "EpubReader");
                caps?.SetValue("ApplicationDescription", "便携式 EPUB 阅读器（预览与查看）");
                using var fa = caps?.CreateSubKey("FileAssociations");
                fa?.SetValue(Ext, ProgId);
            }

            using (var ra = Registry.CurrentUser.CreateSubKey(@"Software\RegisteredApplications"))
                ra?.SetValue("EpubReader", @"Software\EpubReader\Capabilities");

            // 4. 让右键「打开方式」列表中出现 EpubReader
            using (var appCmd = Registry.CurrentUser.CreateSubKey(
                       $@"Software\Classes\Applications\{Path.GetFileName(exePath)}\shell\open\command"))
                appCmd?.SetValue("", $"\"{exePath}\" \"%1\"");

            return "已将 .epub 关联到 EpubReader，双击 EPUB 默认由 EpubReader 打开。";
        }
        catch (Exception ex)
        {
            return "设置失败：" + ex.Message;
        }
    }

    /// <summary>打开 Windows 系统的「默认应用」设置页，可在此正式确认默认打开方式。</summary>
    public static void OpenDefaultAppsSettings()
    {
        try
        {
            Process.Start(new ProcessStartInfo("ms-settings:defaultapps") { UseShellExecute = true });
        }
        catch
        {
            // 忽略
        }
    }
}