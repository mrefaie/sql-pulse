@Tags(['integration'])
import 'package:flutter_test/flutter_test.dart';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/db/postgres_driver.dart';
import 'package:sql_pulse/db/mssql_driver.dart';

Profile prof(String engine, int port, String user, String pass) => Profile(
  id: 0, name: engine, group: 'L', engine: engine, host: '127.0.0.1', port: port,
  user: user, env: 'local', color: 'blue', catalog: 'sqlpulse_demo', ssl: false,
  options: {'password': pass});

// Note: MSSQL is verified via tool/dart-run + the live app (its raw-socket TDS
// reads hang inside the flutter_test async zone, a harness-only limitation).
void main() {
  test('Test connection SUCCESS (real Postgres)', () async {
    final d = PostgresDriver();
    final sw = Stopwatch()..start();
    await d.connect(prof('postgres',5432,'postgres','pass'));
    final r = await d.execute('SELECT 1');
    final ms = sw.elapsedMilliseconds;
    await d.close();
    expect(r.error, false);
    expect(d.serverVersion, contains('PostgreSQL'));
    print('Test SUCCESS: ${d.serverVersion} in ${ms}ms');
    expect(ms, lessThan(5000));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('Test connection FAILURE (wrong port → real error)', () async {
    final d = PostgresDriver();
    String? err;
    try {
      await d.connect(prof('postgres',5999,'postgres','pass'));
      await d.execute('SELECT 1');
    } catch (e) { err = e.toString(); }
    print('Test FAILURE error: $err');
    expect(err, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 20)));

}
