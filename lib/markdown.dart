import 'package:flutter/material.dart';

/// 从 DSH 的 content 数组里抽出纯文本。
String plainTextOf(Object? content) {
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is Map && part['text'] is String) buffer.write(part['text']);
    }
    return buffer.toString();
  }
  return '';
}

/// 极简 Markdown：代码块 / 标题 / 列表 / 行内 `code` 与 **粗体**。
/// 不引第三方库，先把「格式不对」的主要观感修回来。
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map(_block).toList(),
    );
  }

  static List<_Block> _parse(String raw) {
    final lines = raw.split('\n');
    final blocks = <_Block>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(_Block(_Kind.paragraph, paragraph.join('\n').trim()));
      paragraph.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        flush();
        final buffer = <String>[];
        i += 1;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          buffer.add(lines[i]);
          i += 1;
        }
        i += 1;
        blocks.add(_Block(_Kind.code, buffer.join('\n')));
        continue;
      }
      final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        flush();
        blocks.add(_Block(_Kind.heading, heading.group(2)!.trim(), level: heading.group(1)!.length));
        i += 1;
        continue;
      }
      if (RegExp(r'^\s*([-*+]|\d+\.)\s+').hasMatch(line)) {
        flush();
        blocks.add(_Block(_Kind.bullet, line.trim()));
        i += 1;
        continue;
      }
      if (line.trim().isEmpty) {
        flush();
        i += 1;
        continue;
      }
      paragraph.add(line);
      i += 1;
    }
    flush();
    return blocks;
  }

  Widget _block(_Block block) {
    switch (block.kind) {
      case _Kind.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
          child: Text(block.text, style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', height: 1.45)),
        );
      case _Kind.heading:
        final size = switch (block.level) { 1 => 20.0, 2 => 18.0, 3 => 16.0, _ => 15.0 };
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(block.text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
        );
      case _Kind.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6, right: 6),
                child: Icon(Icons.circle, size: 5, color: Colors.black45),
              ),
              Expanded(child: _inline(block.text.replaceFirst(RegExp(r'^\s*([-*+]|\d+\.)\s+'), ''))),
            ],
          ),
        );
      case _Kind.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _inline(block.text),
        );
    }
  }

  Widget _inline(String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*)');
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) spans.add(TextSpan(text: text.substring(index, match.start)));
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontFamily: 'monospace', backgroundColor: Color(0xFFF0F2F5), fontSize: 13.5),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      }
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return Text.rich(TextSpan(children: spans), style: const TextStyle(fontSize: 15, height: 1.5));
  }
}

enum _Kind { paragraph, heading, bullet, code }

class _Block {
  _Block(this.kind, this.text, {this.level = 0});
  final _Kind kind;
  final String text;
  final int level;
}