import 'package:flutter/material.dart';

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

/// 极简 Markdown：代码块 / 标题 / 列表 / 表格 / 引用 / 行内样式。
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.text, {super.key, this.fontSize = 15});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) Padding(
          padding: EdgeInsets.only(bottom: block.kind == _Kind.list ? 2 : 6),
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

      // 代码块
      if (trimmed.startsWith('```')) {
        flush();
        final buffer = <String>[];
        i += 1;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buffer.add(lines[i]);
          i += 1;
        }
        i += 1;
        blocks.add(_Block(_Kind.code, buffer.join('\n')));
        continue;
      }

      // 表格：| a | b |  下一行 |---|---|
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

      // 标题
      final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flush();
        blocks.add(_Block(_Kind.heading, heading.group(2)!.trim(), level: heading.group(1)!.length));
        i += 1;
        continue;
      }

      // 分隔线
      if (RegExp(r'^\s*(-{3,}|\*{3,})\s*$').hasMatch(line)) {
        flush();
        blocks.add(_Block(_Kind.rule, ''));
        i += 1;
        continue;
      }

      // 引用
      if (trimmed.startsWith('> ')) {
        flush();
        blocks.add(_Block(_Kind.quote, trimmed.substring(2)));
        i += 1;
        continue;
      }

      // 列表（含缩进）
      final bullet = RegExp(r'^(\s*)([-*+]|\d+\.)\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        flush();
        blocks.add(_Block(
          _Kind.list,
          bullet.group(3)!.trim(),
          level: (bullet.group(1)!.length / 2).floor(),
          ordered: RegExp(r'\d+\.').hasMatch(bullet.group(2)!),
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
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(block.text,
                style: TextStyle(fontSize: fontSize - 2.5, fontFamily: 'monospace', height: 1.45)),
          ),
        );
      case _Kind.heading:
        final size = switch (block.level) { 1 => 21.0, 2 => 19.0, 3 => 17.0, _ => 16.0 };
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(block.text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
        );
      case _Kind.rule:
        return const Divider(height: 16, color: Color(0xFFE6E9EF));
      case _Kind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFFD3D8E0), width: 3)),
          ),
          child: _inline(block.text, color: Colors.black54),
        );
      case _Kind.list:
        return Padding(
          padding: EdgeInsets.only(left: 2.0 + block.level * 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: Text(block.ordered ? '·' : '•',
                    style: TextStyle(fontSize: fontSize, color: Colors.black45)),
              ),
              Expanded(child: _inline(block.text)),
            ],
          ),
        );
      case _Kind.table:
        final (header, rows) = block.table!;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 34,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 60,
            columnSpacing: 18,
            horizontalMargin: 6,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F6F8)),
            border: TableBorder.all(color: const Color(0xFFE6E9EF), width: 0.6),
            columns: [for (final cell in header) DataColumn(label: Text(cell, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))],
            rows: [
              for (final row in rows)
                DataRow(cells: [
                  for (final cell in row) DataCell(Text(cell, style: const TextStyle(fontSize: 13))),
                ]),
            ],
          ),
        );
      case _Kind.paragraph:
        return _inline(block.text);
    }
  }

  Widget _inline(String text, {Color? color}) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\))');
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) spans.add(TextSpan(text: text.substring(index, match.start)));
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: const Color(0xFFF0F2F5),
            fontSize: fontSize - 1.5,
          ),
        ));
      } else if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      } else {
        final label = token.substring(1, token.indexOf(']'));
        spans.add(TextSpan(text: label, style: const TextStyle(color: Color(0xFF2F6FE4))));
      }
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: fontSize, height: 1.55, color: color ?? const Color(0xFF1A1A1A)),
    );
  }
}

enum _Kind { paragraph, heading, list, code, table, quote, rule }

class _Block {
  _Block(this.kind, this.text, {this.level = 0, this.ordered = false, this.table});
  final _Kind kind;
  final String text;
  final int level;
  final bool ordered;
  final (List<String>, List<List<String>>)? table;
}