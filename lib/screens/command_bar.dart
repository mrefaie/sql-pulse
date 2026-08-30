// SQL Pulse — command bar / quick-action palette.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import 'settings_sheet.dart';
import 'search_sheet.dart';
import 'diff_sheet.dart';

class _Cmd {
  final String group;
  final String label;
  final String icon;
  final String? hint;
  final bool mono;
  final bool danger;
  final VoidCallback run;
  _Cmd(
    this.group,
    this.label,
    this.icon,
    this.run, {
    this.hint,
    this.mono = false,
    this.danger = false,
  });
}

void showCommandBar(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cmd',
    barrierColor: SpColors.of(context).scrim,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, a, b) => const _CommandBar(),
    transitionBuilder: (ctx, anim, b, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _CommandBar extends StatefulWidget {
  const _CommandBar();
  @override
  State<_CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<_CommandBar> {
  String q = '';
  int sel = 0;

  double _fuzzy(String query, String s) {
    final n = s.toLowerCase(), t = query.toLowerCase();
    if (t.isEmpty) return 0;
    if (n.startsWith(t)) return 100;
    final idx = n.indexOf(t);
    if (idx >= 0) return 70 - idx.toDouble();
    var qi = 0;
    for (var i = 0; i < n.length && qi < t.length; i++) {
      if (n[i] == t[qi]) qi++;
    }
    return qi == t.length ? 30 : -1;
  }

  List<_Cmd> _build(BuildContext context, AppState state) {
    final cmds = <_Cmd>[];
    final outer = context;
    for (final nav in const [
      ['browse', 'Browse', 'database'],
      ['query', 'Query console', 'terminal'],
      ['board', 'Board', 'grid'],
      ['diagram', 'ER diagram', 'dotgrid'],
      ['activity', 'Activity', 'history'],
    ]) {
      cmds.add(
        _Cmd('Go to', nav[1], nav[2], () => state.goTab(nav[0]), hint: 'tab'),
      );
    }
    cmds.add(
      _Cmd('Action', 'Search schema', 'search', () => showSearchSheet(outer)),
    );
    cmds.add(_Cmd('Action', 'Settings', 'cog', () => showSettingsSheet(outer)));
    cmds.add(
      _Cmd(
        'Action',
        'Compare connections',
        'gitcompare',
        () => showDiffSheet(outer),
      ),
    );
    cmds.add(
      _Cmd(
        'Action',
        state.theme == 'dark'
            ? 'Switch to light theme'
            : 'Switch to dark theme',
        state.theme == 'dark' ? 'sun' : 'moon',
        state.toggleTheme,
      ),
    );
    cmds.add(
      _Cmd(
        'Action',
        state.masking ? 'Reveal masked data' : 'Mask sensitive data',
        state.masking ? 'eye' : 'eyeoff',
        state.toggleMasking,
      ),
    );
    cmds.add(
      _Cmd('Action', 'Disconnect', 'logout', state.disconnect, danger: true),
    );
    final cat = state.db[state.catalog]!;
    for (final t in cat.tables.values) {
      cmds.add(
        _Cmd(
          'Open table',
          t.name,
          'table',
          () => state.openTable(t.name),
          hint: '${t.rows.length} rows',
          mono: true,
        ),
      );
    }
    for (final cName in state.catalogs) {
      if (cName != state.catalog)
        cmds.add(
          _Cmd(
            'Switch schema',
            cName,
            'database',
            () => state.switchCatalog(cName),
            mono: true,
          ),
        );
    }
    for (final s in state.saved) {
      cmds.add(
        _Cmd(
          'Saved query',
          s.name,
          'bookmark',
          () => state.loadIntoConsole(s.sql),
        ),
      );
    }
    return cmds;
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final cmds = _build(context, state);
    var results = q.trim().isNotEmpty
        ? (cmds
                  .map((cmd) => (cmd: cmd, s: _fuzzy(q.trim(), cmd.label)))
                  .where((x) => x.s >= 0)
                  .toList()
                ..sort((a, b) => b.s.compareTo(a.s)))
              .take(30)
              .map((x) => x.cmd)
              .toList()
        : cmds.take(24).toList();

    // group consecutive
    final rows = <({String? header, _Cmd? cmd, int idx})>[];
    String? lastGroup;
    for (var i = 0; i < results.length; i++) {
      if (results[i].group != lastGroup) {
        rows.add((header: results[i].group, cmd: null, idx: -1));
        lastGroup = results[i].group;
      }
      rows.add((header: null, cmd: results[i], idx: i));
    }

    void exec(_Cmd cmd) {
      Navigator.pop(context);
      Future.microtask(cmd.run);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          top: 70,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(c.dark ? 0.5 : 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      children: [
                        SpIcon('zap', size: 17, color: c.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() {
                              q = v;
                              sel = 0;
                            }),
                            style: sans(size: 14.5, color: c.text),
                            cursorColor: c.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Type a command, table, or query…',
                              hintStyle: sans(size: 14.5, color: c.text4),
                            ),
                          ),
                        ),
                        SpBadge('ESC', fontSize: 9),
                      ],
                    ),
                  ),
                  Flexible(
                    child: results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Empty(
                              icon: 'search',
                              title: 'No commands match "$q"',
                              sub: null,
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(6),
                            children: rows.map((r) {
                              if (r.header != null)
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    10,
                                    5,
                                  ),
                                  child: Eyebrow(r.header!),
                                );
                              final cmd = r.cmd!;
                              final on = r.idx == sel;
                              return GestureDetector(
                                onTap: () => exec(cmd),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: on ? c.surface3 : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: c.surface2,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(color: c.border),
                                        ),
                                        alignment: Alignment.center,
                                        child: SpIcon(
                                          cmd.icon,
                                          size: 15,
                                          color: cmd.danger
                                              ? c.danger
                                              : c.text2,
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Text(
                                          cmd.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: (cmd.mono ? mono : sans)(
                                            size: 13.5,
                                            weight: FontWeight.w500,
                                            color: cmd.danger
                                                ? c.danger
                                                : c.text,
                                          ),
                                        ),
                                      ),
                                      if (cmd.hint != null)
                                        Text(
                                          cmd.hint!,
                                          style: sans(
                                            size: 10.5,
                                            color: c.text4,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
