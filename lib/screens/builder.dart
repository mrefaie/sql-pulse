// SQL Pulse — advanced visual query builder (+ compact sub-builder).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/engines.dart' as en;
import '../engine/sql_engine.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import '../widgets/highlight.dart';

const _qbOps = ['=', '!=', '>', '<', '>=', '<=', 'LIKE', 'IN', 'IS NULL', 'IS NOT NULL'];
const _qbAggs = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];

class QueryBuilder extends StatefulWidget {
  const QueryBuilder({super.key});
  @override
  State<QueryBuilder> createState() => _BuilderState();
}

class _BuilderState extends State<QueryBuilder> {
  late QuerySpec spec;
  final Map<Object, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final cat = state.db[state.catalog]!;
    final names = cat.tables.keys.toList();
    final init = names.contains(state.table) ? state.table : names.first;
    spec = QuerySpec(table: init, limit: '50', offset: '0');
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(Object key, String initial) {
    return _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  void _refresh() => setState(() {});

  List<({String table, String col})> _colsFor(en.EngineDef e, Map<String, TableDef> tables, List<String> tableNames) {
    final out = <({String table, String col})>[];
    for (final tn in tableNames) {
      final t = tables[tn];
      if (t == null) continue;
      for (final col in t.columns) {
        out.add((table: tn, col: col.name));
      }
    }
    return out;
  }

  List<QbJoin> _joinCandidates(Map<String, TableDef> tables, List<String> avail) {
    final cand = <QbJoin>[];
    final seen = avail.toSet();
    for (final at in avail) {
      final t = tables[at];
      if (t == null) continue;
      for (final col in t.columns) {
        if (col.fkTable != null && !seen.contains(col.fkTable)) {
          cand.add(QbJoin(type: 'INNER', leftTable: at, leftCol: col.name, table: col.fkTable!, rightCol: col.fkCol ?? 'id'));
        }
      }
      for (final ot in tables.values) {
        if (seen.contains(ot.name)) continue;
        for (final col in ot.columns) {
          if (col.fkTable == at) {
            cand.add(QbJoin(type: 'INNER', leftTable: at, leftCol: col.fkCol ?? 'id', table: ot.name, rightCol: col.name));
          }
        }
      }
    }
    final uniq = <QbJoin>[];
    final t2 = <String>{};
    for (final c in cand) {
      if (!t2.contains(c.table)) {
        t2.add(c.table);
        uniq.add(c);
      }
    }
    return uniq;
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cat = state.db[state.catalog]!;
    final e = en.eng(state.engine);
    final tableNames = cat.tables.keys.toList();
    final t = cat.tables[spec.table];
    final availTables = [spec.table, ...spec.joins.map((j) => j.table)];
    final availCols = _colsFor(e, cat.tables, availTables);
    final cands = _joinCandidates(cat.tables, availTables);
    final outs = SqlEngine.resolveCols(spec, cat);
    final hasAgg = spec.columns.any((col) => col.agg != null);
    final showHaving = spec.groupBy.isNotEmpty || hasAgg;
    final sql = SqlEngine.buildSqlFromSpec(spec, cat, state.engine);

    String colKey(({String table, String col}) x) => '${x.table}.${x.col}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // FROM
      _Section(title: 'From', icon: 'table', accent: c.accent, trailing: Text('${t?.rows.length ?? 0} rows', style: mono(size: 9, weight: FontWeight.w700, color: c.text3)), child: Wrap(spacing: 7, runSpacing: 7, children: tableNames.map((n) =>
          SpChip(n, on: spec.table == n, onTap: () => setState(() {
            spec.table = n;
            spec.columns = [];
            spec.joins = [];
            spec.filters = [];
            spec.groupBy = [];
            spec.having = null;
            spec.orderBy = [];
          }))).toList())),
      const SizedBox(height: 20),

      // SELECT
      _Section(title: 'Select', icon: 'columns', accent: c.synFn, count: spec.columns.isEmpty ? '*' : '${spec.columns.length}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (spec.columns.isEmpty)
          SpCard(color: c.surface2, padding: const EdgeInsets.all(12), child: Text('All columns (*) — add columns to project or aggregate.', style: sans(size: 12.5, color: c.text3))),
        ...spec.columns.asMap().entries.map((entry) {
          final i = entry.key;
          final col = entry.value;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: _qbRow(c, wrap: true, children: [
            SizedBox(width: 92, child: _Dropdown(value: col.agg ?? '', options: const ['', ..._qbAggs], labels: const {'': 'no agg'}, onChange: (v) => setState(() {
              col.agg = v.isEmpty ? null : v;
              if (v == 'COUNT' && col.col.isEmpty) col.col = '*';
            }))),
            Expanded(child: _Dropdown(value: col.col == '*' ? '*' : '${col.table}.${col.col}', options: [if (col.agg == 'COUNT') '*', ...availCols.map(colKey)], labels: {for (final x in availCols) colKey(x): x.col, '*': '✱ all rows'}, onChange: (v) => setState(() {
              if (v == '*') {
                col.table = spec.table;
                col.col = '*';
              } else {
                col.table = v.split('.').first;
                col.col = v.split('.').skip(1).join('.');
              }
            }))),
            _delBtn(() => setState(() => spec.columns.removeAt(i))),
            SizedBox(width: double.infinity, child: _LiveField(controller: _ctrl('alias$i${identityHashCode(col)}', col.alias), hint: 'alias (optional)', sm: true, onChanged: (v) {
              col.alias = v;
              _refresh();
            })),
          ]));
        }),
        _addBtn('Add column', () => setState(() => spec.columns.add(QbColumn(table: spec.table, col: t!.columns.first.name)))),
      ])),
      const SizedBox(height: 20),

      // JOINS
      _Section(title: 'Joins', icon: 'branch', accent: c.info, count: '${spec.joins.length}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...spec.joins.asMap().entries.map((entry) {
          final i = entry.key;
          final j = entry.value;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: SpCard(padding: const EdgeInsets.all(11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(width: 130, child: Segmented<String>(value: j.type, onChange: (v) => setState(() => j.type = v), btnPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), fontSize: 11, items: const [SegItem('INNER', 'INNER'), SegItem('LEFT', 'LEFT')])),
              const SizedBox(width: 8),
              Expanded(child: Text(j.table, style: mono(size: 12.5, weight: FontWeight.w700, color: c.text))),
              _delBtn(() => setState(() {
                final removed = spec.joins[i].table;
                spec.joins.removeAt(i);
                spec.columns.removeWhere((x) => x.table == removed);
                spec.filters.removeWhere((x) => x.table == removed);
                spec.groupBy.removeWhere((x) => x.table == removed);
              })),
            ]),
            const SizedBox(height: 7),
            Text('ON ${j.leftTable}.${j.leftCol} = ${j.table}.${j.rightCol}', style: mono(size: 10.5, color: c.text3)),
          ])));
        }),
        if (cands.isNotEmpty)
          _addBtn('Add join', () => _addJoinSheet(context, cands))
        else if (spec.joins.isEmpty)
          SpCard(color: c.surface2, padding: const EdgeInsets.all(12), child: Text('No related tables to join from ${spec.table}.', style: sans(size: 12.5, color: c.text3))),
      ])),
      const SizedBox(height: 20),

      // WHERE
      _Section(title: 'Where', icon: 'filter', accent: c.warning, count: '${spec.filters.length}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...spec.filters.asMap().entries.map((entry) {
          final i = entry.key;
          final f = entry.value;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: SpCard(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (i > 0)
                GestureDetector(onTap: () => setState(() => f.conj = f.conj == 'AND' ? 'OR' : 'AND'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(7), border: Border.all(color: c.accentLine)), child: Text(f.conj, style: mono(size: 11, weight: FontWeight.w700, color: c.accent))))
              else
                Text('WHERE', style: mono(size: 9, weight: FontWeight.w700, color: c.text4)),
              const SizedBox(width: 8),
              Expanded(child: _Dropdown(value: '${f.table}.${f.col}', options: availCols.map(colKey).toList(), labels: {for (final x in availCols) colKey(x): x.col}, onChange: (v) => setState(() {
                f.table = v.split('.').first;
                f.col = v.split('.').skip(1).join('.');
              }))),
              const SizedBox(width: 8),
              _delBtn(() => setState(() => spec.filters.removeAt(i))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 116, child: _Dropdown(value: f.op, options: _qbOps, onChange: (v) => setState(() => f.op = v))),
              if (f.sub == null && !f.op.contains('NULL')) ...[
                const SizedBox(width: 8),
                Expanded(child: _LiveField(controller: _ctrl('fval${identityHashCode(f)}', f.value), hint: 'value', sm: true, onChanged: (v) {
                  f.value = v;
                  _refresh();
                })),
              ],
              if (!f.op.contains('NULL')) ...[
                const SizedBox(width: 8),
                SpChip('Subquery', icon: 'layers', on: f.sub != null, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), onTap: () => setState(() {
                  f.sub = f.sub != null ? null : QuerySpec(table: cat.tables.keys.first);
                  f.value = '';
                })),
              ],
            ]),
            if (f.sub != null) Padding(padding: const EdgeInsets.only(top: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Divider(color: c.border, height: 1),
              const SizedBox(height: 8),
              Eyebrow('${f.op} ( subquery )', color: c.accent),
              const SizedBox(height: 8),
              SubBuilder(spec: f.sub!, oneCol: true, onChanged: _refresh),
            ])),
          ])));
        }),
        _addBtn('Add condition', () => setState(() {
          final col = availCols.first;
          spec.filters.add(QbFilter(table: col.table, col: col.col));
        })),
      ])),
      const SizedBox(height: 20),

      // GROUP BY
      _Section(title: 'Group by', icon: 'grid', accent: c.lime, count: '${spec.groupBy.length}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 7, runSpacing: 7, children: availCols.map((col) {
          final on = spec.groupBy.any((g) => g.table == col.table && g.col == col.col);
          return SpChip(col.col, on: on, onTap: () => setState(() {
            if (on) {
              spec.groupBy.removeWhere((g) => g.table == col.table && g.col == col.col);
            } else {
              spec.groupBy.add(QbGroup(col.table, col.col));
            }
          }));
        }).toList()),
        if (showHaving) ...[
          const SizedBox(height: 12),
          const Eyebrow('Having'),
          const SizedBox(height: 8),
          if (spec.having != null)
            SpCard(padding: const EdgeInsets.all(10), child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 86, child: _Dropdown(value: spec.having!.agg, options: _qbAggs, onChange: (v) => setState(() => spec.having!.agg = v))),
              SizedBox(width: 110, child: _Dropdown(value: spec.having!.col == '*' ? '*' : '${spec.having!.table ?? spec.table}.${spec.having!.col}', options: ['*', ...availCols.map(colKey)], labels: {for (final x in availCols) colKey(x): x.col, '*': '✱'}, onChange: (v) => setState(() {
                if (v == '*') {
                  spec.having!.col = '*';
                } else {
                  spec.having!.table = v.split('.').first;
                  spec.having!.col = v.split('.').skip(1).join('.');
                }
              }))),
              SizedBox(width: 64, child: _Dropdown(value: spec.having!.op, options: const ['>', '<', '>=', '<=', '=', '!='], onChange: (v) => setState(() => spec.having!.op = v))),
              SizedBox(width: 80, child: _LiveField(controller: _ctrl('hval', spec.having!.value), hint: 'value', sm: true, onChanged: (v) {
                spec.having!.value = v;
                _refresh();
              })),
              _delBtn(() => setState(() => spec.having = null)),
            ]))
          else
            _addBtn('Add HAVING filter', () => setState(() => spec.having = QbHaving(agg: 'COUNT', table: spec.table, col: '*', op: '>', value: '1'))),
        ],
      ])),
      const SizedBox(height: 20),

      // ORDER BY
      _Section(title: 'Order by', icon: 'sliders', accent: c.synFn, count: '${spec.orderBy.length}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...spec.orderBy.asMap().entries.map((entry) {
          final i = entry.key;
          final o = entry.value;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: _qbRow(c, children: [
            Expanded(child: _Dropdown(value: outs.any((x) => x['label'] == o.label) ? o.label : (outs.isNotEmpty ? outs.first['label'] as String : ''), options: outs.map((x) => x['label'] as String).toList(), onChange: (v) => setState(() => o.label = v))),
            const SizedBox(width: 8),
            SizedBox(width: 130, child: Segmented<String>(value: o.dir, onChange: (v) => setState(() => o.dir = v), btnPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), fontSize: 11, items: const [SegItem('ASC', 'ASC'), SegItem('DESC', 'DESC')])),
            const SizedBox(width: 8),
            _delBtn(() => setState(() => spec.orderBy.removeAt(i))),
          ]));
        }),
        _addBtn('Add sort', () => setState(() {
          if (outs.isNotEmpty) spec.orderBy.add(QbOrder(outs.first['label'] as String, 'ASC'));
        })),
      ])),
      const SizedBox(height: 20),

      // OPTIONS
      _Section(title: 'Options', icon: 'cog', accent: c.text2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpCard(color: c.surface2, padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DISTINCT', style: sans(size: 13, weight: FontWeight.w600, color: c.text)),
            Text('Remove duplicate rows', style: sans(size: 11, color: c.text3)),
          ])),
          SpSwitch(on: spec.distinct, onToggle: () => setState(() => spec.distinct = !spec.distinct)),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Limit'),
            _LiveField(controller: _ctrl('limit', spec.limit), hint: 'none', keyboardType: TextInputType.number, onChanged: (v) {
              spec.limit = v.replaceAll(RegExp(r'[^0-9]'), '');
              _refresh();
            }),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Offset'),
            _LiveField(controller: _ctrl('offset', spec.offset), hint: '0', keyboardType: TextInputType.number, onChanged: (v) {
              spec.offset = v.replaceAll(RegExp(r'[^0-9]'), '');
              _refresh();
            }),
          ])),
        ]),
      ])),
      const SizedBox(height: 20),

      // COMPILED + RUN
      Row(children: [
        const Expanded(child: Eyebrow('Compiled SQL')),
        SpChip('Edit as SQL', icon: 'terminal', onTap: () => state.loadIntoConsole(sql)),
      ]),
      const SizedBox(height: 8),
      CodeBlock(sql),
      const SizedBox(height: 12),
      SpButton(label: 'Run query', icon: 'play', kind: BtnKind.primary, block: true, onTap: () => state.runBuilder(spec, sql)),
    ]);
  }

  void _addJoinSheet(BuildContext context, List<QbJoin> cands) {
    showSpSheet(context, (ctx) {
      final c = SpColors.of(ctx);
      return SpSheet(title: 'Add join', onClose: () => Navigator.pop(ctx), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('Related tables'),
        const SizedBox(height: 12),
        ...cands.map((cand) => Padding(padding: const EdgeInsets.only(bottom: 9), child: SpRow(onTap: () {
          setState(() => spec.joins.add(QbJoin(type: 'INNER', leftTable: cand.leftTable, leftCol: cand.leftCol, table: cand.table, rightCol: cand.rightCol)));
          Navigator.pop(ctx);
        }, child: Row(children: [
          RowIco('branch', iconSize: 16),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cand.table, style: mono(size: 13, weight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 2),
            Text('${cand.leftTable}.${cand.leftCol} → ${cand.table}', style: mono(size: 10.5, color: c.text3)),
          ])),
          SpIcon('plus', size: 17, color: c.accent),
        ])))),
      ]));
    });
  }

  Widget _qbRow(SpColors c, {required List<Widget> children, bool wrap = false}) {
    final content = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11), border: Border.all(color: c.border)),
      child: wrap ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children) : Row(children: children),
    );
    return content;
  }

  Widget _delBtn(VoidCallback onTap) {
    final c = SpColors.of(context);
    return GestureDetector(onTap: onTap, child: Container(width: 30, height: 30, alignment: Alignment.center, child: SpIcon('trash', size: 15, color: c.text3)));
  }

  Widget _addBtn(String label, VoidCallback onTap) {
    final c = SpColors.of(context);
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: c.borderStrong)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SpIcon('plus', size: 15, color: c.text2), const SizedBox(width: 7), Text(label, style: sans(size: 12.5, weight: FontWeight.w600, color: c.text2))]),
    ));
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String icon;
  final Color accent;
  final String? count;
  final Widget? trailing;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.accent, this.count, this.trailing, required this.child});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 22, height: 22, decoration: BoxDecoration(color: accent.withOpacity(0.13), borderRadius: BorderRadius.circular(7)), alignment: Alignment.center, child: SpIcon(icon, size: 13, color: accent)),
        const SizedBox(width: 9),
        Text(title, style: sans(size: 13.5, weight: FontWeight.w700, color: c.text, spacing: -0.2)),
        const Spacer(),
        if (trailing != null) trailing! else if (count != null) Text(count!, style: mono(size: 9, weight: FontWeight.w700, color: c.text3)),
      ]),
      const SizedBox(height: 11),
      child,
    ]);
  }
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
    final opts = options.toSet().toList();
    final val = opts.contains(value) ? value : (opts.isNotEmpty ? opts.first : null);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.border2)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: val,
        isDense: true,
        isExpanded: true,
        dropdownColor: c.surface2,
        icon: SpIcon('chevD', size: 14, color: c.text3),
        style: mono(size: 12, color: c.text),
        items: opts.map((o) => DropdownMenuItem(value: o, child: Text(labels?[o] ?? o, overflow: TextOverflow.ellipsis, style: mono(size: 12, color: c.text)))).toList(),
        onChanged: (v) {
          if (v != null) onChange(v);
        },
      )),
    );
  }
}

/// A text field whose controller is owned by the parent (cursor-stable).
class _LiveField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool sm;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;
  const _LiveField({required this.controller, this.hint, this.sm = false, this.keyboardType, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: mono(size: sm ? 12 : 13, color: c.text),
      cursorColor: c.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: mono(size: sm ? 12 : 13, color: c.text4),
        filled: true,
        fillColor: c.surface2,
        contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: sm ? 9 : 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(sm ? 9 : 11), borderSide: BorderSide(color: c.border2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(sm ? 9 : 11), borderSide: BorderSide(color: c.border2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(sm ? 9 : 11), borderSide: BorderSide(color: c.accentLine)),
      ),
    );
  }
}

/// Compact sub-query builder used for CTEs and WHERE subqueries.
class SubBuilder extends StatefulWidget {
  final QuerySpec spec;
  final bool oneCol;
  final VoidCallback onChanged;
  const SubBuilder({super.key, required this.spec, this.oneCol = false, required this.onChanged});
  @override
  State<SubBuilder> createState() => _SubBuilderState();
}

class _SubBuilderState extends State<SubBuilder> {
  final Map<Object, TextEditingController> _ctrls = {};
  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(Object key, String initial) => _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cat = state.db[state.catalog]!;
    final spec = widget.spec;
    final tableNames = cat.tables.keys.toList();
    final t = cat.tables[spec.table] ?? cat.tables[tableNames.first]!;
    final cols = t.columns.map((x) => x.name).toList();
    final c0 = spec.columns.isNotEmpty ? spec.columns.first : null;
    final f0 = spec.filters.isNotEmpty ? spec.filters.first : null;

    void setProj({String? agg, String? col}) {
      if (spec.columns.isEmpty) spec.columns.add(QbColumn(table: spec.table, col: c0?.col ?? cols.first));
      final x = spec.columns.first;
      if (agg != null) x.agg = agg.isEmpty ? null : agg;
      if (col != null) x.col = col;
      widget.onChanged();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('From'),
      const SizedBox(height: 6),
      _Dropdown(value: spec.table, options: tableNames, onChange: (v) => setState(() {
        spec.table = v;
        spec.columns = [];
        spec.filters = [];
        widget.onChanged();
      })),
      const SizedBox(height: 9),
      Eyebrow(widget.oneCol ? 'Return column' : 'Select'),
      const SizedBox(height: 6),
      Row(children: [
        SizedBox(width: 84, child: _Dropdown(value: c0?.agg ?? '', options: const ['', ..._qbAggs], labels: const {'': 'no agg'}, onChange: (v) => setProj(agg: v))),
        const SizedBox(width: 7),
        Expanded(child: _Dropdown(value: c0?.col ?? cols.first, options: cols, onChange: (v) => setProj(col: v))),
      ]),
      const SizedBox(height: 9),
      Row(children: [const Eyebrow('Where'), const SizedBox(width: 4), Text('· optional', style: sans(size: 10.5, color: c.text4))]),
      const SizedBox(height: 6),
      if (f0 != null)
        Wrap(spacing: 7, runSpacing: 7, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 110, child: _Dropdown(value: f0.col, options: cols, onChange: (v) => setState(() {
            f0.table = spec.table;
            f0.col = v;
            widget.onChanged();
          }))),
          SizedBox(width: 64, child: _Dropdown(value: f0.op, options: const ['=', '!=', '>', '<', '>=', '<=', 'LIKE'], onChange: (v) => setState(() {
            f0.op = v;
            widget.onChanged();
          }))),
          SizedBox(width: 90, child: _LiveField(controller: _ctrl('subval', f0.value), hint: 'value', sm: true, onChanged: (v) {
            f0.value = v;
            widget.onChanged();
          })),
          GestureDetector(onTap: () => setState(() {
            spec.filters.clear();
            widget.onChanged();
          }), child: SpIcon('x', size: 14, color: c.text3)),
        ])
      else
        GestureDetector(onTap: () => setState(() {
          spec.filters.add(QbFilter(table: spec.table, col: cols.first));
          widget.onChanged();
        }), child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: c.borderStrong)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SpIcon('plus', size: 14, color: c.text2), const SizedBox(width: 6), Text('Add filter', style: sans(size: 12, weight: FontWeight.w600, color: c.text2))]))),
    ]);
  }
}
