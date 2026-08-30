// SQL Pulse — visual table & index designer (full DDL).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/engines.dart' as en;
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import '../widgets/highlight.dart';

void showTableDesigner(BuildContext context, {required String mode, TableDef? existing}) {
  showSpSheet(context, (ctx) => _TableDesigner(mode: mode, existing: existing));
}

int _cid = 1;
String _newColId() => 'c${_cid++}';

class _DCol {
  final String id;
  final ColumnDef col;
  bool open;
  _DCol(this.id, this.col) : open = false;
}

class _TableDesigner extends StatefulWidget {
  final String mode; // create | alter
  final TableDef? existing;
  const _TableDesigner({required this.mode, this.existing});
  @override
  State<_TableDesigner> createState() => _TableDesignerState();
}

class _TableDesignerState extends State<_TableDesigner> {
  late TextEditingController nameCtrl;
  late List<_DCol> cols;
  late List<IndexDef> indexes;
  String tab = 'columns';
  late List<ColumnDef> beforeCols;
  late Map<ColumnDef, String> beforeIds;

  bool get isCreate => widget.mode == 'create';

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final e = en.eng(state.engine);
    nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    if (widget.existing != null) {
      beforeCols = widget.existing!.columns.map((c) => c.clone()).toList();
      cols = [];
      beforeIds = {};
      for (var i = 0; i < widget.existing!.columns.length; i++) {
        final orig = widget.existing!.columns[i];
        final id = _newColId();
        cols.add(_DCol(id, orig.clone()));
        beforeIds[beforeCols[i]] = id;
      }
      indexes = (widget.existing!.indexes).map((x) => x.clone()).toList();
    } else {
      beforeCols = [];
      beforeIds = {};
      cols = [_DCol(_newColId(), ColumnDef(name: 'id', type: e.types.first, pk: true, ai: true, nullable: false))];
      indexes = [];
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= cols.length) return;
    setState(() {
      final tmp = cols[i];
      cols[i] = cols[j];
      cols[j] = tmp;
    });
  }

  String _ddl(String engine) {
    final valid = cols.where((c) => c.col.name.trim().isNotEmpty).map((c) => c.col).toList();
    if (isCreate) {
      return en.createTableSql(nameCtrl.text.isEmpty ? 'new_table' : nameCtrl.text, valid, indexes, engine);
    }
    final after = cols.where((c) => c.col.name.trim().isNotEmpty).map((c) => c.col).toList();
    final ids = {...beforeIds};
    for (final dc in cols) {
      ids[dc.col] = dc.id;
    }
    final sql = en.alterDiffSql(nameCtrl.text, beforeCols, after, ids, engine);
    return sql.isEmpty ? '-- no changes' : sql;
  }

  void _apply() {
    final state = context.read<AppState>();
    final valid = cols.where((c) => c.col.name.trim().isNotEmpty).map((c) => c.col).toList();
    if (isCreate) {
      state.createTable(nameCtrl.text.trim(), valid, indexes);
    } else {
      final ids = {...beforeIds};
      for (final dc in cols) {
        ids[dc.col] = dc.id;
      }
      state.alterTable(widget.existing!.name, valid, beforeCols, ids, ids, _ddl(state.engine));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final engine = state.engine;
    final validCount = cols.where((c) => c.col.name.trim().isNotEmpty).length;
    final valid = nameCtrl.text.trim().isNotEmpty && validCount > 0;

    return SpSheet(
      title: isCreate ? 'New table' : 'Alter ${widget.existing!.name}',
      right: EngineTag(engine),
      onClose: () => Navigator.pop(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FieldLabel('Table name'),
        SpInput(controller: nameCtrl, autofocus: isCreate, hint: 'customers', onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        Segmented<String>(value: tab, onChange: (v) => setState(() => tab = v), items: [
          SegItem('columns', 'Columns · $validCount', icon: 'columns'),
          SegItem('indexes', 'Indexes · ${indexes.length}', icon: 'key'),
        ]),
        const SizedBox(height: 14),
        if (tab == 'columns')
          Column(children: [
            ...cols.asMap().entries.map((entry) {
              final i = entry.key;
              final dc = entry.value;
              return Padding(padding: const EdgeInsets.only(bottom: 9), child: _ColRow(
                dc: dc, engine: engine, tables: state.db[state.catalog]!.tables,
                canUp: i > 0, canDown: i < cols.length - 1,
                onChange: () => setState(() {}),
                onDelete: () => setState(() => cols.removeAt(i)),
                onUp: () => _move(i, -1), onDown: () => _move(i, 1),
              ));
            }),
            _AddBtn(label: 'Add column', onTap: () => setState(() => cols.add(_DCol(_newColId(), ColumnDef(name: '', type: en.eng(engine).types.length > 5 ? en.eng(engine).types[5] : en.eng(engine).types.first, nullable: true))))),
          ])
        else
          _IndexEditor(indexes: indexes, cols: cols.where((c) => c.col.name.trim().isNotEmpty).map((c) => c.col).toList(), onChange: () => setState(() {})),
        const SizedBox(height: 18),
        Eyebrow(isCreate ? 'CREATE statement' : 'ALTER statements'),
        const SizedBox(height: 8),
        CodeBlock(_ddl(engine), maxHeight: 200),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SpButton(label: isCreate ? 'Create table' : 'Apply changes', icon: 'check', kind: BtnKind.primary, enabled: valid, onTap: _apply)),
        ]),
      ]),
    );
  }
}

class _ColRow extends StatefulWidget {
  final _DCol dc;
  final String engine;
  final Map<String, TableDef> tables;
  final bool canUp, canDown;
  final VoidCallback onChange, onDelete, onUp, onDown;
  const _ColRow({required this.dc, required this.engine, required this.tables, required this.canUp, required this.canDown, required this.onChange, required this.onDelete, required this.onUp, required this.onDown});
  @override
  State<_ColRow> createState() => _ColRowState();
}

class _ColRowState extends State<_ColRow> {
  late TextEditingController nameCtrl;
  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.dc.col.name);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final e = en.eng(widget.engine);
    final col = widget.dc.col;
    final open = widget.dc.open;
    return SpCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10), child: Row(children: [
        Column(children: [
          GestureDetector(onTap: widget.canUp ? widget.onUp : null, child: SpIcon('chevD', size: 13, color: widget.canUp ? c.text3 : c.text4)),
          Transform.rotate(angle: 3.14159, child: GestureDetector(onTap: widget.canDown ? widget.onDown : null, child: SpIcon('chevD', size: 13, color: widget.canDown ? c.text3 : c.text4))),
        ]),
        const SizedBox(width: 8),
        Expanded(child: SpInput(controller: nameCtrl, hint: 'column_name', onChanged: (v) {
          col.name = v.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
          widget.onChange();
        })),
        if (col.pk) ...[const SizedBox(width: 6), SpBadge('PK', variant: 'pk')],
        if (col.ai) ...[const SizedBox(width: 6), SpBadge('AI', variant: 'accent')],
        if (col.fkTable != null) ...[const SizedBox(width: 6), SpBadge('FK', variant: 'fk')],
        const SizedBox(width: 6),
        GestureDetector(onTap: () => setState(() => widget.dc.open = !open), child: Transform.rotate(angle: open ? 1.5708 : 0, child: SpIcon('chevR', size: 16, color: c.text3))),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(11, 0, 11, 10), child: _typeDropdown(c, e, col)),
      if (open) Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 7, runSpacing: 7, children: [
            _toggle('Primary key', col.pk, () => setState(() {
              col.pk = !col.pk;
              if (col.pk) col.nullable = false;
              widget.onChange();
            })),
            _toggle('Auto-inc', col.ai, () => setState(() {
              col.ai = !col.ai;
              widget.onChange();
            })),
            _toggle('Nullable', col.nullable, () => setState(() {
              col.nullable = !col.nullable;
              widget.onChange();
            }), disabled: col.pk),
          ]),
          const SizedBox(height: 8),
          SpInput(controller: TextEditingController(text: col.def), hint: 'default value', onChanged: (v) {
            col.def = v;
            widget.onChange();
          }),
          const SizedBox(height: 8),
          Row(children: [
            Text('FK →', style: sans(size: 11, color: c.text3)),
            const SizedBox(width: 8),
            Expanded(child: _fkTableDropdown(c, col)),
            if (col.fkTable != null) ...[const SizedBox(width: 8), Expanded(child: _fkColDropdown(c, col))],
          ]),
          const SizedBox(height: 8),
          SpButton(label: 'Drop column', icon: 'trash', kind: BtnKind.ghost, sm: true, color: c.danger, onTap: widget.onDelete),
        ]),
      ),
    ]));
  }

  Widget _typeDropdown(SpColors c, en.EngineDef e, ColumnDef col) {
    final items = [...e.types, if (!e.types.contains(col.type)) col.type];
    return _Dropdown(value: col.type, options: items, onChange: (v) {
      col.type = v;
      widget.onChange();
    });
  }

  Widget _fkTableDropdown(SpColors c, ColumnDef col) {
    return _Dropdown(value: col.fkTable ?? '', options: ['', ...widget.tables.keys], labels: const {'': 'none'}, onChange: (v) {
      setState(() {
        col.fkTable = v.isEmpty ? null : v;
        if (col.fkTable != null) {
          final t = widget.tables[col.fkTable]!;
          col.fkCol = (t.columns.where((x) => x.pk).firstOrNull ?? t.columns.first).name;
        } else {
          col.fkCol = null;
        }
        widget.onChange();
      });
    });
  }

  Widget _fkColDropdown(SpColors c, ColumnDef col) {
    final t = widget.tables[col.fkTable]!;
    return _Dropdown(value: col.fkCol ?? '', options: t.columns.map((x) => x.name).toList(), onChange: (v) {
      setState(() {
        col.fkCol = v;
        widget.onChange();
      });
    });
  }

  Widget _toggle(String label, bool on, VoidCallback onTap, {bool disabled = false}) {
    final c = SpColors.of(context);
    return Opacity(opacity: disabled ? 0.4 : 1, child: GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: on ? c.accentSoft : c.surface2, borderRadius: BorderRadius.circular(9), border: Border.all(color: on ? c.accentLine : c.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: on ? c.accent : c.surface4, borderRadius: BorderRadius.circular(4)), child: on ? Icon(Icons.check, size: 10, color: c.accentInk) : null),
          const SizedBox(width: 6),
          Text(label, style: sans(size: 11.5, weight: FontWeight.w500, color: on ? c.accent : c.text2)),
        ]),
      ),
    ));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _Dropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final Map<String, String>? labels;
  final ValueChanged<String> onChange;
  const _Dropdown({required this.value, required this.options, this.labels, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.border2)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : (options.isNotEmpty ? options.first : null),
          isDense: true,
          isExpanded: true,
          dropdownColor: c.surface2,
          icon: SpIcon('chevD', size: 14, color: c.text3),
          style: mono(size: 12, color: c.text),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(labels?[o] ?? o, overflow: TextOverflow.ellipsis, style: mono(size: 12, color: c.text)))).toList(),
          onChanged: (v) {
            if (v != null) onChange(v);
          },
        ),
      ),
    );
  }
}

class _AddBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: c.borderStrong)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SpIcon('plus', size: 15, color: c.text2),
          const SizedBox(width: 7),
          Text(label, style: sans(size: 12.5, weight: FontWeight.w600, color: c.text2)),
        ]),
      ),
    );
  }
}

class _IndexEditor extends StatelessWidget {
  final List<IndexDef> indexes;
  final List<ColumnDef> cols;
  final VoidCallback onChange;
  const _IndexEditor({required this.indexes, required this.cols, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (indexes.isEmpty)
        SpCard(padding: const EdgeInsets.all(13), child: Text('No secondary indexes. Add one to speed up lookups on non-key columns.', style: sans(size: 12.5, color: c.text3))),
      ...indexes.asMap().entries.map((entry) {
        final i = entry.key;
        final ix = entry.value;
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: SpCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SpIcon('key', size: 14, color: c.accent),
            const SizedBox(width: 8),
            Expanded(child: SpInput(controller: TextEditingController(text: ix.name), onChanged: (v) {
              ix.name = v.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
              onChange();
            })),
            const SizedBox(width: 8),
            GestureDetector(onTap: () {
              indexes.removeAt(i);
              onChange();
            }, child: SpIcon('trash', size: 15, color: c.text4)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: cols.map((col) {
            final on = ix.columns.contains(col.name);
            return SpChip(col.name, on: on, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), onTap: () {
              if (on) {
                ix.columns.remove(col.name);
              } else {
                ix.columns.add(col.name);
              }
              onChange();
            });
          }).toList()),
          const SizedBox(height: 10),
          GestureDetector(onTap: () {
            ix.unique = !ix.unique;
            onChange();
          }, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(color: ix.unique ? c.accent : c.surface4, borderRadius: BorderRadius.circular(4)), child: ix.unique ? Icon(Icons.check, size: 10, color: c.accentInk) : null),
            const SizedBox(width: 7),
            Text('Unique index', style: sans(size: 11.5, weight: FontWeight.w500, color: ix.unique ? c.accent : c.text2)),
          ])),
        ])));
      }),
      _AddBtn(label: 'Add index', onTap: () {
        indexes.add(IndexDef(name: 'idx_${cols.isNotEmpty ? cols.first.name : 'new'}', columns: cols.isNotEmpty ? [cols.first.name] : [], unique: false));
        onChange();
      }),
    ]);
  }
}
