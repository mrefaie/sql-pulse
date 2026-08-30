// SQL Pulse — schema & data diff between two catalogs (local). Ported from diff.js.
import 'models.dart';

class ColDiff {
  final String name;
  final String status; // added | removed | changed | same
  final String? a;
  final String? b;
  ColDiff(this.name, this.status, this.a, this.b);
}

class TableDiff {
  final String name;
  final String status; // added | removed | changed | rows | same
  final List<ColDiff> cols;
  final int? rowsA;
  final int? rowsB;
  TableDiff(this.name, this.status, this.cols, this.rowsA, this.rowsB);
}

class DiffSummary {
  final int added, removed, changed, rows, same;
  DiffSummary(this.added, this.removed, this.changed, this.rows, this.same);
}

class CatalogDiff {
  final List<TableDiff> tables;
  final DiffSummary summary;
  CatalogDiff(this.tables, this.summary);
}

String _sig(ColumnDef c) =>
    '${c.type}${c.pk ? ' PK' : ''}${c.nullable ? '' : ' NOT NULL'}${c.ai ? ' AI' : ''}${c.fkTable != null ? ' FK→${c.fkTable}' : ''}';

CatalogDiff diffCatalogs(Catalog a, Catalog b) {
  final aT = a.tables, bT = b.tables;
  final names = {...aT.keys, ...bT.keys}.toList()..sort();
  final tables = names.map((name) {
    final ta = aT[name], tb = bT[name];
    if (ta != null && tb == null) {
      return TableDiff(name, 'removed', [], ta.rows.length, null);
    }
    if (ta == null && tb != null) {
      return TableDiff(name, 'added', [], null, tb.rows.length);
    }
    final colNames = {...ta!.columns.map((c) => c.name), ...tb!.columns.map((c) => c.name)};
    final cols = colNames.map((cn) {
      ColumnDef? ca;
      for (final c in ta.columns) {
        if (c.name == cn) ca = c;
      }
      ColumnDef? cb;
      for (final c in tb.columns) {
        if (c.name == cn) cb = c;
      }
      if (ca != null && cb == null) return ColDiff(cn, 'removed', _sig(ca), null);
      if (ca == null && cb != null) return ColDiff(cn, 'added', null, _sig(cb));
      final changed = _sig(ca!) != _sig(cb!);
      return ColDiff(cn, changed ? 'changed' : 'same', _sig(ca), _sig(cb));
    }).toList();
    final colDiffs = cols.where((c) => c.status != 'same').length;
    final status = colDiffs > 0
        ? 'changed'
        : (ta.rows.length != tb.rows.length ? 'rows' : 'same');
    return TableDiff(name, status, cols, ta.rows.length, tb.rows.length);
  }).toList();
  final summary = DiffSummary(
    tables.where((t) => t.status == 'added').length,
    tables.where((t) => t.status == 'removed').length,
    tables.where((t) => t.status == 'changed').length,
    tables.where((t) => t.status == 'rows').length,
    tables.where((t) => t.status == 'same').length,
  );
  return CatalogDiff(tables, summary);
}

class RowDiffEntry {
  final String key;
  final String status; // added | removed | changed
  final RowMap? a;
  final RowMap? b;
  final List<String> changedCols;
  RowDiffEntry(this.key, this.status, this.a, this.b, [this.changedCols = const []]);
}

class RowDiff {
  final String pk;
  final List<String> cols;
  final List<RowDiffEntry> rows;
  RowDiff(this.pk, this.cols, this.rows);
}

RowDiff diffRows(TableDef ta, TableDef tb) {
  final pkCol = ta.columns.firstWhere((c) => c.pk, orElse: () => ta.columns.first);
  final pk = pkCol.name;
  final byKeyA = {for (final r in ta.rows) '${r[pk]}': r};
  final byKeyB = {for (final r in tb.rows) '${r[pk]}': r};
  final keys = {...byKeyA.keys, ...byKeyB.keys};
  final cols = ta.columns.map((c) => c.name).toList();
  final rows = <RowDiffEntry>[];
  for (final k in keys) {
    final ra = byKeyA[k], rb = byKeyB[k];
    if (ra != null && rb == null) {
      rows.add(RowDiffEntry(k, 'removed', ra, null));
    } else if (ra == null && rb != null) {
      rows.add(RowDiffEntry(k, 'added', null, rb));
    } else {
      final changedCols = cols.where((c) => '${ra![c]}' != '${rb![c]}').toList();
      if (changedCols.isNotEmpty) {
        rows.add(RowDiffEntry(k, 'changed', ra, rb, changedCols));
      }
    }
  }
  return RowDiff(pk, cols, rows);
}
