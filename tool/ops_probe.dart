// Exercises EVERY DB operation against every networked engine (real Docker DBs).
// Run: dart run tool/ops_probe.dart  (sqlite excluded — needs path_provider/Flutter)
import 'dart:io';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/data/engines.dart' as en;
import 'package:sql_pulse/engine/sql_engine.dart';
import 'package:sql_pulse/db/db_driver.dart';
import 'package:sql_pulse/db/postgres_driver.dart';
import 'package:sql_pulse/db/mysql_driver.dart';
import 'package:sql_pulse/db/mssql_driver.dart';

Profile prof(String engine, int port, String user, String pass) => Profile(
    id: 0, name: engine, group: 'L', engine: engine, host: '127.0.0.1', port: port,
    user: user, env: 'local', color: 'blue', catalog: 'sqlpulse_demo', ssl: false,
    options: {'password': pass});

int _pass = 0, _fail = 0;
void log(String s) => stderr.writeln(s);

Future<void> op(String label, Future<void> Function() fn) async {
  try {
    await fn().timeout(const Duration(seconds: 15));
    _pass++;
    log('   PASS  $label');
  } catch (e) {
    _fail++;
    log('   FAIL  $label  ->  $e');
  }
}

String qi(String id, String engine) => en.quoteId(id, engine);

Future<void> suite(String label, DbDriver d, Profile p) async {
  log('=== $label ===');
  final e = en.eng(p.engine);
  try {
    await d.connect(p).timeout(const Duration(seconds: 15));
    log('   connected: ${d.serverVersion}');
  } catch (e) {
    log('   CONNECT FAILED: $e');
    _fail++;
    return;
  }
  final cat = await d.introspect(p.catalog);

  await op('builder JOIN', () async {
    final spec = QuerySpec(table: 'orders', columns: [
      QbColumn(table: 'users', col: 'username'),
      QbColumn(table: 'orders', col: 'total_amount'),
    ], joins: [QbJoin(type: 'INNER', leftTable: 'orders', leftCol: 'user_id', table: 'users', rightCol: 'id')], limit: '5');
    final r = await d.execute(SqlEngine.buildSqlFromSpec(spec, cat, p.engine));
    if (r.error) throw r.message!;
    if ((r.rows?.length ?? 0) != 5) throw 'expected 5 rows got ${r.rows?.length}';
  });

  await op('builder GROUP BY/HAVING/ORDER', () async {
    final spec = QuerySpec(table: 'orders', columns: [
      QbColumn(table: 'orders', col: 'status'),
      QbColumn(table: 'orders', col: 'order_id', agg: 'COUNT', alias: 'cnt'),
      QbColumn(table: 'orders', col: 'total_amount', agg: 'SUM', alias: 'revenue'),
    ], groupBy: [QbGroup('orders', 'status')], having: QbHaving(agg: 'COUNT', table: 'orders', col: '*', op: '>', value: '1'), orderBy: [QbOrder('cnt', 'DESC')], limit: '10');
    final r = await d.execute(SqlEngine.buildSqlFromSpec(spec, cat, p.engine));
    if (r.error) throw r.message!;
    if ((r.rows?.length ?? 0) == 0) throw 'no rows';
  });

  await op('builder WHERE/ORDER/LIMIT', () async {
    final spec = QuerySpec(table: 'products', filters: [QbFilter(table: 'products', col: 'stock', op: '<', value: '50')], orderBy: [QbOrder('price', 'ASC')], limit: '8');
    final r = await d.execute(SqlEngine.buildSqlFromSpec(spec, cat, p.engine));
    if (r.error) throw r.message!;
  });

  await op('EXPLAIN', () async {
    final r = await d.explain("SELECT * FROM ${qi('orders', p.engine)} WHERE ${qi('status', p.engine)} = 'Completed'");
    if (r.error) throw r.message!;
    if ((r.rows?.length ?? 0) == 0) throw 'plan returned no rows';
  });

  final t = qi('zz_ops_test', p.engine);
  await op('CREATE TABLE', () async {
    final cols = [
      ColumnDef(name: 'id', type: 'INT', pk: true, ai: true, nullable: false),
      ColumnDef(name: 'name', type: e.id == 'mssql' ? 'NVARCHAR(50)' : 'VARCHAR(50)', nullable: false),
      ColumnDef(name: 'qty', type: 'INT', nullable: true),
    ];
    try {
      await d.execute('DROP TABLE $t');
    } catch (_) {}
    final r = await d.execute(en.createTableSql('zz_ops_test', cols, [], p.engine));
    if (r.error) throw r.message!;
  });

  await op('INSERT', () async {
    final r = await d.execute("INSERT INTO $t (${qi('name', p.engine)}, ${qi('qty', p.engine)}) VALUES ('alpha', 5)");
    if (r.error) throw r.message!;
  });

  await op('SELECT inserted row', () async {
    final r = await d.execute('SELECT ${qi('name', p.engine)}, ${qi('qty', p.engine)} FROM $t');
    if (r.error) throw r.message!;
    if ((r.rows?.length ?? 0) != 1) throw 'expected 1 row got ${r.rows?.length}';
    if ('${r.rows!.first[0]}' != 'alpha') throw 'wrong value ${r.rows!.first[0]}';
  });

  await op('UPDATE', () async {
    final r = await d.execute("UPDATE $t SET ${qi('qty', p.engine)} = 9 WHERE ${qi('name', p.engine)} = 'alpha'");
    if (r.error) throw r.message!;
    final v = await d.execute("SELECT ${qi('qty', p.engine)} FROM $t WHERE ${qi('name', p.engine)} = 'alpha'");
    if ('${v.rows!.first[0]}' != '9') throw 'update not applied: ${v.rows!.first[0]}';
  });

  await op('ALTER ADD COLUMN', () async {
    final addKw = e.id == 'mssql' ? 'ADD' : 'ADD COLUMN';
    final r = await d.execute('ALTER TABLE $t $addKw ${qi('note', p.engine)} ${e.id == 'mssql' ? 'NVARCHAR(20)' : 'VARCHAR(20)'} NULL');
    if (r.error) throw r.message!;
    final c2 = await d.introspect(p.catalog);
    if (!c2.tables['zz_ops_test']!.columns.any((c) => c.name == 'note')) throw 'note column not introspected';
  });

  await op('DELETE', () async {
    final r = await d.execute("DELETE FROM $t WHERE ${qi('name', p.engine)} = 'alpha'");
    if (r.error) throw r.message!;
    final v = await d.execute('SELECT COUNT(*) FROM $t');
    if ('${v.rows!.first[0]}' != '0') throw 'rows remain: ${v.rows!.first[0]}';
  });

  await op('DROP TABLE', () async {
    final r = await d.execute('DROP TABLE $t');
    if (r.error) throw r.message!;
  });

  await d.close();
}

Future<void> main() async {
  await suite('PostgreSQL', PostgresDriver(), prof('postgres', 5432, 'postgres', 'pass'));
  await suite('MySQL', MySqlDriver(), prof('mysql', 3306, 'root', 'pass'));
  await suite('MariaDB', MySqlDriver(maria: true), prof('mariadb', 3309, 'root', 'pass'));
  await suite('SQL Server', MssqlDriver(), prof('mssql', 1433, 'sa', 'Str0ng!Passw0rd'));
  log('==== $_pass passed, $_fail failed ====');

}
