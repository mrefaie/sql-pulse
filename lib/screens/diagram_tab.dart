// SQL Pulse — ER diagram (pannable / zoomable canvas).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';

const double _nodeW = 156;

class DiagramTab extends StatefulWidget {
  const DiagramTab({super.key});
  @override
  State<DiagramTab> createState() => _DiagramTabState();
}

class _DiagramTabState extends State<DiagramTab> {
  double zoom = 1;
  Offset pan = Offset.zero;
  Offset? _dragStart;
  Offset? _panStart;

  double _nodeH(TableDef t) => 52 + (t.columns.length.clamp(0, 4)) * 20 + 8;

  Offset _center(Catalog cat, String name) {
    final pos = cat.er[name]!;
    final t = cat.tables[name]!;
    return Offset(pos.x + _nodeW / 2, pos.y + _nodeH(t) / 2);
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cat = state.db[state.catalog]!;
    final rc = relColor(c);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('ER diagram'),
            const SizedBox(height: 4),
            Text('Drag to pan · tap a table to inspect', style: sans(size: 12.5, color: c.text3)),
          ])),
          IconBtn('plus', box: 34, iconSize: 16, onTap: () => setState(() => zoom = (zoom + 0.15).clamp(0.5, 1.6))),
          const SizedBox(width: 6),
          IconBtn('minus', box: 34, iconSize: 16, onTap: () => setState(() => zoom = (zoom - 0.15).clamp(0.5, 1.6))),
          const SizedBox(width: 6),
          IconBtn('scan', box: 34, iconSize: 16, onTap: () => setState(() {
            zoom = 1;
            pan = Offset.zero;
          })),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _DotGridPainter(c.dot))),
                Positioned.fill(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    _dragStart = d.localPosition;
                    _panStart = pan;
                  },
                  onPanUpdate: (d) {
                    if (_dragStart != null) setState(() => pan = _panStart! + (d.localPosition - _dragStart!));
                  },
                  onPanEnd: (_) => _dragStart = null,
                  child: Transform.translate(
                    offset: pan,
                    child: Transform.scale(
                      scale: zoom,
                      alignment: Alignment.topLeft,
                      child: Stack(clipBehavior: Clip.none, children: [
                        // relation lines
                        Positioned(left: 0, top: 0, child: CustomPaint(size: const Size(540, 620), painter: _RelPainter(cat: cat, center: (n) => _center(cat, n), relColors: rc))),
                        // nodes
                        ...cat.er.entries.map((entry) {
                          final name = entry.key;
                          final posn = entry.value;
                          final t = cat.tables[name]!;
                          return Positioned(left: posn.x, top: posn.y, child: _Node(name: name, t: t, onTap: () => _inspect(context, t)));
                        }),
                      ]),
                    ),
                  ),
                )),
                // legend
                Positioned(left: 12, right: 12, bottom: 12, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(color: c.navBg, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.border)),
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: cat.relations.map((r) => Padding(padding: const EdgeInsets.only(right: 12), child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 14, height: 2, color: rc[r.kind]),
                    const SizedBox(width: 5),
                    Text('${r.from}→${r.to}', style: mono(size: 9, color: c.text3)),
                  ]))).toList())),
                )),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  void _inspect(BuildContext context, TableDef t) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) {
      final c = SpColors.of(ctx);
      return SpSheet(
        title: t.name,
        right: SpBadge('TABLE', variant: 'accent'),
        onClose: () => Navigator.pop(ctx),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...t.columns.map((col) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SpIcon(col.pk ? 'key' : col.fkTable != null ? 'link' : 'columns', size: 15, color: col.pk ? c.warning : col.fkTable != null ? c.info : c.text3),
              const SizedBox(width: 10),
              Expanded(child: Text(col.name, style: mono(size: 13, weight: FontWeight.w600, color: c.text))),
              Text(col.type, style: mono(size: 11, color: c.text3)),
            ]),
          ))),
          const SizedBox(height: 14),
          SpButton(label: 'Open table', icon: 'table', block: true, onTap: () {
            state.openTable(t.name);
            Navigator.pop(ctx);
          }),
        ]),
      );
    });
  }
}

class _Node extends StatelessWidget {
  final String name;
  final TableDef t;
  final VoidCallback onTap;
  const _Node({required this.name, required this.t, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _nodeW,
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(c.dark ? 0.5 : 0.18), blurRadius: 40, offset: const Offset(0, 18))]),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9), decoration: BoxDecoration(color: c.surface3, border: Border(bottom: BorderSide(color: c.border))), child: Row(children: [
            SpIcon('table', size: 13, color: c.accent),
            const SizedBox(width: 7),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: mono(size: 12, weight: FontWeight.w700, color: c.text))),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(11, 6, 11, 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ...t.columns.take(4).map((col) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
              SpIcon(col.pk ? 'key' : col.fkTable != null ? 'link' : 'columns', size: 10, color: col.pk ? c.warning : col.fkTable != null ? c.info : c.text4),
              const SizedBox(width: 6),
              Expanded(child: Text(col.name, overflow: TextOverflow.ellipsis, style: mono(size: 10.5, color: c.text2))),
            ]))),
            if (t.columns.length > 4) Padding(padding: const EdgeInsets.only(top: 2), child: Text('+${t.columns.length - 4} more', style: sans(size: 10, color: c.text4))),
          ])),
        ]),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color dot;
  _DotGridPainter(this.dot);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = dot;
    for (double y = 0; y < size.height; y += 22) {
      for (double x = 0; x < size.width; x += 22) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.dot != dot;
}

class _RelPainter extends CustomPainter {
  final Catalog cat;
  final Offset Function(String) center;
  final Map<String, Color> relColors;
  _RelPainter({required this.cat, required this.center, required this.relColors});
  @override
  void paint(Canvas canvas, Size size) {
    for (final r in cat.relations) {
      if (!cat.er.containsKey(r.from) || !cat.er.containsKey(r.to)) continue;
      final a = center(r.from), b = center(r.to);
      final color = relColors[r.kind] ?? relColors['accent']!;
      final line = Paint()
        ..color = color.withOpacity(0.7)
        ..strokeWidth = 2;
      canvas.drawLine(a, b, line);
      final dot = Paint()..color = color;
      canvas.drawCircle(a, 3.5, dot);
      canvas.drawCircle(b, 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(_RelPainter old) => true;
}
