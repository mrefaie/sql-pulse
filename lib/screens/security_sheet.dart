// SQL Pulse — Security sheet (on-device app lock).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/biometric.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/primitives.dart';
import '../widgets/overlays.dart';

void showSecuritySheet(BuildContext context) {
  showSpSheet(context, (ctx) => const _SecuritySheet());
}

class _SecuritySheet extends StatefulWidget {
  const _SecuritySheet();
  @override
  State<_SecuritySheet> createState() => _SecuritySheetState();
}

class _SecuritySheetState extends State<_SecuritySheet> {
  late bool enabled;
  late String method;
  late String pin;
  String pinErr = '';
  String bioMsg = '';
  bool bioOk = false;
  bool verifying = false;

  @override
  void initState() {
    super.initState();
    final lock = context.read<AppState>().lock;
    enabled = lock.enabled;
    method = lock.method;
    pin = lock.pin;
  }

  // Exercise the real device biometric so the user confirms it works at setup
  // time — and, on web, registers the WebAuthn platform credential up front
  // (instead of lazily on the first unlock).
  Future<void> _verifyBiometric() async {
    if (verifying) return;
    setState(() {
      verifying = true;
      bioMsg = '';
    });
    final label = method == 'face' ? 'Face Unlock' : 'Fingerprint';
    bool available = false;
    bool passed = false;
    try {
      available = await biometricAvailable();
      if (available) passed = await biometricAuthenticate('Set up $label for SQL Pulse');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      verifying = false;
      bioOk = passed;
      bioMsg = !available
          ? 'No biometric hardware detected on this device — set a fallback PIN below.'
          : passed
              ? '$label verified — you\'re all set.'
              : 'Could not verify $label. Try again, or use a PIN.';
    });
  }

  Future<void> _save() async {
    final needsPin = method == 'pin';
    if (enabled && needsPin && !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => pinErr = 'PIN must be 4–6 digits');
      return;
    }
    // For a biometric method, confirm the hardware works (and enroll the web
    // credential) before saving, unless the user already verified above or has
    // a valid fallback PIN to fall back on.
    if (enabled && !needsPin && !bioOk && !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      await _verifyBiometric();
      if (!mounted) return;
      if (!bioOk && !RegExp(r'^\d{4,6}$').hasMatch(pin)) return; // block: no biometric, no PIN
    }
    context.read<AppState>().setLock(LockConfig(enabled: enabled, method: method, pin: needsPin ? pin : pin));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final needsPin = method == 'pin';
    final valid = !enabled || !needsPin || RegExp(r'^\d{4,6}$').hasMatch(pin);
    return SpSheet(
      title: 'Security',
      right: Text(enabled ? 'ON' : 'OFF', style: mono(size: 10, weight: FontWeight.w600, color: enabled ? c.success : c.text3)),
      onClose: () => Navigator.pop(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpCard(
          color: c.surface2,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SpIcon('lock', size: 18, color: enabled ? c.accent : c.text3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('App lock', style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
                Text('Require authentication on launch', style: sans(size: 11.5, color: c.text3)),
              ]),
            ),
            SpSwitch(on: enabled, onToggle: () => setState(() => enabled = !enabled)),
          ]),
        ),
        if (enabled) ...[
          const SizedBox(height: 16),
          const FieldLabel('Unlock method'),
          ...[
            ['fingerprint', 'fingerprint', 'Fingerprint', 'Touch the sensor to unlock'],
            ['face', 'faceid', 'Face Unlock', 'Glance to unlock'],
            ['pin', 'lock', 'PIN code', '4–6 digit passcode'],
          ].map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SpRow(
                  selected: method == m[0],
                  padding: const EdgeInsets.all(11),
                  onTap: () => setState(() {
                    method = m[0];
                    bioOk = false;
                    bioMsg = '';
                  }),
                  child: Row(children: [
                    RowIco(m[1]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m[2], style: sans(size: 13.5, weight: FontWeight.w600, color: c.text)),
                        Text(m[3], style: sans(size: 11.5, color: c.text3)),
                      ]),
                    ),
                    if (method == m[0]) SpIcon('check', size: 18, color: c.accent),
                  ]),
                ),
              )),
          if (!needsPin) ...[
            const SizedBox(height: 4),
            SpButton(
              label: verifying ? 'Verifying…' : bioOk ? 'Verified' : 'Test ${method == 'face' ? 'Face Unlock' : 'Fingerprint'}',
              icon: bioOk ? 'check' : (method == 'face' ? 'faceid' : 'fingerprint'),
              kind: bioOk ? BtnKind.ghost : BtnKind.normal,
              block: true,
              enabled: !verifying,
              onTap: _verifyBiometric,
            ),
            if (bioMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(bioMsg, style: sans(size: 11.5, color: bioOk ? c.success : c.text3, height: 1.4)),
              ),
            const SizedBox(height: 8),
          ],
          FieldLabel(needsPin ? 'Set PIN' : 'Fallback PIN', hint: needsPin ? '4–6 digits' : 'optional backup'),
          SpInput(
            hint: '••••',
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() {
              pin = v.replaceAll(RegExp(r'\D'), '');
              pinErr = '';
            }),
          ),
          if (pinErr.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(pinErr, style: sans(size: 11.5, color: c.danger))),
          const SizedBox(height: 16),
          SpCard(
            color: c.infoSoft,
            borderColor: Colors.transparent,
            padding: const EdgeInsets.all(11),
            child: Row(children: [
              SpIcon('shield', size: 15, color: c.info),
              const SizedBox(width: 9),
              Expanded(child: Text('Authentication runs entirely on-device. Credentials never leave this phone.', style: sans(size: 11.5, color: c.info))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SpButton(label: 'Cancel', kind: BtnKind.ghost, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SpButton(label: 'Save', icon: 'check', kind: BtnKind.primary, enabled: valid, onTap: _save)),
        ]),
      ]),
    );
  }
}
