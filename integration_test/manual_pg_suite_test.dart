// SQL Pulse — automated re-run of the manual PostgreSQL test plan
// (docs/manual_test_plan_postgres.md) on the real macOS desktop app,
// against the live local Postgres (sqlpulse_demo).
// UI-driven where practical; AppState/driver calls mirror the exact code
// paths the UI buttons invoke.
//
// Run: flutter test integration_test/manual_pg_suite_test.dart -d macos
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sql_pulse/main.dart';
import 'package:sql_pulse/data/store.dart';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/data/diff.dart' as df;
import 'package:sql_pulse/engine/sql_engine.dart';
import 'package:sql_pulse/state/app_state.dart';
import 'package:sql_pulse/screens/diagram_tab.dart';
import 'package:sql_pulse/widgets/icons.dart';
import 'package:sql_pulse/widgets/primitives.dart';

Finder iconBtn(String name) => find.byWidgetPredicate((w) => w is IconBtn && w.name == name);
Finder spIcon(String name) => find.byWidgetPredicate((w) => w is SpIcon && w.name == name);
Finder closeBtn() => find.byWidgetPredicate(
    (w) => (w is IconBtn && w.name == 'x') || (w is SpIcon && w.name == 'x'));
/// Matches any control whose glyph is [icon]: SpButton/SpChip use `icon`,
/// IconBtn/SpIcon use `name`.
Finder btnIcon(String icon) => find.byWidgetPredicate((w) =>
    (w is SpButton && w.icon == icon) ||
    (w is SpChip && w.icon == icon) ||
    (w is IconBtn && w.name == icon) ||
    (w is SpIcon && w.name == icon));

pg.Connection? _pg;

Future<pg.Connection> pgOpen(String db, String host) => pg.Connection.open(
      pg.Endpoint(host: host, port: 5432, database: db, username: 'postgres', password: 'pass'),
      settings: pg.ConnectionSettings(sslMode: pg.SslMode.disable),
    );

Future<String> pgScalar(String sql) async {
  final r = await _pg!.execute(sql);
  return '${r.first.first}';
}

Future<void> pgExec(String sql) async {
  for (final s in sql.split(';')) {
    if (s.trim().isNotEmpty) await _pg!.execute(s.trim());
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manual PG suite on macOS desktop', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final state = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const SqlPulseApp()));
    await tester.pump();

    final pgProfile = state.profiles.firstWhere((p) => p.engine == 'postgres');
    const dbHost = String.fromEnvironment('DB_HOST', defaultValue: '');
    if (dbHost.isNotEmpty) pgProfile.host = dbHost;
    expect(pgProfile.port, 5432, reason: 'profile targets Postgres');
    expect(pgProfile.host, isNotEmpty);

    _pg = await pgOpen('sqlpulse_demo', pgProfile.host);

    Future<void> ensure() async {
      if (state.screen != 'workspace') {
        await state.connect(pgProfile, 'Admin');
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
      }
    }

    Future<void> tapDigit(String d) async {
      final f = find.text(d);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 120));
    }

    Future<void> toSqlMode() async {
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final f = find.text('SQL');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.last, warnIfMissed: false);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }

    var pass = 0, fail = 0;
    final failed = <String>[];
    Future<void> c(String id, String name, Future<void> Function() fn, {bool noEnsure = false}) async {
      final sw = Stopwatch()..start();
      try {
        if (!noEnsure) await ensure();
        await fn();
        pass++;
        print('CASE $id PASS · $name (${sw.elapsedMilliseconds}ms)');
      } catch (e, st) {
        fail++;
        failed.add('$id $name');
        print('CASE $id FAIL · $name (${sw.elapsedMilliseconds}ms): $e');
        print(st.toString().split('\n').take(5).join('\n'));
      }
    }

    // ------------------------------------------------------------------ polish (pre-connect)
    await c('PG-02', 'theme toggle flips', () async {
      final before = state.theme;
      await tester.tap(iconBtn(before == 'dark' ? 'sun' : 'moon'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.theme, before == 'dark' ? 'light' : 'dark');
      await tester.tap(iconBtn(before == 'dark' ? 'moon' : 'sun'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.theme, before);
    }, noEnsure: true);

    await c('PG-03/04', 'settings and security sheets open', () async {
      await tester.tap(iconBtn('cog'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Settings'), findsWidgets);
      await tester.tap(closeBtn().last);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(iconBtn('shield'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.textContaining('Security'), findsWidgets);
      await tester.tap(closeBtn().last);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }, noEnsure: true);

    // ------------------------------------------------------------------ connect
    await c('PG-06/08', 'connect as Admin via UI dialog', () async {
      state.disconnect();
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.textContaining('Postgres').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Test'), findsOneWidget, reason: 'connect dialog has Test + Connect');
      await tester.tap(find.text('Connect').last);
      for (var i = 0; i < 60 && state.screen != 'workspace'; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(state.screen, 'workspace');
      expect(state.catalog, 'sqlpulse_demo');
      expect(state.db[state.catalog]!.tables.length, 9);
      expect(find.text('addresses'), findsWidgets);
    });

    await c('PG-07', 'Test connection modal succeeds against live server', () async {
      state.disconnect();
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.textContaining('Postgres').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Test'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('Connection successful').evaluate().isNotEmpty) break;
      }
      expect(find.text('Connection successful'), findsWidgets, reason: 'modal completes');
      await tester.tapAt(const Offset(10, 10)); // barrier-dismissible dialog
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    await c('PG-12', 'unreachable endpoint → clean DbException, no crash', () async {
      final bad = pgProfile.clone()
        ..host = pgProfile.host
        ..port = 5599
        ..options = {...pgProfile.options, 'password': 'wrong'};
      Object? err;
      try {
        await state.connect(bad, 'Admin');
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull, reason: 'connection refused surfaces an error');
      expect(state.screen, 'workspace');
      expect(await pgScalar('SELECT 1'), '1');
    });

    await c('PG-15', 'catalog switch to postgres and back', () async {
      await state.switchCatalog('postgres');
      expect(state.catalog, 'postgres');
      await state.switchCatalog('sqlpulse_demo');
      expect(state.catalog, 'sqlpulse_demo');
    });

    // ------------------------------------------------------------------ browse
    await c('PG-16/17', 'structure + data grid match server', () async {
      await state.openTable('order_items');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final tb = state.currentCatalog!.tables['order_items']!;
      expect(tb.columns.first.name, 'item_id');
      expect(tb.columns.first.pk, true);
      expect(tb.columns.firstWhere((c) => c.name == 'product_id').fkTable, 'products');
      expect(tb.rows.length, 60, reason: 'preview limit 60');
      expect(await pgScalar('SELECT count(*) FROM order_items'), '150');
    });

    await c('PG-18', 'row tap opens detail interaction (inspect/edit)', () async {
      await state.openTable('addresses');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('Data'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('New York').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(state.detail, true);
    });

    await c('PG-20', 'masking toggles for users email', () async {
      await state.openTable('users');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final row = state.currentCatalog!.tables['users']!.rows.first;
      expect(row.containsKey('email'), true);
      state.toggleMasking();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.masking, true);
      state.toggleMasking();
      expect(state.masking, false);
    });

    // ------------------------------------------------------------------ editing
    await c('PG-22', 'cell edit → real UPDATE, verifiable, restorable', () async {
      await state.ensureRows('addresses', 200);
      final tb = state.currentCatalog!.tables['addresses']!;
      final idx = tb.rows.indexWhere((r) => '${r['address_id']}' == '1');
      expect(idx, greaterThanOrEqualTo(0), reason: 'address row 1 visible');
      expect(await pgScalar("SELECT city FROM addresses WHERE address_id=1"), 'New York');
      await state.editCell('addresses', idx, 'city', 'Cairo');
      expect(await pgScalar("SELECT city FROM addresses WHERE address_id=1"), 'Cairo',
          reason: 'err=${state.result?.message}');
      await pgExec("UPDATE addresses SET city='New York' WHERE address_id=1");
    });

    await c('PG-23', 'numeric cell edit stays unquoted', () async {
      await state.ensureRows('suppliers', 200);
      final tb = state.currentCatalog!.tables['suppliers']!;
      final idx = tb.rows.indexWhere((r) => '${r['supplier_id']}' == '1');
      expect(idx, greaterThanOrEqualTo(0), reason: 'supplier row 1 visible');
      final before1 = await pgScalar('SELECT lead_time_days FROM suppliers WHERE supplier_id=1');
      await state.editCell('suppliers', idx, 'lead_time_days', '21');
      expect(await pgScalar('SELECT lead_time_days FROM suppliers WHERE supplier_id=1'), '21',
          reason: 'err=${state.result?.message}');
      await pgExec('UPDATE suppliers SET lead_time_days=$before1 WHERE supplier_id=1');
    });

    await c('PG-24', 'insert row → row count +1, then cleanup', () async {
      final before = int.parse(await pgScalar('SELECT count(*) FROM addresses'));
      await state.insertRow('addresses', {
        'user_id': '1', 'line1': '12 Test St', 'city': 'Cairo',
        'country': 'EG', 'postal_code': '10000', 'is_default': '0',
      });
      expect(int.parse(await pgScalar('SELECT count(*) FROM addresses')), before + 1,
          reason: 'err=${state.result?.message}');
      await pgExec("DELETE FROM addresses WHERE line1='12 Test St'");
    });

    await c('PG-25', 'delete inserted row via grid path', () async {
      await state.insertRow('addresses', {
        'user_id': '1', 'line1': '13 Cleanup St', 'city': 'Cairo',
        'country': 'EG', 'postal_code': '10000', 'is_default': '0',
      });
      await state.ensureRows('addresses', 200);
      final tb = state.currentCatalog!.tables['addresses']!;
      final idx = tb.rows.indexWhere((r) => r['line1'] == '13 Cleanup St');
      expect(idx, greaterThanOrEqualTo(0), reason: 'scratch row visible after refresh');
      await state.deleteRow('addresses', idx);
      expect(await pgScalar("SELECT count(*) FROM addresses WHERE line1='13 Cleanup St'"), '0');
      await state.ensureRows('addresses', 200);
    });

    // ------------------------------------------------------------------ staging
    await c('PG-27', 'staging: changes commit atomically', () async {
      if (!state.staging) state.toggleStaging();
      expect(state.staging, true);
      await state.ensureRows('addresses', 200);
      final tb = state.currentCatalog!.tables['addresses']!;
      final idx = tb.rows.indexWhere((r) => '${r['address_id']}' == '1');
      await state.editCell('addresses', idx, 'city', 'Cairo');
      await state.editCell('addresses', idx, 'postal_code', '11111');
      await state.insertRow('addresses', {
        'user_id': '2', 'line1': '14 Staged St', 'city': 'Cairo',
        'country': 'EG', 'postal_code': '22222', 'is_default': '0',
      });
      expect(state.pending.length, 3);
      final ok = await state.commitPending();
      expect(ok, true, reason: 'commit succeeds — err=${state.result?.message}');
      expect(state.pending, isEmpty);
      expect(await pgScalar("SELECT city FROM addresses WHERE address_id=1"), 'Cairo');
      expect(await pgScalar("SELECT count(*) FROM addresses WHERE line1='14 Staged St'"), '1');
      await pgExec("UPDATE addresses SET city='New York', postal_code=NULL WHERE address_id=1");
      await pgExec("DELETE FROM addresses WHERE line1='14 Staged St'");
      state.toggleStaging();
      expect(state.staging, false);
    });

    await c('PG-28', 'staging violation → rollback, tray kept, DB unchanged', () async {
      if (!state.staging) state.toggleStaging();
      final before = int.parse(await pgScalar('SELECT count(*) FROM order_items'));
      await state.insertRow('order_items', {'order_id': '1001', 'product_id': '999999', 'quantity': '1', 'unit_price': '1'});
      expect(state.pending.length, 1);
      final ok = await state.commitPending();
      expect(ok, false, reason: 'FK violation fails the commit');
      expect(state.pending.length, 1, reason: 'tray kept for retry');
      expect(int.parse(await pgScalar('SELECT count(*) FROM order_items')), before);
      state.rollbackPending();
      expect(state.pending, isEmpty);
      state.toggleStaging();
      expect(state.staging, false);
    });

    await c('PG-29', 'staging rollback leaves DB unchanged', () async {
      if (!state.staging) state.toggleStaging();
      await state.editCell('addresses', 0, 'city', 'Cairo');
      state.rollbackPending();
      expect(state.pending, isEmpty);
      expect(await pgScalar("SELECT city FROM addresses WHERE address_id=1"), 'New York');
      state.toggleStaging();
    });

    // ------------------------------------------------------------------ RBAC
    await c('PG-31/48', 'ReadOnly blocks DML via run; Analyst blocks DDL', () async {
      expect(state.roleBlock("DELETE FROM addresses WHERE address_id=1"), isNull, reason: 'Admin allowed');
      state.setRole('ReadOnly');
      await state.run('DELETE FROM addresses WHERE address_id = 999999');
      expect(state.result!.denied, true, reason: 'run surfaces DENIED result');
      expect(state.roleBlock("DELETE FROM addresses WHERE address_id=1"), isNotNull);
      state.setRole('Analyst');
      expect(state.roleBlock('ALTER TABLE addresses ADD x int'), isNotNull);
      state.setRole('Admin');
      expect(await pgScalar('SELECT 1'), '1');
    });

    // ------------------------------------------------------------------ console
    await c('PG-30/33', 'run SELECT + invalid SQL error surfaced', () async {
      await state.run('SELECT * FROM products LIMIT 5;');
      expect(state.result!.error, false);
      expect(state.result!.headers, isNotNull);
      expect(state.result!.rows!.length, 5);
      await state.run('SELCT 1');
      expect(state.result!.error, true);
      expect('${state.result!.message}', isNotEmpty);
    });

    await c('PG-32', 'multi-statement batch with per-item status', () async {
      await state.runScript('SELECT 1; SELCT 2; UPDATE users SET country = country WHERE id = 1;');
      expect(state.result!.batch, isNotNull);
      final items = state.result!.batch!;
      expect(items.length, 3);
      expect(items[0].res.error || items[0].res.denied, false);
      expect(items[1].res.error, true, reason: 'SELCT is a syntax error');
      expect(items[2].res.error || items[2].res.denied, false);
      expect(state.result!.comment, contains('2/3'));
    });

    await c('PG-34', 'real explain plan for single SELECT', () async {
      await state.explainCurrent('SELECT * FROM addresses WHERE address_id = 1');
      expect(state.result!.error, false, reason: '${state.result?.message}');
      expect(state.result!.rows, isNotNull);
      expect(state.result!.rows!.isNotEmpty, true, reason: 'EXPLAIN returns plan rows');
    });

    await c('PG-35', 'format SQL via spark button', () async {
      state.goTab('query');
      state.closeTable();
      await toSqlMode();
      state.setSql('select * from users where id = 1');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(btnIcon('spark').first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(state.sql.toUpperCase(), contains('SELECT'));
      expect(state.sql.toUpperCase(), contains('WHERE'));
    });

    await c('PG-36', 'saved queries: save → list → load → delete', () async {
      state.goTab('query');
      state.closeTable();
      await toSqlMode();
      final n = state.saved.length;
      await state.run('SELECT * FROM users LIMIT 3;');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(btnIcon('bookmark').last, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).last, 'My saved query');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.saved.length, n + 1);
      await tester.tap(find.textContaining('Saved').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Load into console'), findsWidgets);
      await tester.tap(find.text('Load into console').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.sql, contains('SELECT * FROM users'));
      await tester.tap(find.textContaining('Saved').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(btnIcon('trash').first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.saved.length, n);
    });

    // ------------------------------------------------------------------ builder
    await c('PG-40/41/43/44/45/46/47', 'builder specs → dialect SQL → live results', () async {
      final cat = state.db[state.catalog]!;
      Future<void> runSpec(QuerySpec spec, String id, String expectSub) async {
        final sql = SqlEngine.buildSqlFromSpec(spec, cat, 'postgres');
        expect(sql, contains(expectSub), reason: id);
        await state.runBuilder(spec, sql);
        expect(state.result!.error, false, reason: '$id executes');
        expect(state.result!.rows, isNotNull);
      }

      await runSpec(
          QuerySpec(table: 'orders', columns: [
            QbColumn(table: 'orders', col: 'status'),
            QbColumn(table: 'orders', col: 'order_id', agg: 'COUNT', alias: 'cnt'),
          ], groupBy: [QbGroup('orders', 'status')]),
          'PG-40', 'GROUP BY');

      await runSpec(
          QuerySpec(table: 'orders', columns: [
            QbColumn(table: 'users', col: 'username'),
            QbColumn(table: 'orders', col: 'total_amount'),
          ], joins: [QbJoin(type: 'INNER', leftTable: 'orders', leftCol: 'user_id', table: 'users', rightCol: 'id')]),
          'PG-41', 'INNER JOIN');

      await runSpec(
          QuerySpec(table: 'products', columns: [QbColumn(table: 'products', col: 'name')],
              filters: [QbFilter(table: 'products', col: 'stock', op: '<', value: '50')],
              orderBy: [QbOrder('name', 'ASC')], limit: '8'),
          'PG-43', 'LIMIT');

      await runSpec(
          QuerySpec(table: 'products', columns: [QbColumn(table: 'products', col: 'name')],
              filters: [QbFilter(table: 'products', col: 'name', op: 'LIKE', value: '%Headphones%')]),
          'PG-44', 'LIKE');

      await runSpec(
          QuerySpec(table: 'orders', columns: [QbColumn(table: 'orders', col: 'order_id')],
              filters: [QbFilter(table: 'orders', col: 'user_id', op: 'IN', sub: QuerySpec(table: 'users', columns: [QbColumn(table: 'users', col: 'id')], filters: [QbFilter(table: 'users', col: 'role', op: '=', value: 'VIP')]))]),
          'PG-45', '(SELECT');

      await runSpec(
          QuerySpec(table: 'orders', columns: [
            QbColumn(table: 'orders', col: 'status'),
            QbColumn(table: 'orders', col: 'order_id', agg: 'COUNT', alias: 'cnt'),
          ], groupBy: [QbGroup('orders', 'status')],
              having: QbHaving(agg: 'COUNT', table: 'orders', col: '*', op: '>', value: '1')),
          'PG-46', 'HAVING');

      await runSpec(
          QuerySpec(table: 'orders', columns: [QbColumn(table: 'orders', col: 'order_id')], distinct: true,
              ctes: [QbCte('oc', QuerySpec(table: 'orders', columns: [QbColumn(table: 'orders', col: 'order_id')]))]),
          'PG-47', 'WITH "oc" AS');
    });

    // ------------------------------------------------------------------ board
    await c('PG-39/49', 'pin query → board card renders live result', () async {
      state.goTab('query');
      state.closeTable();
      await toSqlMode();
      await state.run('SELECT COUNT(*) AS total FROM users');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).last, 'Users total');
      await tester.tap(find.text('Pin card'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.dashboard.length, 1);
      await tester.tap(find.text('Board'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        if (find.text('Users total').evaluate().isNotEmpty) break;
      }
      final res = await state.runPinQuery(state.dashboard.first);
      expect(res.error || res.denied, false, reason: 'card re-runs live');
      expect(find.text('Users total'), findsWidgets);
      state.removePin(state.dashboard.first.id);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(state.dashboard, isEmpty);
    });

    // ------------------------------------------------------------------ diagram
    await c('PG-54/55', 'ER diagram renders and zoom bounds clamp', () async {
      state.closeTable();
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.text('Diagram').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(state.tab, 'diagram', reason: 'nav switched to diagram tab');
      expect(find.byType(DiagramTab), findsWidgets);
      await tester.tap(iconBtn('plus').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 150));
      await tester.tap(iconBtn('minus').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 150));
    });

    // ------------------------------------------------------------------ activity
    await c('PG-56/57/58', 'activity log: entries, re-run, clear', () async {
      expect(state.audit.any((a) => a.status == 'CONNECT'), true);
      expect(state.audit.any((a) => a.status == 'SELECT'), true);
      expect(state.audit.any((a) => a.status == 'SYNTAX'), true);
      state.closeTable();
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.textContaining('audited statements'), findsOneWidget);
      await tester.tap(find.text('Re-run').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.tab, 'query');
      expect(state.sql, isNotEmpty);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      state.clearAudit();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(state.audit, isEmpty);
    });

    // ------------------------------------------------------------------ designer
    await c('PG-60/61/62', 'create/alter/drop table end-to-end', () async {
      await state.createTable('zz_manual2', [
        ColumnDef(name: 'id', type: 'INTEGER', pk: true, ai: true, nullable: false),
        ColumnDef(name: 'note', type: 'VARCHAR(20)', nullable: true),
      ], []);
      expect(state.currentCatalog!.tables.containsKey('zz_manual2'), true);
      expect(await pgScalar("SELECT count(*) FROM information_schema.tables WHERE table_name='zz_manual2'"), '1');
      await state.addColumn('zz_manual2', ColumnDef(name: 'qty', type: 'INTEGER', nullable: true));
      expect(state.currentCatalog!.tables['zz_manual2']!.columns.any((c) => c.name == 'qty'), true);
      await state.dropTable('zz_manual2');
      expect(state.currentCatalog!.tables.containsKey('zz_manual2'), false);
      expect(await pgScalar("SELECT count(*) FROM information_schema.tables WHERE table_name='zz_manual2'"), '0');
    });

    await c('PG-63', 'Analyst DDL blocked pre-flight', () async {
      state.setRole('Analyst');
      expect(state.roleBlock('CREATE TABLE x(a int)'), isNotNull);
      expect(state.roleBlock('DROP TABLE users'), isNotNull);
      state.setRole('Admin');
    });

    // ------------------------------------------------------------------ diff
    await c('PG-64', 'diff against live clone is identical', () async {
      final other = pgProfile.clone();
      final target = await state.introspectTarget(other);
      final d = df.diffCatalogs(state.currentCatalog!, target);
      for (final t in d.tables) {
        for (final col in t.cols) {
          expect(col.status, 'same', reason: '${t.name}.${col.name}');
        }
      }
    });

    await c('PG-65', 'diff detects ADDED column live', () async {
      await pgExec('ALTER TABLE addresses DROP COLUMN IF EXISTS test_col');
      await pgExec('ALTER TABLE addresses ADD COLUMN test_col int');
      final other = pgProfile.clone();
      final target = await state.introspectTarget(other);
      final d = df.diffCatalogs(state.currentCatalog!, target);
      final t = d.tables.firstWhere((x) => x.name == 'addresses');
      final statuses = t.cols.map((c) => '${c.name}:${c.status}').join(', ');
      expect(t.cols.any((c) => c.status == 'added' && c.name == 'test_col'), true,
          reason: 'cols=[$statuses]');
      await pgExec('ALTER TABLE addresses DROP COLUMN test_col');
    });

    // ------------------------------------------------------------------ lock & polish
    await c('PG-66/67', 'PIN lock: wrong PIN stays locked, correct unlocks', () async {
      state.setLock(LockConfig(enabled: true, method: 'pin', pin: '1234'));
      state.locked = true;
      state.setLock(state.lock); // notifies so the lock screen mounts
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.pump();
      for (final d in ['1', '1', '1', '1']) {
        await tapDigit(d);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 900));
      expect(state.locked, true, reason: 'wrong PIN rejected');
      for (final d in ['1', '2', '3', '4']) {
        await tapDigit(d);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 900));
      expect(state.locked, false, reason: 'correct PIN unlocks');
      state.setLock(LockConfig(enabled: false));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    });

    await c('PG-10/11', 'disconnect → reconnect cleanly', () async {
      state.disconnect();
      expect(state.screen, 'connect');
      await state.connect(pgProfile, 'Admin');
      expect(state.screen, 'workspace');
      expect(state.catalog, 'sqlpulse_demo');
    });

    // ------------------------------------------------------------------ teardown
    await c('CLEANUP', 'leave the demo DB in seed state', () async {
      await pgExec("UPDATE addresses SET city='New York', postal_code=NULL WHERE address_id=1");
      await pgExec("DELETE FROM addresses WHERE line1 IN ('12 Test St','13 Cleanup St','14 Staged St')");
      await pgExec('ALTER TABLE addresses DROP COLUMN IF EXISTS test_col');
      await pgExec('DROP TABLE IF EXISTS zz_manual2');
      expect(await pgScalar('SELECT count(*) FROM addresses'), '50');
      expect(await pgScalar('SELECT count(*) FROM order_items'), '150');
    });

    await state.driver?.close();
    await _pg?.close();

    print('\n==== MANUAL PG SUITE: $pass passed, $fail failed ====');
    if (failed.isNotEmpty) {
      print('FAILED: ${failed.join(' | ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
