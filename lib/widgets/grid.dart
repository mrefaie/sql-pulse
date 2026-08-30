// SQL Pulse — read-only result grid (gtable). Used by results, batch, dashboard.
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class ResultTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Object?>> rows;
  final bool showRowNum;
  final bool flat;
  const ResultTable({super.key, required this.headers, required this.rows, this.showRowNum = true, this.flat = false});

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final hStyle = mono(size: 10.5, weight: FontWeight.w700, color: c.text2, spacing: 0.4);
    final cStyle = mono(size: 12, color: c.text);

    Widget headerCell(String t, {bool rightAlign = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: rightAlign ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(t.toUpperCase(), style: hStyle, maxLines: 1, overflow: TextOverflow.clip),
        );
    Widget bodyCell(Object? v, {bool rowNum = false}) {
      final isNull = v == null;
      final isNum = v is num;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: rowNum ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          isNull ? 'NULL' : '$v',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: cStyle.copyWith(
            color: isNull ? c.text4 : (isNum && !rowNum ? c.synNum : (rowNum ? c.text4 : c.text)),
            fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }

    final table = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder(
        horizontalInside: BorderSide(color: c.border),
        bottom: BorderSide(color: c.border),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(color: c.surface3),
          children: [
            if (showRowNum) headerCell('#', rightAlign: true),
            ...headers.map((h) => headerCell(h)),
          ],
        ),
        ...rows.asMap().entries.map((e) {
          final ri = e.key;
          final row = e.value;
          return TableRow(
            decoration: BoxDecoration(color: ri.isOdd && c.dark ? Colors.white.withOpacity(0.012) : null),
            children: [
              if (showRowNum) bodyCell(ri + 1, rowNum: true),
              ...List.generate(headers.length, (i) => bodyCell(i < row.length ? row[i] : null)),
            ],
          );
        }),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.r),
        border: Border.all(color: c.border),
        boxShadow: !flat && !c.dark ? [BoxShadow(color: const Color(0x121C1A16), blurRadius: 26, offset: const Offset(0, 10))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
          child: table,
        ),
      ),
    );
  }
}
