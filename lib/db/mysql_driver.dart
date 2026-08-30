// SQL Pulse — MySQL / MariaDB driver (package:mysql_client).
import 'package:mysql_client/mysql_client.dart' as my;
import '../data/models.dart';
import 'db_driver.dart';

Object? _coerce(String? v) {
  if (v == null) return null;
  if (RegExp(r'^-?\d{1,15}$').hasMatch(v)) return int.tryParse(v) ?? v;
  if (RegExp(r'^-?\d+\.\d+$').hasMatch(v)) return double.tryParse(v) ?? v;
  return v;
}

class MySqlDriver extends DbDriver {
  my.MySQLConnection? _conn;
  String _currentDb = '';
  String _version = 'MySQL';
  final bool maria;
  MySqlDriver({this.maria = false});

  @override
  String get serverVersion => _version;

  @override
  Future<void> connect(Profile p) async {
    _currentDb = p.catalog;
    final secure = maria ? p.ssl : true; // MySQL 8 default auth needs TLS
    _conn = await my.MySQLConnection.createConnection(
      host: p.host,
      port: p.port,
      userName: p.user,
      password: '${p.options['password'] ?? ''}',
      databaseName: p.catalog,
      secure: secure,
    );
    await _conn!.connect(timeoutMs: 12000);
    final r = await _conn!.execute('SELECT VERSION()');
    _version = '${(maria ? 'MariaDB ' : 'MySQL ')}${r.rows.first.colAt(0)}';
  }

  @override
  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }

  Future<void> _ensure(String db) async {
    if (db.isNotEmpty && db != _currentDb) {
      await _conn!.execute('USE `$db`');
      _currentDb = db;
    }
  }

  @override
  Future<List<String>> listCatalogs() async {
    final r = await _conn!.execute('SHOW DATABASES');
    return r.rows.map((row) => '${row.colAt(0)}').toList();
  }

  @override
  Future<Catalog> introspect(String catalog) async {
    await _ensure(catalog);
    Future<my.IResultSet> q(String s) => _conn!.execute(s, {'db': catalog});
    final cols = await q(
      '''SELECT table_name, column_name, column_type, is_nullable, column_key, extra
        FROM information_schema.columns WHERE table_schema = :db ORDER BY table_name, ordinal_position''',
    );
    final tables = <String, TableDef>{};
    for (final row in cols.rows) {
      final a = row.assoc();
      final tn = '${a['table_name'] ?? a['TABLE_NAME']}';
      tables
          .putIfAbsent(tn, () => TableDef(name: tn, columns: [], rows: []))
          .columns
          .add(
            ColumnDef(
              name: '${a['column_name'] ?? a['COLUMN_NAME']}',
              type: '${a['column_type'] ?? a['COLUMN_TYPE']}',
              nullable: '${a['is_nullable'] ?? a['IS_NULLABLE']}' == 'YES',
              pk: '${a['column_key'] ?? a['COLUMN_KEY']}' == 'PRI',
              ai: '${a['extra'] ?? a['EXTRA']}'.contains('auto_increment'),
            ),
          );
    }

    final fks = await q(
      '''SELECT table_name, column_name, referenced_table_name, referenced_column_name
        FROM information_schema.key_column_usage WHERE table_schema = :db AND referenced_table_name IS NOT NULL''',
    );
    for (final row in fks.rows) {
      final a = row.assoc();
      final t = tables['${a['table_name'] ?? a['TABLE_NAME']}'];
      final col = t?.columns
          .where((c) => c.name == '${a['column_name'] ?? a['COLUMN_NAME']}')
          .toList();
      if (col != null && col.isNotEmpty) {
        col.first.fkTable =
            '${a['referenced_table_name'] ?? a['REFERENCED_TABLE_NAME']}';
        col.first.fkCol =
            '${a['referenced_column_name'] ?? a['REFERENCED_COLUMN_NAME']}';
      }
    }

    final est = await q(
      "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = :db AND table_type = 'BASE TABLE'",
    );
    for (final row in est.rows) {
      final a = row.assoc();
      final t = tables['${a['table_name'] ?? a['TABLE_NAME']}'];
      if (t != null)
        t.rowEstimate =
            int.tryParse('${a['table_rows'] ?? a['TABLE_ROWS'] ?? 0}') ?? 0;
    }

    final views = await q(
      'SELECT table_name, view_definition FROM information_schema.views WHERE table_schema = :db',
    );
    final routines = await q(
      'SELECT routine_name, routine_type, dtd_identifier, routine_definition FROM information_schema.routines WHERE routine_schema = :db',
    );
    final trigs = await q(
      'SELECT trigger_name, event_manipulation, event_object_table, action_statement FROM information_schema.triggers WHERE trigger_schema = :db',
    );

    final cat = Catalog(
      label: catalog,
      tables: tables,
      views: views.rows.map((r) {
        final a = r.assoc();
        return {
          'name': '${a['table_name'] ?? a['TABLE_NAME']}',
          'definition':
              'CREATE VIEW ${a['table_name'] ?? a['TABLE_NAME']} AS\n${a['view_definition'] ?? a['VIEW_DEFINITION']}',
        };
      }).toList(),
      procedures: routines.rows
          .where(
            (r) =>
                '${r.assoc()['routine_type'] ?? r.assoc()['ROUTINE_TYPE']}' ==
                'PROCEDURE',
          )
          .map((r) {
            final a = r.assoc();
            return {
              'name': '${a['routine_name'] ?? a['ROUTINE_NAME']}',
              'params': '',
              'definition':
                  '${a['routine_definition'] ?? a['ROUTINE_DEFINITION'] ?? ''}',
            };
          })
          .toList(),
      functions: routines.rows
          .where(
            (r) =>
                '${r.assoc()['routine_type'] ?? r.assoc()['ROUTINE_TYPE']}' ==
                'FUNCTION',
          )
          .map((r) {
            final a = r.assoc();
            return {
              'name': '${a['routine_name'] ?? a['ROUTINE_NAME']}',
              'params': '',
              'returns': '${a['dtd_identifier'] ?? a['DTD_IDENTIFIER'] ?? ''}',
              'definition':
                  '${a['routine_definition'] ?? a['ROUTINE_DEFINITION'] ?? ''}',
            };
          })
          .toList(),
      triggers: trigs.rows.map((r) {
        final a = r.assoc();
        return {
          'name': '${a['trigger_name'] ?? a['TRIGGER_NAME']}',
          'event': '${a['event_manipulation'] ?? a['EVENT_MANIPULATION']}',
          'target': '${a['event_object_table'] ?? a['EVENT_OBJECT_TABLE']}',
          'definition': '${a['action_statement'] ?? a['ACTION_STATEMENT']}',
        };
      }).toList(),
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
      final r = await _conn!.execute(sql);
      final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
      if (r.cols.isNotEmpty) {
        final headers = r.cols.map((c) => c.name).toList();
        final rows = r.rows
            .map(
              (row) =>
                  List.generate(headers.length, (i) => _coerce(row.colAt(i))),
            )
            .toList();
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
        : ' ORDER BY ${orderBy.map((c) => '`$c`').join(', ')}';
    final r = await _conn!.execute('SELECT * FROM `$table`$ord LIMIT $limit');
    final headers = r.cols.map((c) => c.name).toList();
    return r.rows.map((row) {
      final m = <String, Object?>{};
      for (var i = 0; i < headers.length; i++) {
        m[headers[i]] = _coerce(row.colAt(i));
      }
      return m;
    }).toList();
  }

  String _clean(Object e) => e
      .toString()
      .replaceFirst('MySQLServerException: ', '')
      .replaceFirst('Exception: ', '');
}
