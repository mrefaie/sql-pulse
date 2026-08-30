// SQL Pulse — Settings sheet (theme, masking, lock, data, about).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/engines.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/logo.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';
import 'security_sheet.dart';

void showSettingsSheet(BuildContext context) {
  showSpSheet(context, (ctx) => const _SettingsSheet());
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final prefs = state.prefs;

    Widget settingToggle(String icon, String label, String sub, bool on, VoidCallback onToggle) => Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SpIcon(icon, size: 18, color: on ? c.accent : c.text3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
                Text(sub, style: sans(size: 11.5, color: c.text3)),
              ]),
            ),
            SpSwitch(on: on, onToggle: onToggle),
          ]),
        );

    Widget metric(String val, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(val, style: mono(size: 22, weight: FontWeight.w800, color: c.text, spacing: -0.5)),
            const SizedBox(height: 2),
            Text(label, style: sans(size: 9, weight: FontWeight.w700, color: c.text4, spacing: 0.5)),
          ]),
        );

    return SpSheet(
      title: 'Settings',
      onClose: () => Navigator.pop(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('Appearance'),
        const SizedBox(height: 10),
        SpCard(
          color: c.surface2,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SpIcon(state.theme == 'dark' ? 'moon' : 'sun', size: 18, color: c.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Theme', style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
                Text('Dark or light interface', style: sans(size: 11.5, color: c.text3)),
              ]),
            ),
            SizedBox(
              width: 150,
              child: Segmented<String>(
                value: state.theme,
                onChange: (v) {
                  if (v != state.theme) state.toggleTheme();
                },
                fontSize: 12,
                items: const [SegItem('dark', 'Dark'), SegItem('light', 'Light')],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const Eyebrow('Data & safety'),
        const SizedBox(height: 10),
        SpCard(color: c.surface2, padding: const EdgeInsets.all(4), child: Column(children: [
          settingToggle('eyeoff', 'Mask sensitive data on production', 'Hide emails, secrets, salaries by default', prefs['maskProd'] != false, () => state.setPref('maskProd', !(prefs['maskProd'] != false))),
          Divider(color: c.border, height: 1, indent: 12, endIndent: 12),
          settingToggle('lock', 'Stage edits on production', 'Require commit before writes apply', prefs['stageProd'] != false, () => state.setPref('stageProd', !(prefs['stageProd'] != false))),
          Divider(color: c.border, height: 1, indent: 12, endIndent: 12),
          settingToggle('alert', 'Confirm destructive statements', 'Warn on UPDATE/DELETE without WHERE', prefs['guard'] != false, () => state.setPref('guard', !(prefs['guard'] != false))),
        ])),
        const SizedBox(height: 16),
        const Eyebrow('Security'),
        const SizedBox(height: 10),
        SpCard(color: c.surface2, padding: const EdgeInsets.all(4), child: InkWell(
          onTap: () {
            Navigator.pop(context);
            showSecuritySheet(context);
          },
          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            SpIcon('shield', size: 18, color: state.lock.enabled ? c.accent : c.text3),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('App lock', style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
              Text(state.lock.enabled ? 'Enabled · ${state.lock.method == 'pin' ? 'PIN' : state.lock.method == 'face' ? 'Face' : 'Fingerprint'}' : 'Off', style: sans(size: 11.5, color: c.text3)),
            ])),
            SpIcon('chevR', size: 16, color: c.text3),
          ])),
        )),
        const SizedBox(height: 16),
        const Eyebrow('On-device storage'),
        const SizedBox(height: 10),
        SpCard(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            metric('${state.profiles.length}', 'CONNECTIONS'),
            metric('${state.saved.length}', 'SAVED QUERIES'),
            metric('${state.dashboard.length}', 'BOARD CARDS'),
          ]),
          const SizedBox(height: 13),
          Text('Everything is stored locally on this device. Nothing is sent to a server.', style: sans(size: 11.5, color: c.text3, height: 1.5)),
          const SizedBox(height: 12),
          SpButton(label: 'Reset all local data', icon: 'trash', kind: BtnKind.danger, block: true, onTap: () => _confirmReset(context)),
        ])),
        const SizedBox(height: 16),
        const Eyebrow('About'),
        const SizedBox(height: 10),
        SpCard(padding: const EdgeInsets.all(14), child: Row(children: [
          const SpLogo(size: 38),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SQL Pulse', style: sans(size: 14, weight: FontWeight.w700, color: c.text)),
            Text('v1.0 · local-first · 5 engines', style: mono(size: 11, color: c.text3)),
          ])),
        ])),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: kEngineOrder.map((id) {
          final me = eng(id);
          return SpBadge(me.label, fg: Color(me.color), bg: Color(me.color).withOpacity(0.12));
        }).toList()),
      ]),
    );
  }

  void _confirmReset(BuildContext context) {
    final state = context.read<AppState>();
    showSpDialog(context, (ctx) => SpDialog(
          icon: 'trash',
          iconColor: SpColors.of(ctx).danger,
          title: 'Reset all local data?',
          sub: const Text('Connections, saved queries, board cards, history, lock, and preferences will be erased. This can\'t be undone.'),
          child: Row(children: [
            Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx))),
            const SizedBox(width: 10),
            Expanded(child: SpButton(label: 'Erase', icon: 'trash', kind: BtnKind.danger, onTap: () async {
              await state.resetAll();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            })),
          ]),
        ));
  }
}
