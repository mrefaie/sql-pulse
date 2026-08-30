// SQL Pulse — schema & data diff between two connections (local, on-device).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/diff.dart' as df;
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';

void showDiffSheet(BuildContext context) {
  showSpSheet(context, (ctx) => const _DiffSheet());
}

({Color color, Color soft, String label, String sign}) _meta(
  SpColors c,
  String s,
) => {
  'added': (color: c.success, soft: c.successSoft, label: 'ADDED', sign: '+'),
  'removed': (color: c.danger, soft: c.dangerSoft, label: 'REMOVED', sign: '−'),
  'changed': (
    color: c.warning,
    soft: c.warningSoft,
    label: 'CHANGED',
    sign: '~',
  ),
  'rows': (color: c.info, soft: c.infoSoft, label: 'ROW DELTA', sign: '≠'),
  'same': (color: c.text3, soft: c.surface3, label: 'IDENTICAL', sign: '='),
}[s]!;

class _DiffSheet extends StatefulWidget {
  const _DiffSheet();
  @override
  State<_DiffSheet> createState() => _DiffSheetState();
}

class _DiffSheetState extends State<_DiffSheet> {
  Profile? target;
  String? openTable;
  String mode = 'schema';
  Catalog? _targetCat;
  bool _loading = false;
  String? _err;

  Future<void> _selectTarget(AppState state, Profile p) async {
    setState(() {
      target = p;
      _loading = true;
      _targetCat = null;
      _err = null;
    });
    try {
      final cat = await state.introspectTarget(p);
      // load base previews for small tables so row-diffs are meaningful
      for (final t in (state.currentCatalog?.tables.values ?? <TableDef>[])) {
        if (t.rowEstimate <= 200) await state.ensureRows(t.name);
      }
      if (mounted)
        setState(() {
          _targetCat = cat;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _err = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final others = state.profiles
        .where((p) => state.profile == null || p.id != state.profile!.id)
        .toList();
    final baseCat = state.db[state.catalog]!;

    if (target == null || _loading || _targetCat == null) {
      if (_loading || (target != null && _targetCat == null && _err == null)) {
        return SpSheet(
          title: 'Comparing…',
          onClose: () => Navigator.pop(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Spinner()),
          ),
        );
      }
      return SpSheet(
        title: 'Compare with…',
        onClose: () => Navigator.pop(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Diff ${state.catalog} on ${state.profile?.name ?? 'current'} against another live connection — fetched and compared on-device.',
              style: sans(size: 12.5, color: c.text3),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SpCard(
                  color: c.dangerSoft,
                  borderColor: Colors.transparent,
                  child: Text(_err!, style: mono(size: 11.5, color: c.danger)),
                ),
              ),
            const SizedBox(height: 14),
            if (others.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: SpCard(
                  color: c.infoSoft,
                  borderColor: Colors.transparent,
                  child: Row(
                    children: [
                      SpIcon('info', size: 15, color: c.info),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Only one connection saved — create a second profile (home → New connection) to compare.',
                          style: sans(size: 12, color: c.info),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...others.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _connRow(c, p, () => _selectTarget(state, p)),
                ),
              ),
          ],
        ),
      );
    }

    final targetCat = _targetCat!;
    final diff = df.diffCatalogs(baseCat, targetCat);
    final s = diff.summary;

    return SpSheet(
      title: 'Schema diff',
      right: SpChip(
        'Change',
        icon: 'refresh',
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        onTap: () => setState(() {
          target = null;
          openTable = null;
        }),
      ),
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _diffHead(
                  c,
                  state.profile?.name ?? 'current',
                  state.catalog,
                  state.profile != null
                      ? kTagColors[state.profile!.color]!
                      : c.accent,
                ),
              ),
              SpIcon('arrowR2', size: 18, color: c.text3),
              Expanded(
                child: _diffHead(
                  c,
                  target!.name,
                  target!.catalog,
                  kTagColors[target!.color]!,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final e in [
                ('added', s.added),
                ('removed', s.removed),
                ('changed', s.changed),
                ('rows', s.rows),
                ('same', s.same),
              ])
                SpBadge(
                  '${e.$2} ${_meta(c, e.$1).label.toLowerCase()}',
                  fg: _meta(c, e.$1).color,
                  bg: _meta(c, e.$1).soft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (openTable == null)
            ...diff.tables.map((t) {
              final m = _meta(c, t.status);
              final clickable = t.status == 'changed' || t.status == 'rows';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Opacity(
                  opacity: t.status == 'same' ? 0.6 : 1,
                  child: SpCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    onTap: clickable
                        ? () => setState(() => openTable = t.name)
                        : null,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: m.soft,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            m.sign,
                            style: mono(
                              size: 13,
                              weight: FontWeight.w700,
                              color: m.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: mono(
                                  size: 13,
                                  weight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                t.status == 'added'
                                    ? 'only in ${target!.name}'
                                    : t.status == 'removed'
                                    ? 'only here · ${t.rowsA} rows'
                                    : '${t.cols.where((x) => x.status != 'same').length} col change${t.cols.where((x) => x.status != 'same').length == 1 ? '' : 's'} · ${t.rowsA} vs ${t.rowsB} rows',
                                style: sans(size: 10.5, color: c.text3),
                              ),
                            ],
                          ),
                        ),
                        SpBadge(m.label, fg: m.color, bg: Colors.transparent),
                        if (clickable) ...[
                          const SizedBox(width: 6),
                          SpIcon('chevR', size: 15, color: c.text3),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            })
          else
            _tableDiffDetail(
              c,
              baseCat,
              targetCat,
              diff.tables.firstWhere((t) => t.name == openTable),
            ),
        ],
      ),
    );
  }

  Widget _connRow(SpColors c, Profile p, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: kTagColors[p.color]),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    EngineMark(p.engine, size: 36, radius: 10),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            style: sans(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: c.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.catalog,
                            style: mono(size: 10.5, color: c.text3),
                          ),
                        ],
                      ),
                    ),
                    SpIcon('chevR', size: 16, color: c.text3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _diffHead(
    SpColors c,
    String label,
    String cat,
    Color color,
  ) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: c.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: c.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: sans(size: 12, weight: FontWeight.w700, color: c.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(cat, style: mono(size: 10, color: c.text3)),
      ],
    ),
  );

  Widget _tableDiffDetail(
    SpColors c,
    Catalog baseCat,
    Catalog targetCat,
    df.TableDiff td,
  ) {
    final base = baseCat.tables[openTable], tgt = targetCat.tables[openTable];
    final rowDiff = (base != null && tgt != null)
        ? df.diffRows(base, tgt)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBtn(
              'arrowL',
              box: 36,
              iconSize: 16,
              onTap: () => setState(() => openTable = null),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                td.name,
                style: mono(size: 14, weight: FontWeight.w700, color: c.text),
              ),
            ),
            SizedBox(
              width: 150,
              child: Segmented<String>(
                value: mode,
                onChange: (v) => setState(() => mode = v),
                btnPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                fontSize: 11.5,
                items: const [
                  SegItem('schema', 'Columns'),
                  SegItem('rows', 'Rows'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (mode == 'schema')
          ...td.cols.map((col) {
            final m = _meta(c, col.status);
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Opacity(
                opacity: col.status == 'same' ? 0.5 : 1,
                child: SpCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            child: Text(
                              m.sign,
                              style: mono(
                                size: 13,
                                weight: FontWeight.w700,
                                color: m.color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              col.name,
                              style: mono(
                                size: 12.5,
                                weight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                          ),
                          if (col.status != 'same')
                            SpBadge(m.label, fg: m.color, bg: m.soft),
                        ],
                      ),
                      if (col.status == 'changed')
                        Padding(
                          padding: const EdgeInsets.only(top: 7, left: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '− ${col.a}',
                                style: mono(size: 10.5, color: c.danger),
                              ),
                              Text(
                                '+ ${col.b}',
                                style: mono(size: 10.5, color: c.success),
                              ),
                            ],
                          ),
                        ),
                      if (col.status != 'changed' && col.status != 'same')
                        Padding(
                          padding: const EdgeInsets.only(top: 5, left: 20),
                          child: Text(
                            col.a ?? col.b ?? '',
                            style: mono(size: 10.5, color: c.text3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          })
        else if (rowDiff == null || rowDiff.rows.isEmpty)
          const Empty(
            icon: 'check',
            title: 'Rows identical',
            sub: 'Every row matches by primary key.',
          )
        else ...[
          Text(
            '${rowDiff.rows.length} differing row${rowDiff.rows.length == 1 ? '' : 's'} · keyed by ${rowDiff.pk}',
            style: sans(size: 11, color: c.text3),
          ),
          const SizedBox(height: 6),
          ...rowDiff.rows.take(40).map((r) {
            final m = _meta(c, r.status);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SpCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          child: Text(
                            m.sign,
                            style: mono(
                              size: 13,
                              weight: FontWeight.w700,
                              color: m.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${rowDiff.pk} = ${r.key}',
                            style: mono(
                              size: 12,
                              weight: FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                        ),
                        SpBadge(m.label, fg: m.color, bg: m.soft),
                      ],
                    ),
                    if (r.status == 'changed')
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: r.changedCols
                              .map(
                                (col) => RichText(
                                  text: TextSpan(
                                    style: mono(size: 10.5),
                                    children: [
                                      TextSpan(
                                        text: '$col: ',
                                        style: mono(size: 10.5, color: c.text3),
                                      ),
                                      TextSpan(
                                        text: '${r.a![col] ?? 'NULL'}',
                                        style: mono(
                                          size: 10.5,
                                          color: c.danger,
                                        ),
                                      ),
                                      TextSpan(
                                        text: ' → ',
                                        style: mono(size: 10.5, color: c.text4),
                                      ),
                                      TextSpan(
                                        text: '${r.b![col] ?? 'NULL'}',
                                        style: mono(
                                          size: 10.5,
                                          color: c.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
