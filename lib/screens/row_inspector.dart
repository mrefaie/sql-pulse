// SQL Pulse — quick row inspector (tap a row → detail + actions).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../data/mask.dart' as mask;
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';

class RowInspector extends StatefulWidget {
  final String table;
  final List<ColumnDef> columns;
  final RowMap row;
  final int rowIndex;
  final void Function(String col, Object? val) onFilter;
  const RowInspector({super.key, required this.table, required this.columns, required this.row, required this.rowIndex, required this.onFilter});
  @override
  State<RowInspector> createState() => _RowInspectorState();
}

class _RowInspectorState extends State<RowInspector> {
  String? flash;

  void _note(String msg) {
    setState(() => flash = msg);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => flash = null);
    });
  }

  String _asJson() => const JsonEncoder.withIndent('  ').convert({for (final c in widget.columns) c.name: widget.row[c.name]});

  String _asInsert() {
    String q(Object? v) => v == null ? 'NULL' : (RegExp(r'^-?\d+(\.\d+)?$').hasMatch('$v') ? '$v' : "'${'$v'.replaceAll("'", "''")}'");
    return 'INSERT INTO ${widget.table} (${widget.columns.map((c) => c.name).join(', ')})\nVALUES (${widget.columns.map((c) => q(widget.row[c.name])).join(', ')});';
  }

  Future<void> _copy(String text, String label) async {
    final ok = await Store.copy(text);
    _note(ok ? '$label copied' : 'Copy unavailable here');
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final pkCol = widget.columns.firstWhere((x) => x.pk, orElse: () => widget.columns.first);

    return Stack(children: [
      SpSheet(
        title: '${pkCol.name} = ${widget.row[pkCol.name] ?? 'NULL'}',
        right: SpBadge(widget.table, variant: 'accent'),
        onClose: () => Navigator.pop(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...widget.columns.map((col) {
            final v = widget.row[col.name];
            final isNum = v is num;
            final shown = state.masking && mask.isSensitiveCol(col.name) && v != null ? mask.maskValue(v, col.name) : (v == null ? 'NULL' : '$v');
            return Padding(padding: const EdgeInsets.only(bottom: 7), child: SpCard(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SpIcon(col.pk ? 'key' : col.fkTable != null ? 'link' : 'columns', size: 12, color: col.pk ? c.warning : col.fkTable != null ? c.info : c.text4),
                const SizedBox(width: 7),
                Expanded(child: Text(col.name, style: mono(size: 11, color: c.text3))),
                Text(col.type, style: mono(size: 9.5, color: c.text4)),
                const SizedBox(width: 8),
                GestureDetector(onTap: () {
                  widget.onFilter(col.name, v);
                }, child: SpIcon('filter', size: 13, color: c.text4)),
              ]),
              const SizedBox(height: 5),
              Row(children: [
                Flexible(child: Text(shown, style: mono(size: 13, weight: FontWeight.w600, color: v == null ? c.text4 : isNum ? c.synNum : c.text, height: 1).copyWith(fontStyle: v == null ? FontStyle.italic : FontStyle.normal))),
                if (col.fkTable != null && v != null) ...[
                  const SizedBox(width: 8),
                  SpChip(col.fkTable!, icon: 'arrowR2', padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), onTap: () {
                    state.openTable(col.fkTable!);
                    Navigator.pop(context);
                  }),
                ],
              ]),
            ])));
          }),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 4.2,
            children: [
              SpButton(label: 'Copy JSON', icon: 'copy', kind: BtnKind.ghost, sm: true, onTap: () => _copy(_asJson(), 'JSON')),
              SpButton(label: 'Copy INSERT', icon: 'code', kind: BtnKind.ghost, sm: true, onTap: () => _copy(_asInsert(), 'INSERT')),
              SpButton(label: 'As INSERT', icon: 'terminal', kind: BtnKind.ghost, sm: true, onTap: () {
                state.loadIntoConsole(_asInsert());
                Navigator.pop(context);
              }),
              state.role != 'ReadOnly'
                  ? SpButton(label: 'Delete row', icon: 'trash', kind: BtnKind.danger, sm: true, onTap: () {
                      state.deleteRow(widget.table, widget.rowIndex);
                      Navigator.pop(context);
                    })
                  : SpButton(label: 'Read-only', icon: 'lock', kind: BtnKind.ghost, sm: true, enabled: false),
            ],
          ),
        ]),
      ),
      if (flash != null)
        Positioned(top: 14, left: 0, right: 0, child: Center(child: SpBadge(flash!, variant: 'ok', padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)))),
    ]);
  }
}
