@Tags(['integration'])
import 'package:flutter_test/flutter_test.dart';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/db/db_driver.dart';
import 'package:sql_pulse/db/postgres_driver.dart';
import 'package:sql_pulse/db/mysql_driver.dart';
import 'package:sql_pulse/db/mssql_driver.dart';

Profile prof(String engine, int port, String user, String pass) => Profile(
  id: 0, name: engine, group: 'L', engine: engine, host: '127.0.0.1', port: port,
  user: user, env: 'local', color: 'blue', catalog: 'sqlpulse_demo', ssl: false,
  options: {'password': pass});

Future<void> exercise(String label, DbDriver d, Profile p) async {
  await d.connect(p);
  print('[$label] $label connected: ${d.serverVersion}');
  final cat = await d.introspect(p.catalog);
  print('[$label] tables=${cat.tables.keys.toList()}');
  final u = cat.tables['users']!;
  print('[$label] users cols: ${u.columns.map((c)=>"${c.name}:${c.type}${c.pk?" PK":""}${c.ai?" AI":""}${c.fkTable!=null?" FK>${c.fkTable}":""}").join(", ")}');
  print('[$label] users est=${u.rowEstimate}, relations=${cat.relations.length}, views=${cat.views.length}, procs=${cat.procedures.length}, trigs=${cat.triggers.length}');
  final q = await d.execute('SELECT * FROM users');
  print('[$label] SELECT users -> ${q.rows?.length} rows; first=${q.rows?.first}');
  final agg = await d.execute('SELECT role, COUNT(*) AS cnt FROM users GROUP BY role');
  print('[$label] GROUP BY role -> ${agg.rows}');
  final ord = await d.preview(p.catalog, 'orders', 2);
  print('[$label] preview orders: ${ord}');
  final bad = await d.execute('SELECT * FROM no_such_table_xyz');
  print('[$label] error: ${bad.error} -> ${bad.message}');
  await d.close();
  expect(cat.tables.length, greaterThanOrEqualTo(9));
  expect(cat.views.length, greaterThanOrEqualTo(3));
  expect(cat.procedures.length + cat.functions.length, greaterThanOrEqualTo(2));
  expect(cat.triggers.length, greaterThanOrEqualTo(2));
  expect(q.rows!.length, 200);
}

void main() {
  test('Postgres', () async => exercise('PG', PostgresDriver(), prof('postgres',5432,'postgres','pass')), timeout: const Timeout(Duration(seconds: 30)));
  test('MySQL', () async => exercise('MY', MySqlDriver(), prof('mysql',3306,'root','pass')), timeout: const Timeout(Duration(seconds: 30)));
  test('MariaDB', () async => exercise('MARIA', MySqlDriver(maria:true), prof('mariadb',3309,'root','pass')), timeout: const Timeout(Duration(seconds: 30)));
  // MSSQL verified via the live app / dart run (flutter_test async-zone hangs on raw-socket TDS).
}

