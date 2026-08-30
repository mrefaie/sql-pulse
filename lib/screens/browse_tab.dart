// SQL Pulse — Browse (schema explorer) + Table detail (structure/data/insights/relations).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/engines.dart';
import '../data/mask.dart' as mask;
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import '../widgets/highlight.dart';
import 'designer.dart';
import 'row_inspector.dart';
import 'workspace.dart';

const List<List<String>> _objTypes = [
  ['tables', 'Tables', 'table'],
  ['views', 'Views', 'filter'],
  ['procedures', 'Procedures', 'cog'],
  ['functions', 'Functions', 'fx'],
  ['triggers', 'Triggers', 'zap'],
];

class BrowseTab extends StatefulWidget {
  const BrowseTab({super.key});
  @override
  State<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<BrowseTab> {
  String type = 'tables';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cat = state.db[state.catalog]!;
    final elabels = eng(state.engine).objectLabels;

    List<Map<String, dynamic>> objs(String t) {
      switch (t) {
        case 'views':
          return cat.views;
        case 'procedures':
          return cat.procedures;
        case 'functions':
          return cat.functions;
        case 'triggers':
          return cat.triggers;
      }
      return [];
    }

    final counts = {
      'tables': cat.tables.length,
      'views': cat.views.length,
      'procedures': cat.procedures.length,
      'functions': cat.functions.length,
      'triggers': cat.triggers.length,
    };
    bool filter(String s) => s.toLowerCase().contains(q.toLowerCase());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        Eyebrow('Schema · ${cat.label}'),
        const SizedBox(height: 10),
        SpInput(
          hint: 'Search objects',
          mono: false,
          onChanged: (v) => setState(() => q = v),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _objTypes.map((t) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SpChip(
                  elabels[t[0]] ?? t[1],
                  icon: t[2],
                  mono: false,
                  on: type == t[0],
                  onTap: () => setState(() => type = t[0]),
                  trailing: Text(
                    '${counts[t[0]]}',
                    style: sans(
                      size: 11,
                      weight: FontWeight.w700,
                      color: (type == t[0] ? c.accent : c.text2).withOpacity(
                        0.6,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (type == 'tables') ...[
          ...cat.tables.values
              .where((t) => filter(t.name))
              .map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: SpRow(
                    onTap: () => state.openTable(t.name),
                    child: Row(
                      children: [
                        RowIco('table'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: mono(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${t.columns.length} columns · ${t.displayRows} rows',
                                    style: sans(size: 11.5, color: c.text3),
                                  ),
                                  if (t.columns.any(
                                    (col) => col.fkTable != null,
                                  )) ...[
                                    const SizedBox(width: 8),
                                    SpBadge('FK', variant: 'fk'),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        SpIcon('chevR', size: 18, color: c.text3),
                      ],
                    ),
                  ),
                ),
              ),
          if (state.role != 'ReadOnly' && state.role != 'Analyst')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SpButton(
                label: 'New table',
                icon: 'plus',
                kind: BtnKind.ghost,
                block: true,
                onTap: () => showTableDesigner(context, mode: 'create'),
              ),
            ),
        ] else ...[
          ...objs(type)
              .where((o) => filter(o['name'] as String))
              .map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: SpRow(
                    onTap: () => _showDef(context, type, o),
                    child: Row(
                      children: [
                        RowIco(
                          _objTypes.firstWhere((x) => x[0] == type)[2],
                          iconSize: 17,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o['name'] as String,
                                style: mono(
                                  size: 13,
                                  weight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                o['event'] != null
                                    ? '${o['event']} · ${o['target']}'
                                    : o['returns'] != null
                                    ? '(${o['params']}) → ${o['returns']}'
                                    : (o['params'] as String?)?.isNotEmpty ==
                                          true
                                    ? '(${o['params']})'
                                    : 'view definition',
                                overflow: TextOverflow.ellipsis,
                                style: mono(size: 11, color: c.text3),
                              ),
                            ],
                          ),
                        ),
                        SpIcon('code', size: 16, color: c.text3),
                      ],
                    ),
                  ),
                ),
              ),
          if (objs(type).where((o) => filter(o['name'] as String)).isEmpty)
            Empty(
              icon: _objTypes.firstWhere((x) => x[0] == type)[2],
              title: 'No $type in ${cat.label}',
              sub: 'Switch catalog or create one from the SQL console.',
            ),
        ],
      ],
    );
  }

  void _showDef(BuildContext context, String type, Map<String, dynamic> o) {
    final state = context.read<AppState>();
    showSpSheet(
      context,
      (ctx) => SpSheet(
        title: o['name'] as String,
        right: SpBadge(
          type.substring(0, type.length - 1).toUpperCase(),
          variant: 'accent',
        ),
        onClose: () => Navigator.pop(ctx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CodeBlock(o['definition'] as String),
            const SizedBox(height: 14),
            SpButton(
              label: 'Open in SQL console',
              icon: 'terminal',
              block: true,
              onTap: () {
                state.loadIntoConsole(o['definition'] as String);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

const int kRowCap = 60;

class TableDetail extends StatefulWidget {
  const TableDetail({super.key});
  @override
  State<TableDetail> createState() => _TableDetailState();
}

class _TableDetailState extends State<TableDetail> {
  String view = 'structure';
  ({int r, String col})? editing;
  final _editCtrl = TextEditingController();

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cat = state.db[state.catalog]!;
    final t = cat.tables[state.table];
    if (t == null) return const SizedBox.shrink();

    final fkOut = t.columns.where((col) => col.fkTable != null).toList();
    final fkIn = <Map<String, String>>[];
    for (final tb in cat.tables.values) {
      for (final col in tb.columns) {
        if (col.fkTable == t.name)
          fkIn.add({'table': tb.name, 'col': col.name, 'ref': col.fkCol ?? ''});
      }
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const _EnvRibbonProxy(),
          // top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconBtn('arrowL', onTap: state.closeTable),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: sans(
                              size: 17,
                              weight: FontWeight.w700,
                              color: c.text,
                              spacing: -0.3,
                            ),
                          ),
                          Text(
                            '${cat.label} · ${t.displayRows} rows · ${t.columns.length} cols',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(size: 11, color: c.text3),
                          ),
                        ],
                      ),
                    ),
                    _ExportMenuBtn(
                      onExport: (fmt) => state.exportTable(fmt, t.name),
                      count: t.displayRows,
                    ),
                    const SizedBox(width: 6),
                    IconBtn(
                      'play',
                      color: c.accent,
                      iconSize: 16,
                      onTap: () => state.runSelect(t.name),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Segmented<String>(
                  value: view,
                  onChange: (v) => setState(() => view = v),
                  fontSize: 10.5,
                  btnPadding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 8,
                  ),
                  items: const [
                    SegItem('structure', 'Structure', icon: 'columns'),
                    SegItem('data', 'Data', icon: 'rows'),
                    SegItem('insights', 'Insights', icon: 'chart'),
                    SegItem('relations', 'Relations', icon: 'branch'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  children: [
                    if (view == 'structure') ..._structure(context, state, t),
                    if (view == 'data')
                      _DataView(
                        table: t,
                        editing: editing,
                        editCtrl: _editCtrl,
                        onEditStart: (r, col, val) {
                          setState(() {
                            editing = (r: r, col: col);
                            _editCtrl.text = val;
                          });
                        },
                        onCommit: () {
                          if (editing != null) {
                            state.editCell(
                              t.name,
                              editing!.r,
                              editing!.col,
                              _editCtrl.text,
                            );
                            setState(() => editing = null);
                          }
                        },
                        onCancel: () => setState(() => editing = null),
                      ),
                    if (view == 'insights') InsightsView(table: t),
                    if (view == 'relations')
                      ..._relations(context, state, t, fkOut, fkIn),
                  ],
                ),
                if (view == 'data' && state.role != 'ReadOnly')
                  Positioned(
                    right: 16,
                    bottom: state.pending.isNotEmpty ? 196 : 132,
                    child: GestureDetector(
                      onTap: () => _insertRow(context, t),
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: c.accent.withOpacity(0.32),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            SpIcon('plus', size: 18, color: c.accentInk),
                            const SizedBox(width: 8),
                            Text(
                              'Insert row',
                              style: sans(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: c.accentInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                PendingTray(
                  bottom: view == 'data' && state.role != 'ReadOnly'
                      ? 132
                      : 132,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _structure(BuildContext context, AppState state, TableDef t) {
    final c = SpColors.of(context);
    return [
      ...t.columns.map(
        (col) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SpCard(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                RowIco(
                  col.pk ? 'key' : 'columns',
                  iconSize: 16,
                  bg: col.pk ? c.warningSoft : c.surface3,
                  fg: col.pk ? c.warning : c.text2,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            col.name,
                            style: mono(
                              size: 13.5,
                              weight: FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                          if (col.pk) SpBadge('PK', variant: 'pk'),
                          if (col.fkTable != null)
                            SpBadge('FK→${col.fkTable}', variant: 'fk'),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${col.type} · ${col.nullable ? 'NULL' : 'NOT NULL'}${col.ai ? ' · AUTO_INCREMENT' : ''}',
                        style: mono(size: 11.5, color: c.text3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: SpButton(
              label: 'Add column',
              icon: 'plus',
              kind: BtnKind.ghost,
              enabled: state.role != 'ReadOnly' && state.role != 'Analyst',
              onTap: () => _addColumn(context, t),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: SpButton(
              label: 'Edit schema',
              icon: 'sliders',
              enabled: state.role != 'ReadOnly' && state.role != 'Analyst',
              onTap: () =>
                  showTableDesigner(context, mode: 'alter', existing: t),
            ),
          ),
        ],
      ),
      if (state.role != 'ReadOnly' && state.role != 'Analyst')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SpButton(
            label: 'Drop table',
            icon: 'trash',
            kind: BtnKind.ghost,
            color: c.danger,
            onTap: () => _dropTable(context, t),
          ),
        ),
      if (state.role == 'ReadOnly' || state.role == 'Analyst')
        DdlLock(role: state.role),
    ];
  }

  List<Widget> _relations(
    BuildContext context,
    AppState state,
    TableDef t,
    List<ColumnDef> fkOut,
    List<Map<String, String>> fkIn,
  ) {
    return [
      _RelGroup(
        title: 'References (outgoing)',
        empty: 'This table has no foreign keys.',
        children: fkOut
            .map(
              (col) => _RelRow(
                icon: 'branch',
                from: '${t.name}.${col.name}',
                to: '${col.fkTable}.${col.fkCol}',
                onGo: () => state.openTable(col.fkTable!),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 18),
      _RelGroup(
        title: 'Referenced by (incoming)',
        empty: 'No other table references this one.',
        children: fkIn
            .map(
              (col) => _RelRow(
                icon: 'link',
                from: '${col['table']}.${col['col']}',
                to: '${t.name}.${col['ref']}',
                onGo: () => state.openTable(col['table']!),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 18),
      SpButton(
        label: 'View in ER diagram',
        icon: 'dotgrid',
        block: true,
        onTap: () => state.gotoDiagram(),
      ),
    ];
  }

  void _addColumn(BuildContext context, TableDef t) {
    final state = context.read<AppState>();
    showSpSheet(
      context,
      (ctx) => _AddColumnSheet(
        onAdd: (col) {
          state.addColumn(t.name, col);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _insertRow(BuildContext context, TableDef t) {
    final state = context.read<AppState>();
    showSpSheet(
      context,
      (ctx) => _InsertRowSheet(
        columns: t.columns,
        onInsert: (vals) {
          state.insertRow(t.name, vals);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _dropTable(BuildContext context, TableDef t) {
    final state = context.read<AppState>();
    showSpDialog(
      context,
      (ctx) => SpDialog(
        icon: 'trash',
        iconColor: SpColors.of(ctx).danger,
        title: 'Drop table?',
        sub: Text(
          '${t.name} and all ${t.displayRows} rows will be permanently removed.',
        ),
        child: Row(
          children: [
            Expanded(
              child: SpButton(
                label: 'Cancel',
                kind: BtnKind.ghost,
                onTap: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SpButton(
                label: 'Drop',
                icon: 'trash',
                kind: BtnKind.danger,
                onTap: () {
                  state.dropTable(t.name);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// EnvRibbon shown above the table detail (re-uses workspace ribbon logic).
class _EnvRibbonProxy extends StatelessWidget {
  const _EnvRibbonProxy();
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final env = context.watch<AppState>().profile?.env;
    final meta = {
      'prod': (label: 'PRODUCTION', color: c.danger, soft: c.dangerSoft),
      'staging': (label: 'STAGING', color: c.warning, soft: c.warningSoft),
    }[env];
    if (meta == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: meta.soft,
        border: Border(bottom: BorderSide(color: meta.color)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: meta.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            meta.label,
            style: sans(
              size: 10,
              weight: FontWeight.w800,
              color: meta.color,
              spacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportMenuBtn extends StatelessWidget {
  final void Function(String) onExport;
  final int count;
  const _ExportMenuBtn({required this.onExport, required this.count});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Export',
      color: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: c.border2),
      ),
      onSelected: onExport,
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Eyebrow('Export $count rows'),
        ),
        _mi(ctx, 'csv', 'download', 'CSV'),
        _mi(ctx, 'json', 'download', 'JSON'),
        _mi(ctx, 'sql', 'code', 'INSERT statements'),
      ],
      child: IconBtn('download', iconSize: 16),
    );
  }

  PopupMenuItem<String> _mi(
    BuildContext ctx,
    String v,
    String icon,
    String label,
  ) {
    final c = SpColors.of(ctx);
    return PopupMenuItem(
      value: v,
      height: 40,
      child: Row(
        children: [
          SpIcon(icon, size: 16, color: c.text2),
          const SizedBox(width: 10),
          Text(label, style: sans(size: 13, color: c.text)),
        ],
      ),
    );
  }
}

// ---- data view ----
class _DataView extends StatelessWidget {
  final TableDef table;
  final ({int r, String col})? editing;
  final TextEditingController editCtrl;
  final void Function(int, String, String) onEditStart;
  final VoidCallback onCommit;
  final VoidCallback onCancel;
  const _DataView({
    required this.table,
    required this.editing,
    required this.editCtrl,
    required this.onEditStart,
    required this.onCommit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final t = table;
    final rows = t.rows.take(kRowCap).toList();
    final total = t.displayRows;
    final capped = total > rows.length;
    final pend = state.pendingFor(t.name);
    final hasSensitive = t.columns.any((col) => mask.isSensitiveCol(col.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                capped
                    ? 'Showing ${rows.length} of $total rows'
                    : '$total rows',
                style: sans(size: 12, color: c.text3),
              ),
            ),
            if (state.role != 'ReadOnly')
              SpChip(
                state.staging ? 'Staged' : 'Live',
                icon: state.staging ? 'lock' : 'play',
                on: state.staging,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                onTap: state.toggleStaging,
              ),
            if (hasSensitive) ...[
              const SizedBox(width: 8),
              SpChip(
                state.masking ? 'Masked' : 'Reveal',
                icon: state.masking ? 'eyeoff' : 'eye',
                on: state.masking,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                onTap: state.toggleMasking,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (state.staging)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SpCard(
              color: c.accentSoft,
              borderColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  SpIcon('lock', size: 14, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Staged mode — edits are held until you commit.',
                      style: sans(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: c.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _EditableGrid(
          table: t,
          rows: rows,
          pend: pend,
          masking: state.masking,
          role: state.role,
          editing: editing,
          editCtrl: editCtrl,
          onEditStart: onEditStart,
          onCommit: onCommit,
          onCancel: onCancel,
          onDelete: (r) => _confirmDelete(context, state, t, r),
          onInspect: (ri) => _inspect(context, t, ri),
        ),
        if (capped)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SpCard(
              color: c.infoSoft,
              borderColor: Colors.transparent,
              padding: const EdgeInsets.all(11),
              child: Row(
                children: [
                  SpIcon('info', size: 15, color: c.info),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Add a WHERE filter or LIMIT in the Query tab to page through all $total rows.',
                      style: sans(size: 12, color: c.info),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (state.role == 'ReadOnly')
          DdlLock(
            role: state.role,
            note: 'Read-only role — cells are not editable.',
          ),
      ],
    );
  }

  void _inspect(BuildContext context, TableDef t, int ri) {
    final state = context.read<AppState>();
    if (ri >= t.rows.length) return;
    showSpSheet(
      context,
      (ctx) => RowInspector(
        table: t.name,
        columns: t.columns,
        row: t.rows[ri],
        rowIndex: ri,
        onFilter: (col, val) {
          Navigator.pop(ctx);
          state.runSelect2(t.name, col, val);
        },
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    AppState state,
    TableDef t,
    int ri,
  ) {
    showSpDialog(
      context,
      (ctx) => SpDialog(
        icon: 'trash',
        iconColor: SpColors.of(ctx).danger,
        title: 'Delete row ${ri + 1}?',
        sub: Text('${t.name}: the row will be removed from the live database.'),
        child: Row(
          children: [
            Expanded(
              child: SpButton(
                label: 'Cancel',
                kind: BtnKind.ghost,
                onTap: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SpButton(
                label: 'Delete',
                icon: 'trash',
                kind: BtnKind.danger,
                onTap: () {
                  state.deleteRow(t.name, ri);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableGrid extends StatelessWidget {
  final TableDef table;
  final List<RowMap> rows;
  final ({
    Map<String, String> updates,
    Set<int> deletes,
    List<PendingChange> inserts,
  })
  pend;
  final bool masking;
  final String role;
  final ({int r, String col})? editing;
  final TextEditingController editCtrl;
  final void Function(int, String, String) onEditStart;
  final VoidCallback onCommit;
  final VoidCallback onCancel;
  final void Function(int) onDelete;
  final void Function(int) onInspect;
  const _EditableGrid({
    required this.table,
    required this.rows,
    required this.pend,
    required this.masking,
    required this.role,
    required this.editing,
    required this.editCtrl,
    required this.onEditStart,
    required this.onCommit,
    required this.onCancel,
    required this.onDelete,
    required this.onInspect,
  });

  String _fmt(Object? v) => v == null ? 'NULL' : '$v';
  String _disp(Object? v, String col) =>
      (masking && mask.isSensitiveCol(col) && v != null)
      ? mask.maskValue(v, col)
      : _fmt(v);

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final t = table;
    final hStyle = mono(
      size: 10.5,
      weight: FontWeight.w700,
      color: c.text2,
      spacing: 0.4,
    );

    Widget headerCell(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      alignment: Alignment.centerLeft,
      child: Text(text.toUpperCase(), style: hStyle),
    );

    final tableWidget = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder(
        horizontalInside: BorderSide(color: c.border),
        bottom: BorderSide(color: c.border),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(color: c.surface3),
          children: [
            const SizedBox(width: 52),
            ...t.columns.map(
              (col) => headerCell('${col.pk ? '⚷ ' : ''}${col.name}'),
            ),
          ],
        ),
        ...rows.asMap().entries.map((entry) {
          final ri = entry.key;
          final row = entry.value;
          final deleted = pend.deletes.contains(ri);
          return TableRow(
            decoration: BoxDecoration(color: deleted ? c.dangerSoft : null),
            children: [
              // actions
              SizedBox(
                width: 52,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onInspect(ri),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SpIcon('search', size: 15, color: c.text3),
                      if (role != 'ReadOnly') ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onDelete(ri),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: SpIcon(
                                deleted ? 'refresh' : 'trash',
                                size: 15,
                                color: deleted ? c.danger : c.text4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              ...t.columns.map((col) {
                final isEd =
                    editing != null &&
                    editing!.r == ri &&
                    editing!.col == col.name;
                final dirty = pend.updates.containsKey('$ri:${col.name}');
                final v = dirty
                    ? pend.updates['$ri:${col.name}']
                    : row[col.name];
                final isNum = v is num;
                if (isEd) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: editCtrl,
                      autofocus: true,
                      style: mono(size: 12, color: c.text),
                      cursorColor: c.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: c.surface4,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: c.accentLine),
                        ),
                      ),
                      onSubmitted: (_) => onCommit(),
                      onTapOutside: (_) => onCommit(),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: role != 'ReadOnly' && !deleted
                      ? () => onEditStart(ri, col.name, _fmt(v))
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: dirty
                        ? BoxDecoration(
                            border: Border.all(color: c.warning, width: 1.5),
                          )
                        : null,
                    child: Text(
                      _disp(v, col.name),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style:
                          mono(
                            size: 12,
                            color: dirty
                                ? c.warning
                                : (v == null
                                      ? c.text4
                                      : col.pk
                                      ? c.warning
                                      : (isNum ? c.synNum : c.text)),
                            height: 1,
                          ).copyWith(
                            decoration: deleted
                                ? TextDecoration.lineThrough
                                : null,
                            fontStyle: v == null
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                    ),
                  ),
                );
              }),
            ],
          );
        }),
        // inserts
        ...pend.inserts.map(
          (p) => TableRow(
            decoration: BoxDecoration(color: c.successSoft),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SpIcon('plus', size: 13, color: c.success),
              ),
              ...t.columns.map((col) {
                final raw = p.vals?[col.name];
                final v = (raw != null && raw != '')
                    ? raw
                    : (col.ai ? 'auto' : null);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    v == null ? 'NULL' : '$v',
                    maxLines: 1,
                    style: mono(size: 12, color: c.success),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.r),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 32,
          ),
          child: tableWidget,
        ),
      ),
    );
  }
}

// ---- structure helpers ----
class DdlLock extends StatelessWidget {
  final String role;
  final String? note;
  const DdlLock({super.key, required this.role, this.note});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SpCard(
        color: c.warningSoft,
        borderColor: Colors.transparent,
        padding: const EdgeInsets.all(11),
        child: Row(
          children: [
            SpIcon('lock', size: 15, color: c.warning),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                note ??
                    'The $role role cannot run DDL — adding columns is disabled.',
                style: sans(size: 12, color: c.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelGroup extends StatelessWidget {
  final String title;
  final String empty;
  final List<Widget> children;
  const _RelGroup({
    required this.title,
    required this.empty,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Eyebrow(title),
        const SizedBox(height: 10),
        if (children.isNotEmpty)
          Column(
            children: children
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: w,
                  ),
                )
                .toList(),
          )
        else
          SpCard(
            padding: const EdgeInsets.all(14),
            child: Text(empty, style: sans(size: 12.5, color: c.text3)),
          ),
      ],
    );
  }
}

class _RelRow extends StatelessWidget {
  final String icon;
  final String from;
  final String to;
  final VoidCallback onGo;
  const _RelRow({
    required this.icon,
    required this.from,
    required this.to,
    required this.onGo,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return SpRow(
      onTap: onGo,
      child: Row(
        children: [
          RowIco(icon, iconSize: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  from,
                  style: mono(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text('→ $to', style: mono(size: 11, color: c.text3)),
              ],
            ),
          ),
          SpIcon('chevR', size: 16, color: c.text3),
        ],
      ),
    );
  }
}

// ---- add column / insert row sheets ----
class _AddColumnSheet extends StatefulWidget {
  final void Function(ColumnDef) onAdd;
  const _AddColumnSheet({required this.onAdd});
  @override
  State<_AddColumnSheet> createState() => _AddColumnSheetState();
}

class _AddColumnSheetState extends State<_AddColumnSheet> {
  final name = TextEditingController();
  String type = 'VARCHAR(255)';
  bool nullable = true;
  static const types = [
    'VARCHAR(255)',
    'INT',
    'DECIMAL(10,2)',
    'DATETIME',
    'TEXT',
    'TINYINT(1)',
  ];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return SpSheet(
      title: 'Add column',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Eyebrow('ALTER TABLE · DDL'),
          const SizedBox(height: 12),
          const FieldLabel('Column name'),
          SpInput(
            controller: name,
            hint: 'avatar_url',
            mono: false,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Data type'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: types
                .map(
                  (ty) => SpChip(
                    ty,
                    on: type == ty,
                    onTap: () => setState(() => type = ty),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          SpCard(
            color: c.surface2,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SpIcon('info', size: 18, color: nullable ? c.accent : c.text3),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Allow NULL',
                        style: sans(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                      Text(
                        'Column accepts empty values',
                        style: sans(size: 11.5, color: c.text3),
                      ),
                    ],
                  ),
                ),
                SpSwitch(
                  on: nullable,
                  onToggle: () => setState(() => nullable = !nullable),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CodeBlock(
            'ALTER TABLE … ADD COLUMN ${name.text.isEmpty ? 'col' : name.text} $type ${nullable ? 'NULL' : 'NOT NULL'};',
          ),
          const SizedBox(height: 16),
          SpButton(
            label: 'Apply ALTER',
            kind: BtnKind.primary,
            block: true,
            enabled: name.text.trim().isNotEmpty,
            onTap: () => widget.onAdd(
              ColumnDef(name: name.text.trim(), type: type, nullable: nullable),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsertRowSheet extends StatefulWidget {
  final List<ColumnDef> columns;
  final void Function(Map<String, String>) onInsert;
  const _InsertRowSheet({required this.columns, required this.onInsert});
  @override
  State<_InsertRowSheet> createState() => _InsertRowSheetState();
}

class _InsertRowSheetState extends State<_InsertRowSheet> {
  final Map<String, TextEditingController> ctrls = {};
  @override
  void initState() {
    super.initState();
    for (final c in widget.columns) {
      ctrls[c.name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return SpSheet(
      title: 'Insert row',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Eyebrow('INSERT INTO · new record'),
          const SizedBox(height: 14),
          ...widget.columns.map(
            (col) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text(
                          col.name,
                          style: mono(
                            size: 11.5,
                            weight: FontWeight.w600,
                            color: c.text2,
                          ),
                        ),
                        if (col.pk) ...[
                          const SizedBox(width: 7),
                          SpBadge('PK', variant: 'pk'),
                        ],
                        const SizedBox(width: 7),
                        Text(col.type, style: sans(size: 11.5, color: c.text4)),
                      ],
                    ),
                  ),
                  SpInput(
                    controller: ctrls[col.name],
                    hint: col.ai ? 'auto' : col.type,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SpButton(
            label: 'Commit INSERT',
            kind: BtnKind.primary,
            block: true,
            onTap: () {
              widget.onInsert({
                for (final e in ctrls.entries) e.key: e.value.text,
              });
            },
          ),
        ],
      ),
    );
  }
}

// ---- insights ----
bool _isNumericType(String t) => RegExp(
  r'INT|DECIMAL|DOUBLE|FLOAT|NUMERIC|BIGINT|TINYINT',
  caseSensitive: false,
).hasMatch(t);

class InsightsView extends StatelessWidget {
  final TableDef table;
  const InsightsView({super.key, required this.table});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final t = table;
    final rows = t.rows;
    final numCols = t.columns.where((col) => _isNumericType(col.type)).length;
    final fkCols = t.columns.where((col) => col.fkTable != null).length;

    Widget metric(String val, String label, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            val,
            style: mono(
              size: 18,
              weight: FontWeight.w700,
              color: color ?? c.text,
              spacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: sans(
              size: 10.5,
              weight: FontWeight.w600,
              color: c.text3,
              spacing: 0.3,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Table profile'),
              const SizedBox(height: 12),
              Row(
                children: [
                  metric('${t.displayRows}', 'ROWS'),
                  metric('${t.columns.length}', 'COLUMNS'),
                  metric('$numCols', 'NUMERIC'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  metric(
                    '${t.columns.where((col) => col.pk).length}',
                    'PRIMARY KEY',
                    color: c.warning,
                  ),
                  metric('$fkCols', 'FOREIGN KEY', color: c.info),
                  metric(
                    '${t.columns.where((col) => !col.nullable).length}',
                    'NOT NULL',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Eyebrow('Column statistics · loaded page'),
        const SizedBox(height: 10),
        ...t.columns.map(
          (col) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ColStatCard(col: col, rows: rows),
          ),
        ),
      ],
    );
  }
}

class _ColStatCard extends StatelessWidget {
  final ColumnDef col;
  final List<RowMap> rows;
  const _ColStatCard({required this.col, required this.rows});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final vals = rows.map((r) => r[col.name]).toList();
    final n = vals.length;
    final nulls = vals.where((v) => v == null || v == '').length;
    final present = vals.where((v) => v != null && v != '').toList();
    final distinct = present.map((v) => '$v').toSet();
    final nullPct = n > 0 ? (nulls / n * 100).round() : 0;
    final fillPct = n > 0 ? ((n - nulls) / n * 100).round() : 0;
    final numeric = _isNumericType(col.type);
    num? mn, mx;
    double? avg;
    if (numeric) {
      final nums = present
          .map((v) => num.tryParse('$v'))
          .whereType<num>()
          .toList();
      if (nums.isNotEmpty) {
        mn = nums.reduce((a, b) => a < b ? a : b);
        mx = nums.reduce((a, b) => a > b ? a : b);
        avg =
            (nums.fold<num>(0, (a, b) => a + b) / nums.length * 100).round() /
            100;
      }
    }
    List<({String val, int count, int pct})>? top;
    if (distinct.isNotEmpty && distinct.length <= 12 && !col.pk) {
      final counts = <String, int>{};
      for (final v in present) {
        counts['$v'] = (counts['$v'] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()..sort((a, b) => b.value - a.value);
      top = sorted
          .take(6)
          .map(
            (e) => (
              val: e.key,
              count: e.value,
              pct: n > 0 ? (e.value / n * 100).round() : 0,
            ),
          )
          .toList();
    }

    Widget stat(String label, String val, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: sans(
            size: 9,
            weight: FontWeight.w700,
            color: c.text4,
            spacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: mono(
            size: 13,
            weight: FontWeight.w700,
            color: color ?? c.text,
          ),
        ),
      ],
    );

    return SpCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SpIcon(
                col.pk
                    ? 'key'
                    : col.fkTable != null
                    ? 'link'
                    : 'columns',
                size: 14,
                color: col.pk
                    ? c.warning
                    : col.fkTable != null
                    ? c.info
                    : c.text3,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  col.name,
                  style: mono(size: 13, weight: FontWeight.w700, color: c.text),
                ),
              ),
              Text(col.type, style: mono(size: 10.5, color: c.text4)),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: fillPct.clamp(0, 100),
                        child: Container(
                          height: 6,
                          color: nullPct > 0 ? c.accent : c.success,
                        ),
                      ),
                      Expanded(
                        flex: nullPct.clamp(0, 100),
                        child: Container(
                          height: 6,
                          color: c.danger.withOpacity(0.5),
                        ),
                      ),
                      if (fillPct + nullPct < 100)
                        Expanded(
                          flex: 100 - fillPct - nullPct,
                          child: Container(height: 6, color: c.surface3),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 86,
                child: Text(
                  nulls > 0 ? '$nullPct% null' : 'no nulls',
                  textAlign: TextAlign.right,
                  style: mono(size: 10.5, color: c.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              stat('DISTINCT', '${distinct.length}'),
              stat('FILLED', '${n - nulls}/$n'),
              if (mn != null) stat('MIN', '$mn'),
              if (mx != null) stat('MAX', '$mx'),
              if (avg != null) stat('AVG', '$avg'),
              if (distinct.length == n && n > 0 && !numeric)
                stat('UNIQUE', '✓', color: c.success),
            ],
          ),
          if (top != null) ...[
            const SizedBox(height: 12),
            ...top.map(
              (tp) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        tp.val,
                        overflow: TextOverflow.ellipsis,
                        style: mono(size: 11, color: c.text2),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 14,
                          color: c.surface3,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: (tp.pct / 100).clamp(0.03, 1),
                              child: Container(color: c.accent),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${tp.count} · ${tp.pct}%',
                        textAlign: TextAlign.right,
                        style: mono(size: 10.5, color: c.text3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
