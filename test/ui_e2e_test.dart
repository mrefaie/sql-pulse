// SQL Pulse — end-to-end: connect to the REAL Postgres Docker DB and verify the
// workspace renders live schema + rows. Uses runAsync for real network I/O.
@Tags(['integration'])
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sql_pulse/data/store.dart';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/state/app_state.dart';
import 'package:sql_pulse/main.dart';

void main() {
  testWidgets('connect to real Postgres and browse live data', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const SqlPulseApp()));
    await tester.pump();

    // connect to the real Postgres docker DB
    final pg = state.profiles.firstWhere((p) => p.engine == 'postgres');
    await tester.runAsync(() => state.connect(pg, 'Admin'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // workspace shows the live catalog + real introspected tables
    expect(state.screen, 'workspace');
    expect(state.catalog, 'sqlpulse_demo');
    expect(find.text('sqlpulse_demo'), findsWidgets);
    expect(find.text('users'), findsWidgets);
    expect(find.text('orders'), findsWidgets);
    // rich schema introspected: FK relations, views, routines, triggers
    expect(state.currentCatalog!.relations.isNotEmpty, true);
    expect(state.currentCatalog!.tables.length, greaterThanOrEqualTo(9));
    expect(state.currentCatalog!.views.length, greaterThanOrEqualTo(3));
    expect(state.currentCatalog!.procedures.length + state.currentCatalog!.functions.length, greaterThanOrEqualTo(2));
    expect(state.currentCatalog!.triggers.length, greaterThanOrEqualTo(2));

    // run a real query through the visual builder (buildSql → execute)
    await tester.runAsync(() => state.runBuilder(
          QuerySpec(table: 'orders', columns: [
            QbColumn(table: 'orders', col: 'status'),
            QbColumn(table: 'orders', col: 'order_id', agg: 'COUNT', alias: 'cnt'),
          ], groupBy: [QbGroup('orders', 'status')]),
          'SELECT "status", COUNT("order_id") AS "cnt" FROM "orders" GROUP BY "status"'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(state.result!.error, false);
    expect(state.result!.headers, contains('cnt'));

    // open a table → loads a real preview of rows from the server
    await tester.runAsync(() => state.openTable('users'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    final rows = state.currentCatalog!.tables['users']!.rows;
    expect(rows.isNotEmpty, true);
    expect('${rows.first['username']}', startsWith('user')); // real seeded value
    expect(rows.first.containsKey('email'), true);

    // run a real query
    await tester.runAsync(() => state.run('SELECT role, COUNT(*) AS cnt FROM users GROUP BY role'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(state.result!.error, false);
    expect(state.result!.headers, contains('cnt'));
    expect(state.result!.rows!.isNotEmpty, true);

    await tester.runAsync(() => state.driver!.close());
  }, timeout: const Timeout(Duration(seconds: 40)));
}
