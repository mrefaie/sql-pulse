// SQL Pulse — Connection & profiles screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/seed_data.dart';
import '../data/engines.dart';
import '../data/store.dart';
import '../db/db_driver.dart';
import '../db/driver_factory.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/logo.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import 'editor_screen.dart';
import 'settings_sheet.dart';
import 'security_sheet.dart';

const Map<String, String> kEnvBadge = {'prod': 'warn', 'replica': 'fk', 'staging': 'accent', 'local': ''};
const Map<String, String> kEnvLabel = {'prod': 'PRODUCTION', 'replica': 'REPLICA', 'staging': 'STAGING', 'local': 'LOCAL'};

String connAddr(Profile p) => eng(p.engine).fileBased ? p.host : '${p.user}@${p.host}:${p.port}';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  String q = '';
  late Map<String, bool> collapsed;

  @override
  void initState() {
    super.initState();
    final saved = Store.load()['collapsedGroups'];
    collapsed = saved is Map ? saved.map((k, v) => MapEntry(k as String, v as bool)) : {};
  }

  void _toggleGroup(String g) {
    setState(() => collapsed[g] = !(collapsed[g] ?? false));
    Store.save({'collapsedGroups': collapsed});
  }

  bool _matches(Profile p) {
    if (q.trim().isEmpty) return true;
    return '${p.name} ${p.host} ${p.user} ${p.engine} ${p.label}'.toLowerCase().contains(q.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final profiles = state.profiles;

    final present = profiles.map((p) => p.group).where((g) => g.isNotEmpty).toSet();
    final customGroups = present.where((g) => !kGroups.contains(g)).toList()..sort();
    final orderedGroups = [...kGroups.where((g) => present.contains(g)), ...customGroups];
    final ungrouped = profiles.where((p) => p.group.isEmpty || !orderedGroups.contains(p.group)).toList();
    final allGroups = [...orderedGroups, if (ungrouped.isNotEmpty) 'Other'];

    return Column(children: [
      SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Row(children: [
              const SpLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SQL Pulse', style: sans(size: 20, weight: FontWeight.w800, color: c.text, spacing: -0.5)),
                  Text('Multi-engine SQL client', style: mono(size: 11, color: c.text3)),
                ]),
              ),
              IconBtn('cog', onTap: () => showSettingsSheet(context)),
              const SizedBox(width: 8),
              IconBtn('shield', color: state.lock.enabled ? c.accent : null, onTap: () => showSecuritySheet(context)),
              const SizedBox(width: 8),
              IconBtn(state.theme == 'dark' ? 'sun' : 'moon', onTap: state.toggleTheme),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            SpButton(label: 'New connection', icon: 'plus', kind: BtnKind.primary, block: true, onTap: () => _openEditor(context, null)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SpInput(hint: 'Filter connections', onChanged: (v) => setState(() => q = v), mono: false),
              ),
              const SizedBox(width: 10),
              Text('${profiles.length} saved', style: mono(size: 11, color: c.text4)),
            ]),
            const SizedBox(height: 16),
            ...allGroups.map((group) {
              final items = (group == 'Other' ? ungrouped : profiles.where((p) => p.group == group)).where(_matches).toList();
              if (q.trim().isNotEmpty && items.isEmpty) return const SizedBox.shrink();
              final isCollapsed = collapsed[group] ?? false;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  GestureDetector(
                    onTap: () => _toggleGroup(group),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      child: Row(children: [
                        Transform.rotate(angle: isCollapsed ? -1.5708 : 0, child: SpIcon('chevD', size: 15, color: c.text3)),
                        const SizedBox(width: 9),
                        SpIcon('folder', size: 15, color: c.text3),
                        const SizedBox(width: 9),
                        Eyebrow(group),
                        const SizedBox(width: 9),
                        Text('${items.length}', style: sans(size: 11, weight: FontWeight.w700, color: c.text4)),
                        const SizedBox(width: 9),
                        Expanded(child: Container(height: 1, color: c.border)),
                      ]),
                    ),
                  ),
                  if (!isCollapsed)
                    Padding(
                      padding: const EdgeInsets.only(top: 11),
                      child: Column(children: items.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ConnRow(p: p, onConnect: () => _openConnect(context, p), onActions: () => _openActions(context, p)),
                      )).toList()),
                    ),
                ]),
              );
            }),
          ],
        ),
      ),
    ]);
  }

  void _openEditor(BuildContext context, Profile? p) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) => ConnectionEditor(
          profile: p,
          onSave: (data) {
            if (p == null) {
              state.addProfile(data);
            } else {
              state.updateProfile(p.id, data);
            }
            Navigator.pop(ctx);
          },
          onTest: (draft) {
            Navigator.pop(ctx);
            _openTest(context, draft);
          },
        ));
  }

  void _openConnect(BuildContext context, Profile p) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) => _ConnectDialog(
          profile: p,
          onTest: () {
            Navigator.pop(ctx);
            _openTest(context, p);
          },
          onConnect: (role) async {
            Navigator.pop(ctx);
            // loading overlay
            showDialog(
              context: context,
              barrierDismissible: false,
              barrierColor: SpColors.of(context).scrim,
              builder: (_) => Center(child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: SpColors.of(context).surface, borderRadius: BorderRadius.circular(20)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Spinner(size: 36),
                  const SizedBox(height: 14),
                  Text('Connecting to ${p.host}…', style: sans(size: 13, color: SpColors.of(context).text2)),
                ]),
              )),
            );
            try {
              await state.connect(p, role);
              if (context.mounted) Navigator.pop(context); // remove loading
            } catch (e) {
              if (context.mounted) Navigator.pop(context); // remove loading
              if (context.mounted) {
                showSpDialog(context, (dctx) => SpDialog(
                      icon: 'alert', iconColor: SpColors.of(dctx).danger, title: 'Connection failed',
                      sub: Text(e is DbException ? e.message : e.toString()),
                      child: SpButton(label: 'Close', kind: BtnKind.primary, block: true, onTap: () => Navigator.pop(dctx)),
                    ));
              }
            }
          },
        ));
  }

  void _openTest(BuildContext context, Profile p) {
    showSpDialog(context, (ctx) => _TestModal(profile: p));
  }

  void _openActions(BuildContext context, Profile p) {
    final state = context.read<AppState>();
    showSpSheet(context, (ctx) => SpSheet(
          title: p.name,
          right: TagDot(p.color, size: 12),
          onClose: () => Navigator.pop(ctx),
          child: Column(children: [
            _ActionItem(icon: 'play', label: 'Connect', onTap: () {
              Navigator.pop(ctx);
              _openConnect(context, p);
            }),
            _ActionItem(icon: 'cog', label: 'Edit details', onTap: () {
              Navigator.pop(ctx);
              _openEditor(context, p);
            }),
            _ActionItem(icon: 'columns', label: 'Duplicate', onTap: () {
              state.duplicateProfile(p);
              Navigator.pop(ctx);
            }),
            _ActionItem(icon: 'gauge', label: 'Test connection', onTap: () {
              Navigator.pop(ctx);
              _openTest(context, p);
            }),
            Divider(color: SpColors.of(ctx).border, height: 13),
            _ActionItem(icon: 'trash', label: 'Delete connection', danger: true, onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context, p);
            }),
          ]),
        ));
  }

  void _confirmDelete(BuildContext context, Profile p) {
    final state = context.read<AppState>();
    showSpDialog(context, (ctx) => SpDialog(
          icon: 'trash',
          iconColor: SpColors.of(ctx).danger,
          title: 'Delete connection?',
          sub: Text('"${p.name}" will be permanently removed. This can\'t be undone.'),
          child: Row(children: [
            Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx))),
            const SizedBox(width: 10),
            Expanded(child: SpButton(label: 'Delete', icon: 'trash', kind: BtnKind.danger, onTap: () {
              state.deleteProfile(p.id);
              Navigator.pop(ctx);
            })),
          ]),
        ));
  }
}

class _ConnRow extends StatelessWidget {
  final Profile p;
  final VoidCallback onConnect;
  final VoidCallback onActions;
  const _ConnRow({required this.p, required this.onConnect, required this.onActions});

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
        boxShadow: c.dark ? null : [BoxShadow(color: const Color(0x121C1A16), blurRadius: 26, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: kTagColors[p.color]),
          Expanded(
            child: GestureDetector(
              onTap: onConnect,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 13, 4, 13),
                child: Row(children: [
                  EngineMark(p.engine, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: sans(size: 14.5, weight: FontWeight.w700, color: c.text, spacing: -0.2))),
                        if (p.label.isNotEmpty) ...[const SizedBox(width: 7), SpBadge(p.label)],
                      ]),
                      const SizedBox(height: 3),
                      Text(connAddr(p), overflow: TextOverflow.ellipsis, style: mono(size: 11.5, color: c.text3)),
                      const SizedBox(height: 9),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        EngineTag(p.engine),
                        SpBadge(kEnvLabel[p.env] ?? p.env, variant: kEnvBadge[p.env] ?? ''),
                        if (p.ssl) SpBadge('SSL', icon: 'lock'),
                        if (p.ssh) SpBadge('SSH', icon: 'network'),
                        SpBadge(p.catalog, variant: 'accent'),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          GestureDetector(
            onTap: onActions,
            behavior: HitTestBehavior.opaque,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.center, child: SpIcon('more', size: 20, color: c.text3)),
          ),
        ]),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final String icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _ActionItem({required this.icon, required this.label, this.danger = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
        child: Row(children: [
          SpIcon(icon, size: 17, color: danger ? c.danger : c.text2),
          const SizedBox(width: 10),
          Text(label, style: sans(size: 14, weight: FontWeight.w600, color: danger ? c.danger : c.text)),
        ]),
      ),
    );
  }
}

class _ConnectDialog extends StatefulWidget {
  final Profile profile;
  final VoidCallback onTest;
  final void Function(String role) onConnect;
  const _ConnectDialog({required this.profile, required this.onTest, required this.onConnect});
  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  String role = 'Admin';
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final p = widget.profile;
    return SpSheet(
      title: 'Connect',
      right: SpBadge(kEnvLabel[p.env] ?? p.env, variant: kEnvBadge[p.env] ?? ''),
      onClose: () => Navigator.pop(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpCard(
          child: Row(children: [
            EngineMark(p.engine, size: 44, radius: 13),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: sans(size: 15, weight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text(connAddr(p), style: mono(size: 11.5, color: c.text3)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  EngineTag(p.engine),
                  SpBadge(p.catalog, variant: 'accent'),
                  if (p.ssl) SpBadge('SSL', icon: 'lock'),
                  if (p.ssh) SpBadge('SSH', icon: 'network'),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Connect as role'),
        ...kRoles.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SpRow(
                selected: role == r.id,
                padding: const EdgeInsets.all(11),
                onTap: () => setState(() => role = r.id),
                child: Row(children: [
                  RowIco('', bg: role == r.id ? c.accentSoft : null, fg: role == r.id ? c.accent : null).withGlyph(RoleGlyph(r.id, color: role == r.id ? c.accent : c.text2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.label, style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
                      Text(r.desc, style: sans(size: 11.5, color: c.text3)),
                    ]),
                  ),
                  if (role == r.id) SpIcon('check', size: 18, color: c.accent),
                ]),
              ),
            )),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: SpButton(label: 'Test', icon: 'gauge', kind: BtnKind.ghost, onTap: widget.onTest)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SpButton(label: 'Connect', icon: 'play', kind: BtnKind.primary, onTap: () => widget.onConnect(role))),
        ]),
      ]),
    );
  }
}

/// Small helper to render a RowIco-styled box with a custom glyph child.
extension on RowIco {
  Widget withGlyph(Widget glyph) => Builder(builder: (context) {
        final c = SpColors.of(context);
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: bg ?? c.surface3, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: glyph,
        );
      });
}

class _TestModal extends StatefulWidget {
  final Profile profile;
  const _TestModal({required this.profile});
  @override
  State<_TestModal> createState() => _TestModalState();
}

/// Performs a REAL connection test: opens the driver, runs a `SELECT 1`,
/// reports the live server version, round-trip latency, or the real error.
class _TestModalState extends State<_TestModal> {
  late List<String> steps;
  int idx = 0; // index of the step currently running
  bool done = false;
  bool failed = false;
  String? error;
  String? version;
  int? latencyMs;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    final e = eng(p.engine);
    steps = e.fileBased
        ? ['Opening database file', 'Reading version', 'Running test query']
        : ['Connecting to ${p.host}:${p.port}', 'Authenticating ${p.user}', 'Running test query'];
    _run();
  }

  Future<void> _run() async {
    final sw = Stopwatch()..start();
    final drv = makeDriver(widget.profile.engine);
    try {
      // step 0 + 1: open connection + authenticate (driver.connect does both)
      await drv.connect(widget.profile);
      if (!mounted) return;
      version = drv.serverVersion;
      setState(() => idx = 2);
      // step 2: a real round-trip query
      final r = await drv.execute('SELECT 1');
      if (r.error) throw DbException(r.message ?? 'Test query failed');
      latencyMs = sw.elapsedMilliseconds;
      if (!mounted) return;
      setState(() => done = true);
    } catch (e) {
      latencyMs = sw.elapsedMilliseconds;
      if (mounted) {
        setState(() {
          failed = true;
          error = e is DbException ? e.message : e.toString();
        });
      }
    } finally {
      try {
        await drv.close();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final p = widget.profile;
    final e = eng(p.engine);
    final running = !done && !failed;
    return SpDialog(
      width: 360,
      icon: done ? 'check' : failed ? 'alert' : null,
      iconColor: done ? c.success : c.danger,
      title: done ? 'Connection successful' : failed ? 'Connection failed' : null,
      sub: done ? Text('Reached ${p.host} in ${latencyMs ?? '–'} ms') : null,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (running) ...[
          const SizedBox(height: 6),
          const Center(child: Spinner(size: 40)),
          const SizedBox(height: 14),
          Center(child: Text('Testing connection…', style: sans(size: 15, weight: FontWeight.w700, color: c.text))),
          const SizedBox(height: 4),
          Center(child: Text(p.name, style: mono(size: 11.5, color: c.text3))),
          const SizedBox(height: 18),
        ],
        ...steps.asMap().entries.map((entry) {
          final i = entry.key;
          final label = entry.value;
          // a step is done if past it; failed at the active one when failed
          final isFailedStep = failed && i == idx;
          final stateStr = done
              ? 'done'
              : isFailedStep
                  ? 'fail'
                  : (i < idx ? 'done' : (i == idx && running ? 'active' : 'pending'));
          return Opacity(
            opacity: stateStr == 'pending' ? 0.4 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
              child: Row(children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: stateStr == 'done' ? c.successSoft : stateStr == 'fail' ? c.dangerSoft : c.surface3, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: stateStr == 'done'
                      ? SpIcon('check', size: 13, color: c.success)
                      : stateStr == 'fail'
                          ? SpIcon('x', size: 13, color: c.danger)
                          : stateStr == 'active'
                              ? const Spinner(size: 15)
                              : Container(width: 5, height: 5, decoration: BoxDecoration(color: c.text4, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 11),
                Text(label, style: mono(size: 12, color: stateStr == 'done' ? c.text : stateStr == 'fail' ? c.danger : c.text3)),
              ]),
            ),
          );
        }),
        if (failed) ...[
          const SizedBox(height: 12),
          SpCard(color: c.dangerSoft, borderColor: Colors.transparent, padding: const EdgeInsets.all(12), child: Text(error ?? 'Unknown error', style: mono(size: 11.5, color: c.danger, height: 1.5))),
          const SizedBox(height: 14),
          SpButton(label: 'Close', kind: BtnKind.primary, block: true, onTap: () => Navigator.pop(context)),
        ],
        if (done) ...[
          const SizedBox(height: 14),
          SpCard(
            color: c.surface2,
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(child: _Kv('Server', version ?? e.serverVersion)),
                Expanded(child: _Kv('Latency', '${latencyMs ?? '–'} ms')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Kv('Engine', e.label)),
                Expanded(child: _Kv('Host', e.fileBased ? p.host.split('/').last : '${p.host}:${p.port}')),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          SpButton(label: 'Done', kind: BtnKind.primary, block: true, onTap: () => Navigator.pop(context)),
        ],
      ]),
    );
  }
}

class _Kv extends StatelessWidget {
  final String k;
  final String v;
  const _Kv(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k.toUpperCase(), style: sans(size: 9.5, weight: FontWeight.w700, color: c.text4, spacing: 0.5)),
      const SizedBox(height: 3),
      Text(v, style: mono(size: 12.5, weight: FontWeight.w600, color: c.text)),
    ]);
  }
}
