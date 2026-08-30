// SQL Pulse — global schema search (tables, columns, views, procs, fns, triggers).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import '../widgets/highlight.dart';

void showSearchSheet(BuildContext context) {
  showSpSheet(context, (ctx) => const _SearchSheet());
}

class _SearchItem {
  final String kind;
  final String name;
  final String? table;
  final String? def;
  final String sub;
  final String icon;
  _SearchItem({
    required this.kind,
    required this.name,
    this.table,
    this.def,
    required this.sub,
    required this.icon,
  });
}

List<_SearchItem> _buildIndex(Catalog cat) {
  final items = <_SearchItem>[];
  for (final t in cat.tables.values) {
    items.add(
      _SearchItem(
        kind: 'table',
        name: t.name,
        table: t.name,
        sub: '${t.columns.length} cols · ${t.displayRows} rows',
        icon: 'table',
      ),
    );
    for (final col in t.columns) {
      items.add(
        _SearchItem(
          kind: 'column',
          name: col.name,
          table: t.name,
          sub:
              '${t.name} · ${col.type}${col.pk ? ' · PK' : ''}${col.fkTable != null ? ' · FK→${col.fkTable}' : ''}',
          icon: col.pk
              ? 'key'
              : col.fkTable != null
              ? 'link'
              : 'columns',
        ),
      );
    }
  }
  for (final v in cat.views) {
    items.add(
      _SearchItem(
        kind: 'view',
        name: v['name'] as String,
        def: v['definition'] as String,
        sub: 'view',
        icon: 'filter',
      ),
    );
  }
  for (final p in cat.procedures) {
    items.add(
      _SearchItem(
        kind: 'procedure',
        name: p['name'] as String,
        def: p['definition'] as String,
        sub: 'procedure(${p['params'] ?? ''})',
        icon: 'cog',
      ),
    );
  }
  for (final f in cat.functions) {
    items.add(
      _SearchItem(
        kind: 'function',
        name: f['name'] as String,
        def: f['definition'] as String,
        sub: 'function → ${f['returns'] ?? ''}',
        icon: 'fx',
      ),
    );
  }
  for (final t in cat.triggers) {
    items.add(
      _SearchItem(
        kind: 'trigger',
        name: t['name'] as String,
        def: t['definition'] as String,
        sub: '${t['event']} · ${t['target']}',
        icon: 'zap',
      ),
    );
  }
  return items;
}

double _score(String q, String name) {
  final n = name.toLowerCase(), s = q.toLowerCase();
  if (n == s) return 100;
  if (n.startsWith(s)) return 80 - (n.length - s.length) * 0.3;
  final idx = n.indexOf(s);
  if (idx >= 0) return 55 - idx * 0.5;
  var qi = 0;
  for (var i = 0; i < n.length && qi < s.length; i++) {
    if (n[i] == s[qi]) qi++;
  }
  return qi == s.length ? 25 - (n.length - s.length) * 0.1 : -1;
}

const _searchKinds = [
  ['all', 'All'],
  ['table', 'Tables'],
  ['column', 'Columns'],
  ['view', 'Views'],
  ['procedure', 'Code'],
];

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String q = '';
  String kind = 'all';

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cat = state.db[state.catalog]!;
    final index = _buildIndex(cat);
    const codeKinds = ['view', 'procedure', 'function', 'trigger'];

    var results = index;
    if (kind != 'all') {
      results = results
          .where(
            (i) => kind == 'procedure'
                ? codeKinds.contains(i.kind)
                : i.kind == kind,
          )
          .toList();
    }
    if (q.trim().isNotEmpty) {
      final scored =
          results
              .map((i) => (item: i, s: _score(q.trim(), i.name)))
              .where((x) => x.s >= 0)
              .toList()
            ..sort((a, b) => b.s.compareTo(a.s));
      results = scored.map((x) => x.item).toList();
    } else {
      results = results.where((i) => i.kind == 'table').toList();
    }
    results = results.take(60).toList();

    return SpSheet(
      title: 'Search schema',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpInput(
            hint: 'Find tables, columns, views…',
            autofocus: true,
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _searchKinds
                  .map(
                    (k) => Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: SpChip(
                        k[1],
                        on: kind == k[0],
                        onTap: () => setState(() => kind = k[0]),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            q.trim().isNotEmpty
                ? '${results.length} match${results.length == 1 ? '' : 'es'}'
                : 'Browse tables · type to search columns & code',
            style: sans(size: 11, color: c.text3),
          ),
          const SizedBox(height: 9),
          if (results.isEmpty)
            Empty(
              icon: 'search',
              title: 'No matches',
              sub: 'Nothing in ${state.catalog} matches "$q".',
            )
          else
            ...results.map(
              (it) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SpRow(
                  padding: const EdgeInsets.all(11),
                  onTap: () {
                    if (it.kind == 'table' || it.kind == 'column') {
                      state.openTable(it.table!);
                      Navigator.pop(context);
                    } else {
                      _showDef(context, it);
                    }
                  },
                  child: Row(
                    children: [
                      RowIco(it.icon, box: 32, iconSize: 15),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _highlighted(c, it.name, q.trim()),
                            const SizedBox(height: 2),
                            Text(
                              it.sub,
                              overflow: TextOverflow.ellipsis,
                              style: sans(size: 10.5, color: c.text3),
                            ),
                          ],
                        ),
                      ),
                      SpBadge(it.kind, fontSize: 9),
                      const SizedBox(width: 8),
                      SpIcon(
                        it.kind == 'table' || it.kind == 'column'
                            ? 'chevR'
                            : 'code',
                        size: 15,
                        color: c.text3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _highlighted(SpColors c, String name, String query) {
    if (query.isEmpty)
      return Text(
        name,
        style: mono(size: 13, weight: FontWeight.w600, color: c.text),
      );
    final idx = name.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0)
      return Text(
        name,
        style: mono(size: 13, weight: FontWeight.w600, color: c.text),
      );
    return RichText(
      text: TextSpan(
        style: mono(size: 13, weight: FontWeight.w600, color: c.text),
        children: [
          TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + query.length),
            style: mono(size: 13, weight: FontWeight.w700, color: c.accent),
          ),
          TextSpan(text: name.substring(idx + query.length)),
        ],
      ),
    );
  }

  void _showDef(BuildContext context, _SearchItem it) {
    final state = context.read<AppState>();
    showSpSheet(
      context,
      (ctx) => SpSheet(
        title: it.name,
        right: SpBadge(it.kind.toUpperCase(), variant: 'accent'),
        onClose: () => Navigator.pop(ctx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CodeBlock(it.def ?? ''),
            const SizedBox(height: 14),
            SpButton(
              label: 'Open in SQL console',
              icon: 'terminal',
              block: true,
              onTap: () {
                state.loadIntoConsole(it.def ?? '');
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
