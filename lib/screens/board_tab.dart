// SQL Pulse — pinned-query board (metric / chart / table cards).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import '../widgets/grid.dart';

int _firstNumeric(List<String> headers, List<List<Object?>> rows) {
  bool isId(String h) => RegExp(r'(^|_)id$', caseSensitive: false).hasMatch(h);
  final cand = <int>[];
  for (var i = 0; i < headers.length; i++) {
    if (rows.any((r) => i < r.length && r[i] is num) && rows.every((r) => i >= r.length || r[i] == null || r[i] is num)) cand.add(i);
  }
  for (final i in cand) {
    if (!isId(headers[i])) return i;
  }
  return cand.isNotEmpty ? cand.first : -1;
}

class BoardTab extends StatelessWidget {
  const BoardTab({super.key});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final pins = state.dashboard;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Eyebrow('Board'),
        const SizedBox(height: 4),
        Text('${pins.length} pinned quer${pins.length == 1 ? 'y' : 'ies'} · live on-device', style: sans(size: 12.5, color: c.text3)),
        const SizedBox(height: 14),
        if (pins.isEmpty)
          const Empty(icon: 'grid', title: 'No pinned cards yet', sub: 'Run a query, then tap "Pin" in the results to add a live metric, chart, or table here.')
        else
          ...pins.map((pin) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _PinCard(pin: pin))),
      ],
    );
  }
}

class _PinCard extends StatelessWidget {
  final PinCard pin;
  const _PinCard({required this.pin});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    return FutureBuilder<QueryResult>(
      future: state.runPinQuery(pin),
      builder: (context, snap) {
        final res = snap.data;
        final err = res != null && (res.error || res.denied);
        Widget body;
        if (!snap.hasData) {
          body = const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Spinner(size: 22));
        } else if (err) {
          body = Text(res!.message ?? 'Query failed', style: mono(size: 11.5, color: c.danger));
        } else {
          body = pin.viz == 'metric' ? _metricViz(c, res!) : pin.viz == 'chart' ? _chartViz(c, res!) : _tableViz(res!);
        }
        return SpCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(13, 12, 13, 10), child: Row(children: [
            RowIco(pin.viz == 'metric' ? 'gauge' : pin.viz == 'chart' ? 'chart' : 'rows', box: 30, iconSize: 15, bg: c.accentSoft, fg: c.accent),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pin.name, overflow: TextOverflow.ellipsis, style: sans(size: 13.5, weight: FontWeight.w700, color: c.text)),
              Text('${pin.catalog} · ${res?.ms ?? 0}ms', style: mono(size: 10, color: c.text3)),
            ])),
            IconBtn('terminal', box: 28, iconSize: 14, onTap: () => state.runPin(pin)),
            const SizedBox(width: 6),
            IconBtn('x', box: 28, iconSize: 14, onTap: () => state.removePin(pin.id)),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(13, 0, 13, 14), child: body),
        ]));
      },
    );
  }

  Widget _metricViz(SpColors c, QueryResult res) {
    if (res.headers == null || res.rows!.isEmpty) return Text('No data', style: sans(size: 12, color: c.text3));
    final ni = _firstNumeric(res.headers!, res.rows!);
    Object? val;
    String label;
    if (res.rows!.length == 1 && ni >= 0) {
      val = res.rows!.first[ni];
      label = res.headers![ni];
    } else if (ni >= 0) {
      val = res.rows!.fold<num>(0, (a, r) => a + (ni < r.length && r[ni] is num ? r[ni] as num : 0));
      label = 'Σ ${res.headers![ni]}';
    } else {
      val = res.rows!.length;
      label = 'rows';
    }
    final display = val is num ? (val == val.roundToDouble() ? '${val.toInt()}' : val.toStringAsFixed(2)) : '$val';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(display, style: mono(size: 38, weight: FontWeight.w800, color: c.text, height: 1, spacing: -1.5)),
      const SizedBox(height: 4),
      Text('$label · ${res.rows!.length} row${res.rows!.length == 1 ? '' : 's'}', style: sans(size: 11.5, weight: FontWeight.w600, color: c.text3)),
    ]);
  }

  Widget _chartViz(SpColors c, QueryResult res) {
    if (res.headers == null || res.rows!.isEmpty) return Text('No data', style: sans(size: 12, color: c.text3));
    final ni = _firstNumeric(res.headers!, res.rows!);
    if (ni < 0) return Text('No numeric column to chart', style: sans(size: 12, color: c.text3));
    var li = -1;
    for (var i = 0; i < res.headers!.length; i++) {
      if (i != ni && res.rows!.any((r) => i < r.length && r[i] is String)) {
        li = i;
        break;
      }
    }
    if (li < 0) {
      for (var i = 0; i < res.headers!.length; i++) {
        if (i != ni) {
          li = i;
          break;
        }
      }
    }
    final data = res.rows!.take(8).toList().asMap().entries.map((e) {
      final r = e.value;
      return (label: li < 0 ? '#${e.key + 1}' : '${li < r.length ? r[li] : 'NULL'}', val: ni < r.length && r[ni] is num ? r[ni] as num : 0);
    }).toList();
    final max = data.map((d) => d.val.abs()).fold<num>(1, (a, b) => a > b ? a : b);
    return Column(children: data.map((d) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [
      SizedBox(width: 80, child: Text(d.label, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: mono(size: 10.5, color: c.text2))),
      const SizedBox(width: 9),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Container(height: 16, color: c.surface3, child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: (d.val.abs() / max).clamp(0.03, 1).toDouble(), child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [c.accent, c.accent2])))))))),
      const SizedBox(width: 9),
      SizedBox(width: 50, child: Text(d.val is int || d.val == d.val.roundToDouble() ? '${d.val.toInt()}' : d.val.toStringAsFixed(1), textAlign: TextAlign.right, style: mono(size: 10.5, color: c.synNum))),
    ]))).toList());
  }

  Widget _tableViz(QueryResult res) {
    if (res.headers == null) return Text(res.comment ?? 'No rows', style: const TextStyle());
    return ResultTable(headers: res.headers!, rows: res.rows!.take(5).toList(), showRowNum: false, flat: true);
  }
}

class PinDialog extends StatefulWidget {
  const PinDialog({super.key});
  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final name = TextEditingController();
  String viz = 'metric';
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.read<AppState>();
    return SpDialog(
      icon: 'grid', title: 'Pin to board', sub: const Text('Saved on-device and re-run live each time you open the board.'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpInput(controller: name, hint: 'Card title', mono: false, autofocus: true),
        const SizedBox(height: 14),
        const FieldLabel('Visualize as'),
        Row(children: [
          for (final v in const [['metric', 'gauge', 'Metric'], ['chart', 'chart', 'Chart'], ['table', 'rows', 'Table']]) ...[
            Expanded(child: GestureDetector(
              onTap: () => setState(() => viz = v[0]),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                decoration: BoxDecoration(color: viz == v[0] ? c.accentSoft : c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: viz == v[0] ? c.accent : c.border)),
                child: Column(children: [
                  SpIcon(v[1], size: 18, color: viz == v[0] ? c.accent : c.text3),
                  const SizedBox(height: 5),
                  Text(v[2], style: sans(size: 11.5, weight: FontWeight.w600, color: viz == v[0] ? c.accent : c.text2)),
                ]),
              ),
            )),
            if (v[0] != 'table') const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SpButton(label: 'Pin card', icon: 'grid', kind: BtnKind.primary, onTap: () {
            state.pinToDashboard(name.text, viz);
            Navigator.pop(context);
          })),
        ]),
      ]),
    );
  }
}
