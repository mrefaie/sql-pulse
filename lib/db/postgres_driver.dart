// SQL Pulse — PostgreSQL driver (package:postgres v3).
import 'package:postgres/postgres.dart' as pg;
import '../data/models.dart';
import 'db_driver.dart';

Object? _coerce(Object? v) {
  if (v == null || v is num || v is String || v is bool) return v;
  if (v is DateTime) return v.toIso8601String().replaceFirst('T', ' ');
  return v.toString();
}

class PostgresDriver extends DbDriver {
  pg.Connection? _conn;
  late Profile _profile;
  String _currentDb = 'postgres';
  String _version = 'PostgreSQL';

  @override
  String get serverVersion => _version;

  Future<pg.Connection> _open(String db) async {
    final o = _profile.options;
    final ssl = (o['pgSslMode'] ?? 'disable');
    final secure = ssl != 'disable' && _profile.ssl;
    final conn = await pg.Connection.open(
      pg.Endpoint(
        host: _profile.host,
        port: _profile.port,
        database: db,
        username: _profile.user,
        password: '${o['password'] ?? ''}',
      ),
      settings: pg.ConnectionSettings(
        sslMode: secure ? pg.SslMode.require : pg.SslMode.disable,
        connectTimeout: const Duration(seconds: 12),
      ),
    );
    return conn;
  }

  @override
  Future<void> connect(Profile p) async {
    _profile = p;
    _currentDb = p.catalog.isNotEmpty ? p.catalog : 'postgres';
    try {
      _conn = await _open(_currentDb);
    } catch (_) {
      // fall back to the default 'postgres' db if the chosen one is unreachable
      _currentDb = 'postgres';
      _conn = await _open(_currentDb);
    }
    final r = await _conn!.execute('SELECT version()');
    _version = '${r.first.first}'.split(' on ').first;
  }

  @override
  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }

  Future<void> _ensure(String db) async {
    if (db != _currentDb || _conn == null) {
      await _conn?.close();
      _conn = await _open(db);
      _currentDb = db;
    }
  }

  @override
  Future<List<String>> listCatalogs() async {
    final r = await _conn!.execute(
      "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn ORDER BY datname",
    );
    return r.map((row) => '${row.first}').toList();
  }

  @override
  Future<Catalog> introspect(String catalog) async {
    await _ensure(catalog);
    final cols = await _conn!.execute('''
      SELECT c.table_name, c.column_name, c.data_type, c.character_maximum_length,
             c.numeric_precision, c.numeric_scale, c.is_nullable, c.column_default
      FROM information_schema.columns c
      JOIN information_schema.tables t ON t.table_name = c.table_name AND t.table_schema = c.table_schema
      WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
      ORDER BY c.table_name, c.ordinal_position''');

    final tables = <String, TableDef>{};
    for (final row in cols) {
      final tn = '${row[0]}';
      final name = '${row[1]}';
      final dataType = '${row[2]}';
      final charLen = row[3];
      final numP = row[4], numS = row[5];
      final nullable = '${row[6]}' == 'YES';
      final def = row[7]?.toString() ?? '';
      var type = dataType;
      if (charLen != null)
        type = '$dataType($charLen)';
      else if (numP != null &&
          (dataType.contains('numeric') || dataType.contains('decimal')))
        type = 'numeric($numP,${numS ?? 0})';
      final ai = def.contains('nextval');
      tables
          .putIfAbsent(tn, () => TableDef(name: tn, columns: [], rows: []))
          .columns
          .add(
            ColumnDef(
              name: name,
              type: type,
              nullable: nullable,
              ai: ai,
              def: ai ? '' : def,
            ),
          );
    }

    // primary keys
    final pks = await _conn!.execute(
      '''
      SELECT kcu.table_name, kcu.column_name FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
      WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = 'public' ''',
    );
    for (final row in pks) {
      final t = tables['${row[0]}'];
      t?.columns
              .firstWhere(
                (c) => c.name == '${row[1]}',
                orElse: () => ColumnDef(name: '', type: ''),
              )
              .pk =
          true;
    }

    // foreign keys
    final fks = await _conn!.execute(
      '''
      SELECT kcu.table_name, kcu.column_name, ccu.table_name AS ref_table, ccu.column_name AS ref_col
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public' ''',
    );
    for (final row in fks) {
      final t = tables['${row[0]}'];
      final c = t?.columns.where((c) => c.name == '${row[1]}').toList();
      if (c != null && c.isNotEmpty) {
        c.first.fkTable = '${row[2]}';
        c.first.fkCol = '${row[3]}';
      }
    }

    // row estimates (fast, from stats)
    final counts = await _conn!.execute(
      "SELECT relname, n_live_tup FROM pg_stat_user_tables",
    );
    final countMap = {for (final r in counts) '${r[0]}': (r[1] as int?) ?? 0};
    for (final e in tables.entries) {
      e.value.rowEstimate = countMap[e.key] ?? 0;
    }

    final views = await _conn!.execute(
      "SELECT table_name, view_definition FROM information_schema.views WHERE table_schema = 'public'",
    );
    final routines = await _conn!.execute(
      "SELECT routine_name, routine_type, data_type, routine_definition FROM information_schema.routines WHERE specific_schema = 'public'",
    );
    final trigs = await _conn!.execute(
      "SELECT trigger_name, event_manipulation, event_object_table, action_statement FROM information_schema.triggers WHERE trigger_schema = 'public'",
    );

    final cat = Catalog(
      label: catalog,
      tables: tables,
      views: views
          .map(
            (r) => {
              'name': '${r[0]}',
              'definition': 'CREATE VIEW ${r[0]} AS\n${r[1]}',
            },
          )
          .toList(),
      procedures: routines
          .where((r) => '${r[1]}' == 'PROCEDURE')
          .map(
            (r) => {
              'name': '${r[0]}',
              'params': '',
              'definition': '${r[3] ?? '-- ${r[0]}'}',
            },
          )
          .toList(),
      functions: routines
          .where((r) => '${r[1]}' == 'FUNCTION')
          .map(
            (r) => {
              'name': '${r[0]}',
              'params': '',
              'returns': '${r[2]}',
              'definition': '${r[3] ?? '-- ${r[0]}'}',
            },
          )
          .toList(),
      triggers: trigs
          .map(
            (r) => {
              'name': '${r[0]}',
              'event': '${r[1]}',
              'target': '${r[2]}',
              'definition': '${r[3]}',
            },
          )
          .toList(),
    );
    cat.relations = buildRelations(tables);
    cat.er = autoErLayout(tables.keys);
    return cat;
  }

  @override
  Future<QueryResult> execute(String sql, {String? catalog}) async {
    if (catalog != null) await _ensure(catalog);
    final sw = Stopwatch()..start();
    try {
      final r = await _conn!.execute(sql, ignoreRows: false);
      final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
      if (r.schema.columns.isNotEmpty && returnsRows(sql)) {
        final headers = r.schema.columns
            .map((c) => c.columnName ?? '?')
            .toList();
        final rows = r.map((row) => row.map(_coerce).toList()).toList();
        return QueryResult(
          ms: ms,
          headers: headers,
          rows: rows,
          comment: '${rows.length} row${rows.length == 1 ? '' : 's'} in set.',
        );
      }
      final verb = sql.trimLeft().split(RegExp(r'\s')).first.toUpperCase();
      return QueryResult(
        ms: ms,
        status: true,
        statementType: verb,
        comment: 'Query OK · ${r.affectedRows} row(s) affected.',
      );
    } catch (e) {
      return QueryResult(
        ms: (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999),
        error: true,
        message: _clean(e),
      );
    }
  }

  @override
  Future<List<RowMap>> preview(
    String catalog,
    String table,
    int limit, {
    List<String>? orderBy,
  }) async {
    await _ensure(catalog);
    final ord = orderBy == null || orderBy.isEmpty
        ? ''
        : ' ORDER BY ${orderBy.map((c) => '"$c"').join(', ')}';
    final r = await _conn!.execute('SELECT * FROM "$table"$ord LIMIT $limit');
    final headers = r.schema.columns.map((c) => c.columnName ?? '?').toList();
    return r.map((row) {
      final m = <String, Object?>{};
      for (var i = 0; i < headers.length; i++) {
        m[headers[i]] = _coerce(row[i]);
      }
      return m;
    }).toList();
  }

  String _clean(Object e) {
    var s = e.toString();
    final m = RegExp(r'message:\s*(.+?)(,|\))', dotAll: true).firstMatch(s);
    return m != null ? m.group(1)!.trim() : s.replaceFirst('Exception: ', '');
  }
}
