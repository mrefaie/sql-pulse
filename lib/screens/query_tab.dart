// SQL Pulse — Query (console + results + EXPLAIN); Builder lives in builder.dart.
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
import '../widgets/grid.dart';
import 'builder.dart';
import 'board_tab.dart';

class QueryTab extends StatefulWidget {
  const QueryTab({super.key});
  @override
  State<QueryTab> createState() => _QueryTabState();
}

class _QueryTabState extends State<QueryTab> {
  late String mode;
  late int _lastSignal;
  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _lastSignal = state.consoleSignal;
    mode = state.consoleSignal > 0 ? 'sql' : 'builder';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.consoleSignal != _lastSignal) {
      _lastSignal = state.consoleSignal;
      mode = 'sql';
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Segmented<String>(value: mode, onChange: (v) => setState(() => mode = v), items: const [
          SegItem('builder', 'Visual builder', icon: 'sliders'),
          SegItem('sql', 'SQL', icon: 'terminal'),
        ]),
        const SizedBox(height: 14),
        mode == 'builder' ? const QueryBuilder() : const Console(),
        const ResultsPanel(),
      ],
    );
  }
}

class Console extends StatefulWidget {
  const Console({super.key});
  @override
  State<Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<Console> {
  late TextEditingController ctrl;
  late int _lastSignal;
  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    ctrl = TextEditingController(text: state.sql);
    _lastSignal = state.consoleSignal;
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _setSql(String v) {
    ctrl.text = v;
    context.read<AppState>().setSql(v);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    if (state.consoleSignal != _lastSignal) {
      _lastSignal = state.consoleSignal;
      ctrl.text = state.sql;
    }
    final e = en.eng(state.engine);
    final stmtCount = SqlEngine.splitStatements(state.sql).length;
    final isBatch = stmtCount > 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Eyebrow('SQL console · ${state.role} role')),
        SpChip('Saved${state.saved.isNotEmpty ? ' · ${state.saved.length}' : ''}', icon: 'bookmark', padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), onTap: () => _savedSheet(context)),
        const SizedBox(width: 6),
        EngineTag(state.engine),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11), border: Border.all(color: c.border2)),
        child: TextField(
          controller: ctrl,
          onChanged: (v) => state.setSql(v),
          minLines: 6,
          maxLines: 14,
          style: mono(size: 13, color: c.text, height: 1.6),
          cursorColor: c.accent,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.all(13)),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: e.snippets.map((s) => Padding(padding: const EdgeInsets.only(right: 7), child: SpChip(s[0], onTap: () => _setSql(s[1])))).toList())),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(width: 46, child: SpButton(icon: 'bookmark', kind: BtnKind.ghost, sm: true, onTap: () => _saveDialog(context))),
        const SizedBox(width: 10),
        SizedBox(width: 46, child: SpButton(icon: 'spark', kind: BtnKind.ghost, sm: true, onTap: () => _setSql(SqlEngine.formatSql(state.sql, state.engine)))),
        const SizedBox(width: 10),
        Expanded(child: SpButton(label: 'Explain', icon: 'gauge', kind: BtnKind.ghost, onTap: () => state.explainCurrent(state.sql))),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: isBatch
            ? SpButton(label: 'Run all · $stmtCount', icon: 'layers', kind: BtnKind.primary, onTap: () => state.runScript(state.sql))
            : SpButton(label: 'Run', icon: 'play', kind: BtnKind.primary, onTap: () => _attemptRun(context))),
      ]),
    ]);
  }

  ({String verb, bool noWhere, bool prod})? _guardCheck(BuildContext context) {
    final state = context.read<AppState>();
    if (state.prefs['guard'] == false) return null;
    final s = state.sql.trim();
    final m = RegExp(r'^\s*(update|delete|drop|truncate)', caseSensitive: false).firstMatch(s);
    if (m == null) return null;
    final verb = m.group(1)!.toLowerCase();
    final noWhere = RegExp(r'^(update|delete)', caseSensitive: false).hasMatch(s) && !RegExp(r'\bwhere\b', caseSensitive: false).hasMatch(s);
    if (!state.isProd() && !noWhere && verb != 'drop' && verb != 'truncate') return null;
    return (verb: verb, noWhere: noWhere, prod: state.isProd());
  }

  void _attemptRun(BuildContext context) {
    final g = _guardCheck(context);
    final state = context.read<AppState>();
    if (g == null) {
      state.run(state.sql);
    } else {
      _guardDialog(context, g);
    }
  }

  void _guardDialog(BuildContext context, ({String verb, bool noWhere, bool prod}) g) {
    final state = context.read<AppState>();
    showSpDialog(context, (ctx) {
      final c = SpColors.of(ctx);
      return SpDialog(
        icon: 'warn2', iconColor: c.danger,
        title: g.noWhere ? '${g.verb.toUpperCase()} without WHERE' : 'Confirm ${g.verb.toUpperCase()}',
        sub: Text(g.noWhere
            ? 'This ${g.verb} has no WHERE clause and will affect every row${g.prod ? ' on a production connection' : ''}.'
            : 'You\'re about to run a ${g.verb} on ${state.profile?.name ?? 'this connection'}${g.prod ? ' — a production environment' : ''}.'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (g.prod)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: SpCard(color: c.dangerSoft, borderColor: Colors.transparent, padding: const EdgeInsets.all(10), child: Row(children: [
              SpIcon('alert', size: 15, color: c.danger),
              const SizedBox(width: 8),
              Expanded(child: Text('Production · ${state.profile?.host}', style: sans(size: 11.5, weight: FontWeight.w600, color: c.danger))),
            ]))),
          CodeBlock(state.sql, fontSize: 11, maxHeight: 100),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: SpButton(label: 'Run anyway', icon: 'check', kind: BtnKind.danger, onTap: () {
              Navigator.pop(ctx);
              state.run(state.sql);
            })),
          ]),
        ]),
      );
    });
  }

  void _saveDialog(BuildContext context) {
    final state = context.read<AppState>();
    final nameCtrl = TextEditingController();
    showSpDialog(context, (ctx) => SpDialog(
          icon: 'bookmark', title: 'Save query', sub: const Text('Stored on this device only.'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SpInput(controller: nameCtrl, hint: 'Query name', mono: false, autofocus: true),
            const SizedBox(height: 12),
            CodeBlock(state.sql, fontSize: 11, maxHeight: 100),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: SpButton(label: 'Save', icon: 'check', kind: BtnKind.primary, onTap: () {
                state.saveQuery(nameCtrl.text, state.sql);
                Navigator.pop(ctx);
              })),
            ]),
          ]),
        ));
  }

  void _savedSheet(BuildContext context) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
          final c = SpColors.of(ctx);
          return SpSheet(
            title: 'Saved queries',
            right: SpBadge('${state.saved.length}'),
            onClose: () => Navigator.pop(ctx),
            child: state.saved.isEmpty
                ? const Empty(icon: 'bookmark', title: 'No saved queries', sub: 'Write a query and tap the bookmark to save it on this device.')
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: state.saved.map((s) => Padding(padding: const EdgeInsets.only(bottom: 9), child: SpCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        SpIcon('bookmark', size: 14, color: c.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis, style: sans(size: 13.5, weight: FontWeight.w700, color: c.text))),
                        EngineTag(s.engine, fontSize: 9),
                        const SizedBox(width: 8),
                        GestureDetector(onTap: () {
                          state.deleteSaved(s.id);
                          setSheet(() {});
                        }, child: SpIcon('trash', size: 15, color: c.text4)),
                      ]),
                      const SizedBox(height: 8),
                      CodeBlock(s.sql, fontSize: 11, maxHeight: 92),
                      const SizedBox(height: 9),
                      SpButton(label: 'Load into console', icon: 'terminal', sm: true, block: true, onTap: () {
                        _setSql(s.sql);
                        Navigator.pop(ctx);
                      }),
                    ])))).toList()),
          );
        }));
  }
}

// ---- results panel ----
class ResultsPanel extends StatefulWidget {
  const ResultsPanel({super.key});
  @override
  State<ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends State<ResultsPanel> {
  String view = 'table';
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final res = state.result;
    if (res == null) {
      return Padding(padding: const EdgeInsets.only(top: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
        Eyebrow('Results'),
        SizedBox(height: 10),
        Empty(icon: 'rows', title: 'No results yet', sub: 'Build a query or run a statement to see rows here.'),
      ]));
    }
    if (res.explain != null) return _ExplainView(res: res);
    if (res.batch != null) return _BatchView(res: res);

    final tabular = !res.denied && !res.error && !res.status && res.headers != null;
    final srcName = (RegExp(r'''from\s+[`"\[]?(\w+)''', caseSensitive: false).firstMatch(state.sql)?.group(1)) ?? 'result';
    final hasRows = tabular && res.rows!.isNotEmpty;

    return Padding(padding: const EdgeInsets.only(top: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Eyebrow('Results')),
        if (hasRows) ...[
          _ExportMenu(sourceName: srcName),
          const SizedBox(width: 8),
          SpChip('Pin', icon: 'grid', padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), onTap: () => showSpDialog(context, (_) => const PinDialog())),
          const SizedBox(width: 8),
          SizedBox(width: 150, child: Segmented<String>(value: view, onChange: (v) => setState(() => view = v), iconOnly: true, btnPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), items: const [
            SegItem('table', '', icon: 'table'),
            SegItem('cards', '', icon: 'grid'),
            SegItem('json', '', icon: 'code'),
            SegItem('chart', '', icon: 'chart'),
          ])),
        ],
      ]),
      const SizedBox(height: 4),
      Align(alignment: Alignment.centerRight, child: Text('${res.ms} ms', style: mono(size: 11, color: c.text3))),
      const SizedBox(height: 8),
      if (res.denied || res.error)
        SpCard(color: res.denied ? c.warningSoft : c.dangerSoft, borderColor: Colors.transparent, padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SpIcon(res.denied ? 'lock' : 'alert', size: 17, color: res.denied ? c.warning : c.danger),
            const SizedBox(width: 9),
            Text(res.denied ? 'Access denied' : 'Statement error', style: sans(size: 13, weight: FontWeight.w700, color: res.denied ? c.warning : c.danger)),
          ]),
          const SizedBox(height: 9),
          Text(res.message ?? '', style: mono(size: 12, color: c.text2, height: 1.5)),
        ]))
      else if (res.status)
        SpCard(color: c.successSoft, borderColor: Colors.transparent, padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [SpIcon('check', size: 17, color: c.success), const SizedBox(width: 9), Text('${res.statementType} executed', style: sans(size: 13, weight: FontWeight.w700, color: c.success))]),
          const SizedBox(height: 9),
          Text(res.comment ?? '', style: mono(size: 12, color: c.text2)),
        ]))
      else
        _ResultViews(headers: res.headers!, rows: res.rows!, view: view, comment: res.comment ?? ''),
    ]));
  }
}

class _ResultViews extends StatelessWidget {
  final List<String> headers;
  final List<List<Object?>> rows;
  final String view;
  final String comment;
  const _ResultViews({required this.headers, required this.rows, required this.view, required this.comment});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    if (rows.isEmpty) return const Empty(icon: 'search', title: 'No rows', sub: 'The query ran successfully but matched no rows.');
    Widget body;
    if (view == 'cards') {
      body = _ResultCards(headers: headers, rows: rows);
    } else if (view == 'json') {
      body = CodeBlock(_toJson(headers, rows), json: true, maxHeight: 460);
    } else if (view == 'chart') {
      body = _ResultChart(headers: headers, rows: rows);
    } else {
      body = ResultTable(headers: headers, rows: rows);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      body,
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(comment, style: mono(size: 11, color: c.text3))),
    ]);
  }

  String _toJson(List<String> headers, List<List<Object?>> rows) {
    final buf = StringBuffer('[\n');
    for (var ri = 0; ri < rows.length; ri++) {
      buf.write('  {\n');
      for (var i = 0; i < headers.length; i++) {
        final v = i < rows[ri].length ? rows[ri][i] : null;
        final val = v == null ? 'null' : (v is num ? '$v' : '"${'$v'.replaceAll('"', '\\"')}"');
        buf.write('    "${headers[i]}": $val${i < headers.length - 1 ? ',' : ''}\n');
      }
      buf.write('  }${ri < rows.length - 1 ? ',' : ''}\n');
    }
    buf.write(']');
    return buf.toString();
  }
}

class _ResultCards extends StatelessWidget {
  final List<String> headers;
  final List<List<Object?>> rows;
  const _ResultCards({required this.headers, required this.rows});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Column(children: rows.asMap().entries.map((entry) {
      final ri = entry.key;
      final row = entry.value;
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: SpCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10), decoration: BoxDecoration(color: c.surface2, border: Border(bottom: BorderSide(color: c.border))), child: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: c.surface4, borderRadius: BorderRadius.circular(5)), child: Text('${ri + 1}', style: mono(size: 9, weight: FontWeight.w700, color: c.text3))),
          const SizedBox(width: 9),
          Expanded(child: Text('${headers[0]}: ${row.isNotEmpty && row[0] != null ? row[0] : 'NULL'}', overflow: TextOverflow.ellipsis, style: mono(size: 12.5, weight: FontWeight.w700, color: c.text))),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(13, 4, 13, 8), child: Column(children: headers.skip(1).toList().asMap().entries.map((e) {
          final i = e.key;
          final h = e.value;
          final v = (i + 1) < row.length ? row[i + 1] : null;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(border: i < headers.length - 2 ? Border(bottom: BorderSide(color: c.border)) : null),
            child: Row(children: [
              SizedBox(width: 120, child: Text(h, overflow: TextOverflow.ellipsis, style: mono(size: 11, color: c.text3))),
              Expanded(child: Text(v == null ? 'NULL' : '$v', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: mono(size: 12, color: v == null ? c.text4 : v is num ? c.synNum : c.text).copyWith(fontStyle: v == null ? FontStyle.italic : FontStyle.normal))),
            ]),
          );
        }).toList())),
      ])));
    }).toList());
  }
}

class _ResultChart extends StatelessWidget {
  final List<String> headers;
  final List<List<Object?>> rows;
  const _ResultChart({required this.headers, required this.rows});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final numericCols = <int>[];
    for (var i = 0; i < headers.length; i++) {
      if (rows.any((r) => i < r.length && r[i] is num) && rows.every((r) => i >= r.length || r[i] == null || r[i] is num)) numericCols.add(i);
    }
    if (numericCols.isEmpty) return const Empty(icon: 'chart', title: 'No numeric column', sub: 'Add an aggregate or numeric column to visualize results as a chart.');
    bool isId(String h) => RegExp(r'(^|_)id$|_id$', caseSensitive: false).hasMatch(h);
    final numIdx = numericCols.firstWhere((i) => !isId(headers[i]), orElse: () => numericCols.first);
    var labelIdx = -1;
    for (var i = 0; i < headers.length; i++) {
      if (i != numIdx && rows.any((r) => i < r.length && r[i] is String)) {
        labelIdx = i;
        break;
      }
    }
    if (labelIdx == -1) {
      for (var i = 0; i < headers.length; i++) {
        if (i != numIdx) {
          labelIdx = i;
          break;
        }
      }
    }
    final data = rows.take(24).toList().asMap().entries.map((e) {
      final r = e.value;
      return (label: labelIdx == -1 ? '#${e.key + 1}' : (labelIdx < r.length && r[labelIdx] != null ? '${r[labelIdx]}' : 'NULL'), val: numIdx < r.length && r[numIdx] is num ? r[numIdx] as num : 0);
    }).toList();
    final max = data.map((d) => d.val.abs()).fold<num>(1, (a, b) => a > b ? a : b);
    return SpCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SpIcon('chart', size: 15, color: c.accent),
        const SizedBox(width: 8),
        Expanded(child: RichText(text: TextSpan(style: mono(size: 11.5, color: c.text2), children: [
          TextSpan(text: headers[numIdx]),
          TextSpan(text: ' by ', style: mono(size: 11.5, color: c.text4)),
          TextSpan(text: labelIdx == -1 ? 'row' : headers[labelIdx]),
        ]))),
      ]),
      const SizedBox(height: 14),
      ...data.map((d) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(children: [
        SizedBox(width: 90, child: Text(d.label, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: mono(size: 11, color: c.text2))),
        const SizedBox(width: 10),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: Container(height: 18, color: c.surface3, child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: (d.val.abs() / max).clamp(0.02, 1).toDouble(), child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [c.accent, c.accent2])))))))),
        const SizedBox(width: 10),
        SizedBox(width: 56, child: Text(d.val == d.val.roundToDouble() ? '${d.val.toInt()}' : d.val.toStringAsFixed(2), textAlign: TextAlign.right, style: mono(size: 11, color: c.synNum))),
      ]))),
    ]));
  }
}

class _ExportMenu extends StatelessWidget {
  final String sourceName;
  const _ExportMenu({required this.sourceName});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.read<AppState>();
    return PopupMenuButton<String>(
      tooltip: 'Export',
      color: c.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: c.border2)),
      onSelected: (fmt) async {
        final r = await state.exportResult(fmt, sourceName);
        if (fmt == 'copy' && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r == 'ok' ? 'Copied JSON' : 'Copy failed'), duration: const Duration(milliseconds: 1400)));
        }
      },
      itemBuilder: (ctx) => [
        _mi(ctx, 'csv', 'download', 'Download CSV'),
        _mi(ctx, 'json', 'download', 'Download JSON'),
        _mi(ctx, 'sql', 'code', 'Download INSERTs'),
        _mi(ctx, 'copy', 'copy', 'Copy as JSON'),
      ],
      child: SpChip('Export', icon: 'download', padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6)),
    );
  }

  PopupMenuItem<String> _mi(BuildContext ctx, String v, String icon, String label) {
    final c = SpColors.of(ctx);
    return PopupMenuItem(value: v, height: 40, child: Row(children: [SpIcon(icon, size: 16, color: c.text2), const SizedBox(width: 10), Text(label, style: sans(size: 13, color: c.text))]));
  }
}

// ---- batch ----
const _batchStatus = {
  'SELECT': 'info', 'DML': 'success', 'DDL': 'accent', 'DENIED': 'warning', 'SYNTAX': 'danger', 'OK': 'text2',
};

class _BatchView extends StatefulWidget {
  final QueryResult res;
  const _BatchView({required this.res});
  @override
  State<_BatchView> createState() => _BatchViewState();
}

class _BatchViewState extends State<_BatchView> {
  int? open;
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final res = widget.res;
    final ok = res.batch!.where((i) => !i.res.error && !i.res.denied).length;
    final failed = res.batch!.length - ok;
    Color statusColor(String s) => {'info': c.info, 'success': c.success, 'accent': c.accent, 'warning': c.warning, 'danger': c.danger}[_batchStatus[s] ?? 'text2'] ?? c.text2;

    return Padding(padding: const EdgeInsets.only(top: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Eyebrow('Script · ${res.batch!.length} statements')), Text('${res.ms} ms', style: mono(size: 11, color: c.text3))]),
      const SizedBox(height: 10),
      Row(children: [
        SpBadge('$ok ok', variant: 'ok'),
        if (failed > 0) ...[const SizedBox(width: 8), SpBadge('$failed failed', variant: 'err')],
      ]),
      const SizedBox(height: 12),
      ...res.batch!.asMap().entries.map((entry) {
        final i = entry.key;
        final it = entry.value;
        final st = SqlEngine.statusFor(it.res, it.sql);
        final col = statusColor(st);
        final isOpen = open == i;
        final ok2 = !it.res.error && !it.res.denied;
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: SpCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(onTap: () => setState(() => open = isOpen ? null : i), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
            Container(width: 22, height: 22, decoration: BoxDecoration(color: col.withOpacity(0.15), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: Text('${i + 1}', style: mono(size: 10.5, weight: FontWeight.w700, color: col))),
            const SizedBox(width: 9),
            SpBadge(st, fg: col, bg: col.withOpacity(0.15)),
            const SizedBox(width: 9),
            Expanded(child: Text(it.sql.replaceAll(RegExp(r'\s+'), ' '), overflow: TextOverflow.ellipsis, style: mono(size: 11.5, color: c.text2))),
            SpIcon(ok2 ? 'check' : 'alert', size: 14, color: ok2 ? c.success : c.danger),
            const SizedBox(width: 6),
            Transform.rotate(angle: isOpen ? 3.14159 : 0, child: SpIcon('chevD', size: 15, color: c.text3)),
          ]))),
          if (isOpen) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Divider(color: c.border, height: 1),
            const SizedBox(height: 10),
            CodeBlock(it.sql, fontSize: 11),
            const SizedBox(height: 10),
            if (it.res.headers != null)
              ResultTable(headers: it.res.headers!, rows: it.res.rows!.take(20).toList())
            else
              Text(it.res.message ?? it.res.comment ?? '', style: mono(size: 11.5, color: ok2 ? c.text2 : c.danger)),
          ])),
        ])));
      }),
    ]));
  }
}

// ---- explain ----
class _ExplainView extends StatefulWidget {
  final QueryResult res;
  const _ExplainView({required this.res});
  @override
  State<_ExplainView> createState() => _ExplainViewState();
}

class _ExplainViewState extends State<_ExplainView> {
  String view = 'tree';
  int sel = 0;
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final nodes = widget.res.explain!;
    final high = nodes.any((n) => n.cost == 'HIGH');
    Color costColor(String cost) => {'HIGH': c.danger, 'MEDIUM': c.warning, 'LOW': c.success}[cost] ?? c.success;
    Color costSoft(String cost) => {'HIGH': c.dangerSoft, 'MEDIUM': c.warningSoft, 'LOW': c.successSoft}[cost] ?? c.successSoft;

    return Padding(padding: const EdgeInsets.only(top: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Eyebrow('Execution plan · EXPLAIN')),
        SizedBox(width: 120, child: Segmented<String>(value: view, onChange: (v) => setState(() => view = v), iconOnly: true, btnPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), items: const [SegItem('tree', '', icon: 'dotgrid'), SegItem('detail', '', icon: 'rows')])),
      ]),
      const SizedBox(height: 10),
      SpCard(color: high ? c.warningSoft : c.successSoft, borderColor: Colors.transparent, padding: const EdgeInsets.all(14), child: Row(children: [
        SpIcon(high ? 'alert' : 'check', size: 18, color: high ? c.warning : c.success),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(high ? 'Optimization recommended' : 'Plan looks healthy', style: sans(size: 13, weight: FontWeight.w700, color: high ? c.warning : c.success)),
          const SizedBox(height: 2),
          Text(high ? 'A full table scan was detected in this plan.' : 'All steps use indexes efficiently.', style: sans(size: 11.5, color: c.text2)),
        ])),
      ])),
      const SizedBox(height: 14),
      if (view == 'tree')
        _PlanTree(nodes: nodes, sel: sel, onSel: (i) => setState(() => sel = i), costColor: costColor, costSoft: costSoft)
      else
        ...nodes.map((n) {
          final col = costColor(n.cost);
          return Padding(padding: const EdgeInsets.only(bottom: 12), child: SpCard(borderColor: col.withOpacity(0.33), padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Expanded(child: Text(n.op, style: sans(size: 13.5, weight: FontWeight.w700, color: c.text))),
              SpBadge(n.cost, fg: col, bg: costSoft(n.cost)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field('TABLE', n.table)),
              Expanded(child: _field('ACCESS', n.access, color: n.access == 'ALL' ? c.warning : c.success)),
              Expanded(child: _field('ROWS', '${n.rows}')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field('POSSIBLE KEYS', n.possible)),
              Expanded(child: _field('KEY USED', n.key, color: n.key == 'NULL' ? c.text3 : c.accent)),
            ]),
            const SizedBox(height: 12),
            _advice(c, n.advice, col, n.cost),
          ])));
        }),
    ]));
  }

  Widget _field(String label, String val, {Color? color}) {
    final c = SpColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: sans(size: 9, weight: FontWeight.w700, color: c.text4, spacing: 0.5)),
      const SizedBox(height: 3),
      Text(val, overflow: TextOverflow.ellipsis, style: mono(size: 12, weight: FontWeight.w600, color: color ?? c.text)),
    ]);
  }

  Widget _advice(SpColors c, String advice, Color col, String cost) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SpIcon(cost == 'HIGH' ? 'alert' : 'info', size: 15, color: col),
          const SizedBox(width: 9),
          Expanded(child: Text(advice, style: mono(size: 11.5, color: c.text2, height: 1.55))),
        ]),
      );
}

class _PlanTree extends StatelessWidget {
  final List<PlanNode> nodes;
  final int sel;
  final ValueChanged<int> onSel;
  final Color Function(String) costColor;
  final Color Function(String) costSoft;
  const _PlanTree({required this.nodes, required this.sel, required this.onSel, required this.costColor, required this.costSoft});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final maxRows = nodes.map((n) => n.rows).fold<int>(1, (a, b) => a > b ? a : b);
    final minRows = nodes.map((n) => n.rows).fold<int>(1 << 30, (a, b) => a < b ? a : b);
    final chain = [...nodes, PlanNode(op: 'Result', cost: 'LOW', rows: minRows == (1 << 30) ? 1 : minRows, result: true)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16), child: Column(children: chain.asMap().entries.map((entry) {
        final i = entry.key;
        final n = entry.value;
        final col = costColor(n.cost);
        final widthPct = ((n.rows / maxRows) * 100).clamp(14, 100).round();
        final isSel = sel == i;
        return Column(children: [
          if (i > 0) Container(width: 2, height: 22, color: c.borderStrong),
          GestureDetector(
            onTap: n.result ? null : () => onSel(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: n.result ? c.surface3 : (isSel ? costSoft(n.cost) : c.surface2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: n.result ? c.border2 : (isSel ? col : Colors.transparent), width: 1.5),
              ),
              child: Column(children: [
                Row(children: [
                  Container(width: 26, height: 26, decoration: BoxDecoration(color: n.result ? c.accent : costSoft(n.cost), borderRadius: BorderRadius.circular(8)), alignment: Alignment.center, child: SpIcon(n.result ? 'check' : (n.access == 'ALL' || RegExp(r'scan', caseSensitive: false).hasMatch(n.op) ? 'rows' : RegExp(r'join|loop|hash', caseSensitive: false).hasMatch(n.op) ? 'branch' : 'key'), size: 15, color: n.result ? c.accentInk : col)),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.op, overflow: TextOverflow.ellipsis, style: sans(size: 12.5, weight: FontWeight.w700, color: c.text)),
                    if (n.table.isNotEmpty) Text(n.table, style: mono(size: 10, color: c.text3)),
                  ])),
                  if (!n.result) SpBadge(n.cost, fg: col, bg: costSoft(n.cost)),
                ]),
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: Container(height: 6, color: c.surface4, child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: widthPct / 100, child: Container(color: n.result ? c.accent : col)))))),
                  const SizedBox(width: 8),
                  SizedBox(width: 64, child: Text('${n.rows} row${n.rows == 1 ? '' : 's'}', textAlign: TextAlign.right, style: mono(size: 10, color: c.text3))),
                ]),
              ]),
            ),
          ),
        ]);
      }).toList())),
      if (sel < nodes.length) ...[
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final n = nodes[sel];
          final col = costColor(n.cost);
          return SpCard(borderColor: col.withOpacity(0.33), padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ACCESS', style: sans(size: 9, weight: FontWeight.w700, color: c.text4, spacing: 0.5)), const SizedBox(height: 3), Text(n.access, style: mono(size: 12, weight: FontWeight.w600, color: n.access == 'ALL' ? c.warning : c.success))])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('KEY USED', style: sans(size: 9, weight: FontWeight.w700, color: c.text4, spacing: 0.5)), const SizedBox(height: 3), Text(n.key, style: mono(size: 12, weight: FontWeight.w600, color: n.key == 'NULL' ? c.text3 : c.accent))])),
            ]),
            const SizedBox(height: 11),
            Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SpIcon(n.cost == 'HIGH' ? 'alert' : 'info', size: 15, color: col),
              const SizedBox(width: 9),
              Expanded(child: Text(n.advice, style: mono(size: 11.5, color: c.text2, height: 1.55))),
            ])),
          ]));
        }),
      ],
    ]);
  }
}
