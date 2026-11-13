import 'package:flutter/material.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'downloads.dart';
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
  /// 每个文件的状态：null=未下载，0~1=进度，-1=完成，-2=失败
  final Map<int, double> _progress = {};
  final Map<int, String> _savedPath = {};
  final Set<int> _failed = {};

  Future<void> _download(int index) async {
    if (_progress.containsKey(index) && _progress[index]! >= 0 && _progress[index]! < 1) {
      return;
    }
    final file = widget.files[index];
    final target = resolveDeliveredPath(file.path, widget.cwd);
    setState(() {
      _failed.remove(index);
      _savedPath.remove(index);
      _progress[index] = 0;
    });
    try {
      final saved = await downloadWorkspaceFile(
        widget.client,
        widget.sessionId,
        target,
        fileName: _fileNameOf(target),
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress[index] = p.fraction ?? 0);
        },
      );
      if (!mounted) return;
      final reason = kLastSaveError.value;
      setState(() {
        if (saved == null) {
          _progress.remove(index);
        } else {
          _progress[index] = -1;
          _savedPath[index] = saved;
        }
      });
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason == null ? '保存失败' : '保存失败：$reason'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _progress.remove(index);
        _failed.add(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$error'), duration: const Duration(seconds: 4)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox.shrink();
    return Container(
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
    );
  }

  Widget _row(int index) {
    final file = widget.files[index];
    final name = _fileNameOf(resolveDeliveredPath(file.path, widget.cwd));
    final progress = _progress[index];
    final done = progress != null && progress < 0;
    final failed = _failed.contains(index);

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