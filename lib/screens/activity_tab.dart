// SQL Pulse — Activity / audit log with filters + re-run.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';
import '../widgets/highlight.dart';

const _filters = ['All', 'SELECT', 'DML', 'DDL', 'DENIED'];

bool _runnable(String q) {
  if (q.isEmpty || q.contains('…') || q.startsWith('CONNECT') || q.startsWith('SYNC')) return false;
  return RegExp(r'^(select|show|describe|desc|explain|insert|update|delete|create|alter|drop|exec)', caseSensitive: false).hasMatch(q.trim());
}

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key});
  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final state = context.watch<AppState>();
    final logs = state.audit.where((l) => filter == 'All' || l.status == filter).toList();

    Color statusColor(String s) => {
          'SELECT': c.info, 'DML': c.success, 'DDL': c.accent, 'DENIED': c.warning,
          'SYNTAX': c.danger, 'EXPLAIN': c.synFn, 'CONNECT': c.text2, 'OK': c.text2,
        }[s] ?? c.text2;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Activity'),
            const SizedBox(height: 4),
            Text('${state.audit.length} audited statements', style: sans(size: 12.5, color: c.text3)),
          ])),
          SpButton(label: 'Clear', icon: 'trash', kind: BtnKind.ghost, sm: true, onTap: state.clearAudit),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: _filters.map((f) => Padding(padding: const EdgeInsets.only(right: 8), child: SpChip(f, on: filter == f, onTap: () => setState(() => filter = f)))).toList())),
        const SizedBox(height: 14),
        if (logs.isEmpty)
          const Empty(icon: 'history', title: 'Nothing here', sub: 'No statements match this filter.')
        else
          ...logs.map((l) {
            final col = statusColor(l.status);
            return Padding(padding: const EdgeInsets.only(bottom: 9), child: SpCard(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                SpBadge(l.status, fg: col, bg: col.withOpacity(0.13)),
                if (l.table.isNotEmpty) ...[const SizedBox(width: 8), Text(l.table, style: mono(size: 11, color: c.text3))],
                const Spacer(),
                Text(timeAgo(l.at), style: mono(size: 10.5, color: c.text4)),
              ]),
              const SizedBox(height: 9),
              CodeBlock(l.query, fontSize: 11.5, padding: const EdgeInsets.all(10)),
              const SizedBox(height: 9),
              Row(children: [
                RoleGlyph(l.role, size: 13, color: c.text3),
                const SizedBox(width: 5),
                Text(l.role, style: sans(size: 11, color: c.text3)),
                const SizedBox(width: 12),
                Text('${l.ms} ms', style: mono(size: 11, color: c.text3)),
                if (l.rows > 0) ...[const SizedBox(width: 12), Text('${l.rows} rows', style: mono(size: 11, color: c.text3))],
                const Spacer(),
                if (_runnable(l.query))
                  SpChip('Re-run', icon: 'rerun', padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), onTap: () => state.loadIntoConsole(l.query)),
              ]),
            ])));
          }),
      ],
    );
  }
}
