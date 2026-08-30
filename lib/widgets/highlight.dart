// SQL Pulse — SQL & JSON syntax highlighting → InlineSpans. Ported from highlightSql/Json.
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

const _sqlKw = {'select', 'from', 'where', 'join', 'inner', 'left', 'right', 'on', 'group', 'by', 'order', 'having', 'limit', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'view', 'procedure', 'function', 'trigger', 'alter', 'add', 'drop', 'column', 'index', 'as', 'and', 'or', 'not', 'null', 'primary', 'key', 'foreign', 'references', 'begin', 'end', 'return', 'returns', 'if', 'then', 'else', 'for', 'each', 'row', 'replace', 'distinct', 'union', 'desc', 'asc', 'show', 'tables', 'describe', 'explain', 'default', 'unique', 'constraint', 'auto_increment'};
const _sqlType = {'int', 'varchar', 'decimal', 'datetime', 'date', 'double', 'tinyint', 'text', 'bigint', 'float', 'char', 'boolean', 'timestamp'};
const _sqlFn = {'sum', 'avg', 'count', 'min', 'max', 'now', 'coalesce', 'concat', 'upper', 'lower', 'round'};

List<TextSpan> highlightSql(String sql, SpColors c, {double size = 12, double height = 1.7}) {
  final spans = <TextSpan>[];
  final base = TextStyle(color: c.text, fontFamily: 'JetBrainsMono');
  final re = RegExp(r"('[^']*'|" r'"[^"]*")|(\b\d+\.?\d*\b)|([A-Za-z_][A-Za-z0-9_]*)|(\s+)|([^\sA-Za-z0-9_])');
  for (final m in re.allMatches(sql)) {
    final tok = m.group(0)!;
    Color? color;
    if (m.group(1) != null) {
      color = c.synStr;
    } else if (m.group(2) != null) {
      color = c.synNum;
    } else if (m.group(3) != null) {
      final lw = tok.toLowerCase();
      if (_sqlKw.contains(lw)) {
        color = c.synKw;
      } else if (_sqlType.contains(lw) || _sqlFn.contains(lw)) {
        color = c.synFn;
      }
    } else if (m.group(5) != null) {
      color = c.synPunc;
    }
    spans.add(TextSpan(text: tok, style: color != null ? base.copyWith(color: color) : base));
  }
  return spans;
}

List<TextSpan> highlightJson(String text, SpColors c) {
  final spans = <TextSpan>[];
  final base = TextStyle(color: c.text, fontFamily: 'JetBrainsMono');
  final re = RegExp(r'("(?:\\.|[^"\\])*"\s*:)|("(?:\\.|[^"\\])*")|(\b-?\d+(?:\.\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)|([{}\[\],])');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    Color color = c.synPunc;
    if (m.group(1) != null) {
      color = c.synKw;
    } else if (m.group(2) != null) {
      color = c.synStr;
    } else if (m.group(3) != null) {
      color = c.synNum;
    } else if (m.group(4) != null) {
      color = c.synFn;
    }
    spans.add(TextSpan(text: m.group(0), style: base.copyWith(color: color)));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: base));
  return spans;
}

/// A styled code block rendering highlighted SQL.
class CodeBlock extends StatelessWidget {
  final String code;
  final double fontSize;
  final double? maxHeight;
  final bool json;
  final EdgeInsets padding;
  const CodeBlock(this.code, {super.key, this.fontSize = 12, this.maxHeight, this.json = false, this.padding = const EdgeInsets.all(13)});

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final spans = json ? highlightJson(code, c) : highlightSql(code, c);
    Widget body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(R.r),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText.rich(
          TextSpan(children: spans),
          style: mono(size: fontSize, height: 1.7),
        ),
      ),
    );
    if (maxHeight != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: SingleChildScrollView(child: body),
      );
    }
    return body;
  }
}
