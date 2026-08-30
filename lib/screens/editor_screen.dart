// SQL Pulse — Connection editor (engine-aware, schema-driven options).
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../data/models.dart';
import '../data/seed_data.dart';
import '../data/engines.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';

class ConnectionEditor extends StatefulWidget {
  final Profile? profile;
  final void Function(Profile data) onSave;
  final void Function(Profile draft) onTest;
  const ConnectionEditor({super.key, this.profile, required this.onSave, required this.onTest});
  @override
  State<ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<ConnectionEditor> {
  late String engine;
  late TextEditingController name, group, label, host, port, user, catalogCtrl;
  late String color, catalog, env;
  late bool ssh, ssl;
  late Map<String, Object?> o;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    engine = p?.engine ?? 'mysql';
    name = TextEditingController(text: p?.name ?? '');
    group = TextEditingController(text: p?.group ?? 'Local');
    label = TextEditingController(text: p?.label ?? '');
    host = TextEditingController(text: p?.host ?? '');
    port = TextEditingController(text: '${p?.port ?? eng(p?.engine ?? 'mysql').port}');
    user = TextEditingController(text: p?.user ?? '');
    color = p?.color ?? 'blue';
    catalog = p?.catalog ?? '';
    catalogCtrl = TextEditingController(text: catalog);
    env = p?.env ?? 'local';
    ssh = p?.ssh ?? false;
    ssl = p?.ssl ?? true;
    o = {...defaultsFor(p?.engine ?? 'mysql'), ...(p?.options ?? {})};
  }

  @override
  void dispose() {
    for (final c in [name, group, label, host, port, user, catalogCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void set(String k, Object? v) => setState(() => o[k] = v);

  void switchEngine(String id) {
    final prevDefaultPort = eng(engine).port;
    final preserved = {
      'password': o['password'], 'sshHost': o['sshHost'], 'sshPort': o['sshPort'], 'sshUser': o['sshUser'],
      'sshAuth': o['sshAuth'], 'sshKeyFile': o['sshKeyFile'], 'sshPassphrase': o['sshPassphrase'], 'sshKnownHosts': o['sshKnownHosts'],
      'caFile': o['caFile'], 'certFile': o['certFile'], 'keyFile': o['keyFile'], 'readOnly': o['readOnly'],
    };
    setState(() {
      o = {...defaultsFor(id), ...preserved};
      if (port.text.isEmpty || port.text == '$prevDefaultPort') port.text = '${eng(id).port}';
      engine = id;
    });
  }

  bool get valid {
    final e = eng(engine);
    return e.fileBased
        ? name.text.trim().isNotEmpty && host.text.trim().isNotEmpty
        : name.text.trim().isNotEmpty && host.text.trim().isNotEmpty && user.text.trim().isNotEmpty;
  }

  Profile collect() {
    final e = eng(engine);
    final opts = {...o};
    if (e.tls?.toggleKey != null) opts[e.tls!.toggleKey!] = ssl;
    return Profile(
      id: widget.profile?.id ?? 0,
      name: name.text.trim(),
      group: group.text.trim().isEmpty ? 'Local' : group.text.trim(),
      label: label.text.trim(),
      color: color,
      engine: engine,
      host: host.text.trim(),
      port: int.tryParse(port.text) ?? e.port,
      user: user.text.trim(),
      catalog: catalog,
      env: env,
      ssl: e.fileBased ? false : ssl,
      ssh: e.fileBased ? false : ssh,
      options: opts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final e = eng(engine);
    final isNew = widget.profile == null;
    final tls = e.tls;

    // advanced rows: pair consecutive half-width fields
    final advRows = <List<Object>>[];
    for (var i = 0; i < e.advanced.length; i++) {
      final it = e.advanced[i];
      if (it is OptField && it.half && i + 1 < e.advanced.length && e.advanced[i + 1] is OptField && (e.advanced[i + 1] as OptField).half) {
        advRows.add([it, e.advanced[i + 1]]);
        i++;
      } else {
        advRows.add([it]);
      }
    }

    return SpSheet(
      title: isNew ? 'New connection' : 'Edit connection',
      right: SpChip('Test', icon: 'gauge', onTap: valid ? () => widget.onTest(collect()) : null),
      onClose: () => Navigator.pop(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ENGINE PICKER
        const FieldLabel('Database engine'),
        Wrap(spacing: 8, runSpacing: 8, children: kEngineOrder.map((id) {
          final me = eng(id);
          final on = engine == id;
          final col = Color(me.color);
          return SizedBox(
            width: (MediaQuery.of(context).size.width - 32 - 16) / 3,
            child: GestureDetector(
              onTap: () => switchEngine(id),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: on ? col.withOpacity(0.12) : c.surface2,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: on ? col : c.border),
                ),
                child: Column(children: [
                  Container(width: 30, height: 30, decoration: BoxDecoration(color: col.withOpacity(0.15), borderRadius: BorderRadius.circular(9)), alignment: Alignment.center, child: SpIcon('database', size: 16, color: col)),
                  const SizedBox(height: 7),
                  Text(me.label, style: sans(size: 12, weight: FontWeight.w700, color: on ? col : c.text2)),
                  const SizedBox(height: 2),
                  Text(me.fileBased ? 'file' : ':${me.port}', style: mono(size: 9.5, color: c.text4)),
                ]),
              ),
            ),
          );
        }).toList()),
        const SizedBox(height: 12),

        // GENERAL
        FormSection(icon: 'info', title: 'General', accent: c.accent, children: [
          _field('Connection name', SpInput(controller: name, mono: false, onChanged: (_) => setState(() {}), hint: 'Production · Primary')),
          _field('Folder', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 7, runSpacing: 7, children: [
              ...{...kGroups, if (widget.profile?.group != null && !kGroups.contains(widget.profile!.group)) widget.profile!.group}.map((g) =>
                  SpChip(g, icon: 'folder', mono: false, on: group.text == g, onTap: () => setState(() => group.text = g))),
            ]),
            const SizedBox(height: 8),
            SpInput(controller: group, mono: false, hint: 'or type a folder name…', onChanged: (_) => setState(() {})),
          ]), hint: 'group by project / environment'),
          _field('Label', SpInput(controller: label, mono: false, hint: 'Primary writer'), hint: 'optional'),
          _field('Color tag', Wrap(spacing: 10, runSpacing: 10, children: kTags.map((t) {
            final tc = kTagColors[t]!;
            return GestureDetector(
              onTap: () => setState(() => color = t),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: tc, borderRadius: BorderRadius.circular(9),
                  border: color == t ? Border.all(color: tc, width: 2) : null,
                  boxShadow: color == t ? [BoxShadow(color: c.surface, spreadRadius: 2), BoxShadow(color: tc, spreadRadius: 4)] : null,
                ),
                alignment: Alignment.center,
                child: color == t ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
            );
          }).toList())),
          if (e.fileBased)
            _field('Database file', _FilePickerField(value: '${host.text}', placeholder: 'Choose database.sqlite', onPick: (f) => setState(() => host.text = f), onClear: () => setState(() => host.text = '')), hint: 'path to the .sqlite / .db file')
          else
            Row(children: [
              Expanded(child: _field('Host', SpInput(controller: host, mono: false, hint: '10.0.1.42', onChanged: (_) => setState(() {})))),
              const SizedBox(width: 10),
              SizedBox(width: 92, child: _field('Port', SpInput(controller: port, keyboardType: TextInputType.number))),
            ]),
          _field('Default ${e.schemaTerm}', SpInput(controller: catalogCtrl, hint: e.fileBased ? 'main' : 'database name', onChanged: (v) => catalog = v), hint: 'loaded on connect'),
          _field('Environment', _ChipSelect(value: env, options: const ['prod', 'replica', 'staging', 'local'], labels: const {'prod': 'Production', 'replica': 'Replica', 'staging': 'Staging', 'local': 'Local'}, onChange: (v) => setState(() => env = v))),
        ]),
        const SizedBox(height: 12),

        // AUTHENTICATION
        if (!e.fileBased)
          FormSection(icon: 'key', title: 'Authentication', accent: c.warning, children: [
            _field('Username', SpInput(controller: user, mono: false, hint: 'root', onChanged: (_) => setState(() {}))),
            ...e.auth.map((f) => _OptionField(f: f, o: o, set: set)),
          ]),
        if (!e.fileBased) const SizedBox(height: 12),

        // SSH TUNNEL
        if (!e.noSsh)
          FormSection(icon: 'network', title: 'SSH tunnel', hint: ssh ? 'enabled' : 'disabled', accent: c.info, defaultOpen: ssh, children: [
            _ToggleLine(label: 'Forward through a bastion host', on: ssh, onToggle: () => setState(() => ssh = !ssh)),
            if (ssh) ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _OptionField(f: OptField(key: 'sshHost', label: 'SSH host', placeholder: 'bastion.net'), o: o, set: set)),
                const SizedBox(width: 10),
                SizedBox(width: 90, child: _OptionField(f: OptField(key: 'sshPort', label: 'Port', type: 'number'), o: o, set: set)),
              ]),
              _OptionField(f: OptField(key: 'sshUser', label: 'SSH user', placeholder: 'jump_admin'), o: o, set: set),
              _field('Auth method', _ChipSelect(value: '${o['sshAuth']}', options: const ['key', 'password', 'agent'], labels: const {'key': 'Private key', 'password': 'Password', 'agent': 'SSH agent'}, onChange: (v) => set('sshAuth', v))),
              if (o['sshAuth'] == 'key') ...[
                _field('Private key file', _FilePickerField(value: '${o['sshKeyFile']}', placeholder: 'Choose id_rsa / .pem', onPick: (f) => set('sshKeyFile', f), onClear: () => set('sshKeyFile', ''))),
                _OptionField(f: OptField(key: 'sshPassphrase', label: 'Key passphrase', hint: 'optional', type: 'password', placeholder: 'leave blank if none'), o: o, set: set),
              ],
              if (o['sshAuth'] == 'password')
                _OptionField(f: OptField(key: 'sshPassphrase', label: 'SSH password', type: 'password', placeholder: '••••••••'), o: o, set: set),
              _OptionField(f: OptField(key: 'sshKnownHosts', label: 'Known hosts'), o: o, set: set),
            ],
          ]),
        if (!e.noSsh) const SizedBox(height: 12),

        // TLS
        if (tls != null)
          FormSection(icon: 'lock', title: tls.title, hint: ssl ? 'enabled' : 'disabled', accent: c.success, defaultOpen: ssl, children: [
            _ToggleLine(label: tls.toggleLabel, on: ssl, onToggle: () => setState(() => ssl = !ssl)),
            if (ssl) ...[
              const SizedBox(height: 14),
              if (tls.modeKey != null) _field('SSL mode', _ChipSelect(value: '${o[tls.modeKey]}', options: tls.modes, mono: tls.modeMono, onChange: (v) => set(tls.modeKey!, v))),
              if (tls.extraToggles.isNotEmpty)
                SpCard(color: c.surface2, padding: const EdgeInsets.all(4), child: Column(children: [
                  for (var i = 0; i < tls.extraToggles.length; i++) ...[
                    if (i > 0) Divider(color: c.border, height: 1, indent: 12, endIndent: 12),
                    _ToggleLine(pad: true, label: tls.extraToggles[i].label, sub: tls.extraToggles[i].sub, on: o[tls.extraToggles[i].key] == true, onToggle: () => set(tls.extraToggles[i].key, !(o[tls.extraToggles[i].key] == true))),
                  ],
                ])),
              if (tls.extraToggles.isNotEmpty) const SizedBox(height: 14),
              ...tls.files.map((f) => _OptionField(f: f, o: o, set: set)),
            ],
          ]),
        if (tls != null) const SizedBox(height: 12),

        // ADVANCED
        FormSection(icon: 'sliders', title: 'Advanced', accent: c.synFn, defaultOpen: false, children: [
          ...advRows.map((row) {
            if (row.length == 2) {
              return Row(children: row.map((it) => Expanded(child: _OptionField(f: it as OptField, o: o, set: set))).toList());
            }
            final item = row[0];
            if (item is OptGroup) {
              final visible = item.items.where((it) => it.showIf == null || it.showIf!(o)).toList();
              return SpCard(color: c.surface2, padding: const EdgeInsets.all(4), child: Column(children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) Divider(color: c.border, height: 1, indent: 12, endIndent: 12),
                  _ToggleLine(pad: true, label: visible[i].label, sub: visible[i].sub, on: o[visible[i].key] == true, onToggle: () => set(visible[i].key, !(o[visible[i].key] == true))),
                ],
              ]));
            }
            return _OptionField(f: item as OptField, o: o, set: set);
          }),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SpButton(label: isNew ? 'Create connection' : 'Save changes', icon: 'check', kind: BtnKind.primary, enabled: valid, onTap: () => widget.onSave(collect()))),
        ]),
      ]),
    );
  }

  Widget _field(String label, Widget child, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(label, hint: hint), child]),
      );
}

class _ChipSelect extends StatelessWidget {
  final String value;
  final List<String> options;
  final Map<String, String>? labels;
  final ValueChanged<String> onChange;
  final bool mono;
  const _ChipSelect({required this.value, required this.options, required this.onChange, this.labels, this.mono = false});
  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 7, runSpacing: 7, children: options.map((opt) =>
        SpChip(labels?[opt] ?? opt, mono: mono, on: value == opt, onTap: () => onChange(opt))).toList());
  }
}

class _ToggleLine extends StatelessWidget {
  final String label;
  final String? sub;
  final bool on;
  final VoidCallback onToggle;
  final bool pad;
  const _ToggleLine({required this.label, this.sub, required this.on, required this.onToggle, this.pad = false});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Padding(
      padding: EdgeInsets.all(pad ? 12 : 0),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(sub!, style: sans(size: 11.5, color: c.text3))),
        ])),
        SpSwitch(on: on, onToggle: onToggle),
      ]),
    );
  }
}

class _OptionField extends StatefulWidget {
  final OptField f;
  final Map<String, Object?> o;
  final void Function(String, Object?) set;
  const _OptionField({required this.f, required this.o, required this.set});
  @override
  State<_OptionField> createState() => _OptionFieldState();
}

class _OptionFieldState extends State<_OptionField> {
  TextEditingController? _ctrl;
  @override
  void initState() {
    super.initState();
    final f = widget.f;
    if (f.type != 'chips' && f.type != 'file') {
      _ctrl = TextEditingController(text: '${widget.o[f.key] ?? ''}');
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final o = widget.o;
    final set = widget.set;
    if (f.showIf != null && !f.showIf!(o)) return const SizedBox.shrink();
    final v = '${o[f.key] ?? ''}';
    Widget inner;
    if (f.type == 'chips') {
      inner = _ChipSelect(value: v, options: f.options, mono: f.mono, onChange: (x) => set(f.key, x));
    } else if (f.type == 'file') {
      inner = _FilePickerField(value: v, placeholder: f.placeholder ?? 'Choose file', onPick: (x) => set(f.key, x), onClear: () => set(f.key, ''));
    } else {
      inner = SpInput(
        controller: _ctrl,
        obscure: f.type == 'password',
        keyboardType: f.type == 'number' ? TextInputType.number : null,
        hint: f.placeholder,
        onChanged: (x) => set(f.key, x),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(f.label, hint: f.hint), inner]),
    );
  }
}

class _FilePickerField extends StatelessWidget {
  final String value;
  final String placeholder;
  final void Function(String) onPick;
  final VoidCallback onClear;
  const _FilePickerField({required this.value, required this.placeholder, required this.onPick, required this.onClear});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final has = value.isNotEmpty;
    return GestureDetector(
      onTap: has ? null : () async {
        final files = await FilePicker.pickFiles();
        if (files.isNotEmpty) onPick(files.first.name);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(11), border: Border.all(color: c.borderStrong, style: BorderStyle.solid)),
        child: Row(children: [
          SpIcon(has ? 'check' : 'folder', size: 15, color: has ? c.success : c.text3),
          const SizedBox(width: 9),
          Expanded(child: Text(has ? value : placeholder, overflow: TextOverflow.ellipsis, style: mono(size: 12, color: has ? c.text : c.text4))),
          if (has)
            GestureDetector(onTap: onClear, child: SpIcon('x', size: 14, color: c.text3))
          else
            Text('Browse', style: sans(size: 11.5, weight: FontWeight.w600, color: c.accent)),
        ]),
      ),
    );
  }
}

/// Collapsible form section card.
class FormSection extends StatefulWidget {
  final String icon;
  final String title;
  final String? hint;
  final bool defaultOpen;
  final Color? accent;
  final List<Widget> children;
  const FormSection({super.key, required this.icon, required this.title, this.hint, this.defaultOpen = true, this.accent, required this.children});
  @override
  State<FormSection> createState() => _FormSectionState();
}

class _FormSectionState extends State<FormSection> {
  late bool open;
  @override
  void initState() {
    super.initState();
    open = widget.defaultOpen;
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final accent = widget.accent ?? c.accent;
    return SpCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(color: accent.withOpacity(0.13), borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: SpIcon(widget.icon, size: 16, color: accent)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: sans(size: 13.5, weight: FontWeight.w700, color: c.text, spacing: -0.2)),
                if (widget.hint != null) Text(widget.hint!, style: sans(size: 11, color: c.text3)),
              ])),
              Transform.rotate(angle: open ? 3.14159 : 0, child: SpIcon('chevD', size: 17, color: c.text3)),
            ]),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children)),
      ]),
    );
  }
}
