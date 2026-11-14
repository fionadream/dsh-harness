import 'package:flutter/material.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'download_manager.dart';
import 'files.dart';
import 'theme.dart';

/// Agent 通过 `present` 工具声明的交付文件（`deliverables/presented`）。
class DeliveredFile {
  const DeliveredFile({required this.path, this.description});

  /// 声明里的原始路径：绝对路径，或相对会话工作区。
  final String path;
  final String? description;

  static List<DeliveredFile> fromEventData(Object? data) {
    if (data is! Map) return const [];
    final files = data['files'];
    if (files is! List) return const [];
    final out = <DeliveredFile>[];
    for (final item in files) {
      if (item is! Map) continue;
      final path = item['path'];
      if (path is! String || path.trim().isEmpty) continue;
      final description = item['description'];
      out.add(DeliveredFile(
        path: path.trim(),
        description: description is String && description.isNotEmpty ? description : null,
      ));
    }
    return out;
  }
}

/// 交给工作区读取接口的路径：绝对路径转成相对会话 cwd。
String resolveDeliveredPath(String rawPath, String? cwd) {
  var path = rawPath.trim().replaceAll('\\', '/');
  final base = cwd?.trim().replaceAll('\\', '/');
  if (base != null && base.isNotEmpty) {
    if (path.toLowerCase().startsWith(base.toLowerCase())) {
      path = path.substring(base.length);
    }
  }
  return path.replaceFirst(RegExp(r'^/+'), '');
}

String _fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

/// 「交付了 N 个文件」卡片：每个文件可下载，显示进度与结果。
class DeliverableCard extends StatefulWidget {
  const DeliverableCard({
    super.key,
    required this.client,
    required this.sessionId,
    required this.cwd,
    required this.files,
  });

  final DshClient client;
  final String sessionId;
  final String? cwd;
  final List<DeliveredFile> files;

  @override
  State<DeliverableCard> createState() => _DeliverableCardState();
}

class _DeliverableCardState extends State<DeliverableCard> {
  /// 点下载：交给全局管理器，**不再自己持有进度**。
  /// 这样滑动列表、切到别的 App 都不会中断（v0.2.68）。
  void _download(int index) {
    final file = widget.files[index];
    final target = resolveDeliveredPath(file.path, widget.cwd);
    final key = DownloadManager.keyOf(widget.sessionId, target);
    final existing = DownloadManager.instance.taskOf(key);
    if (existing != null && existing.active) {
      DownloadManager.instance.cancel(key);
      return;
    }
    DownloadManager.instance.start(
      client: widget.client,
      sessionId: widget.sessionId,
      path: target,
      fileName: _fileNameOf(target),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: DownloadManager.instance.revision,
      builder: (context, _, __) => Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: T.divider),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 18, color: T.text),
                const SizedBox(width: 8),
                Text(
                  '交付了 ${widget.files.length} 个文件',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: T.text),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < widget.files.length; i += 1) ...[
              _row(i),
              if (i != widget.files.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(int index) {
    final file = widget.files[index];
    final target = resolveDeliveredPath(file.path, widget.cwd);
    final name = _fileNameOf(target);
    final task = DownloadManager.instance.taskOf(
      DownloadManager.keyOf(widget.sessionId, target),
    );
    final active = task?.active ?? false;
    final done = task?.status == DownloadStatus.done;
    final failed = task?.status == DownloadStatus.failed;
    final progress = active ? (task?.fraction ?? 0.0) : null;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: done ? null : () => _download(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: T.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 20, color: T.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: T.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? '已保存'
                        : failed
                            ? '下载失败，点此重试'
                            : progress == null
                                ? (file.description ?? '点击下载')
                                : '正在下载… ${(progress * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: failed ? T.danger : T.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (done)
              const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF32C48D))
            else if (progress != null)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, value: progress <= 0 ? null : progress),
              )
            else
              const Icon(Icons.download_rounded, size: 20, color: T.brand),
          ],
        ),
      ),
    );
  }
}