// SQL Pulse — lightweight SQL execution engine. Ported from engine.js.
import '../data/models.dart';
import '../data/engines.dart' as en;

class _Vocab {
  final String scan, seek, range, accessScan, accessSeek, accessRange, keyword;
  const _Vocab(this.scan, this.seek, this.range, this.accessScan, this.accessSeek, this.accessRange, this.keyword);
}

const Map<String, _Vocab> _planVocab = {
  'mysql': _Vocab('Full table scan', 'Unique index lookup', 'Index range scan', 'ALL', 'eq_ref', 'range', 'EXPLAIN'),
  'mariadb': _Vocab('Full table scan', 'Unique index lookup', 'Index range scan', 'ALL', 'eq_ref', 'range', 'EXPLAIN'),
  'sqlite': _Vocab('SCAN TABLE', 'SEARCH using PK', 'SEARCH using index', 'SCAN', 'SEARCH', 'SEARCH', 'EXPLAIN QUERY PLAN'),
  'postgres': _Vocab('Seq Scan', 'Index Scan using pkey', 'Bitmap Index Scan', 'Seq Scan', 'Index Scan', 'Bitmap Scan', 'EXPLAIN ANALYZE'),
  'mssql': _Vocab('Table Scan', 'Clustered Index Seek', 'Index Seek', 'Table Scan', 'Clustered Index Seek', 'Index Seek', 'SET STATISTICS PROFILE ON'),
};

class SqlEngine {
  static double _round2(num x) => (x * 100).round() / 100;

  static List<PlanNode> explainFor(String sql, Catalog cat, String engineId) {
    final v = _planVocab[engineId] ?? _planVocab['mysql']!;
    final q = sql.toLowerCase();
    final nodes = <PlanNode>[];
    final m = RegExp(r'''from\s+[`"\[]?(\w+)''', caseSensitive: false).firstMatch(sql);
    final tbl = m != null ? m.group(1)! : 'users';
    if (q.contains('join')) {
      nodes.add(PlanNode(
        op: engineId == 'mssql' ? 'Hash Match (join)' : engineId == 'postgres' ? 'Hash Join' : 'Nested loop join',
        table: 'orders o', access: v.accessScan, possible: 'PRIMARY, user_id_idx',
        key: engineId == 'mysql' ? 'NULL' : 'orders_pkey',
        rows: cat.tables['orders']?.rows.length ?? 5, cost: 'MEDIUM',
        advice: 'Scans all order rows to drive the join. Fine at this size; add a covering index once orders grows past a few thousand rows.',
      ));
      nodes.add(PlanNode(
        op: v.seek, table: 'users u', access: v.accessSeek, possible: 'PRIMARY',
        key: engineId == 'mysql' ? 'PRIMARY' : 'users_pkey', rows: 1, cost: 'LOW',
        advice: 'Optimal — each matching user is fetched directly by primary key.',
      ));
    } else if (q.contains('where')) {
      final indexed = RegExp(r'\b(id|sku|product_id|order_id|device_id)\b').hasMatch(q);
      if (indexed) {
        nodes.add(PlanNode(
          op: v.range, table: tbl, access: v.accessSeek, possible: 'PRIMARY, id_idx',
          key: engineId == 'mysql' ? 'PRIMARY' : '${tbl}_pkey', rows: 1, cost: 'LOW',
          advice: 'Excellent index selection — lookup scales logarithmically.',
        ));
      } else {
        final fix = engineId == 'mssql'
            ? 'CREATE NONCLUSTERED INDEX idx_category ON $tbl (category_id);'
            : engineId == 'postgres'
                ? 'CREATE INDEX idx_category ON $tbl (category_id);'
                : 'ALTER TABLE $tbl ADD INDEX idx_category (category_id);';
        nodes.add(PlanNode(
          op: v.scan, table: tbl, access: v.accessScan, possible: 'NULL', key: 'NULL',
          rows: cat.tables[tbl]?.rows.length ?? 40, cost: 'HIGH',
          advice: 'No index covers this filter. Consider:\n$fix',
        ));
      }
    } else {
      nodes.add(PlanNode(
        op: v.scan, table: tbl, access: v.accessScan, possible: 'NULL', key: 'NULL',
        rows: cat.tables[tbl]?.rows.length ?? 40, cost: 'HIGH',
        advice: 'A full scan reads every row. Add a WHERE filter on an indexed column to narrow the set.',
      ));
    }
    return nodes;
  }

  static String _unquote(String s) => s.replaceAll(RegExp(r'''[`"\[\]]'''), '');

  static QueryResult runSql(Map<String, Catalog> db, String catalog, String sql, String role, String engineId) {
    final sw = Stopwatch()..start();
    final cat = db[catalog]!;
    final raw = (sql).trim();
    final q = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    QueryResult done(QueryResult r) {
      r.ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 999);
      return r;
    }

    if (raw.isEmpty) return done(QueryResult(error: true, message: 'Empty statement.'));

    final isWrite = RegExp(r'^(insert|update|delete)').hasMatch(q);
    final isDdl = RegExp(r'^(create|alter|drop)').hasMatch(q);
    if (role == 'ReadOnly' && (isWrite || isDdl)) {
      return done(QueryResult(denied: true, message: 'Access denied — the Read-only role cannot run write or DDL statements.'));
    }
    if (role == 'Analyst' && isDdl) {
      return done(QueryResult(denied: true, message: 'Access denied — the Analyst role cannot modify schema (DDL).'));
    }

    if (q.startsWith('explain ')) {
      final inner = raw.replaceFirst(RegExp(r'^explain\s+(analyze\s+)?', caseSensitive: false), '').trim();
      return done(QueryResult(explain: explainFor(inner, cat, engineId), comment: 'Execution plan generated.'));
    }

    if (q.startsWith('show tables') ||
        q.contains('from sys.tables') ||
        q.contains('from pg_catalog.pg_tables') ||
        q.contains('from pg_tables')) {
      final rows = cat.tables.keys.map((t) => <Object?>[t]).toList();
      final head = q.contains('sys.tables')
          ? 'name'
          : (q.contains('pg_tables') ? 'tablename' : 'Tables_in_$catalog');
      return done(QueryResult(headers: [head], rows: rows, comment: '${rows.length} tables.'));
    }

    if (q.startsWith('describe ') || q.startsWith('desc ') || q.startsWith('exec sp_help') || q.startsWith('sp_help')) {
      final m = RegExp(r"(?:describe|desc|sp_help)\s+'?([^\s';]+)", caseSensitive: false).firstMatch(raw);
      final name = _unquote(m != null ? m.group(1)! : '');
      final tb = cat.tables[name];
      if (tb == null) return done(QueryResult(error: true, message: "Table '$name' not found."));
      return done(QueryResult(
        headers: ['Field', 'Type', 'Null', 'Key', 'Extra'],
        rows: tb.columns
            .map((c) => <Object?>[c.name, c.type, c.nullable ? 'YES' : 'NO', c.pk ? 'PRI' : (c.fkTable != null ? 'MUL' : ''), c.ai ? 'auto_increment' : ''])
            .toList(),
        comment: 'Described $name.',
      ));
    }

    if (q.startsWith('select')) {
      final fromM = RegExp(r'''from\s+([`"\[]?\w+[`"\]]?)''', caseSensitive: false).firstMatch(raw);
      if (fromM == null) return done(QueryResult(error: true, message: 'Malformed query: missing FROM clause.'));
      final tableName = _unquote(fromM.group(1)!);

      if (q.contains('join')) {
        final users = cat.tables['users'], orders = cat.tables['orders'];
        if (users != null && orders != null) {
          final headers = ['username', 'email', 'order_id', 'order_date', 'total_amount', 'status'];
          var rows = orders.rows.map((o) {
            final u = users.rows.firstWhere((u) => u['id'] == o['user_id'], orElse: () => {});
            return <Object?>[u['username'] ?? '', u['email'] ?? '', o['order_id'], o['order_date'], o['total_amount'], o['status']];
          }).toList();
          final cap = RegExp(r'\btop\s+(\d+)', caseSensitive: false).firstMatch(raw) ??
              RegExp(r'fetch\s+next\s+(\d+)', caseSensitive: false).firstMatch(raw) ??
              RegExp(r'limit\s+(\d+)', caseSensitive: false).firstMatch(raw);
          if (cap != null) rows = rows.take(int.parse(cap.group(1)!)).toList();
          return done(QueryResult(headers: headers, rows: rows, comment: '${rows.length} rows from join.'));
        }
      }

      final tb = cat.tables[tableName];
      if (tb == null) return done(QueryResult(error: true, message: "Table '$tableName' is not in this schema."));

      var colSec = raw.substring(raw.toLowerCase().indexOf('select') + 6, raw.toLowerCase().indexOf('from')).trim();
      colSec = colSec.replaceFirst(RegExp(r'^distinct\s+', caseSensitive: false), '').replaceFirst(RegExp(r'^top\s+\d+\s+', caseSensitive: false), '').trim();
      var cols = colSec == '*'
          ? tb.columns.map((c) => c.name).toList()
          : colSec.split(',').map((s) => _unquote(s.trim()).split('.').last).toList();
      cols = cols.where((c) => tb.columns.any((x) => x.name == c)).toList();
      if (cols.isEmpty) cols = tb.columns.map((c) => c.name).toList();

      var rows = List<RowMap>.of(tb.rows);
      final whM = RegExp(r'''where\s+([\w.`"\[\]]+)\s*=\s*'?([^'";]+)'?''', caseSensitive: false).firstMatch(raw);
      if (whM != null) {
        final f = _unquote(whM.group(1)!).split('.').last;
        final val = whM.group(2)!.trim();
        rows = rows.where((r) => '${r[f]}'.toLowerCase() == val.toLowerCase()).toList();
      }
      final offM = RegExp(r'offset\s+(\d+)', caseSensitive: false).firstMatch(raw);
      if (offM != null) rows = rows.skip(int.parse(offM.group(1)!)).toList();
      final cap = RegExp(r'\btop\s+(\d+)', caseSensitive: false).firstMatch(raw) ??
          RegExp(r'fetch\s+next\s+(\d+)', caseSensitive: false).firstMatch(raw) ??
          RegExp(r'limit\s+(\d+)', caseSensitive: false).firstMatch(raw);
      if (cap != null) rows = rows.take(int.parse(cap.group(1)!)).toList();

      return done(QueryResult(
        headers: cols,
        rows: rows.map((r) => cols.map((c) => r[c]).toList()).toList(),
        comment: '${rows.length} rows in set.',
      ));
    }

    final verb = q.split(' ')[0].toUpperCase();
    final affected = 1 + (raw.length % 2);
    var msg = 'Query OK · $affected row${affected > 1 ? 's' : ''} affected.';
    if (q.startsWith('update')) msg = 'Query OK · $affected row(s) updated.';
    if (q.startsWith('delete')) msg = 'Query OK · $affected row(s) deleted.';
    if (q.startsWith('create')) msg = 'Query OK · object created.';
    if (q.startsWith('alter')) msg = 'Query OK · table altered.';
    return done(QueryResult(status: true, statementType: verb, comment: msg));
  }

  static String statusFor(QueryResult res, String sql) {
    if (res.denied) return 'DENIED';
    if (res.error) return 'SYNTAX';
    if (res.explain != null) return 'EXPLAIN';
    final q = sql.trim().toLowerCase();
    if (q.startsWith('select') || q.startsWith('show') || q.startsWith('desc')) return 'SELECT';
    if (RegExp(r'^(create|alter|drop)').hasMatch(q)) return 'DDL';
    if (RegExp(r'^(insert|update|delete)').hasMatch(q)) return 'DML';
    return 'OK';
  }

  // ===== structured builder executor =====
  static Object? _getVal(Map<String, Object?> rec, String table, String col) {
    final k = '$table.$col';
    if (rec.containsKey(k)) return rec[k];
    for (final key in rec.keys) {
      if (key.endsWith('.$col')) return rec[key];
    }
    return null;
  }

  static List<Map<String, Object?>> resolveCols(QuerySpec spec, Catalog cat) {
    final cols = (spec.columns.isNotEmpty)
        ? spec.columns
        : cat.tables[spec.table]!.columns
            .map((c) => QbColumn(table: spec.table, col: c.name))
            .toList();
    final bare = <String, int>{};
    for (final c in cols) {
      if (c.agg == null) bare[c.col] = (bare[c.col] ?? 0) + 1;
    }
    return cols.map((c) {
      var label = c.alias.trim();
      if (label.isEmpty) {
        label = c.agg != null
            ? '${c.agg}(${c.col})'
            : ((bare[c.col] ?? 0) > 1 ? '${c.table}.${c.col}' : c.col);
      }
      return {'label': label, 'table': c.table, 'col': c.col, 'agg': c.agg};
    }).toList();
  }

  static bool _cmp(Object? lhs, String op, Object? rhsRaw) {
    if (op == 'IS NULL') return lhs == null;
    if (op == 'IS NOT NULL') return lhs != null;
    if (lhs == null) return false;
    if (op == 'IN' || op == 'NOT IN') {
      final inList = '$rhsRaw'.split(',').map((s) => s.trim().toLowerCase()).contains('$lhs'.toLowerCase());
      return op == 'IN' ? inList : !inList;
    }
    if (op == 'LIKE') {
      var pat = RegExp.escape('$rhsRaw').replaceAll('%', '.*').replaceAll('_', '.');
      return RegExp('^$pat\$', caseSensitive: false).hasMatch('$lhs');
    }
    final ln = double.tryParse('$lhs');
    final rn = double.tryParse('$rhsRaw');
    final numeric = ln != null && rn != null &&
        RegExp(r'^-?\d').hasMatch('$lhs'.trim()) && RegExp(r'^-?\d').hasMatch('$rhsRaw'.trim());
    if (numeric) {
      switch (op) {
        case '=': return ln == rn;
        case '!=': return ln != rn;
        case '>': return ln > rn;
        case '<': return ln < rn;
        case '>=': return ln >= rn;
        case '<=': return ln <= rn;
      }
    } else {
      final a = '$lhs'.toLowerCase();
      final b = '$rhsRaw'.toLowerCase();
      switch (op) {
        case '=': return a == b;
        case '!=': return a != b;
        case '>': return a.compareTo(b) > 0;
        case '<': return a.compareTo(b) < 0;
        case '>=': return a.compareTo(b) >= 0;
        case '<=': return a.compareTo(b) <= 0;
      }
    }
    return false;
  }

  static Object? _aggregate(String agg, String col, List<Map<String, Object?>> recs, String table) {
    if (agg == 'COUNT') {
      return col == '*' ? recs.length : recs.where((r) => _getVal(r, table, col) != null).length;
    }
    final nums = recs.map((r) => double.tryParse('${_getVal(r, table, col)}')).whereType<double>().toList();
    if (nums.isEmpty) return null;
    final sum = nums.fold<double>(0, (a, b) => a + b);
    if (agg == 'SUM') return _round2(sum);
    if (agg == 'AVG') return _round2(sum / nums.length);
    if (agg == 'MIN') return nums.reduce((a, b) => a < b ? a : b);
    if (agg == 'MAX') return nums.reduce((a, b) => a > b ? a : b);
    return null;
  }

  static String _inferType(List<List<Object?>> rows, int idx) {
    final vals = rows.map((r) => idx < r.length ? r[idx] : null).where((v) => v != null).toList();
    return vals.isNotEmpty && vals.every((v) => v is num) ? 'DECIMAL' : 'VARCHAR';
  }

  static Map<String, Catalog> _materializeCtes(Map<String, Catalog> db, String catalog, QuerySpec spec, String role) {
    if (spec.ctes.isEmpty) return db;
    final work = {for (final e in db.entries) e.key: e.value.clone()};
    for (final cte in spec.ctes) {
      if (cte.name.isEmpty || cte.sub.table.isEmpty) continue;
      final res = runBuilder(work, catalog, cte.sub, role);
      if (res.headers != null) {
        work[catalog]!.tables[cte.name] = TableDef(
          name: cte.name,
          cte: true,
          columns: List.generate(res.headers!.length, (i) => ColumnDef(name: res.headers![i], type: _inferType(res.rows!, i))),
          rows: res.rows!.map((r) {
            final o = <String, Object?>{};
            for (var i = 0; i < res.headers!.length; i++) {
              o[res.headers![i]] = i < r.length ? r[i] : null;
            }
            return o;
          }).toList(),
        );
      }
    }
    return work;
  }

  static QueryResult runBuilder(Map<String, Catalog> db0, String catalog, QuerySpec spec, String role) {
    final db = _materializeCtes(db0, catalog, spec, role);
    final cat = db[catalog]!;
    final sw = Stopwatch()..start();
    QueryResult done(QueryResult r) {
      r.ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 999);
      return r;
    }
    final base = cat.tables[spec.table];
    if (base == null) return done(QueryResult(error: true, message: 'Select a table to query.'));

    var records = base.rows.map((r) {
      final rec = <String, Object?>{};
      for (final c in base.columns) {
        rec['${spec.table}.${c.name}'] = r[c.name];
      }
      return rec;
    }).toList();

    for (final j in spec.joins) {
      final jt = cat.tables[j.table];
      if (jt == null) continue;
      final out = <Map<String, Object?>>[];
      for (final rec in records) {
        final lv = _getVal(rec, j.leftTable, j.leftCol);
        final matches = jt.rows.where((jr) => '${jr[j.rightCol]}' == '$lv').toList();
        if (matches.isNotEmpty) {
          for (final m in matches) {
            final nr = {...rec};
            for (final c in jt.columns) {
              nr['${j.table}.${c.name}'] = m[c.name];
            }
            out.add(nr);
          }
        } else if (j.type == 'LEFT') {
          final nr = {...rec};
          for (final c in jt.columns) {
            nr['${j.table}.${c.name}'] = null;
          }
          out.add(nr);
        }
      }
      records = out;
    }

    final subCache = <String, List<Object?>>{};
    List<Object?> evalSub(QuerySpec sub) {
      final key = sub.hashCode.toString() + sub.table + sub.filters.length.toString();
      if (subCache.containsKey(key)) return subCache[key]!;
      final r = runBuilder(db, catalog, sub, role);
      final vals = (r.rows != null) ? r.rows!.map((row) => row.isNotEmpty ? row[0] : null).toList() : <Object?>[];
      return subCache[key] = vals;
    }

    final filters = spec.filters.where((f) => f.col.isNotEmpty && (f.sub != null || f.op == 'IS NULL' || f.op == 'IS NOT NULL' || f.value != '')).toList();
    if (filters.isNotEmpty) {
      records = records.where((rec) {
        bool? acc;
        for (var i = 0; i < filters.length; i++) {
          final f = filters[i];
          bool c;
          if (f.sub != null) {
            final lhs = _getVal(rec, f.table, f.col);
            final vals = evalSub(f.sub!);
            if (f.op == 'NOT IN') {
              c = !vals.map((e) => '$e').contains('$lhs');
            } else if (f.op == 'IN') {
              c = vals.map((e) => '$e').contains('$lhs');
            } else {
              final scalar = vals.isNotEmpty ? vals[0] : null;
              c = _cmp(lhs, f.op == 'IN' ? '=' : f.op, scalar);
            }
          } else {
            c = _cmp(_getVal(rec, f.table, f.col), f.op, f.value);
          }
          acc = i == 0 ? c : (f.conj == 'OR' ? (acc! || c) : (acc! && c));
        }
        return acc ?? true;
      }).toList();
    }

    final outs = resolveCols(spec, cat);
    final hasAgg = outs.any((o) => o['agg'] != null);
    final groupBy = spec.groupBy;
    List<List<Object?>> rows;
    if (hasAgg || groupBy.isNotEmpty) {
      final groups = <String, List<Map<String, Object?>>>{};
      for (final rec in records) {
        final key = groupBy.map((g) => _getVal(rec, g.table, g.col)).join('');
        groups.putIfAbsent(key, () => []).add(rec);
      }
      var list = groups.values.toList();
      final h = spec.having;
      if (h != null && h.agg.isNotEmpty && h.col.isNotEmpty && h.value != '') {
        list = list.where((recs) => _cmp(_aggregate(h.agg, h.col, recs, h.table ?? spec.table), h.op, h.value)).toList();
      }
      rows = list.map((recs) => outs.map<Object?>((o) => o['agg'] != null
          ? _aggregate(o['agg'] as String, o['col'] as String, recs, o['table'] as String)
          : _getVal(recs[0], o['table'] as String, o['col'] as String)).toList()).toList();
    } else {
      rows = records.map((rec) => outs.map<Object?>((o) => _getVal(rec, o['table'] as String, o['col'] as String)).toList()).toList();
    }

    if (spec.distinct) {
      final seen = <String>{};
      rows = rows.where((r) {
        final k = r.map((e) => '$e').join('');
        if (seen.contains(k)) return false;
        seen.add(k);
        return true;
      }).toList();
    }

    final headers = outs.map((o) => o['label'] as String).toList();
    final ob = spec.orderBy.where((o) => headers.contains(o.label)).toList();
    if (ob.isNotEmpty) {
      rows.sort((ra, rb) {
        for (final o in ob) {
          final i = headers.indexOf(o.label);
          final a = ra[i], b = rb[i];
          final an = double.tryParse('$a'), bn = double.tryParse('$b');
          int c;
          if (an != null && bn != null) {
            c = an.compareTo(bn);
          } else {
            c = '${a ?? ''}'.compareTo('${b ?? ''}');
          }
          if (c != 0) return o.dir == 'DESC' ? -c : c;
        }
        return 0;
      });
    }

    final total = rows.length;
    final offset = (int.tryParse(spec.offset) ?? 0).clamp(0, 1 << 30);
    final limit = (spec.limit.isEmpty) ? null : (int.tryParse(spec.limit) ?? 0).clamp(0, 1 << 30);
    var sliced = offset > 0 ? rows.skip(offset).toList() : rows;
    if (limit != null) sliced = sliced.take(limit).toList();

    final agg = (hasAgg || groupBy.isNotEmpty) ? ' · aggregated' : '';
    return done(QueryResult(
      headers: headers,
      rows: sliced,
      comment: '${sliced.length} row${sliced.length == 1 ? '' : 's'}${total != sliced.length ? ' of $total' : ''} in set$agg.',
    ));
  }

  static String _quoteOne(Object? v) =>
      RegExp(r'^-?\d+(\.\d+)?$').hasMatch('$v'.trim()) ? '$v'.trim() : "'$v'";

  static String _quote(Object? v) {
    if (v == '' || v == null) return "''";
    if ('$v'.contains(',')) {
      return '(${'$v'.split(',').map((s) => _quoteOne(s.trim())).join(', ')})';
    }
    return _quoteOne(v);
  }

  static String buildSqlFromSpec(QuerySpec spec, Catalog cat, String engineId) {
    final e = en.eng(engineId);
    final qualify = spec.joins.isNotEmpty;
    String qc(String table, String col) => en.quoteCol(table, col, qualify, e.id);

    final offset = int.tryParse(spec.offset) ?? 0;
    final hasLimit = spec.limit.isNotEmpty;
    final useTop = e.limitStyle == 'top' && hasLimit && offset == 0;

    var selectList = '*';
    if (spec.columns.isNotEmpty) {
      selectList = spec.columns.map((c) {
        var e2 = c.agg != null
            ? '${c.agg}(${c.agg == 'COUNT' && c.col == '*' ? '*' : qc(c.table, c.col)})'
            : qc(c.table, c.col);
        if (c.alias.trim().isNotEmpty) e2 += ' AS ${en.quoteId(c.alias.trim(), e.id)}';
        return e2;
      }).join(', ');
    }
    var sql = 'SELECT ${spec.distinct ? 'DISTINCT ' : ''}${useTop ? 'TOP ${spec.limit} ' : ''}$selectList\nFROM ${en.quoteId(spec.table.isEmpty ? '…' : spec.table, e.id)}';
    for (final j in spec.joins) {
      sql += '\n${j.type} JOIN ${en.quoteId(j.table, e.id)} ON ${qc(j.leftTable, j.leftCol)} = ${qc(j.table, j.rightCol)}';
    }
    final filters = spec.filters.where((f) => f.col.isNotEmpty).toList();
    if (filters.isNotEmpty) {
      sql += '\nWHERE ' + filters.asMap().entries.map((entry) {
        final i = entry.key;
        final f = entry.value;
        final lead = i > 0 ? ' ${f.conj} ' : '';
        if (f.sub != null) {
          final subSql = buildSqlFromSpec(f.sub!, cat, engineId).replaceAll(RegExp(r';$'), '').replaceAll('\n', ' ');
          return '$lead${qc(f.table, f.col)} ${f.op} ($subSql)';
        }
        final c = '${qc(f.table, f.col)} ${f.op}' + (RegExp(r'NULL').hasMatch(f.op) ? '' : ' ${_quote(f.value)}');
        return '$lead$c';
      }).join('');
    }
    if (spec.groupBy.isNotEmpty) {
      sql += '\nGROUP BY ${spec.groupBy.map((g) => qc(g.table, g.col)).join(', ')}';
    }
    final h = spec.having;
    if (h != null && h.agg.isNotEmpty && h.col.isNotEmpty) {
      sql += '\nHAVING ${h.agg}(${h.col == '*' ? '*' : qc(h.table ?? spec.table, h.col)}) ${h.op} ${_quote(h.value)}';
    }
    final ob = List.of(spec.orderBy);
    final needsOrderForPaging = e.limitStyle == 'top' && hasLimit && offset > 0 && ob.isEmpty;
    if (ob.isNotEmpty || needsOrderForPaging) {
      final list = ob.isNotEmpty ? ob.map((o) => '${en.quoteId(o.label, e.id)} ${o.dir}').join(', ') : '(SELECT NULL)';
      sql += '\nORDER BY $list';
    }
    if (e.limitStyle == 'top') {
      if (hasLimit && offset > 0) {
        sql += '\nOFFSET $offset ROWS FETCH NEXT ${spec.limit} ROWS ONLY';
      } else if (offset > 0) {
        sql += '\nOFFSET $offset ROWS';
      }
    } else {
      if (hasLimit) {
        sql += '\nLIMIT ${spec.limit}${offset > 0 ? ' OFFSET $offset' : ''}';
      } else if (offset > 0) {
        sql += '\nOFFSET $offset';
      }
    }
    final ctes = spec.ctes.where((c) => c.name.isNotEmpty && c.sub.table.isNotEmpty).toList();
    if (ctes.isNotEmpty) {
      final defs = ctes.map((c) {
        final body = buildSqlFromSpec(c.sub, cat, engineId).replaceAll(RegExp(r';$'), '').split('\n').map((l) => '  $l').join('\n');
        return '${en.quoteId(c.name, e.id)} AS (\n$body\n)';
      }).join(',\n');
      return 'WITH $defs\n$sql;';
    }
    return '$sql;';
  }

  static List<String> splitStatements(String sql) {
    final out = <String>[];
    var cur = '';
    var inS = false, inD = false, inLine = false, inBlk = false;
    for (var i = 0; i < sql.length; i++) {
      final ch = sql[i];
      final nx = i + 1 < sql.length ? sql[i + 1] : '';
      if (inLine) {
        if (ch == '\n') inLine = false;
        cur += ch;
        continue;
      }
      if (inBlk) {
        if (ch == '*' && nx == '/') {
          inBlk = false;
          cur += '*/';
          i++;
        } else {
          cur += ch;
        }
        continue;
      }
      if (!inS && !inD && ch == '-' && nx == '-') {
        inLine = true;
        cur += ch;
        continue;
      }
      if (!inS && !inD && ch == '/' && nx == '*') {
        inBlk = true;
        cur += '/*';
        i++;
        continue;
      }
      if (ch == "'" && !inD) {
        inS = !inS;
      } else if (ch == '"' && !inS) {
        inD = !inD;
      }
      if (ch == ';' && !inS && !inD) {
        if (cur.trim().isNotEmpty) out.add(cur.trim());
        cur = '';
      } else {
        cur += ch;
      }
    }
    if (cur.trim().isNotEmpty) out.add(cur.trim());
    return out;
  }

  // ---- SQL formatter ----
  static const _kw = {'select', 'from', 'where', 'group', 'by', 'having', 'order', 'asc', 'desc', 'limit', 'offset', 'join', 'inner', 'left', 'right', 'outer', 'cross', 'on', 'and', 'or', 'not', 'null', 'is', 'in', 'like', 'between', 'as', 'union', 'all', 'distinct', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'view', 'index', 'primary', 'key', 'foreign', 'references', 'default', 'unique', 'with', 'returning', 'case', 'when', 'then', 'else', 'end', 'count', 'sum', 'avg', 'min', 'max'};

  static String formatSql(String sql, String engineId) =>
      splitStatements(sql).map((s) => _formatOne(s)).join('\n\n');

  static List<String> _splitTop(String str) {
    final out = <String>[];
    var depth = 0, cur = '', inS = false;
    for (final ch in str.split('')) {
      if (ch == "'") inS = !inS;
      if (!inS && ch == '(') depth++;
      if (!inS && ch == ')') depth--;
      if (!inS && ch == ',' && depth == 0) {
        out.add(cur);
        cur = '';
      } else {
        cur += ch;
      }
    }
    if (cur.trim().isNotEmpty) out.add(cur);
    return out;
  }

  static String _formatOne(String sql) {
    var s = sql.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r';$'), '');
    if (s.isEmpty) return '';
    const major = ['WITH', 'SELECT', 'FROM', 'WHERE', 'GROUP BY', 'HAVING', 'ORDER BY', 'LIMIT', 'OFFSET', 'UNION ALL', 'UNION', 'VALUES', 'SET', 'INSERT INTO', 'UPDATE', 'DELETE FROM', 'CREATE TABLE', 'CREATE VIEW', 'ALTER TABLE', 'RETURNING'];
    const joins = ['LEFT JOIN', 'RIGHT JOIN', 'INNER JOIN', 'OUTER JOIN', 'CROSS JOIN', 'JOIN'];
    s = s.replaceAllMapped(RegExp(r"('[^']*')|" r'("[^"]*")|' r'`[^`]*`|\b([a-zA-Z_]+)\b'), (m) {
      if (m.group(1) != null || m.group(2) != null) return m.group(0)!;
      final word = m.group(3);
      if (word != null && _kw.contains(word.toLowerCase())) return word.toUpperCase();
      return m.group(0)!;
    });
    for (final k in major) {
      s = s.replaceAllMapped(RegExp('\\s+(${k.replaceAll(' ', '\\s+')})\\b', caseSensitive: false), (m) => '\n${m.group(1)}');
    }
    for (final k in joins) {
      s = s.replaceAllMapped(RegExp('\\s+(${k.replaceAll(' ', '\\s+')})\\b', caseSensitive: false), (m) => '\n  ${m.group(1)}');
    }
    s = s.replaceAllMapped(RegExp(r'\s+(AND|OR)\b', caseSensitive: false), (m) => '\n  ${m.group(1)}');
    final lines = s.split('\n').map((line) {
      final mt = RegExp(r'^(SELECT)(\s+DISTINCT)?\s+(.+)$', caseSensitive: false).firstMatch(line);
      if (mt != null && !RegExp(r'^\s*\*').hasMatch(mt.group(3)!)) {
        final cols = _splitTop(mt.group(3)!);
        if (cols.length > 1) {
          return 'SELECT${mt.group(2) != null ? ' DISTINCT' : ''}\n${cols.map((c) => '  ${c.trim()}').join(',\n')}';
        }
      }
      return line;
    });
    return '${lines.join('\n')};';
  }
}
