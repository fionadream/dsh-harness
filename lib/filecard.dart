import 'package:flutter/material.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'downloads.dart';
import 'files.dart';
import 'theme.dart';

/// 消息内文件卡片：扫描正文中的文件路径，校验存在后提供下载。
class FileStrip extends StatefulWidget {
  const FileStrip({
    super.key,
    required this.client,
    required this.sessionId,
    required this.text,
    this.cwd,
  });

  final DshClient client;
  final String sessionId;
  final String text;
  final String? cwd;

  @override
  State<FileStrip> createState() => _FileStripState();
}

class _FileCandidate {
  _FileCandidate(this.name, this.path, this.bytes);
  final String name;
  final String path;
  final int? bytes;
}

class _FileStripState extends State<FileStrip> {
  /// 扫描结果缓存：key = 会话 + 正文。
  /// 列表重建时 widget 会被替换成同一个正文的新实例，没有缓存就会重新扫描、
  /// 卡片先消失再出现，高度一变整屏就跳。
  static final Map<String, List<_FileCandidate>> _cache = <String, List<_FileCandidate>>{};

  final List<_FileCandidate> _files = [];
  bool _checked = false;
  String? _busy;
  double? _progress;

  String get _cacheKey => '${widget.sessionId}\u0000${widget.text}';

  @override
  void initState() {
    super.initState();
    final cached = _cache[_cacheKey];
    if (cached != null) {
      // 命中缓存：首帧就有确定高度，不会跳
      _files
        ..clear()
        ..addAll(cached);
      _checked = true;
    } else {
      _scan();
    }
  }

  static final RegExp _windowsAbs =
      RegExp(r'[A-Za-z]:[\\/][^\s"<>|]*?\.[A-Za-z0-9]{1,6}');
  static final RegExp _relPath =
      RegExp(r'(?:[\w\-.]+[\\/])+[\w\-. ]+\.[A-Za-z0-9]{1,6}');

  Future<void> _scan() async {
    final raw = widget.text;
    final hits = <String>{};

    for (final m in _windowsAbs.allMatches(raw)) {
      hits.add(m.group(0)!);
    }
    for (final m in _relPath.allMatches(raw)) {
      hits.add(m.group(0)!);
    }

    final found = <_FileCandidate>[];
    for (final hit in hits) {
      if (found.length >= 4) break;
      var path = _normalize(hit);
      final cwd = widget.cwd;
      if (cwd != null && cwd.isNotEmpty) {
        final normalizedCwd = _normalize(cwd);
        if (path.toLowerCase().startsWith(normalizedCwd.toLowerCase())) {
          path = path.substring(normalizedCwd.length).replaceFirst(RegExp(r'^[/\\]'), '');
        }
      }
      if (path.isEmpty || path == '.') continue;
      // 只认带扩展名的普通文件名
      if (!RegExp(r'\.[A-Za-z0-9]{1,6}$').hasMatch(path)) continue;

      try {
        final value = await widget.client.rpc.call('workspaceFiles/stat', {
          'workspaceFileScopeId': widget.sessionId,
          'path': path,
        });
        if (value is! Map) continue;
        final abs = value['absolutePath'];
        if (abs is! String || abs.isEmpty) continue;
        found.add(_FileCandidate(
          fileNameOf(path),
          path,
          value['bytes'] is int ? value['bytes'] as int : null,
        ));
      } catch (_) {
        // 工作区外或不存在：跳过
      }
    }

    if (!mounted) return;
    if (_cache.length > 300) _cache.clear();
    _cache[_cacheKey] = found;
    setState(() {
      _files
        ..clear()
        ..addAll(found);
      _checked = true;
    });
  }

  static String _normalize(String path) {
    var p = path.trim();
    // 去掉末尾标点（用循环避免正则里的引号转义问题）
    const trailing = '.,;:)]}>"\'`';
    while (p.isNotEmpty && trailing.contains(p[p.length - 1])) {
      p = p.substring(0, p.length - 1);
    }
    p = p.replaceAll('\\', '/');
    return p;
  }

  Future<void> _download(_FileCandidate file) async {
    if (_busy != null) return;
    setState(() {
      _busy = file.name;
      _progress = null;
    });
    try {
      final saved = await downloadWorkspaceFile(
        widget.client,
        widget.sessionId,
        file.path,
        fileName: file.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction);
        },
      );
      if (!mounted) return;
      final reason = kLastSaveError.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null
                ? (reason == null ? '保存失败' : '保存失败：$reason')
                : '已保存到 $saved',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final file in _files)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: T.divider),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _busy == null ? () => _download(file) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 20, color: T.brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, color: T.text),
                            ),
                            if (file.bytes != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                formatBytes(file.bytes!),
                                style: const TextStyle(fontSize: 12, color: T.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_busy == file.name)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, value: _progress),
                        )
                      else
                        const Icon(Icons.download_rounded, size: 22, color: T.brand),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 把字节数格式化成可读文本。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}