import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'files.dart';
import 'theme.dart';

/// 工作区文件浏览 + 下载。
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({
    super.key,
    required this.client,
    required this.sessionId,
    this.saveDir,
    this.initialPath = '',
  });

  final DshClient client;
  final String sessionId;
  final String? saveDir;
  final String initialPath;

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  late String _path = widget.initialPath;
  List<WorkspaceEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String? _busyName;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await listWorkspaceDirectory(widget.client, widget.sessionId, _path);
      if (!mounted) return;
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  List<({String label, String path})> get _crumbs {
    if (_path.isEmpty) return const [];
    final parts = _path.split('/');
    final out = <({String label, String path})>[];
    var acc = '';
    for (final part in parts) {
      acc = acc.isEmpty ? part : '$acc/$part';
      out.add((label: part, path: acc));
    }
    return out;
  }

  Future<void> _download(WorkspaceEntry entry) async {
    if (_busyName != null) return;
    final name = entry.name;
    setState(() {
      _busyName = name;
      _progress = null;
    });
    try {
      final saved = await downloadWorkspaceFile(
        widget.client,
        widget.sessionId,
        _join(_path, entry.name),
        fileName: name,
        saveDir: widget.saveDir,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction);
        },
      );
      if (!mounted) return;
      final message = saved == null ? '已取消' : '已保存到\n$saved';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _busyName = null;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = _crumbs;
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(crumbs.isEmpty ? '工作区文件' : crumbs.last.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (crumbs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() => _path = '');
                        _load();
                      },
                      child: const Text('根目录',
                          style: TextStyle(fontSize: T.tiny, color: T.brand)),
                    ),
                    for (final crumb in crumbs) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text('/', style: TextStyle(fontSize: T.tiny, color: T.textTertiary)),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() => _path = crumb.path);
                          _load();
                        },
                        child: Text(crumb.label,
                            style: const TextStyle(fontSize: T.tiny, color: T.brand)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const Divider(height: 0.8, color: T.divider),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('加载失败：$_error',
            style: const TextStyle(fontSize: 14, color: T.textSecondary)),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Text('空目录', style: TextStyle(fontSize: T.secondary, color: T.textSecondary)),
      );
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 0.8, color: T.divider, indent: 56),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final busy = _busyName == entry.name;
        return SizedBox(
          height: 56,
          child: InkWell(
            onTap: entry.isDirectory
                ? () {
                    setState(() => _path = _join(_path, entry.name));
                    _load();
                  }
                : () => _download(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                    size: 20,
                    color: entry.isDirectory ? T.textSecondary : T.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: T.body, color: T.text),
                    ),
                  ),
                  if (busy)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _progress,
                      ),
                    )
                  else if (entry.isDirectory)
                    const Icon(Icons.chevron_right, size: 20, color: T.textTertiary)
                  else
                    const Icon(Icons.download_rounded, size: 20, color: T.brand),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 一个小工具：把字节数组直接存到已配置目录，供别处复用。
Future<String?> saveBytesToConfiguredDir(
  String? saveDir,
  String fileName,
  Uint8List bytes,
) async {
  final name = sanitizeFileName(fileName);
  if (saveDir != null && saveDir.isNotEmpty && await directoryWritable(saveDir)) {
    return writeToDirectory(saveDir, name, bytes);
  }
  return saveViaDialog(name, bytes);
}