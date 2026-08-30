// SQL Pulse — unit/widget smoke tests (no live DB; see driver_integration_test for real DBs).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sql_pulse/data/store.dart';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/data/seed_data.dart';
import 'package:sql_pulse/engine/sql_engine.dart';
import 'package:sql_pulse/state/app_state.dart';
import 'package:sql_pulse/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('default profiles target the local Docker engines', () {
    final p = defaultProfiles();
    expect(p.map((x) => x.engine).toSet(), containsAll(['postgres', 'mysql', 'mariadb', 'mssql', 'sqlite']));
    final pg = p.firstWhere((x) => x.engine == 'postgres');
    expect(pg.host, '127.0.0.1');
    expect(pg.catalog, 'sqlpulse_demo');
  });

  test('builder generates dialect-aware SQL (TOP/brackets for MSSQL)', () {
    final cat = buildCatalogs()['e_commerce']!;
    final spec = QuerySpec(table: 'users', limit: '10', offset: '0');
    final mssql = SqlEngine.buildSqlFromSpec(spec, cat, 'mssql');
    expect(mssql, contains('TOP 10'));
    expect(mssql, contains('[users]'));
    final pg = SqlEngine.buildSqlFromSpec(spec, cat, 'postgres');
    expect(pg, contains('LIMIT 10'));
    expect(pg, contains('"users"'));
  });

  test('builder executes joins + aggregates + having', () {
    final cat = buildCatalogs()['e_commerce']!;
    final spec = QuerySpec(table: 'users', columns: [
      QbColumn(table: 'users', col: 'role'),
      QbColumn(table: 'users', col: 'id', agg: 'COUNT', alias: 'cnt'),
    ], groupBy: [QbGroup('users', 'role')]);
    final res = SqlEngine.runBuilder({'e_commerce': cat}, 'e_commerce', spec, 'Admin');
    expect(res.headers, containsAll(['role', 'cnt']));
    final total = res.rows!.fold<int>(0, (a, r) => a + (r[1] as int));
    expect(total, cat.tables['users']!.rows.length);
  });

  test('CSV / INSERT export produce correct text', () {
    expect(Store.toCsv(['a', 'b'], [
      [1, 'x'],
      [2, 'y, z'],
    ]), 'a,b\n1,x\n2,"y, z"');
    expect(Store.toInserts('t', ['id'], [[1]]), 'INSERT INTO t (id) VALUES (1);');
  });

  testWidgets('app renders the connection screen with the Docker connections', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(ChangeNotifierProvider(create: (_) => AppState(), child: const SqlPulseApp()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('SQL Pulse'), findsWidgets);
    expect(find.text('New connection'), findsOneWidget);
    expect(find.textContaining('Postgres'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
