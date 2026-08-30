// SQL Pulse — large-schema UI benchmark.
//
// Measures wall-clock latency of the app's real UI paths against a live
// Postgres at two schema sizes: the 9-table demo catalog vs the 502-table
// sqlpulse_bench catalog (see benchmark/seed_large_schema.sql).
//
// Run (desktop baseline, 1400x1400 forced):
//   flutter test integration_test/bench_large_schema_test.dart -d macos \
//     --dart-define=DB_HOST=127.0.0.1 --dart-define=DB_NAME=sqlpulse_demo \
//     --dart-define=BENCH_BIG=false --dart-define=VIEW_1400=true
//   flutter test integration_test/bench_large_schema_test.dart -d macos \
//     --dart-define=DB_HOST=127.0.0.1 --dart-define=DB_NAME=sqlpulse_bench \
//     --dart-define=BENCH_BIG=true --dart-define=VIEW_1400=true
// Run (phone, real 720x1600 surface, LAN host):
//   flutter test integration_test/bench_large_schema_test.dart -d "<serial>" \
//     --dart-define=DB_HOST=192.168.1.120 --dart-define=DB_NAME=sqlpulse_bench \
//     --dart-define=BENCH_BIG=true --dart-define=VIEW_1400=false
//
// NOTE: bool.fromEnvironment only accepts the literal strings 'true'/'false';
// "1" parses as false.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sql_pulse/main.dart';
import 'package:sql_pulse/data/store.dart';
import 'package:sql_pulse/widgets/icons.dart';
import 'package:sql_pulse/widgets/primitives.dart';
import 'package:sql_pulse/state/app_state.dart';

const dbHost = String.fromEnvironment('DB_HOST', defaultValue: '127.0.0.1');
const dbName = String.fromEnvironment('DB_NAME', defaultValue: 'sqlpulse_demo');
const benchBig = bool.fromEnvironment('BENCH_BIG', defaultValue: false);
const force1400 = bool.fromEnvironment('VIEW_1400', defaultValue: true);

Finder btnIcon(String icon) => find.byWidgetPredicate((w) =>
    (w is SpButton && w.icon == icon) ||
    (w is SpChip && w.icon == icon) ||
    (w is IconBtn && w.name == icon) ||
    (w is SpIcon && w.name == icon));

Finder arrowLeft() => find.byWidgetPredicate(
    (w) => (w is IconBtn && w.name == 'arrowL') || (w is SpIcon && w.name == 'arrowL'));

Finder verticalScrollable() => find.byWidgetPredicate((w) =>
    w is Scrollable &&
    (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.right));

Finder textIn(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.data == text);

/// Polls with settled frames until [finder] matches; returns elapsed ms or -1.
Future<int> timeUntil(WidgetTester tester, Finder f,
    {Duration timeout = const Duration(seconds: 90)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    try {
      if (f.evaluate().isNotEmpty) return sw.elapsedMilliseconds;
    } catch (_) {}
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 150),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    } catch (_) {}
  }
  return -1;
}

/// Polls with settled frames until [ready] is true; returns elapsed ms or -1.
Future<int> timeUntilState(WidgetTester tester, bool Function() ready,
    {Duration timeout = const Duration(seconds: 90)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 150));
      return sw.elapsedMilliseconds;
    }
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 150),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    } catch (_) {}
  }
  return -1;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('large-schema benchmark', (tester) async {
    if (force1400) {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final state = AppState();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const SqlPulseApp()));
    await tester.pump();

    // --- workload selection ----------------------------------------------------
    final pgProfile = state.profiles.firstWhere((p) => p.engine == 'postgres');
    final big = benchBig;
    final bigTable = big ? 'bench_big_events' : 'users';
    final structMarker = big ? 'note' : 'email';
    final gridMarker = big ? 'e1' : 'email';
    final countSql = big
        ? 'SELECT count(*) AS total_events FROM bench_big_events;'
        : 'SELECT count(*) AS total_users FROM users;';
    final countValue = big ? '100000' : '44';
    final limitSql = big
        ? 'SELECT * FROM bench_big_events ORDER BY id LIMIT 1000;'
        : 'SELECT * FROM users ORDER BY id LIMIT 50;';
    final limitRows = big ? 1000 : 44;

    pgProfile.host = dbHost;
    pgProfile.catalog = dbName;
    final results = <String, dynamic>{};
    results['schema'] = dbName;
    results['tables'] = big ? 502 : 9;
    results['surface'] = force1400 ? '1400x1400' : 'device';

    Future<void> m(String name, int ms) {
      results[name] = ms;
      print('METRIC $name = ${ms}ms');
      return Future.value();
    }

    // --- 1. connect: profile card -> role -> Connect -> workspace -------------
    {
      await tester.tap(find.textContaining('Postgres ·').first);
      for (var i = 0; i < 30 && find.text('Test').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Admin').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Connect').last);
      final ms = await timeUntil(
          tester, find.textContaining(RegExp('schema ·', caseSensitive: false)),
          timeout: const Duration(seconds: 240));
      await m('connectToWorkspace', ms);
      final settle = Stopwatch()..start();
      try {
        await tester.pumpAndSettle(const Duration(milliseconds: 250),
            EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      } catch (_) {}
      await m('browseSettle', settle.elapsedMilliseconds);
    }

    // --- 2. structure: open the top card -----------------------------------------
    {
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      // Card tap handlers call state.openTable(); drive the same app code path.
      state.openTable(bigTable);
      await tester.pump(const Duration(milliseconds: 500));
      final ms = await timeUntil(tester, textIn(structMarker).first);
      await m('structureOpen', ms);
    }

    // --- 3. data grid: first page load + render -----------------------------------
    {
      final msLoad = await timeUntilState(tester,
          () => state.currentCatalog?.tables[state.table]?.rows.isNotEmpty == true);
      await m('gridDataLoad', msLoad);
      await tester.tap(find.text('Data').first);
      final ms = await timeUntil(tester, textIn(gridMarker).first);
      await m('gridRender', ms);
    }

    // --- 4. query console: aggregate ----------------------------------------------
    {
      await tester.tap(arrowLeft().first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      state.goTab('query');
      state.closeTable();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (find.text('SQL').evaluate().isNotEmpty) {
        await tester.tap(find.text('SQL').last);
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
      }
      state.setSql(countSql);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(btnIcon('play').first);
      final ms = await timeUntil(tester, textIn(countValue).first);
      await m('queryAggregate', ms);
    }

    // --- 5. query console: large result set --------------------------------------
    {
      state.setSql(limitSql);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(btnIcon('play').first);
      final ms = await timeUntilState(tester, () =>
          state.result != null &&
          !state.result!.error &&
          (state.result!.rows?.length ?? 0) >= limitRows);
      await m('queryLimit${limitRows}', ms);
    }

    // --- 6. ER diagram: full graph ------------------------------------------------
    {
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final nav = find.text('Diagram');
      if (nav.evaluate().isNotEmpty) {
        await tester.tap(nav.first);
      }
      final ms = await timeUntil(tester, textIn(big ? 'bench_t_0001' : 'users'));
      await m('diagramPaint', ms);
    }

    // --- 7. browse list scroll cost (5 big flings down) ---------------------------
    {
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final nav = find.text('Browse');
      if (nav.evaluate().isNotEmpty) {
        await tester.tap(nav.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await tester.drag(verticalScrollable().first, const Offset(0, -600),
            warnIfMissed: false);
        try {
          await tester.pumpAndSettle(const Duration(milliseconds: 120),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
        } catch (_) {}
      }
      await m('browseFling5', sw.elapsedMilliseconds);
    }

    print('BENCH_RESULTS ' + results.entries.map((e) => '${e.key}=${e.value}').join(' '));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
