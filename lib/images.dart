import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:dsh_remote/dsh_remote.dart';
import 'theme.dart';

/// 单张待发送图片：先原样入列（立刻显示），后台压缩后回填。
class PendingImage {
  PendingImage(this.bytes, this.name, {this.compressing = false});

  Uint8List bytes;
  final String name;
  bool compressing;

  String get mediaType => 'image/jpeg';

  PromptImage toPromptImage() => PromptImage(
        mediaType: mediaType,
        base64Data: base64Encode(bytes),
        name: name,
      );
}

/// 超过这个大小才压缩；小图（截图、缩略图）直接原样发送，零等待。
const int kMaxInlineImageBytes = 4 * 1024 * 1024;

const int _kMaxSide = 1600;
const int _kJpegQuality = 85;

/// 同步压缩（会占用 CPU，调用方放到 isolate）。
Uint8List compressImageBytes(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return input;
  var out = decoded;
  if (decoded.width > _kMaxSide || decoded.height > _kMaxSide) {
    out = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: _kMaxSide)
        : img.copyResize(decoded, height: _kMaxSide);
  }
  final encoded = img.encodeJpg(out, quality: _kJpegQuality);
  return Uint8List.fromList(encoded);
}

/// 会话里的图片缓存：attachmentId → 字节。
final Map<String, Uint8List> _attachmentCache = {};

/// 渲染消息里的图片（按需从 Host 拉取并缓存）。
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.client,
    required this.sessionId,
    required this.reference,
    this.maxWidth = 220,
    this.maxHeight = 260,
  });

  final DshClient client;
  final String sessionId;
  final ImageAttachment reference;
  final double maxWidth;
  final double maxHeight;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final cached = _attachmentCache[widget.reference.attachmentId];
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final result = await widget.client.attachment(widget.sessionId, widget.reference);
      if (!mounted) return;
      _attachmentCache[widget.reference.attachmentId] = result.bytes;
      setState(() => _bytes = result.bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _placeholder(Widget child) => Container(
        width: 120,
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _placeholder(const Icon(Icons.broken_image_outlined, size: 20, color: T.textTertiary));
    }
    final bytes = _bytes;
    if (bytes == null) {
      return _placeholder(
        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth, maxHeight: widget.maxHeight),
        child: Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }
}

/// 从消息内容里取出图片引用。
List<ImageAttachment> imagePartsOf(Object? content) {
  if (content is! List) return const [];
  final out = <ImageAttachment>[];
  for (final part in content) {
    if (part is! Map) continue;
    if (part['type'] != 'image') continue;
    final attachment = part['attachment'];
    if (attachment is! Map) continue;
    final ref = ImageAttachment.fromJson(attachment);
    if (ref.attachmentId.isNotEmpty) out.add(ref);
  }
  return out;
}

/// 判断服务端是否因为「模型不支持图片」而拒绝。
bool isImageUnsupportedError(Object error) {
  final text = error.toString();
  return text.contains('does not support image input') ||
      text.contains('attachment-invalid');
}