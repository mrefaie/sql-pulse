// SQL Pulse — SQLite driver (package:sqlite3, real local .sqlite files).
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../data/models.dart';
import '../data/seed_data.dart';
import 'db_driver.dart';

Object? _coerce(Object? v) {
  if (v is Uint8List) return '<blob ${v.length}b>';
  return v;
}

class SqliteDriver extends DbDriver {
  Database? _db;
  String _label = 'main';

  @override
  String get serverVersion => 'SQLite ${sqlite3.version.libVersion}';

  @override
  Future<void> connect(Profile p) async {
    var path = '${p.options['dbFile'] ?? p.host}';
    if (path.isEmpty || path == 'sample' || path.startsWith('~')) {
      final dir = await getApplicationSupportDirectory();
      path = '${dir.path}/sqlpulse_sample.sqlite';
    }
    _db = sqlite3.open(path);
    _label = path.split('/').last;
    _seedIfEmpty();
  }

  void _seedIfEmpty() {
    final has = _db!.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' LIMIT 1");
    if (has.isNotEmpty) return;
    final cat = buildCatalogs()['e_commerce']!;
    for (final t in cat.tables.values) {
      final parts = t.columns.map((c) {
        var def = '"${c.name}" ${_sqliteType(c.type)}';
        if (c.pk) def += ' PRIMARY KEY';
        if (!c.nullable && !c.pk) def += ' NOT NULL';
        return def;
      }).toList();
      // foreign keys → so relations + ER diagram populate
      for (final c in t.columns.where((c) => c.fkTable != null)) {
        parts.add('FOREIGN KEY ("${c.name}") REFERENCES "${c.fkTable}"("${c.fkCol ?? 'id'}")');
      }
      _db!.execute('CREATE TABLE "${t.name}" (${parts.join(', ')})');
      for (final r in t.rows) {
        final keys = t.columns.map((c) => '"${c.name}"').join(', ');
        final qs = t.columns.map((_) => '?').join(', ');
        final vals = t.columns.map((c) => r[c.name]).toList();
        _db!.execute('INSERT INTO "${t.name}" ($keys) VALUES ($qs)', vals);
      }
    }
    for (final v in cat.views) {
      try {
        _db!.execute(v['definition'] as String);
      } catch (_) {}
    }
  }

  String _sqliteType(String t) {
    final u = t.toUpperCase();
    if (u.contains('INT')) return 'INTEGER';
    if (RegExp(r'DEC|DOUBLE|FLOAT|NUMERIC|REAL').hasMatch(u)) return 'REAL';
    return 'TEXT';
  }

  @override
  Future<void> close() async {
    _db?.dispose();
    _db = null;
  }

  @override
  Future<List<String>> listCatalogs() async => [_label];

  @override
  Future<Catalog> introspect(String catalog) async {
    final tableNames = _db!.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").map((r) => '${r['name']}').toList();
    final tables = <String, TableDef>{};
    for (final tn in tableNames) {
      final info = _db!.select('PRAGMA table_info("$tn")');
      final fks = _db!.select('PRAGMA foreign_key_list("$tn")');
      final fkMap = {for (final f in fks) '${f['from']}': ('${f['table']}', '${f['to']}')};
      final cols = info.map((r) {
        final name = '${r['name']}';
        final type = '${r['type']}';
        final pk = (r['pk'] as int? ?? 0) > 0;
        final fk = fkMap[name];
        return ColumnDef(
          name: name,
          type: type.isEmpty ? 'TEXT' : type,
          pk: pk,
          nullable: (r['notnull'] as int? ?? 0) == 0 && !pk,
          ai: pk && type.toUpperCase().contains('INTEGER'),
          fkTable: fk?.$1,
          fkCol: fk?.$2,
        );
      }).toList();
      final count = _db!.select('SELECT COUNT(*) AS n FROM "$tn"').first['n'] as int? ?? 0;
      tables[tn] = TableDef(name: tn, columns: cols, rows: [], rowEstimate: count);
    }
    final views = _db!.select("SELECT name, sql FROM sqlite_master WHERE type='view'");
    final trigs = _db!.select("SELECT name, sql, tbl_name FROM sqlite_master WHERE type='trigger'");
    final cat = Catalog(
      label: catalog,
      tables: tables,
      views: views.map((r) => {'name': '${r['name']}', 'definition': '${r['sql']}'}).toList(),
      procedures: const [],
      functions: const [],
      triggers: trigs.map((r) => {'name': '${r['name']}', 'event': 'TRIGGER', 'target': '${r['tbl_name']}', 'definition': '${r['sql']}'}).toList(),
    );
    cat.relations = buildRelations(tables);
    cat.er = autoErLayout(tables.keys);
    return cat;
  }

  @override
  Future<QueryResult> execute(String sql, {String? catalog}) async {
    final sw = Stopwatch()..start();
    try {
      if (returnsRows(sql)) {
        final rs = _db!.select(sql);
        final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
        final headers = rs.columnNames;
        final rows = rs.rows.map((row) => row.map(_coerce).toList()).toList();
        return QueryResult(ms: ms, headers: headers, rows: rows, comment: '${rows.length} row${rows.length == 1 ? '' : 's'} in set.');
      }
      _db!.execute(sql);
      final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
      final verb = sql.trimLeft().split(RegExp(r'\s')).first.toUpperCase();
      return QueryResult(ms: ms, status: true, statementType: verb, comment: 'Query OK · ${_db!.updatedRows} row(s) affected.');
    } catch (e) {
      return QueryResult(ms: (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999), error: true, message: e.toString().replaceFirst('SqliteException(', '').replaceFirst(RegExp(r'\)$'), ''));
    }
  }

  @override
  Future<QueryResult> explain(String sql, {String? catalog}) {
    final body = sql.replaceFirst(RegExp(r'^\s*explain(\s+query\s+plan)?\s+', caseSensitive: false), '').trim();
    return execute('EXPLAIN QUERY PLAN $body');
  }

  @override
  Future<List<RowMap>> preview(String catalog, String table, int limit) async {
    final rs = _db!.select('SELECT * FROM "$table" LIMIT $limit');
    return rs.rows.map((row) {
      final m = <String, Object?>{};
      for (var i = 0; i < rs.columnNames.length; i++) {
        m[rs.columnNames[i]] = _coerce(row[i]);
      }
      return m;
    }).toList();
  }
}
