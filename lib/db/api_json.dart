// SQL Pulse — JSON (de)serialization for the web API (backend <-> web driver).
import '../data/models.dart';

Map<String, dynamic> colToJson(ColumnDef c) => {
      'name': c.name, 'type': c.type, 'pk': c.pk, 'nullable': c.nullable,
      'ai': c.ai, 'fkTable': c.fkTable, 'fkCol': c.fkCol, 'def': c.def,
    };

ColumnDef colFromJson(Map j) => ColumnDef(
      name: j['name'] as String, type: j['type'] as String? ?? '',
      pk: j['pk'] as bool? ?? false, nullable: j['nullable'] as bool? ?? true,
      ai: j['ai'] as bool? ?? false, fkTable: j['fkTable'] as String?,
      fkCol: j['fkCol'] as String?, def: j['def'] as String? ?? '',
    );

Map<String, dynamic> tableToJson(TableDef t) => {
      'name': t.name,
      'columns': t.columns.map(colToJson).toList(),
      'rowEstimate': t.rowEstimate,
      'indexes': t.indexes.map((i) => {'name': i.name, 'columns': i.columns, 'unique': i.unique}).toList(),
    };

TableDef tableFromJson(Map j) => TableDef(
      name: j['name'] as String,
      columns: (j['columns'] as List).map((c) => colFromJson(c as Map)).toList(),
      rows: [],
      rowEstimate: (j['rowEstimate'] as num?)?.toInt() ?? 0,
      indexes: (j['indexes'] as List? ?? []).map((i) => IndexDef(name: i['name'] as String, columns: (i['columns'] as List).cast<String>(), unique: i['unique'] as bool? ?? false)).toList(),
    );

Map<String, dynamic> catalogToJson(Catalog c) => {
      'label': c.label,
      'tables': {for (final e in c.tables.entries) e.key: tableToJson(e.value)},
      'views': c.views,
      'procedures': c.procedures,
      'functions': c.functions,
      'triggers': c.triggers,
      'er': {for (final e in c.er.entries) e.key: [e.value.x, e.value.y]},
      'relations': c.relations.map((r) => {'from': r.from, 'to': r.to, 'label': r.label, 'kind': r.kind}).toList(),
    };

Catalog catalogFromJson(Map j) {
  final tables = <String, TableDef>{};
  (j['tables'] as Map).forEach((k, v) => tables[k as String] = tableFromJson(v as Map));
  return Catalog(
    label: j['label'] as String? ?? '',
    tables: tables,
    views: (j['views'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList(),
    procedures: (j['procedures'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList(),
    functions: (j['functions'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList(),
    triggers: (j['triggers'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList(),
    er: {for (final e in (j['er'] as Map).entries) e.key as String: Offset2((e.value[0] as num).toDouble(), (e.value[1] as num).toDouble())},
    relations: (j['relations'] as List).map((r) => Relation(r['from'] as String, r['to'] as String, r['label'] as String, r['kind'] as String)).toList(),
  );
}

Map<String, dynamic> planToJson(PlanNode n) => {
      'op': n.op, 'table': n.table, 'access': n.access, 'possible': n.possible,
      'key': n.key, 'rows': n.rows, 'cost': n.cost, 'advice': n.advice, 'result': n.result,
    };

PlanNode planFromJson(Map j) => PlanNode(
      op: j['op'] as String, table: j['table'] as String? ?? '', access: j['access'] as String? ?? '',
      possible: j['possible'] as String? ?? '', key: j['key'] as String? ?? '', rows: (j['rows'] as num?)?.toInt() ?? 0,
      cost: j['cost'] as String? ?? 'LOW', advice: j['advice'] as String? ?? '', result: j['result'] as bool? ?? false,
    );

Map<String, dynamic> resultToJson(QueryResult r) => {
      'ms': r.ms, 'error': r.error, 'denied': r.denied, 'message': r.message,
      'headers': r.headers, 'rows': r.rows, 'status': r.status,
      'statementType': r.statementType, 'comment': r.comment,
      'explain': r.explain?.map(planToJson).toList(),
      'batch': r.batch?.map((b) => {'sql': b.sql, 'res': resultToJson(b.res)}).toList(),
    };

QueryResult resultFromJson(Map j) => QueryResult(
      ms: (j['ms'] as num?)?.toInt() ?? 1,
      error: j['error'] as bool? ?? false,
      denied: j['denied'] as bool? ?? false,
      message: j['message'] as String?,
      headers: (j['headers'] as List?)?.cast<String>(),
      rows: (j['rows'] as List?)?.map((row) => (row as List).cast<Object?>()).toList(),
      status: j['status'] as bool? ?? false,
      statementType: j['statementType'] as String?,
      comment: j['comment'] as String?,
      explain: (j['explain'] as List?)?.map((e) => planFromJson(e as Map)).toList(),
      batch: (j['batch'] as List?)?.map((b) => BatchItem(b['sql'] as String, resultFromJson(b['res'] as Map))).toList(),
    );

List<RowMap> rowsFromJson(List j) => j.map((r) => (r as Map).cast<String, Object?>()).toList();
