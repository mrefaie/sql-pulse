// SQL Pulse — workspace shell: env ribbon, header, bottom nav, pending tray, tab routing.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/seed_data.dart';
import '../data/engines.dart' as en;
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import 'browse_tab.dart';
import 'query_tab.dart';
import 'board_tab.dart';
import 'diagram_tab.dart';
import 'activity_tab.dart';
import 'settings_sheet.dart';
import 'search_sheet.dart';
import 'diff_sheet.dart';
import 'command_bar.dart';

const List<List<String>> kNav = [
  ['browse', 'Browse', 'database'],
  ['query', 'Query', 'terminal'],
  ['board', 'Board', 'grid'],
  ['diagram', 'Diagram', 'dotgrid'],
  ['activity', 'Activity', 'history'],
];

const Map<String, String> kRoleBadge = {'Admin': 'accent', 'Developer': 'fk', 'Analyst': 'warn', 'ReadOnly': ''};

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final base = SpColors.of(context);
    final tint = base.withAccent(state.profile != null ? kTagColors[state.profile!.color] : null);

    // re-tint the whole workspace subtree
    return SpThemeScope(
      colors: tint,
      child: Material(
        color: tint.bg,
        child: state.detail ? const TableDetail() : const _WorkspaceBody(),
      ),
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Widget body;
    switch (state.tab) {
      case 'query':
        body = const QueryTab();
        break;
      case 'board':
        body = const BoardTab();
        break;
      case 'diagram':
        body = const DiagramTab();
        break;
      case 'activity':
        body = const ActivityTab();
        break;
      default:
        body = const BrowseTab();
    }
    return SafeArea(
      bottom: false,
      child: Column(children: [
        const _EnvRibbon(),
        const WorkspaceHeader(),
        Expanded(child: Stack(children: [body, const PendingTray()])),
        const _BottomNav(),
      ]),
    );
  }
}

class _EnvRibbon extends StatelessWidget {
  const _EnvRibbon();
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
      decoration: BoxDecoration(color: meta.soft, border: Border(bottom: BorderSide(color: meta.color))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(meta.label, style: sans(size: 10, weight: FontWeight.w800, color: meta.color, spacing: 1.2)),
        if (env == 'prod') ...[
          const SizedBox(width: 6),
          Text('· write with care', style: sans(size: 10, weight: FontWeight.w600, color: meta.color.withOpacity(0.8))),
        ],
      ]),
    );
  }
}

class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final p = state.profile;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _catalogMenu(context),
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              RowIco('database', box: 36, iconSize: 18, bg: c.accentSoft, fg: c.accent),
              const SizedBox(width: 9),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(state.catalog, overflow: TextOverflow.ellipsis, style: sans(size: 15.5, weight: FontWeight.w700, color: c.text))),
                    SpIcon('chevD', size: 14, color: c.text3),
                  ]),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    EngineTag(state.engine, fontSize: 9.5, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(p?.host ?? 'localhost', overflow: TextOverflow.ellipsis, style: mono(size: 11, color: c.text3))),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _roleMenu(context),
          child: SpBadge(state.role, variant: kRoleBadge[state.role] ?? '', icon: null, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7)),
        ),
        const SizedBox(width: 8),
        IconBtn('zap', box: 34, iconSize: 16, onTap: () => showCommandBar(context)),
        const SizedBox(width: 6),
        IconBtn('more', box: 34, iconSize: 18, onTap: () => _moreMenu(context)),
      ]),
    );
  }

  void _catalogMenu(BuildContext context) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) => SpSheet(
          title: 'Switch ${en.eng(state.engine).schemaTerm}',
          onClose: () => Navigator.pop(ctx),
          child: Column(children: (state.catalogs.isEmpty ? [state.catalog] : state.catalogs).map((cat) {
            final on = state.catalog == cat;
            final c = SpColors.of(ctx);
            return InkWell(
              onTap: () {
                state.switchCatalog(cat);
                Navigator.pop(ctx);
              },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13), child: Row(children: [
                SpIcon('database', size: 16, color: on ? c.accent : c.text3),
                const SizedBox(width: 10),
                Expanded(child: Text(cat, style: mono(size: 13, color: c.text))),
                if (on) SpIcon('check', size: 15, color: c.accent),
              ])),
            );
          }).toList()),
        ));
  }

  void _roleMenu(BuildContext context) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) => SpSheet(
          title: 'Active role',
          onClose: () => Navigator.pop(ctx),
          child: Column(children: kRoles.map((r) {
            final on = state.role == r.id;
            final c = SpColors.of(ctx);
            return InkWell(
              onTap: () {
                state.setRole(r.id);
                Navigator.pop(ctx);
              },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), child: Row(children: [
                RoleGlyph(r.id, size: 16, color: on ? c.accent : c.text3),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.label, style: sans(size: 13, weight: FontWeight.w600, color: c.text)),
                  Text(r.desc, style: sans(size: 10.5, color: c.text3)),
                ])),
                if (on) SpIcon('check', size: 15, color: c.accent),
              ])),
            );
          }).toList()),
        ));
  }

  void _moreMenu(BuildContext context) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) {
      final c = SpColors.of(ctx);
      Widget item(String icon, String label, VoidCallback onTap, {bool danger = false}) => InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13), child: Row(children: [
              SpIcon(icon, size: 16, color: danger ? c.danger : c.text2),
              const SizedBox(width: 12),
              Text(label, style: sans(size: 14, weight: FontWeight.w500, color: danger ? c.danger : c.text)),
            ])),
          );
      return SpSheet(
        title: 'Menu',
        onClose: () => Navigator.pop(ctx),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          item('search', 'Search schema', () {
            Navigator.pop(ctx);
            showSearchSheet(context);
          }),
          item('gitcompare', 'Compare connections', () {
            Navigator.pop(ctx);
            showDiffSheet(context);
          }),
          item(state.theme == 'dark' ? 'sun' : 'moon', state.theme == 'dark' ? 'Light theme' : 'Dark theme', () {
            state.toggleTheme();
            Navigator.pop(ctx);
          }),
          item('cog', 'Settings', () {
            Navigator.pop(ctx);
            showSettingsSheet(context);
          }),
          Divider(color: c.border, height: 13),
          item('logout', 'Disconnect', () {
            Navigator.pop(ctx);
            state.disconnect();
          }, danger: true),
        ]),
      );
    });
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 6 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: c.navBg, border: Border(top: BorderSide(color: c.border))),
      child: Row(children: kNav.map((it) {
        final active = state.tab == it[0];
        return Expanded(
          child: GestureDetector(
            onTap: () => state.goTab(it[0]),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SpIcon(it[2], size: 21, color: active ? c.accent : c.text3),
                const SizedBox(height: 4),
                Text(it[1], style: sans(size: 10.5, weight: FontWeight.w600, color: active ? c.accent : c.text3, spacing: -0.1)),
              ]),
            ),
          ),
        );
      }).toList()),
    );
  }
}

class PendingTray extends StatefulWidget {
  final double bottom;
  const PendingTray({super.key, this.bottom = 16});
  @override
  State<PendingTray> createState() => _PendingTrayState();
}

class _PendingTrayState extends State<PendingTray> {
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final n = state.pending.length;
    if (n == 0) return const SizedBox.shrink();
    return Positioned(
      left: 14, right: 14, bottom: widget.bottom,
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 28, offset: Offset(0, 12))]),
          child: Row(children: [
            SpIcon('save', size: 17, color: c.accentInk),
            const SizedBox(width: 10),
            Expanded(child: Text('$n pending change${n > 1 ? 's' : ''}', style: sans(size: 13.5, weight: FontWeight.w700, color: c.accentInk))),
            Text('Review', style: sans(size: 11.5, weight: FontWeight.w700, color: c.accentInk.withOpacity(0.85))),
            const SizedBox(width: 6),
            SpIcon('chevR', size: 16, color: c.accentInk),
          ]),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) {
      final c = SpColors.of(ctx);
      final pending = state.pending;
      final byKind = {'update': 0, 'insert': 0, 'delete': 0};
      for (final p in pending) {
        byKind[p.kind] = byKind[p.kind]! + 1;
      }
      final kindMeta = {
        'update': (color: c.warning, icon: 'columns', verb: 'UPDATE'),
        'insert': (color: c.success, icon: 'plus', verb: 'INSERT'),
        'delete': (color: c.danger, icon: 'trash', verb: 'DELETE'),
      };
      return StatefulBuilder(builder: (ctx, setSheet) {
        final n = state.pending.length;
        if (n == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.maybePop(ctx));
          return const SizedBox.shrink();
        }
        return SpSheet(
          title: 'Pending changes',
          right: SpBadge('$n'),
          onClose: () => Navigator.pop(ctx),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: byKind.entries.where((e) => e.value > 0).map((e) {
              final m = kindMeta[e.key]!;
              return Padding(padding: const EdgeInsets.only(right: 8), child: SpBadge('${e.value} ${m.verb}', fg: m.color, bg: Colors.transparent));
            }).toList()),
            const SizedBox(height: 14),
            ...state.pending.map((p) {
              final m = kindMeta[p.kind]!;
              return Padding(padding: const EdgeInsets.only(bottom: 8), child: SpCard(padding: const EdgeInsets.all(11), child: Row(children: [
                SpIcon(m.icon, size: 15, color: m.color),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.label, overflow: TextOverflow.ellipsis, style: mono(size: 11.5, weight: FontWeight.w600, color: c.text)),
                  Text(p.table, style: sans(size: 10.5, color: c.text3)),
                ])),
                GestureDetector(onTap: () {
                  state.discardPending(p.id);
                  setSheet(() {});
                }, child: SpIcon('x', size: 16, color: c.text3)),
              ])));
            }),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: SpButton(label: 'Rollback all', icon: 'x', kind: BtnKind.ghost, onTap: () {
                state.rollbackPending();
                Navigator.pop(ctx);
              })),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: SpButton(label: 'Commit $n', icon: 'check', kind: BtnKind.primary, onTap: () {
                state.commitPending();
                Navigator.pop(ctx);
              })),
            ]),
          ]),
        );
      });
    });
  }
}
