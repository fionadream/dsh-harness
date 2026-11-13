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

/// 「下载」根目录的几种写法，不同 ROM 不一样，挨个试。
const List<String> _downloadRoots = <String>[
  '/storage/emulated/0/Download',
  '/sdcard/Download',
];

/// 候选目录：先 `下载/DSH R`，再 `下载` 本身（插件万一没建子目录）。
List<String> _candidateDirs() => <String>[
      for (final root in _downloadRoots) '$root/$kDownloadFolder',
      for (final root in _downloadRoots) root,
    ];

/// 核实到的落地文件。
class _Landed {
  const _Landed(this.path, this.name, this.bytes);
  final String path;
  final String name;
  final int bytes;
}

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

/// 最近一次「静默保存」失败的原因，供 UI 提示用。
final ValueNotifier<String?> kLastSaveError = ValueNotifier<String?>(null);

Future<void> _ensureMediaStore() async {
  if (_mediaStoreReady) return;
  MediaStore.appFolder = kDownloadFolder;
  await MediaStore.ensureInitialized();
  _mediaStoreReady = true;
}

/// 不弹框直接写入「下载/DSH R」。
///
/// **不再相信 `MediaStore().saveFile()` 的返回值**：实测它经常写完文件后
/// 抛异常或返回 null，导致上层误判失败、又弹一次系统保存框、索引也写不进去。
/// 现在以磁盘为准——文件真的在、字节数对，就算成功。
Future<DownloadedItem?> saveToDownloads(String name, Uint8List bytes) async {
  kLastSaveError.value = null;
  final started = DateTime.now();
  String? pluginError;
  DownloadedItem? pluginItem;

  File? temp;
  try {
    await _ensureMediaStore();
    final dir = await getTemporaryDirectory();
    temp = File('${dir.path}/$name');
    await temp.writeAsBytes(bytes, flush: true);
    final info = await MediaStore().saveFile(
      tempFilePath: temp.path,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: FilePath.root,
    );
    if (info == null) {
      pluginError = '插件未返回保存结果';
    } else {
      final uri = info.uri.toString();
      if (uri.isEmpty) {
        pluginError = '插件返回的地址为空';
      } else {
        // 只有插件明确说成功了才留作兜底（磁盘核实失败时用）
        pluginItem = DownloadedItem(
          name: info.name,
          uri: uri,
          bytes: bytes.length,
          time: DateTime.now(),
        );
      }
    }
  } catch (error) {
    pluginError = '$error';
  } finally {
    if (temp != null) {
      try {
        if (temp.existsSync()) await temp.delete();
      } catch (_) {}
    }
  }

  // 首选：磁盘核实（拿到的是真实路径）
  final landed = await _confirmLanded(name, bytes.length, started);
  final item = landed != null
      ? DownloadedItem(
          name: landed.name,
          uri: landed.path,
          bytes: landed.bytes,
          time: DateTime.now(),
        )
      : pluginItem;
  if (item == null) {
    kLastSaveError.value =
        pluginError == null ? '文件没有出现在「下载/$kDownloadFolder」里' : '写入失败：$pluginError';
    return null;
  }
  await _record(item);
  return item;
}

/// 去磁盘确认文件真的落地了。
Future<_Landed?> _confirmLanded(String name, int expectedBytes, DateTime since) async {
  for (final dir in _candidateDirs()) {
    try {
      final file = File('$dir/$name');
      if (!file.existsSync()) continue;
      final length = file.lengthSync();
      if (length == expectedBytes) return _Landed(file.path, name, length);
    } catch (_) {}
  }
  // 插件可能改名（`x (1).pdf`）：按「大小相同 + 刚写进来」找最新的一个
  final floor = since.subtract(const Duration(seconds: 2));
  for (final dir in _candidateDirs()) {
    try {
      final folder = Directory(dir);
      if (!folder.existsSync()) continue;
      _Landed? best;
      DateTime? bestTime;
      for (final entry in folder.listSync(followLinks: false)) {
        if (entry is! File) continue;
        try {
          final stat = entry.statSync();
          if (stat.size != expectedBytes) continue;
          if (stat.modified.isBefore(floor)) continue;
          if (bestTime != null && !stat.modified.isAfter(bestTime)) continue;
          bestTime = stat.modified;
          best = _Landed(entry.path, _nameOfPath(entry.path), stat.size);
        } catch (_) {}
      }
      if (best != null) return best;
    } catch (_) {}
  }
  return null;
}

String _nameOfPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

/// 扫描「下载/DSH R」里的真实文件（索引为空/丢失时的兜底）。
/// 目录枚举被系统拒绝时返回空列表，不抛异常。
Future<List<DownloadedItem>> scanDownloadFolder() async {
  final seen = <String>{};
  final items = <DownloadedItem>[];
  for (final dir in _candidateDirs()) {
    try {
      final folder = Directory(dir);
      if (!folder.existsSync()) continue;
      for (final entry in folder.listSync(followLinks: false)) {
        if (entry is! File) continue;
        final name = _nameOfPath(entry.path);
        if (name.startsWith('.') || !seen.add(name)) continue;
        try {
          final stat = entry.statSync();
          items.add(DownloadedItem(
            name: name,
            uri: entry.path,
            bytes: stat.size,
            time: stat.modified,
          ));
        } catch (_) {}
      }
    } catch (_) {}
  }
  items.sort((a, b) => b.time.compareTo(a.time));
  return items;
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
    await MediaStore().deleteFile(
      fileName: item.name,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: kDownloadFolder,
    );
  } catch (_) {}
  // 扫描出来的记录带真实路径，再按路径删一次，避免插件删除失败留下孤儿文件
  if (item.uri.startsWith('/')) {
    try {
      final file = File(item.uri);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
}

Future<String> openDownloaded(DownloadedItem item) async {
  final uri = item.uri;
  // 索引里可能是 content://、绝对路径，也可能只有文件名
  final target =
      uri.startsWith('content://') || uri.startsWith('file://') || uri.startsWith('/')
          ? uri
          : item.name;
  final result = await OpenFilex.open(target);
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
    // 索引 ∪ 目录扫描：索引可能因为历史 bug 是空的，直接看文件夹最靠谱。
    final indexed = await loadDownloadIndex();
    final scanned = await scanDownloadFolder();
    final merged = <String, DownloadedItem>{};
    for (final item in indexed) {
      merged[item.name] = item;
    }
    for (final item in scanned) {
      // 扫描结果带真实路径，优先用它
      merged[item.name] = item;
    }
    final items = merged.values.toList()..sort((a, b) => b.time.compareTo(a.time));
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
