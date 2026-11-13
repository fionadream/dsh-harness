import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'main.dart' show secureStoreRead, secureStoreWrite;
import 'theme.dart';

/// 下载索引的存储键。
const String kDownloadIndexKey = 'downloads.index';

/// MediaStore 里的子目录名。
const String kDownloadFolder = 'DSH R';

const String _kInternalRoot = 'DSH R';

/// 一条已下载记录。
class DownloadedItem {
  DownloadedItem({
    required this.name,
    required this.uri,
    required this.bytes,
    required this.time,
  });

  final String name;
  final String uri;
  final int bytes;
  final DateTime time;

  Map<String, Object?> toJson() => {
        'name': name,
        'uri': uri,
        'bytes': bytes,
        'time': time.toIso8601String(),
      };

  static DownloadedItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final uri = json['uri'];
    if (name is! String || uri is! String) return null;
    final bytes = json['bytes'];
    final time = json['time'];
    return DownloadedItem(
      name: name,
      uri: uri,
      bytes: bytes is int ? bytes : 0,
      time: DateTime.tryParse(time is String ? time : '') ?? DateTime.now(),
    );
  }
}

var _mediaStoreReady = false;

Future<void> _ensureMediaStore() async {
  if (_mediaStoreReady) return;
  MediaStore.appFolder = _kInternalRoot;
  _mediaStoreReady = true;
}

/// 不弹框直接写入「下载/DSH R」。成功返回 content:// 地址，失败返回 null。
Future<DownloadedItem?> saveToDownloads(String name, Uint8List bytes) async {
  try {
    await _ensureMediaStore();
    final dir = await getTemporaryDirectory();
    final temp = File('${dir.path}/$name');
    await temp.writeAsBytes(bytes, flush: true);
    final info = await MediaStore().saveFile(
      tempFilePath: temp.path,
      dirType: DirType.download,
      dirsType: DirsType.normal,
      relativePath: kDownloadFolder,
    );
    try {
      await temp.delete();
    } catch (_) {}
    final uri = info.uri.toString();
    if (uri.isEmpty) return null;
    final item = DownloadedItem(
      name: info.title ?? name,
      uri: uri,
      bytes: bytes.length,
      time: DateTime.now(),
    );
    await _record(item);
    return item;
  } catch (_) {
    return null;
  }
}

Future<List<DownloadedItem>> loadDownloadIndex() async {
  try {
    final raw = await secureStoreRead(kDownloadIndexKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final entry in decoded)
        if (DownloadedItem.fromJson(entry) case final item?) item,
    ];
  } catch (_) {
    return [];
  }
}

Future<void> _saveIndex(List<DownloadedItem> items) async {
  final encoded = jsonEncode([for (final item in items) item.toJson()]);
  await secureStoreWrite(kDownloadIndexKey, encoded);
}

Future<void> _record(DownloadedItem item) async {
  final items = await loadDownloadIndex();
  items.removeWhere((existing) => existing.uri == item.uri || existing.name == item.name);
  items.insert(0, item);
  await _saveIndex(items);
}

Future<void> removeDownloadRecord(DownloadedItem item) async {
  final items = await loadDownloadIndex();
  items.removeWhere((existing) => existing.uri == item.uri);
  await _saveIndex(items);
  try {
    await _ensureMediaStore();
    final store = MediaStore();
    if (item.uri.startsWith('content://')) {
      await store.deleteFile(item.uri);
    }
  } catch (_) {}
}

Future<String> openDownloaded(DownloadedItem item) async {
  final result = await OpenFilex.open(item.uri.startsWith('content://') ? item.uri : item.name);
  return result.message;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatTime(DateTime time) {
  final now = DateTime.now();
  final sameDay = now.year == time.year && now.month == time.month && now.day == time.day;
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  if (sameDay) return '今天 $hh:$mm';
  return '${time.month}月${time.day}日 $hh:$mm';
}

/// 设置里的「已下载文件」页面。
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<DownloadedItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await loadDownloadIndex();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _open(DownloadedItem item) async {
    final message = await openDownloaded(item);
    if (!mounted) return;
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmDelete(DownloadedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件？'),
        content: Text('${item.name}\n会同时从「下载」目录里删掉。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: T.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await removeDownloadRecord(item);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgGray,
      appBar: AppBar(
        backgroundColor: T.bgGray,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('已下载文件'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open_rounded, size: 36, color: T.textTertiary),
              const SizedBox(height: 12),
              const Text('还没有下载过文件', style: TextStyle(fontSize: T.secondary, color: T.textSecondary)),
              const SizedBox(height: 6),
              Text('文件会保存到 内部存储/${kDownloadFolder}/',
                  style: const TextStyle(fontSize: T.tiny, color: T.textTertiary)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 0.8, color: T.divider, indent: 56),
      itemBuilder: (context, index) {
        final item = _items[index];
        return SizedBox(
          height: 64,
          child: InkWell(
            onTap: () => _open(item),
            onLongPress: () => _confirmDelete(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 22, color: T.brand),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, color: T.text)),
                        const SizedBox(height: 3),
                        Text('${formatBytes(item.bytes)} · ${formatTime(item.time)}',
                            style: const TextStyle(fontSize: 12, color: T.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded, size: 18, color: T.textTertiary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}