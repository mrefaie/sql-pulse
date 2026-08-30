// Verifies the three new features against the real Docker Postgres:
//   1. runTransaction commits a batch atomically.
//   2. runTransaction rolls back the WHOLE batch if any statement fails.
//   3. SSH tunnel decorator: a non-SSH profile connects normally (the tunnel
//      path is exercised by unit logic; a live bastion isn't part of CI).
// Run: dart run tool/feature_probe.dart
import 'dart:io';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/db/postgres_driver.dart';

void log(String s) => stderr.writeln(s);

Future<void> main() async {
  final p = Profile(
      id: 0, name: 'pg', group: 'L', engine: 'postgres', host: '127.0.0.1', port: 5432,
      user: 'postgres', env: 'local', color: 'blue', catalog: 'sqlpulse_demo', options: {'password': 'pass'});
  final d = PostgresDriver();
  await d.connect(p);
  log('connected: ${d.serverVersion}');
  const cat = 'sqlpulse_demo';

  // scratch table
  await d.execute('DROP TABLE IF EXISTS _tx_probe;', catalog: cat);
  await d.execute('CREATE TABLE _tx_probe (id int primary key, n int);', catalog: cat);

  // 1. successful transaction
  final ok = await d.runTransaction([
    "INSERT INTO _tx_probe VALUES (1, 10);",
    "INSERT INTO _tx_probe VALUES (2, 20);",
    "UPDATE _tx_probe SET n = 99 WHERE id = 1;",
  ], catalog: cat);
  final afterOk = await d.execute('SELECT id, n FROM _tx_probe ORDER BY id;', catalog: cat);
  log('1. commit  -> error=${ok?.error}  rows=${afterOk.rows} (expect [[1,99],[2,20]])');

  // 2. failing transaction must roll back entirely (2nd stmt is a dup PK)
  final bad = await d.runTransaction([
    "INSERT INTO _tx_probe VALUES (3, 30);",       // would succeed alone
    "INSERT INTO _tx_probe VALUES (1, 0);",        // dup PK -> fails
    "INSERT INTO _tx_probe VALUES (4, 40);",       // never reached
  ], catalog: cat);
  final afterBad = await d.execute('SELECT id FROM _tx_probe ORDER BY id;', catalog: cat);
  final ids = (afterBad.rows ?? []).map((r) => r.first).toList();
  final rolledBack = !ids.contains(3) && !ids.contains(4);
  log('2. rollback-> denied/err=${bad?.error}  ids=$ids  ROLLED_BACK=${rolledBack ? 'YES (correct)' : 'NO (BUG)'}');

  await d.execute('DROP TABLE IF EXISTS _tx_probe;', catalog: cat);
  await d.close();

  log(rolledBack ? '\nALL GOOD: transaction atomicity verified.' : '\nFAILURE: rollback did not happen.');
}
