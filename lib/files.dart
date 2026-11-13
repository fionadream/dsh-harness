import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'downloads.dart';

/// 上传上限：Host 内联回退路由的上限是 30 MiB。
const int kMaxUploadBytes = 30 * 1024 * 1024;

/// 下载分块：先试 2 MiB（协议上限），失败自动退回 512 KiB。
const int kReadWindowBytesFast = 2 * 1024 * 1024;
const int kReadWindowBytesSafe = 512 * 1024;

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

/// 上传结果：要么是文件回执（真附件），要么是工作区相对路径（回落方案）。
class UploadOutcome {
  const UploadOutcome.receipt(this.receiptId, this.name) : path = null;
  const UploadOutcome.workspace(this.path, this.name) : receiptId = null;

  final String? receiptId;
  final String? path;
  final String name;

  bool get isReceipt => receiptId != null;
}

/// 上传到会话。
///
/// 优先走 `uploadFile`：整个文件一次 RPC 发走（≤30 MiB），**只有一次往返**，
/// 返回的 receiptId 可直接传 `prompt(fileReceiptIds:)`，是真正的附件。
/// dsh-Go 用的就是这条路径。
///
/// 该 Host 不支持时（旧版本 / 通道限制），自动回落到 `uploadWorkspaceFile`
/// ——它按 64 KiB 分块、每块等确认，慢但可用。
Future<UploadOutcome> uploadToSession(
  DshClient client,
  String sessionId,
  PickedUpload picked,
) async {
  if (picked.size > kMaxUploadBytes) {
    throw Exception('文件超过 30 MiB，请先压缩或拆分');
  }
  try {
    final receipt = await client.uploadFile(sessionId, picked.bytes, name: picked.name);
    if (receipt.receiptId.isNotEmpty) {
      return UploadOutcome.receipt(receipt.receiptId, picked.name);
    }
  } catch (_) {
    // 落到下面的工作区上传
  }
  final uploaded = await client.uploadWorkspaceFile(
    sessionId,
    picked.bytes,
    name: picked.name,
  );
  return UploadOutcome.workspace(uploaded.path, picked.name);
}

/* -------------------------------------------------------------- 下载 */

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
///
/// 块大小自适应：默认试 [kReadWindowBytesFast]，失败（帧过大/超时）就降到
/// [kReadWindowBytesSafe] 重试同一段，之后整个文件都用小块，不会中断。
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
  var window = kReadWindowBytesFast;
  var downgraded = false;

  while (true) {
    if (isCancelled?.call() ?? false) throw const DownloadCancelled();

    Object? value;
    try {
      value = await client.rpc.call('workspaceFiles/readBytes', {
        'workspaceFileScopeId': sessionId,
        'path': path,
        'options': {
          'range': {'offset': offset, 'length': window},
        },
      });
    } catch (error) {
      // 首次用大块失败：退回小块重试同一段，绝不中断下载。
      if (!downgraded && window > kReadWindowBytesSafe) {
        downgraded = true;
        window = kReadWindowBytesSafe;
        continue;
      }
      rethrow;
    }
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

/// 下载到「内部存储/下载/DSH R」。
///
/// 只走静默保存，**不再弹系统保存框**（用户 2026-11-13 明确要求）。
/// 返回落地位置；失败返回 null，真实原因在 [kLastSaveError] 里。
Future<String?> downloadWorkspaceFile(
  DshClient client,
  String sessionId,
  String path, {
  required String fileName,
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
  final saved = await saveToDownloads(name, bytes);
  if (saved == null) return null;
  // 直写成功 → 在 DSH R 子目录；回退 MediaStore → 落在 Download 根目录
  if (saved.uri.contains('/$kDownloadFolder/')) {
    return '内部存储/$kDownloadFolder/${saved.name}';
  }
  return '内部存储/Download/${saved.name}（未授权「所有文件访问」，没能进 $kDownloadFolder）';
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