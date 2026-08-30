// SQL Pulse — core data models (ported from the prototype's data layer).

typedef RowMap = Map<String, Object?>;

class ColumnDef {
  String name;
  String type;
  bool pk;
  bool nullable;
  bool ai;
  String? fkTable;
  String? fkCol;
  String def;

  ColumnDef({
    required this.name,
    required this.type,
    this.pk = false,
    this.nullable = true,
    this.ai = false,
    this.fkTable,
    this.fkCol,
    this.def = '',
  });

  ColumnDef clone() => ColumnDef(
        name: name,
        type: type,
        pk: pk,
        nullable: nullable,
        ai: ai,
        fkTable: fkTable,
        fkCol: fkCol,
        def: def,
      );
}

class IndexDef {
  String name;
  List<String> columns;
  bool unique;
  IndexDef({required this.name, required this.columns, this.unique = false});
  IndexDef clone() => IndexDef(name: name, columns: List.of(columns), unique: unique);
}

class TableDef {
  String name;
  List<ColumnDef> columns;
  List<RowMap> rows;
  List<IndexDef> indexes;
  bool cte;

  /// Total row count from the server (rows holds only a lazily-loaded preview).
  int rowEstimate;

  /// Whether [rows] has been loaded from the live DB yet.
  bool loaded;

  TableDef({
    required this.name,
    required this.columns,
    required this.rows,
    List<IndexDef>? indexes,
    this.cte = false,
    this.rowEstimate = 0,
    this.loaded = false,
  }) : indexes = indexes ?? [];

  /// Best row count to display (estimate from the server, else loaded count).
  int get displayRows => rowEstimate > 0 ? rowEstimate : rows.length;

  TableDef clone() => TableDef(
        name: name,
        columns: columns.map((c) => c.clone()).toList(),
        rows: rows.map((r) => Map<String, Object?>.of(r)).toList(),
        indexes: indexes.map((i) => i.clone()).toList(),
        cte: cte,
        rowEstimate: rowEstimate,
        loaded: loaded,
      );
}

class Relation {
  final String from;
  final String to;
  final String label;
  final String kind;
  Relation(this.from, this.to, this.label, this.kind);
}

class Catalog {
  String label;
  Map<String, TableDef> tables;
  List<Map<String, dynamic>> views;
  List<Map<String, dynamic>> procedures;
  List<Map<String, dynamic>> functions;
  List<Map<String, dynamic>> triggers;
  Map<String, Offset2> er;
  List<Relation> relations;

  Catalog({
    required this.label,
    required this.tables,
    this.views = const [],
    this.procedures = const [],
    this.functions = const [],
    this.triggers = const [],
    this.er = const {},
    this.relations = const [],
  });

  Catalog clone() => Catalog(
        label: label,
        tables: {for (final e in tables.entries) e.key: e.value.clone()},
        views: views,
        procedures: procedures,
        functions: functions,
        triggers: triggers,
        er: er,
        relations: relations,
      );
}

/// Lightweight x/y holder for ER node positions.
class Offset2 {
  final double x;
  final double y;
  const Offset2(this.x, this.y);
}

class Profile {
  int id;
  String name;
  String group;
  String engine;
  String host;
  int port;
  String user;
  String env; // prod | replica | staging | local
  String color;
  String label;
  bool ssl;
  bool ssh;
  String catalog;
  Map<String, Object?> options;

  Profile({
    required this.id,
    required this.name,
    required this.group,
    required this.engine,
    required this.host,
    required this.port,
    required this.user,
    required this.env,
    required this.color,
    this.label = '',
    this.ssl = false,
    this.ssh = false,
    required this.catalog,
    Map<String, Object?>? options,
  }) : options = options ?? {};

  Profile clone() => Profile(
        id: id,
        name: name,
        group: group,
        engine: engine,
        host: host,
        port: port,
        user: user,
        env: env,
        color: color,
        label: label,
        ssl: ssl,
        ssh: ssh,
        catalog: catalog,
        options: Map<String, Object?>.of(options),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'group': group,
        'engine': engine,
        'host': host,
        'port': port,
        'user': user,
        'env': env,
        'color': color,
        'label': label,
        'ssl': ssl,
        'ssh': ssh,
        'catalog': catalog,
        'options': options,
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        group: j['group'] as String? ?? 'Local',
        engine: j['engine'] as String? ?? 'mysql',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        user: j['user'] as String? ?? '',
        env: j['env'] as String? ?? 'local',
        color: j['color'] as String? ?? 'blue',
        label: j['label'] as String? ?? '',
        ssl: j['ssl'] as bool? ?? false,
        ssh: j['ssh'] as bool? ?? false,
        catalog: j['catalog'] as String? ?? 'e_commerce',
        options: (j['options'] as Map?)?.cast<String, Object?>() ?? {},
      );
}

class RoleDef {
  final String id;
  final String label;
  final String desc;
  final String icon;
  const RoleDef(this.id, this.label, this.desc, this.icon);
}

class AuditEntry {
  String role;
  String status;
  String table;
  String query;
  int ms;
  int rows;
  int at; // millis since epoch

  AuditEntry({
    required this.role,
    required this.status,
    this.table = '',
    required this.query,
    this.ms = 1,
    this.rows = 0,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'status': status,
        'table': table,
        'query': query,
        'ms': ms,
        'rows': rows,
        'at': at,
      };

  static AuditEntry fromJson(Map<String, dynamic> j) => AuditEntry(
        role: j['role'] as String? ?? 'Admin',
        status: j['status'] as String? ?? 'OK',
        table: j['table'] as String? ?? '',
        query: j['query'] as String? ?? '',
        ms: (j['ms'] as num?)?.toInt() ?? 1,
        rows: (j['rows'] as num?)?.toInt() ?? 0,
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class SavedQuery {
  final int id;
  final String name;
  final String sql;
  final String engine;
  final String catalog;
  final int at;
  SavedQuery({
    required this.id,
    required this.name,
    required this.sql,
    required this.engine,
    required this.catalog,
    required this.at,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sql': sql,
        'engine': engine,
        'catalog': catalog,
        'at': at,
      };
  static SavedQuery fromJson(Map<String, dynamic> j) => SavedQuery(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Untitled query',
        sql: j['sql'] as String? ?? '',
        engine: j['engine'] as String? ?? 'mysql',
        catalog: j['catalog'] as String? ?? 'e_commerce',
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class PinCard {
  final int id;
  final String name;
  final String viz; // metric | chart | table
  final String sql;
  final String catalog;
  final String engine;
  final int at;
  PinCard({
    required this.id,
    required this.name,
    required this.viz,
    required this.sql,
    required this.catalog,
    required this.engine,
    required this.at,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'viz': viz,
        'sql': sql,
        'catalog': catalog,
        'engine': engine,
        'at': at,
      };
  static PinCard fromJson(Map<String, dynamic> j) => PinCard(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Untitled card',
        viz: j['viz'] as String? ?? 'metric',
        sql: j['sql'] as String? ?? '',
        catalog: j['catalog'] as String? ?? 'e_commerce',
        engine: j['engine'] as String? ?? 'mysql',
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// Pending change in staged (transaction) mode.
class PendingChange {
  final String id;
  final String kind; // update | insert | delete
  final String table;
  final int ri;
  final String col;
  final Object? value;
  final RowMap? vals;
  final String label;
  PendingChange({
    required this.id,
    required this.kind,
    required this.table,
    this.ri = -1,
    this.col = '',
    this.value,
    this.vals,
    required this.label,
  });
}

class LockConfig {
  bool enabled;
  String method; // fingerprint | face | pin
  String pin;
  LockConfig({this.enabled = false, this.method = 'fingerprint', this.pin = ''});
  Map<String, dynamic> toJson() => {'enabled': enabled, 'method': method, 'pin': pin};
  static LockConfig fromJson(Map<String, dynamic>? j) => j == null
      ? LockConfig()
      : LockConfig(
          enabled: j['enabled'] as bool? ?? false,
          method: j['method'] as String? ?? 'fingerprint',
          pin: j['pin'] as String? ?? '',
        );
}

/// Execution-plan node.
class PlanNode {
  final String op;
  final String table;
  final String access;
  final String possible;
  final String key;
  final int rows;
  final String cost; // HIGH | MEDIUM | LOW
  final String advice;
  final bool result;
  PlanNode({
    required this.op,
    this.table = '',
    this.access = '',
    this.possible = '',
    this.key = '',
    this.rows = 0,
    this.cost = 'LOW',
    this.advice = '',
    this.result = false,
  });
}

class BatchItem {
  final String sql;
  final QueryResult res;
  BatchItem(this.sql, this.res);
}

/// Result of running a statement / builder spec.
class QueryResult {
  int ms;
  bool error;
  bool denied;
  String? message;
  List<String>? headers;
  List<List<Object?>>? rows;
  bool status;
  String? statementType;
  String? comment;
  List<PlanNode>? explain;
  List<BatchItem>? batch;

  QueryResult({
    this.ms = 1,
    this.error = false,
    this.denied = false,
    this.message,
    this.headers,
    this.rows,
    this.status = false,
    this.statementType,
    this.comment,
    this.explain,
    this.batch,
  });
}

/// ---- Visual builder spec ----
class QbColumn {
  String table;
  String col;
  String? agg;
  String alias;
  QbColumn({required this.table, required this.col, this.agg, this.alias = ''});
}

class QbJoin {
  String type; // INNER | LEFT
  String leftTable;
  String leftCol;
  String table;
  String rightCol;
  QbJoin({
    required this.type,
    required this.leftTable,
    required this.leftCol,
    required this.table,
    required this.rightCol,
  });
}

class QbFilter {
  String conj; // AND | OR
  String table;
  String col;
  String op;
  String value;
  QuerySpec? sub;
  QbFilter({
    this.conj = 'AND',
    required this.table,
    required this.col,
    this.op = '=',
    this.value = '',
    this.sub,
  });
}

class QbGroup {
  String table;
  String col;
  QbGroup(this.table, this.col);
}

class QbHaving {
  String agg;
  String? table;
  String col;
  String op;
  String value;
  QbHaving({required this.agg, this.table, required this.col, this.op = '>', this.value = ''});
}

class QbOrder {
  String label;
  String dir; // ASC | DESC
  QbOrder(this.label, this.dir);
}

class QbCte {
  String name;
  QuerySpec sub;
  QbCte(this.name, this.sub);
}

class QuerySpec {
  String table;
  bool distinct;
  List<QbColumn> columns;
  List<QbJoin> joins;
  List<QbFilter> filters;
  List<QbGroup> groupBy;
  QbHaving? having;
  List<QbOrder> orderBy;
  String limit;
  String offset;
  List<QbCte> ctes;

  QuerySpec({
    required this.table,
    this.distinct = false,
    List<QbColumn>? columns,
    List<QbJoin>? joins,
    List<QbFilter>? filters,
    List<QbGroup>? groupBy,
    this.having,
    List<QbOrder>? orderBy,
    this.limit = '',
    this.offset = '0',
    List<QbCte>? ctes,
  })  : columns = columns ?? [],
        joins = joins ?? [],
        filters = filters ?? [],
        groupBy = groupBy ?? [],
        orderBy = orderBy ?? [],
        ctes = ctes ?? [];
}
