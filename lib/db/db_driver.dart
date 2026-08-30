// SQL Pulse — real database driver abstraction + shared introspection helpers.
import '../data/models.dart';

/// A live connection to a real database server/file.
abstract class DbDriver {
  String get serverVersion;

  /// Open a connection using the profile (host/port/user/password/options).
  Future<void> connect(Profile p);

  Future<void> close();

  /// List selectable catalogs (databases for MySQL/MSSQL/SQLite, or you may
  /// return databases for Postgres too — switching reconnects to that db).
  Future<List<String>> listCatalogs();

  /// Introspect a catalog's schema into the shared [Catalog] model
  /// (tables with columns/PK/FK/AI, views, procedures, functions, triggers).
  Future<Catalog> introspect(String catalog);

  /// Execute arbitrary SQL against [catalog] (or the current one).
  Future<QueryResult> execute(String sql, {String? catalog});

  /// Fetch a preview of rows from a table (SELECT * … LIMIT).
  Future<List<RowMap>> preview(String catalog, String table, int limit);

  /// Return a real execution/query plan for [sql]. Default uses ANSI `EXPLAIN`;
  /// SQLite and SQL Server override with their own mechanism.
  Future<QueryResult> explain(String sql, {String? catalog}) {
    final body = sql.replaceFirst(RegExp(r'^\s*explain\s+', caseSensitive: false), '').trim();
    return execute('EXPLAIN $body', catalog: catalog);
  }

  /// Statements that begin / commit / roll back a transaction for this engine.
  /// SQL Server overrides these with its `… TRANSACTION` forms.
  String get txBegin => 'BEGIN';
  String get txCommit => 'COMMIT';
  String get txRollback => 'ROLLBACK';

  /// Execute [stmts] atomically in a single transaction on this connection.
  /// On the first failing statement the whole batch is rolled back and that
  /// statement's error result is returned; otherwise the commit result.
  /// Returns null for an empty list.
  Future<QueryResult?> runTransaction(List<String> stmts, {String? catalog}) async {
    if (stmts.isEmpty) return null;
    final begin = await execute(txBegin, catalog: catalog);
    if (begin.error) return begin;
    for (final s in stmts) {
      QueryResult r;
      try {
        r = await execute(s, catalog: catalog);
      } catch (e) {
        r = QueryResult(error: true, message: '$e', ms: 1);
      }
      if (r.error) {
        try {
          await execute(txRollback, catalog: catalog);
        } catch (_) {}
        return r; // surface the offending statement's error
      }
    }
    return execute(txCommit, catalog: catalog);
  }
}

class DbException implements Exception {
  final String message;
  DbException(this.message);
  @override
  String toString() => message;
}

// ---- shared helpers used by all drivers ----

/// Auto-arrange table nodes in a 3-column grid for the ER diagram,
/// matching the spacing the design used (x: 24/252/480, y stepping).
Map<String, Offset2> autoErLayout(Iterable<String> names) {
  final out = <String, Offset2>{};
  const xs = [24.0, 252.0, 480.0];
  final perCol = <int>[0, 0, 0];
  var i = 0;
  for (final n in names) {
    final col = i % 3;
    final y = 36.0 + perCol[col] * 200.0;
    out[n] = Offset2(xs[col], y);
    perCol[col]++;
    i++;
  }
  return out;
}

const _relKinds = ['accent', 'warn', 'info', 'lime', 'violet', 'pink', 'coral'];

/// Derive ER relations from the FK metadata already set on table columns.
List<Relation> buildRelations(Map<String, TableDef> tables) {
  final rels = <Relation>[];
  var k = 0;
  for (final t in tables.values) {
    for (final c in t.columns) {
      if (c.fkTable != null && tables.containsKey(c.fkTable)) {
        rels.add(Relation(t.name, c.fkTable!, '${t.name}.${c.name} → ${c.fkTable}.${c.fkCol}', _relKinds[k % _relKinds.length]));
        k++;
      }
    }
  }
  return rels;
}

/// True if a SQL string is a row-returning statement (SELECT/SHOW/WITH/EXPLAIN…).
bool returnsRows(String sql) {
  final q = sql.trimLeft().toLowerCase();
  return q.startsWith('select') || q.startsWith('show') || q.startsWith('with') ||
      q.startsWith('explain') || q.startsWith('describe') || q.startsWith('desc ') ||
      q.startsWith('pragma') || q.startsWith('values') || q.startsWith('table ');
}
