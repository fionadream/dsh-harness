import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// 只取「可见文本」部分：过滤掉 reasoning（思考过程）。
String visibleTextOf(Object? content) {
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type'];
      final text = part['text'];
      if (text is! String) continue;
      if (type == 'reasoning' || type == 'thinking') continue;
      buffer.write(text);
    }
    return buffer.toString();
  }
  return '';
}

/// 极简 Markdown：代码块（带复制）/ 标题 / 列表 / 表格 / 引用 / 行内样式。
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.text, {super.key, this.fontSize = T.body});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          Padding(
            padding: EdgeInsets.only(bottom: block.kind == _Kind.list ? 4 : 12),
            child: _build(block),
          ),
      ],
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
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        flush();
        final buffer = <String>[];
        var lang = trimmed.substring(3).trim();
        i += 1;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buffer.add(lines[i]);
          i += 1;
        }
        i += 1;
        blocks.add(_Block(_Kind.code, buffer.join('\n'), lang: lang));
        continue;
      }

      if (trimmed.startsWith('|') && i + 1 < lines.length && RegExp(r'^\s*\|[\s:|-]+\|\s*$').hasMatch(lines[i + 1])) {
        flush();
        final header = _cells(line);
        i += 2;
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(_cells(lines[i]));
          i += 1;
        }
        blocks.add(_Block(_Kind.table, '', table: (header, rows)));
        continue;
      }

      final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flush();
        blocks.add(_Block(_Kind.heading, heading.group(2)!.trim(), level: heading.group(1)!.length));
        i += 1;
        continue;
      }

      if (RegExp(r'^\s*(-{3,}|\*{3,})\s*$').hasMatch(line)) {
        flush();
        blocks.add(_Block(_Kind.rule, ''));
        i += 1;
        continue;
      }

      if (trimmed.startsWith('> ')) {
        flush();
        blocks.add(_Block(_Kind.quote, trimmed.substring(2)));
        i += 1;
        continue;
      }

      final bullet = RegExp(r'^(\s*)([-*+]|\d+\.)\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        flush();
        blocks.add(_Block(
          _Kind.list,
          bullet.group(3)!.trim(),
          level: (bullet.group(1)!.length / 2).floor(),
          ordered: RegExp(r'\d+\.').hasMatch(bullet.group(2)!),
          marker: bullet.group(2)!,
        ));
        i += 1;
        continue;
      }

      if (trimmed.isEmpty) {
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

  static List<String> _cells(String line) {
    var body = line.trim();
    if (body.startsWith('|')) body = body.substring(1);
    if (body.endsWith('|')) body = body.substring(0, body.length - 1);
    return body.split('|').map((c) => c.trim()).toList(growable: false);
  }

  Widget _build(_Block block) {
    switch (block.kind) {
      case _Kind.code:
        return Container(
          decoration: BoxDecoration(color: T.codeBg, borderRadius: BorderRadius.circular(T.rCode)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
                child: Row(
                  children: [
                    Text(block.lang.isEmpty ? '代码' : block.lang,
                        style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: block.text)),
                      icon: const Icon(Icons.copy_rounded, size: 14, color: T.textSecondary),
                      label: const Text('复制', style: TextStyle(fontSize: T.tiny, color: T.textSecondary)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Text(block.text,
                      style: TextStyle(fontSize: fontSize - 2.5, fontFamily: 'monospace', height: 1.6)),
                ),
              ),
            ],
          ),
        );
      case _Kind.heading:
        final size = switch (block.level) { 1 => 21.0, 2 => 19.5, 3 => 18.0, _ => 17.0 };
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(block.text,
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, height: 1.5, color: T.text)),
        );
      case _Kind.rule:
        return const Divider(height: 20, color: T.divider);
      case _Kind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFFDCDCE0), width: 3)),
          ),
          child: _inline(block.text, color: T.textSecondary),
        );
      case _Kind.list:
        return Padding(
          padding: EdgeInsets.only(left: block.level * 14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: block.ordered ? 22 : 14,
                child: Text(block.ordered ? '${block.marker}' : '•',
                    style: TextStyle(fontSize: fontSize, height: T.bodyH, color: T.textSecondary)),
              ),
              Expanded(child: _inline(block.text)),
            ],
          ),
        );
      case _Kind.table:
        return _table(block.table!);
      case _Kind.paragraph:
        return _inline(block.text);
    }
  }

  Widget _table((List<String>, List<List<String>>) data) {
    final (header, rows) = data;
    Widget cell(String text, {bool head = false}) => ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: head
                ? Text(text,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: T.text))
                : _inline(text, size: 15),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: T.divider),
        borderRadius: BorderRadius.circular(T.rCode),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: const Color(0xFFFAFAFA),
              child: Row(
                children: [for (final h in header) cell(h, head: true)],
              ),
            ),
            for (final row in rows)
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider, width: 0.8)),
                ),
                child: Row(
                  children: [for (final c in row) cell(c)],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inline(String text, {Color? color, double? size}) {
    final base = size ?? fontSize;
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\[[^\]]+\]\([^)]+\))');
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) spans.add(TextSpan(text: text.substring(index, match.start)));
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: T.codeBg,
            fontSize: base - 1.5,
          ),
        ));
      } else if (token.startsWith('**') || token.startsWith('__')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      } else {
        final label = token.substring(1, token.indexOf(']'));
        spans.add(TextSpan(text: label, style: const TextStyle(color: T.brand)));
      }
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: base, height: T.bodyH, letterSpacing: T.letter, color: color ?? T.text),
    );
  }
}

enum _Kind { paragraph, heading, list, code, table, quote, rule }

class _Block {
  _Block(this.kind, this.text, {this.level = 0, this.ordered = false, this.marker = '', this.lang = '', this.table});
  final _Kind kind;
  final String text;
  final int level;
  final bool ordered;
  final String marker;
  final String lang;
  final (List<String>, List<List<String>>)? table;
}
