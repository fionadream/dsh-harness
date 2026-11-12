import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:dsh_remote/dsh_remote.dart';
import 'theme.dart';

/// 单张待发送图片（本地字节，已在压缩后）。
class PendingImage {
  PendingImage(this.bytes, this.name);

  final Uint8List bytes;
  final String name;

  String get mediaType => 'image/jpeg';

  PromptImage toPromptImage() => PromptImage(
        mediaType: mediaType,
        base64Data: base64Encode(bytes),
        name: name,
      );
}

/// 超过这个大小才压缩；手机截图通常几百 KB，不会触发。
const int kMaxInlineImageBytes = 1400 * 1024;

const int _kMaxSide = 1600;
const int _kJpegQuality = 85;

/// 同步压缩（会占用 CPU，调用方应放到 isolate）。
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

/// 准备好要发送的图片字节：小图原样返回，大图压缩。
Future<Uint8List> prepareImageForSend(Uint8List bytes) async {
  if (bytes.length <= kMaxInlineImageBytes) return bytes;
  return compute(compressImageBytes, bytes);
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
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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