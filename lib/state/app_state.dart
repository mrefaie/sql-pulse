// SQL Pulse — central app state & actions, backed by REAL database drivers.
import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../data/seed_data.dart';
import '../data/store.dart';
import '../data/engines.dart' as en;
import '../engine/sql_engine.dart';
import '../db/db_driver.dart';
import '../db/driver_factory.dart';

class AppState extends ChangeNotifier {
  // ---- core state ----
  String screen = 'connect'; // connect | workspace
  Profile? profile;
  String role = 'Admin';
  String catalog = '';
  String engine = 'mysql';
  String tab = 'browse';
  String table = '';
  bool detail = false;

  /// Live introspected catalogs by name (only the loaded ones).
  Map<String, Catalog> db = {};
  List<String> catalogs = [];

  String sql = 'SELECT * FROM users LIMIT 10;';
  QueryResult? result;
  bool busy = false; // a query/connect is running
  bool connecting = false;

  List<AuditEntry> audit = [];
  String theme = 'dark';
  List<Profile> profiles = [];
  List<SavedQuery> saved = [];
  List<PinCard> dashboard = [];
  int consoleSignal = 0;
  bool staging = false;
  bool masking = false;
  Map<String, bool> prefs = {
    'maskProd': true,
    'stageProd': true,
    'guard': true,
  };
  LockConfig lock = LockConfig();
  bool locked = false;
  List<PendingChange> pending = [];

  final List<RoleDef> roles = kRoles;

  DbDriver? _driver;
  DbDriver? get driver => _driver;

  AppState() {
    final p = Store.load();
    audit = (p['audit'] is List && (p['audit'] as List).isNotEmpty)
        ? (p['audit'] as List)
              .map(
                (e) => AuditEntry.fromJson((e as Map).cast<String, dynamic>()),
              )
              .toList()
        : [];
    theme = p['theme'] as String? ?? 'dark';
    profiles = (p['profiles'] is List)
        ? (p['profiles'] as List)
              .map((e) => Profile.fromJson((e as Map).cast<String, dynamic>()))
              .toList()
        : defaultProfiles();
    saved = (p['saved'] is List)
        ? (p['saved'] as List)
              .map(
                (e) => SavedQuery.fromJson((e as Map).cast<String, dynamic>()),
              )
              .toList()
        : [];
    dashboard = (p['dashboard'] is List)
        ? (p['dashboard'] as List)
              .map((e) => PinCard.fromJson((e as Map).cast<String, dynamic>()))
              .toList()
        : [];
    if (p['prefs'] is Map) {
      prefs = {
        ...prefs,
        ...(p['prefs'] as Map).map((k, v) => MapEntry(k as String, v as bool)),
      };
    }
    lock = LockConfig.fromJson((p['lock'] as Map?)?.cast<String, dynamic>());
    locked = lock.enabled;
  }

  Catalog? get currentCatalog => db[catalog];

  // ---- persistence ----
  void _saveProfiles() =>
      Store.save({'profiles': profiles.map((p) => p.toJson()).toList()});
  void _saveSaved() =>
      Store.save({'saved': saved.map((s) => s.toJson()).toList()});
  void _saveDashboard() =>
      Store.save({'dashboard': dashboard.map((d) => d.toJson()).toList()});
  void _saveAudit() =>
      Store.save({'audit': audit.take(60).map((a) => a.toJson()).toList()});

  bool isProd() => profile != null && profile!.env == 'prod';

  void addAudit({
    required String status,
    String table = '',
    required String query,
    int ms = 1,
    int rows = 0,
  }) {
    audit.insert(
      0,
      AuditEntry(
        role: role,
        status: status,
        table: table,
        query: query.trim(),
        ms: ms,
        rows: rows,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (audit.length > 60) audit = audit.sublist(0, 60);
    _saveAudit();
  }

  String _qid(String name) => en.quoteId(name, engine);
  String _qval(Object? v) {
    if (v == null) return 'NULL';
    if (v is num) return '$v';
    return "'${v.toString().replaceAll("'", "''")}'";
  }

  ColumnDef? _pkOf(TableDef t) {
    for (final c in t.columns) {
      if (c.pk) return c;
    }
    return t.columns.isNotEmpty ? t.columns.first : null;
  }

  // ---- theme ----
  void toggleTheme() {
    theme = theme == 'dark' ? 'light' : 'dark';
    Store.save({'theme': theme});
    notifyListeners();
  }

  // ---- profiles ----
  int _nextId(List<int> ids) =>
      (ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b)) + 1;
  void addProfile(Profile data) {
    data.id = _nextId(profiles.map((p) => p.id).toList());
    profiles = [...profiles, data];
    _saveProfiles();
    notifyListeners();
  }

  void updateProfile(int id, Profile data) {
    data.id = id;
    profiles = profiles.map((p) => p.id == id ? data : p).toList();
    _saveProfiles();
    notifyListeners();
  }

  void deleteProfile(int id) {
    profiles = profiles.where((p) => p.id != id).toList();
    _saveProfiles();
    notifyListeners();
  }

  void duplicateProfile(Profile p) {
    final c = p.clone();
    c.id = _nextId(profiles.map((x) => x.id).toList());
    c.name = '${p.name} (copy)';
    profiles = [...profiles, c];
    _saveProfiles();
    notifyListeners();
  }

  // ---- connect (REAL) ----
  Future<void> connect(Profile p, String r) async {
    connecting = true;
    notifyListeners();
    final drv = makeDriver(p.engine);
    try {
      await drv.connect(p);
      final cats = await drv.listCatalogs();
      final startCat = cats.contains(p.catalog)
          ? p.catalog
          : (cats.isNotEmpty ? cats.first : p.catalog);
      final cat = await drv.introspect(startCat);
      await _driver?.close();
      _driver = drv;
      profile = p;
      engine = p.engine;
      role = (p.options['readOnly'] == true) ? 'ReadOnly' : r;
      catalog = startCat;
      catalogs = cats;
      db = {startCat: cat};
      tab = 'browse';
      detail = false;
      result = null;
      pending = [];
      staging = p.env == 'prod' && prefs['stageProd'] != false;
      masking = p.env == 'prod' && prefs['maskProd'] != false;
      table = cat.tables.keys.isNotEmpty ? cat.tables.keys.first : '';
      sql = 'SELECT * FROM ${table.isEmpty ? 'table' : table} LIMIT 50;';
      screen = 'workspace';
      connecting = false;
      addAudit(
        status: 'CONNECT',
        query:
            'CONNECT ${p.host}:${p.port} · ${en.eng(p.engine).label} · ${drv.serverVersion}',
        ms: 1,
      );
      notifyListeners();
    } catch (e) {
      connecting = false;
      try {
        await drv.close();
      } catch (_) {}
      notifyListeners();
      throw DbException(e is DbException ? e.message : e.toString());
    }
  }

  void disconnect() {
    _driver?.close();
    _driver = null;
    screen = 'connect';
    db = {};
    catalogs = [];
    notifyListeners();
  }

  Future<void> switchCatalog(String c) async {
    if (c == catalog && db.containsKey(c)) return;
    busy = true;
    notifyListeners();
    try {
      final cat = await _driver!.introspect(c);
      catalog = c;
      db = {c: cat};
      table = cat.tables.keys.isNotEmpty ? cat.tables.keys.first : '';
      detail = false;
      result = null;
    } catch (e) {
      result = QueryResult(error: true, message: e.toString());
    }
    busy = false;
    notifyListeners();
  }

  void setRole(String r) {
    role = r;
    notifyListeners();
  }

  Future<void> openTable(String n) async {
    table = n;
    detail = true;
    notifyListeners();
    final t = currentCatalog?.tables[n];
    if (t != null && !t.loaded) {
      try {
        final rows = await _driver!.preview(
          catalog,
          n,
          60,
          orderBy: t.columns.where((c) => c.pk).map((c) => c.name).toList(),
        );
        t.rows = rows;
        t.loaded = true;
        if (t.rowEstimate < rows.length) t.rowEstimate = rows.length;
        notifyListeners();
      } catch (_) {}
    }
  }

  void closeTable() {
    detail = false;
    notifyListeners();
  }

  void gotoDiagram() {
    detail = false;
    tab = 'diagram';
    notifyListeners();
  }

  void goTab(String id) {
    detail = false;
    tab = id;
    notifyListeners();
  }

  Future<void> runSelect(String n) async {
    detail = false;
    tab = 'query';
    await run('SELECT * FROM ${_qid(n)} LIMIT 50;');
  }

  Future<void> runSelect2(String n, String col, Object? val) async {
    final v = val is num ? '$val' : "'${val.toString().replaceAll("'", "''")}'";
    detail = false;
    tab = 'query';
    await run('SELECT * FROM ${_qid(n)} WHERE ${_qid(col)} = $v;');
  }

  void loadIntoConsole(String q) {
    sql = q;
    tab = 'query';
    result = null;
    consoleSignal++;
    detail = false;
    notifyListeners();
  }

  void setSql(String q) {
    sql = q;
  }

  // ---- role-based access control (REAL enforcement) ----
  static final _ddlVerbs = {
    'create',
    'alter',
    'drop',
    'truncate',
    'rename',
    'comment',
  };
  static final _dmlVerbs = {
    'insert',
    'update',
    'delete',
    'merge',
    'replace',
    'upsert',
    'call',
    'exec',
    'execute',
  };

  /// Returns a denial reason if the active [role] may not run [sql], else null.
  /// Enforces the role contracts: ReadOnly = SELECT only; Analyst = DML but no
  /// DDL; Developer = DDL+DML but no user/permission management; Admin = all.
  String? roleBlock(String sql) {
    if (role == 'Admin') return null;
    final s = sql.trimLeft().toLowerCase();
    final verb = RegExp(r'^[a-z]+').firstMatch(s)?.group(0) ?? '';
    bool hasWrite() =>
        RegExp(r'\b(insert|update|delete|merge|replace)\b').hasMatch(s);
    final isUserMgmt =
        {'grant', 'revoke'}.contains(verb) ||
        RegExp(r'^(create|alter|drop)\s+(user|role|login|group)\b').hasMatch(s);
    switch (role) {
      case 'ReadOnly':
        final writes =
            _ddlVerbs.contains(verb) ||
            _dmlVerbs.contains(verb) ||
            {'grant', 'revoke'}.contains(verb) ||
            (verb == 'with' && hasWrite());
        if (writes)
          return 'Read-only role — only SELECT statements are permitted.';
        break;
      case 'Analyst':
        if (_ddlVerbs.contains(verb))
          return 'Analyst role — schema changes (DDL) are not permitted.';
        if (isUserMgmt)
          return 'Analyst role — permission changes are not allowed.';
        break;
      case 'Developer':
        if (isUserMgmt)
          return 'Developer role — user & permission management is not allowed.';
        break;
    }
    return null;
  }

  // ---- execute (REAL) ----
  Future<void> run(String q) async {
    if (_driver == null) return;
    final denied = roleBlock(q);
    if (denied != null) {
      busy = false;
      sql = q;
      result = QueryResult(error: true, denied: true, ms: 1, message: denied);
      addAudit(status: 'DENIED', table: '', query: q, ms: 1, rows: 0);
      notifyListeners();
      return;
    }
    busy = true;
    sql = q;
    notifyListeners();
    final res = await _driver!.execute(q, catalog: catalog);
    result = res;
    busy = false;
    final m = RegExp(
      r'''from\s+[`"\[]?(\w+)''',
      caseSensitive: false,
    ).firstMatch(q);
    addAudit(
      status: res.error ? 'SYNTAX' : SqlEngine.statusFor(res, q),
      table: m?.group(1) ?? '',
      query: q,
      ms: res.ms,
      rows: res.rows?.length ?? 0,
    );
    notifyListeners();
  }

  Future<void> runScript(String script) async {
    final stmts = SqlEngine.splitStatements(script);
    if (stmts.isEmpty) {
      result = QueryResult(
        error: true,
        message: 'No statements to run.',
        ms: 1,
      );
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    final sw = Stopwatch()..start();
    final items = <BatchItem>[];
    for (final s in stmts) {
      final denied = roleBlock(s);
      if (denied != null) {
        items.add(
          BatchItem(
            s,
            QueryResult(error: true, denied: true, ms: 1, message: denied),
          ),
        );
        continue;
      }
      items.add(BatchItem(s, await _driver!.execute(s, catalog: catalog)));
    }
    final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
    final okCount = items.where((i) => !i.res.error && !i.res.denied).length;
    sql = script;
    result = QueryResult(
      batch: items,
      ms: ms,
      comment: '$okCount/${items.length} statements succeeded.',
    );
    busy = false;
    addAudit(
      status: items.any((i) => i.res.error) ? 'SYNTAX' : 'DML',
      query: 'BATCH · ${items.length} statements',
      ms: ms,
      rows: items.fold(0, (a, i) => a + (i.res.rows?.length ?? 0)),
    );
    notifyListeners();
  }

  Future<void> runBuilder(QuerySpec spec, String sqlStr) async {
    await run(sqlStr);
  }

  /// Real, dialect-aware query plan via the driver.
  Future<void> explainCurrent(String q) async {
    if (_driver == null) return;
    busy = true;
    sql = q;
    notifyListeners();
    final res = await _driver!.explain(q, catalog: catalog);
    result = res;
    busy = false;
    addAudit(
      status: 'EXPLAIN',
      query: 'EXPLAIN $q',
      ms: res.ms,
      rows: res.rows?.length ?? 0,
    );
    notifyListeners();
  }

  // ---- editing (REAL SQL) ----
  Future<void> _exec(
    String sql, {
    String status = 'DML',
    String table = '',
    int rows = 1,
  }) async {
    final denied = roleBlock(sql);
    if (denied != null) {
      result = QueryResult(error: true, denied: true, ms: 1, message: denied);
      addAudit(status: 'DENIED', table: table, query: sql, ms: 1, rows: 0);
      return;
    }
    final res = await _driver!.execute(sql, catalog: catalog);
    if (res.error) {
      result = res;
    }
    addAudit(
      status: res.error ? 'SYNTAX' : status,
      table: table,
      query: sql,
      ms: res.ms,
      rows: res.error ? 0 : rows,
    );
  }

  Future<void> _refresh(String tb) async {
    final t = currentCatalog?.tables[tb];
    if (t == null) return;
    try {
      t.rows = await _driver!.preview(
        catalog,
        tb,
        60,
        orderBy: t.columns.where((c) => c.pk).map((c) => c.name).toList(),
      );
      t.loaded = true;
    } catch (_) {}
  }

  Future<void> editCell(String tb, int ri, String col, String val) async {
    final t = currentCatalog!.tables[tb]!;
    if (staging) {
      pending = [
        ...pending.where(
          (x) =>
              !(x.kind == 'update' &&
                  x.table == tb &&
                  x.ri == ri &&
                  x.col == col),
        ),
        PendingChange(
          id: _pid(),
          kind: 'update',
          table: tb,
          ri: ri,
          col: col,
          value: val,
          label: "UPDATE $tb SET $col = '$val'",
        ),
      ];
      notifyListeners();
      return;
    }
    final pk = _pkOf(t)!;
    final pkVal = t.rows[ri][pk.name];
    final colDef = t.columns.firstWhere((c) => c.name == col);
    final typed =
        en.eng(engine).fileBased ||
            RegExp(
              r'INT|DEC|NUM|DOUBLE|FLOAT|REAL|BIGINT|MONEY',
              caseSensitive: false,
            ).hasMatch(colDef.type)
        ? (num.tryParse(val)?.toString() ?? _qval(val))
        : _qval(val);
    await _exec(
      'UPDATE ${_qid(tb)} SET ${_qid(col)} = $typed WHERE ${_qid(pk.name)} = ${_qval(pkVal)};',
      table: tb,
    );
    await _refresh(tb);
    notifyListeners();
  }

  Future<void> addColumn(String tb, ColumnDef c) async {
    final addKw = engine == 'mssql' ? 'ADD' : 'ADD COLUMN';
    await _exec(
      'ALTER TABLE ${_qid(tb)} $addKw ${_qid(c.name)} ${c.type} ${c.nullable ? 'NULL' : 'NOT NULL'};',
      status: 'DDL',
      table: tb,
      rows: 0,
    );
    await _reintrospect();
    notifyListeners();
  }

  Future<void> createTable(
    String name,
    List<ColumnDef> cols,
    List<IndexDef> indexes,
  ) async {
    final ddl = en.createTableSql(name, cols, indexes, engine);
    await _exec(ddl, status: 'DDL', table: name, rows: 0);
    await _reintrospect();
    table = name;
    detail = true;
    notifyListeners();
  }

  Future<void> alterTable(
    String origName,
    List<ColumnDef> newCols,
    List<ColumnDef> beforeCols,
    Map<ColumnDef, String> beforeIds,
    Map<ColumnDef, String> afterIds,
    String ddl,
  ) async {
    if (ddl.trim().isNotEmpty && ddl.trim() != '-- no changes') {
      for (final stmt in SqlEngine.splitStatements(ddl)) {
        await _exec(stmt, status: 'DDL', table: origName, rows: 0);
      }
    }
    await _reintrospect();
    notifyListeners();
  }

  Future<void> dropTable(String tb) async {
    await _exec('DROP TABLE ${_qid(tb)};', status: 'DDL', table: tb, rows: 0);
    detail = false;
    await _reintrospect();
    notifyListeners();
  }

  Future<void> _reintrospect() async {
    try {
      final cat = await _driver!.introspect(catalog);
      db = {...db, catalog: cat};
    } catch (_) {}
  }

  String _insertSql(String tb, Map<String, Object?> vals, TableDef t) {
    final cols = <String>[];
    final vs = <String>[];
    for (final c in t.columns) {
      if (c.ai) continue;
      final v = vals[c.name];
      if (v == null || v == '') {
        if (!c.nullable) continue;
        cols.add(_qid(c.name));
        vs.add('NULL');
        continue;
      }
      cols.add(_qid(c.name));
      final isNum = RegExp(
        r'INT|DEC|NUM|DOUBLE|FLOAT|REAL|BIGINT|MONEY',
        caseSensitive: false,
      ).hasMatch(c.type);
      vs.add(isNum && num.tryParse('$v') != null ? '$v' : _qval(v));
    }
    return 'INSERT INTO ${_qid(tb)} (${cols.join(', ')}) VALUES (${vs.join(', ')});';
  }

  Future<void> insertRow(String tb, Map<String, String> vals) async {
    final t = currentCatalog!.tables[tb]!;
    if (staging) {
      pending = [
        ...pending,
        PendingChange(
          id: _pid(),
          kind: 'insert',
          table: tb,
          vals: {...vals},
          label: 'INSERT INTO $tb',
        ),
      ];
      notifyListeners();
      return;
    }
    await _exec(_insertSql(tb, vals, t), table: tb);
    t.rowEstimate += 1;
    await _refresh(tb);
    notifyListeners();
  }

  Future<void> deleteRow(String tb, int ri) async {
    final t = currentCatalog!.tables[tb]!;
    if (staging) {
      if (pending.any((x) => x.kind == 'delete' && x.table == tb && x.ri == ri))
        return;
      pending = [
        ...pending,
        PendingChange(
          id: _pid(),
          kind: 'delete',
          table: tb,
          ri: ri,
          label: 'DELETE FROM $tb (row ${ri + 1})',
        ),
      ];
      notifyListeners();
      return;
    }
    final pk = _pkOf(t)!;
    final pkVal = ri < t.rows.length ? t.rows[ri][pk.name] : null;
    await _exec(
      'DELETE FROM ${_qid(tb)} WHERE ${_qid(pk.name)} = ${_qval(pkVal)};',
      table: tb,
    );
    if (t.rowEstimate > 0) t.rowEstimate -= 1;
    await _refresh(tb);
    notifyListeners();
  }

  // ---- staging / masking ----
  void toggleStaging() {
    staging = !staging;
    notifyListeners();
  }

  void toggleMasking() {
    masking = !masking;
    notifyListeners();
  }

  void setPref(String k, bool v) {
    prefs = {...prefs, k: v};
    Store.save({'prefs': prefs});
    notifyListeners();
  }

  Future<void> resetAll() async {
    await Store.reset();
    disconnect();
    audit = [];
    theme = 'dark';
    profiles = defaultProfiles();
    saved = [];
    dashboard = [];
    prefs = {'maskProd': true, 'stageProd': true, 'guard': true};
    lock = LockConfig();
    locked = false;
    pending = [];
    notifyListeners();
  }

  // ---- pending tray ----
  int _pidCounter = 0;
  String _pid() => 'p${_pidCounter++}_${DateTime.now().microsecondsSinceEpoch}';

  ({Map<String, String> updates, Set<int> deletes, List<PendingChange> inserts})
  pendingFor(String tb) {
    final updates = <String, String>{};
    final deletes = <int>{};
    final inserts = <PendingChange>[];
    for (final p in pending) {
      if (p.table != tb) continue;
      if (p.kind == 'update') {
        updates['${p.ri}:${p.col}'] = '${p.value}';
      } else if (p.kind == 'delete') {
        deletes.add(p.ri);
      } else if (p.kind == 'insert') {
        inserts.add(p);
      }
    }
    return (updates: updates, deletes: deletes, inserts: inserts);
  }

  void discardPending(String id) {
    pending = pending.where((x) => x.id != id).toList();
    notifyListeners();
  }

  void rollbackPending() {
    pending = [];
    notifyListeners();
  }

  /// Apply all staged changes atomically: build the SQL, run it inside a real
  /// transaction, and only clear the tray + refresh on success. A failure rolls
  /// back the whole batch (nothing is written) and keeps the pending changes so
  /// the user can fix and retry. Returns true on commit.
  Future<bool> commitPending() async {
    if (pending.isEmpty) return true;
    if (role == 'ReadOnly') {
      result = QueryResult(
        error: true,
        denied: true,
        ms: 1,
        message: 'Read-only role — cannot commit changes.',
      );
      notifyListeners();
      return false;
    }
    final affectedTables = <String>{};
    final stmts = <String>[];
    for (final p in pending) {
      final t = currentCatalog?.tables[p.table];
      if (t == null) continue;
      affectedTables.add(p.table);
      final pk = _pkOf(t)!;
      if (p.kind == 'update' && p.ri < t.rows.length) {
        final pkVal = t.rows[p.ri][pk.name];
        stmts.add(
          'UPDATE ${_qid(p.table)} SET ${_qid(p.col)} = ${_qval(p.value)} WHERE ${_qid(pk.name)} = ${_qval(pkVal)};',
        );
      } else if (p.kind == 'insert') {
        stmts.add(_insertSql(p.table, p.vals ?? {}, t));
      } else if (p.kind == 'delete' && p.ri < t.rows.length) {
        final pkVal = t.rows[p.ri][pk.name];
        stmts.add(
          'DELETE FROM ${_qid(p.table)} WHERE ${_qid(pk.name)} = ${_qval(pkVal)};',
        );
      }
    }
    if (stmts.isEmpty) {
      pending = [];
      notifyListeners();
      return true;
    }
    busy = true;
    notifyListeners();
    final sw = Stopwatch()..start();
    final res = await _driver!.runTransaction(stmts, catalog: catalog);
    final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
    busy = false;
    if (res != null && res.error) {
      // rolled back — keep the tray, surface the failing statement
      result = res;
      addAudit(
        status: 'ROLLBACK',
        query: 'COMMIT · ${stmts.length} statements (rolled back)',
        ms: ms,
        rows: 0,
      );
      notifyListeners();
      return false;
    }
    addAudit(
      status: 'COMMIT',
      query: 'COMMIT · ${stmts.length} statements',
      ms: ms,
      rows: stmts.length,
    );
    for (final tb in affectedTables) {
      await _refresh(tb);
    }
    pending = [];
    notifyListeners();
    return true;
  }

  void clearAudit() {
    audit = [];
    _saveAudit();
    notifyListeners();
  }

  // ---- lock ----
  void setLock(LockConfig next) {
    lock = next;
    Store.save({'lock': lock.toJson()});
    notifyListeners();
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  // ---- saved queries ----
  void saveQuery(String name, String q) {
    saved = [
      SavedQuery(
        id: DateTime.now().millisecondsSinceEpoch,
        name: name.trim().isEmpty ? 'Untitled query' : name.trim(),
        sql: q,
        engine: engine,
        catalog: catalog,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      ...saved,
    ];
    if (saved.length > 100) saved = saved.sublist(0, 100);
    _saveSaved();
    notifyListeners();
  }

  void deleteSaved(int id) {
    saved = saved.where((x) => x.id != id).toList();
    _saveSaved();
    notifyListeners();
  }

  // ---- dashboard ----
  void pinToDashboard(String name, String viz) {
    dashboard = [
      PinCard(
        id: DateTime.now().millisecondsSinceEpoch,
        name: name.trim().isEmpty ? 'Untitled card' : name.trim(),
        viz: viz,
        sql: sql,
        catalog: catalog,
        engine: engine,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      ...dashboard,
    ];
    if (dashboard.length > 30) dashboard = dashboard.sublist(0, 30);
    _saveDashboard();
    notifyListeners();
  }

  void removePin(int id) {
    dashboard = dashboard.where((x) => x.id != id).toList();
    _saveDashboard();
    notifyListeners();
  }

  Future<void> runPin(PinCard pin) async {
    tab = 'query';
    await run(pin.sql);
  }

  /// Live re-run for a board card against the current connection.
  Future<QueryResult> runPinQuery(PinCard pin) async {
    if (_driver == null)
      return QueryResult(error: true, message: 'Not connected');
    return _driver!.execute(pin.sql, catalog: catalog);
  }

  /// Load a preview of rows for a table in the current catalog if not loaded.
  Future<void> ensureRows(String table, [int limit = 200]) async {
    final t = currentCatalog?.tables[table];
    if (t == null || t.loaded || _driver == null) return;
    try {
      t.rows = await _driver!.preview(
        catalog,
        table,
        limit,
        orderBy: t.columns.where((c) => c.pk).map((c) => c.name).toList(),
      );
      t.loaded = true;
    } catch (_) {}
  }

  /// Introspect another connection's catalog (for the diff sheet).
  Future<Catalog> introspectTarget(Profile p) async {
    final drv = makeDriver(p.engine);
    await drv.connect(p);
    try {
      final cats = await drv.listCatalogs();
      final cat = cats.contains(p.catalog)
          ? p.catalog
          : (cats.isNotEmpty ? cats.first : p.catalog);
      final c = await drv.introspect(cat);
      // load previews for row-level diffs of small tables
      for (final t in c.tables.values) {
        if (t.rowEstimate <= 200) {
          try {
            t.rows = await drv.preview(cat, t.name, 200);
            t.loaded = true;
          } catch (_) {}
        }
      }
      return c;
    } finally {
      await drv.close();
    }
  }

  // ---- export ----
  Future<String?> exportResult(String fmt, String sourceName) async {
    final r = result;
    if (r == null || r.headers == null) return null;
    final base = sourceName.replaceAll(
      RegExp(r'[^a-z0-9_]+', caseSensitive: false),
      '_',
    );
    if (fmt == 'csv')
      return Store.shareOrDownload(
        '$base.csv',
        Store.toCsv(r.headers!, r.rows!),
      );
    if (fmt == 'json')
      return Store.shareOrDownload(
        '$base.json',
        Store.toJsonStr(r.headers!, r.rows!),
      );
    if (fmt == 'sql')
      return Store.shareOrDownload(
        '$base.sql',
        Store.toInserts(sourceName, r.headers!, r.rows!),
      );
    if (fmt == 'copy')
      return (await Store.copy(Store.toJsonStr(r.headers!, r.rows!)))
          ? 'ok'
          : 'fail';
    return null;
  }

  Future<void> exportTable(String fmt, String tb) async {
    // export the full table from the server (not just the preview)
    final res = await _driver!.execute(
      'SELECT * FROM ${_qid(tb)}',
      catalog: catalog,
    );
    if (res.headers == null) return;
    if (fmt == 'csv')
      await Store.shareOrDownload(
        '$tb.csv',
        Store.toCsv(res.headers!, res.rows!),
      );
    if (fmt == 'json')
      await Store.shareOrDownload(
        '$tb.json',
        Store.toJsonStr(res.headers!, res.rows!),
      );
    if (fmt == 'sql')
      await Store.shareOrDownload(
        '$tb.sql',
        Store.toInserts(tb, res.headers!, res.rows!),
      );
  }
}
