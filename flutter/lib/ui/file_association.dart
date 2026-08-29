import 'dart:io';

/// .epub 文件关联：写当前用户的注册表（HKCU），无需管理员权限。
/// 与 C# 版 FileAssociation.cs 的行为一致。
class FileAssociation {
  FileAssociation._();

  static const _progId = 'EpubReader.Document';
  static const _ext = '.epub';

  static String get _exePath => Platform.resolvedExecutable;

  static Future<String> setAsDefault() async {
    try {
      final exe = _exePath;
      final openCmd = '"$exe" "%1"';
      final iconRef = '"$exe",0';

      // reg add <key> [/v name | /ve] [/d data] /f
      Future<void> reg(String key, {String? value, String? data}) async {
        final args = ['add', key];
        if (value != null) {
          args..add('/v')..add(value);
        } else {
          args.add('/ve');
        }
        if (data != null) args..add('/d')..add(data);
        args.add('/f');
        final r = await Process.run('reg', args, runInShell: true);
        if (r.exitCode != 0) {
          throw Exception('reg ${r.exitCode}: ${r.stderr}');
        }
      }

      await reg(r'Software\Classes\.epub', data: _progId);
      await reg(r'Software\Classes\$_progId', data: 'EPUB 电子书');
      await reg(
        'Software\\Classes\\$_progId\\shell\\open\\command',
        data: openCmd,
      );
      await reg(
        'Software\\Classes\\$_progId\\DefaultIcon',
        data: iconRef,
      );
      await reg(
        r'Software\EpubReader\Capabilities',
        value: 'ApplicationName',
        data: 'EpubReader',
      );
      await reg(
        r'Software\EpubReader\Capabilities',
        value: 'ApplicationDescription',
        data: '便携式 EPUB 阅读器（预览与查看）',
      );
      await reg(
        r'Software\EpubReader\Capabilities\FileAssociations',
        value: _ext,
        data: _progId,
      );
      await reg(
        r'Software\RegisteredApplications',
        value: 'EpubReader',
        data: r'Software\EpubReader\Capabilities',
      );
      await reg(
        'Software\\Classes\\Applications\\${_exeName()}\\shell\\open\\command',
        data: openCmd,
      );

      return '已将 .epub 关联到 EpubReader，双击 EPUB 默认由 EpubReader 打开。';
    } catch (ex) {
      return '设置失败：$ex';
    }
  }

  /// 打开 Windows 系统的「默认应用」设置页。
  static Future<void> openDefaultAppsSettings() async {
    try {
      await Process.run(
        'cmd',
        ['/c', 'start', '', 'ms-settings:defaultapps'],
        runInShell: true,
      );
    } catch (_) {
      // 忽略
    }
  }

  static String _exeName() => _exePath.replaceAll('/', '\\').split('\\').last;
}
