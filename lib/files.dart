import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'package:dsh_remote/dsh_remote.dart';

/// 上传上限：Host 内联回退路由的上限是 30 MiB。
const int kMaxUploadBytes = 30 * 1024 * 1024;

/// 下载分块大小（Host 单窗口上限 2 MiB，这里取 512 KiB 稳妥些）。
const int kReadWindowBytes = 512 * 1024;

/// 单个下载文件上限（协议允许 100 MiB）。
const int kMaxDownloadBytes = 100 * 1024 * 1024;

/* ---------------------------------------------------------------- 上传 */

class PickedUpload {
  PickedUpload(this.name, this.bytes);
  final String name;
  final Uint8List bytes;

  int get size => bytes.length;
}

/// 让用户选一个文件；返回 null 表示取消。超限返回异常由调用方提示。
Future<PickedUpload?> pickFileForUpload() async {
  final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null) return null;
  return PickedUpload(file.name, bytes);
}

/// 上传到会话工作区，返回 receiptId（可直接用于 prompt 的 fileReceiptIds）。
Future<({String receiptId, String name})> uploadToSession(
  DshClient client,
  String sessionId,
  PickedUpload picked,
) async {
  if (picked.size > kMaxUploadBytes) {
    throw Exception('文件超过 30 MiB，请先压缩或拆分');
  }
  final receipt = await client.uploadFile(sessionId, picked.bytes, name: picked.name);
  return (receiptId: receipt.receiptId, name: picked.name);
}

/* ------------------------------------------------------------ 保存目录 */

/// 选择保存目录；返回路径或 null（取消）。
Future<String?> pickSaveDirectory() async {
  return FilePicker.platform.getDirectoryPath(dialogTitle: '选择文件保存目录');
}

/// 目录是否可写。
Future<bool> directoryWritable(String? dir) async {
  if (dir == null || dir.isEmpty) return false;
  try {
    final probe = File('$dir${Platform.pathSeparator}.dsh_write_test');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// 把字节写到 [dir]／[name]；成功返回落地路径，失败抛异常。
Future<String> writeToDirectory(String dir, String name, Uint8List bytes) async {
  final target = File('$dir${Platform.pathSeparator}$name');
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

/// 兜底：走系统「保存到」对话框（不需要任何存储权限）。
/// 成功返回路径；用户取消返回 null。
Future<String?> saveViaDialog(String name, Uint8List bytes) async {
  return FilePicker.platform.saveFile(
    dialogTitle: '保存到…',
    fileName: name,
    bytes: bytes,
  );
}

/* -------------------------------------------------------------- 下载 */

class WorkspaceEntry {
  WorkspaceEntry(this.name, this.isDirectory);
  final String name;
  final bool isDirectory;

  static WorkspaceEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final type = json['type'];
    return WorkspaceEntry(name, type == 'directory');
  }
}

/// 列出工作区目录（path 为空字符串表示根目录）。
Future<List<WorkspaceEntry>> listWorkspaceDirectory(
  DshClient client,
  String sessionId,
  String path,
) async {
  final value = await client.rpc.call('workspaceFiles/list', {
    'workspaceFileScopeId': sessionId,
    'path': path,
  });
  final map = value is Map ? value : const {};
  final entries = map['entries'];
  if (entries is! List) return const [];
  return [
    for (final item in entries)
      if (WorkspaceEntry.fromJson(item) case final entry?) entry,
  ];
}

class DownloadProgress {
  DownloadProgress(this.received, this.total);
  final int received;
  final int? total;
  double? get fraction => (total == null || total == 0) ? null : received / total!;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => '已取消';
}

/// 从 Host 的工作区分块读取一个文件，边读边喂给 [onChunk]。
/// 返回字节数。通过 [isCancelled] 可以中途取消。
Future<int> readWorkspaceFile(
  DshClient client,
  String sessionId,
  String path, {
  required Future<void> Function(Uint8List chunk) onChunk,
  void Function(DownloadProgress)? onProgress,
  bool Function()? isCancelled,
}) async {
  var offset = 0;
  String? expectedVersion;
  int? total;

  while (true) {
    if (isCancelled?.call() ?? false) throw const DownloadCancelled();

    final value = await client.rpc.call('workspaceFiles/readBytes', {
      'workspaceFileScopeId': sessionId,
      'path': path,
      'options': {
        'range': {'offset': offset, 'length': kReadWindowBytes},
      },
    });
    if (value is! Map) throw Exception('读取失败：返回格式异常');

    final version = value['version'];
    if (version is String && version.isNotEmpty) {
      if (expectedVersion != null && version != expectedVersion) {
        throw Exception('文件在读取过程中被修改，请重试');
      }
      expectedVersion = version;
    }

    final data = _bytesOf(value['data']);
    offset += data.length;
    if (offset > kMaxDownloadBytes) throw Exception('文件超过 100 MiB，无法下载');

    if (data.isNotEmpty) await onChunk(data);
    final reported = value['bytes'];
    if (reported is int) total = reported;
    onProgress?.call(DownloadProgress(offset, total));

    if (value['eof'] == true || data.isEmpty) return offset;
  }
}

Uint8List _bytesOf(Object? data) {
  if (data is Uint8List) return data;
  if (data is String) {
    try {
      return base64Decode(data);
    } catch (_) {
      return Uint8List(0);
    }
  }
  if (data is List) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i += 1) {
      final value = data[i];
      out[i] = value is int ? value : 0;
    }
    return out;
  }
  return Uint8List(0);
}

/// 下载到已配置目录；目录不可用时回退到系统保存对话框。
/// 返回落地路径，取消返回 null。
Future<String?> downloadWorkspaceFile(
  DshClient client,
  String sessionId,
  String path, {
  required String fileName,
  String? saveDir,
  void Function(DownloadProgress)? onProgress,
  bool Function()? isCancelled,
}) async {
  final builder = BytesBuilder(copy: false);
  await readWorkspaceFile(
    client,
    sessionId,
    path,
    onChunk: (chunk) async => builder.add(chunk),
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
  final bytes = builder.takeBytes();
  final name = sanitizeFileName(fileName);

  if (saveDir != null && saveDir.isNotEmpty && await directoryWritable(saveDir)) {
    return writeToDirectory(saveDir, name, bytes);
  }
  return saveViaDialog(name, bytes);
}

String sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}

/// 把工作区相对路径的最后一段当作文件名。
String fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

void logFileOp(String message) {
  if (kDebugMode) debugPrint('[files] $message');
}