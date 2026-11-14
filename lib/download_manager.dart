import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'downloads.dart';
import 'files.dart';
import 'main.dart' show secureStoreRead, secureStoreWrite;

/// 下载任务状态。
enum DownloadStatus { queued, running, done, failed, cancelled }

/// 一条下载任务。生命周期**不依赖任何 Widget**：
/// 滑动会话、切到别的 App、甚至退出当前页面都不会中断。
class DownloadTask {
  DownloadTask({
    required this.key,
    required this.sessionId,
    required this.path,
    required this.fileName,
  });

  final String key;
  final String sessionId;
  final String path;
  final String fileName;

  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int? total;
  String? savedPath;
  String? error;

  double? get fraction {
    final size = total;
    if (size == null || size <= 0) return null;
    return (received / size).clamp(0.0, 1.0);
  }

  bool get active =>
      status == DownloadStatus.queued || status == DownloadStatus.running;
}

/// 断点续传记录：存在安全存储里，按任务 key 索引。
class _ResumeRecord {
  const _ResumeRecord({required this.version, required this.received, required this.partPath});

  final String version;
  final int received;
  final String partPath;

  String encode() => jsonEncode({'version': version, 'received': received, 'part': partPath});

  static _ResumeRecord? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final version = map['version'];
      final received = map['received'];
      final part = map['part'];
      if (version is! String || received is! int || part is! String) return null;
      return _ResumeRecord(version: version, received: received, partPath: part);
    } catch (_) {
      return null;
    }
  }
}

/// 全局下载管理器：串行队列 + 断点续传 + 与页面解耦。
class DownloadManager {
  DownloadManager._();

  static final DownloadManager instance = DownloadManager._();

  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};

  /// UI 监听这个计数器刷新（任何任务状态变化都会 +1）。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final List<String> _queue = <String>[];
  bool _pumping = false;

  /// 任务是否还在跑（供保活判断"正在下载时不要断连"）。
  bool get hasActive => _tasks.values.any((t) => t.active);

  DownloadTask? taskOf(String key) => _tasks[key];

  static String keyOf(String sessionId, String path) => '$sessionId\u0000$path';

  void _touch() => revision.value += 1;

  /// 开始（或继续）下载。已存在任务时直接返回它。
  DownloadTask start({
    required DshClient client,
    required String sessionId,
    required String path,
    required String fileName,
  }) {
    final key = keyOf(sessionId, path);
    final existing = _tasks[key];
    if (existing != null && existing.active) return existing;

    final task = DownloadTask(
      key: key,
      sessionId: sessionId,
      path: path,
      fileName: fileName,
    );
    _tasks[key] = task;
    _queue.add(key);
    _touch();
    unawaited(_pump(client));
    return task;
  }

  /// 取消：清掉临时文件与续传记录，不再进队列。
  void cancel(String key) {
    final task = _tasks[key];
    if (task == null) return;
    if (task.status == DownloadStatus.running) {
      task.status = DownloadStatus.cancelled;
    } else {
      _tasks.remove(key);
      _queue.remove(key);
    }
    _touch();
    unawaited(_clearResume(key));
  }

  Future<void> _pump(DshClient client) async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final key = _queue.removeAt(0);
        final task = _tasks[key];
        if (task == null || task.status == DownloadStatus.cancelled) continue;
        await _run(client, task);
      }
    } finally {
      _pumping = false;
    }
  }

  String _resumeKey(String key) => 'dl.resume.$key';

  Future<void> _clearResume(String key) async {
    await secureStoreWrite(_resumeKey(key), '');
  }

  Future<void> _run(DshClient client, DownloadTask task) async {
    task.status = DownloadStatus.running;
    task.error = null;
    task.savedPath = null;
    _touch();

    File? part;
    try {
      // 1) 先问服务端：版本 + 总大小（决定能不能续传）
      String? version;
      int? total;
      try {
        final stat = await client.rpc.call('workspaceFiles/stat', {
          'workspaceFileScopeId': task.sessionId,
          'path': task.path,
        });
        if (stat is Map) {
          final v = stat['version'];
          if (v is String) version = v;
          final b = stat['bytes'];
          if (b is int) total = b;
        }
      } catch (_) {}

      task.total = total;

      // 2) 找断点
      final record = _ResumeRecord.decode(await secureStoreRead(_resumeKey(task.key)));
      var startOffset = 0;
      if (record != null && version != null && record.version == version) {
        final file = File(record.partPath);
        if (file.existsSync() && file.lengthSync() == record.received) {
          startOffset = record.received;
          part = file;
        }
      }
      if (part == null) {
        final dir = await getTemporaryDirectory();
        part = File('${dir.path}/dsh_dl_${task.key.hashCode.abs()}.part');
        if (part.existsSync()) {
          try {
            await part.delete();
          } catch (_) {}
        }
        await part.writeAsBytes(const <int>[], flush: true);
      }
      task.received = startOffset;
      _touch();
      if (version != null) {
        await secureStoreWrite(
          _resumeKey(task.key),
          _ResumeRecord(
            version: version,
            received: startOffset,
            partPath: part.path,
          ).encode(),
        );
      }

      // 3) 边下边写 .part（每 1 MiB 落盘一次，杀进程也能续）
      var flushedAt = startOffset;
      final sink = part.openWrite(mode: FileMode.append);
      try {
        await readWorkspaceFile(
          client,
          task.sessionId,
          task.path,
          startOffset: startOffset,
          isCancelled: () => task.status == DownloadStatus.cancelled,
          onChunk: (Uint8List chunk) async {
            sink.add(chunk);
            task.received += chunk.length;
            if (task.received - flushedAt >= 1024 * 1024) {
              flushedAt = task.received;
              await sink.flush();
              if (version != null) {
                await secureStoreWrite(
                  _resumeKey(task.key),
                  _ResumeRecord(
                    version: version,
                    received: task.received,
                    partPath: part!.path,
                  ).encode(),
                );
              }
              _touch();
            }
          },
          onProgress: (progress) {
            task.total = progress.total ?? task.total;
            _touch();
          },
        );
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (task.status == DownloadStatus.cancelled) {
        await _clearResume(task.key);
        try {
          if (part.existsSync()) await part.delete();
        } catch (_) {}
        _touch();
        return;
      }

      // 4) 落盘到「下载/DSH R」
      final bytes = await part.readAsBytes();
      final name = sanitizeFileName(task.fileName);
      final saved = await saveToDownloads(name, bytes);
      if (saved == null) {
        task.status = DownloadStatus.failed;
        task.error = kLastSaveError.value ?? '保存失败';
      } else {
        task.status = DownloadStatus.done;
        task.savedPath = saved.uri.contains('/$kDownloadFolder/')
            ? '内部存储/$kDownloadFolder/${saved.name}'
            : '内部存储/Download/${saved.name}（未授权「所有文件访问」，没能进 $kDownloadFolder）';
        task.received = bytes.length;
        task.total = bytes.length;
        await _clearResume(task.key);
        try {
          await part.delete();
        } catch (_) {}
      }
    } catch (error) {
      if (task.status == DownloadStatus.cancelled) {
        await _clearResume(task.key);
      } else {
        task.status = DownloadStatus.failed;
        task.error = '$error';
        // 失败保留 .part 与记录，下次可续
      }
    } finally {
      _touch();
    }
  }

  /// 清空已完成/失败的旧记录（列表刷新时调用，避免无限增长）。
  void pruneFinished({int keep = 30}) {
    final finished = _tasks.values
        .where((t) => !t.active)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (finished.length <= keep) return;
    for (final task in finished.take(finished.length - keep)) {
      _tasks.remove(task.key);
    }
    _touch();
  }
}