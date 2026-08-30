// SQL Pulse — seeds the local Postgres demo database (sqlpulse_demo) from the
// app's own catalog generator (lib/data/seed_data.dart), matching the default
// 'Postgres · Local Docker' profile. Idempotent: drops and recreates objects.
// Run: dart run tool/seed_pg.dart
import 'package:postgres/postgres.dart' as pg;
import 'package:sql_pulse/data/seed_data.dart';
import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/data/engines.dart';

const _host = '127.0.0.1';
const _port = 5432;
const _user = 'postgres';
const _pass = 'pass';
const _db = 'sqlpulse_demo';

/// Seed data uses MySQL-flavored types; map the ones Postgres rejects.
String _pgType(String t) {
  final u = t.toUpperCase();
  if (u.startsWith('TINYINT')) return 'SMALLINT';
  if (u == 'DATETIME') return 'TIMESTAMP';
  return t;
}

String _qval(Object? v) {
  if (v == null) return 'NULL';
  if (v is num) return '$v';
  return "'${v.toString().replaceAll("'", "''")}'";
}

final _dollarTag = RegExp(r'^\$[a-zA-Z_]*\$');

/// Split on ';' outside string literals and $$-quoted bodies (postgres
/// package executes one statement at a time).
List<String> _split(String sql) {
  final out = <String>[];
  var buf = StringBuffer();
  var dollar = false;
  var i = 0;
  while (i < sql.length) {
    final ch = sql[i];
    if (!dollar && ch == "'") {
      buf.write(ch);
      i++;
      while (i < sql.length) {
        buf.write(sql[i]);
        if (sql[i] == "'") {
          if (i + 1 < sql.length && sql[i + 1] == "'") {
            buf.write(sql[i + 1]);
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (ch == r'$') {
      final m = _dollarTag.matchAsPrefix(sql.substring(i));
      if (m != null) {
        dollar = !dollar;
        final tag = m[0]!;
        buf.write(tag);
        i += tag.length;
        continue;
      }
    }
    if (!dollar && ch == ';') {
      out.add(buf.toString());
      buf = StringBuffer();
      i++;
      continue;
    }
    buf.write(ch);
    i++;
  }
  out.add(buf.toString());
  return out;
}

Future<void> execAll(pg.Connection c, String sql) async {
  for (final stmt in _split(sql)) {
    final s = stmt.trim();
    if (s.isNotEmpty) await c.execute(s);
  }
}

Future<void> main() async {
  Future<pg.Connection> open(String db) => pg.Connection.open(
        pg.Endpoint(host: _host, port: _port, database: db, username: _user, password: _pass),
        settings: pg.ConnectionSettings(sslMode: pg.SslMode.disable),
      );

  final admin = await open('postgres');
  final exists = await admin.execute("SELECT 1 FROM pg_database WHERE datname = '$_db'");
  if (exists.isEmpty) {
    await admin.execute('CREATE DATABASE $_db OWNER $_user');
    print('created database $_db');
  }
  await admin.close();

  final conn = await open(_db);

  final cat = buildCatalogs()['e_commerce']!;

  // tables (FK order: referenced tables first)
  final order = [
    'users', 'categories', 'suppliers', 'products', 'addresses',
    'payments', 'orders', 'order_items', 'reviews',
  ];
  for (final name in order) {
    final t = cat.tables[name]!;
    final cols = t.columns.map((c) => ColumnDef(
          name: c.name,
          type: _pgType(c.type),
          pk: c.pk,
          nullable: c.nullable,
          ai: c.ai,
          fkTable: c.fkTable,
          fkCol: c.fkCol,
          def: c.def,
        )).toList();
    final ddl = createTableSql(name, cols, t.indexes, 'postgres');
    await execAll(conn, 'DROP TABLE IF EXISTS "$name" CASCADE;\n$ddl');
  }
  print('created ${order.length} tables');

  // rows
  for (final name in order) {
    final t = cat.tables[name]!;
    for (final r in t.rows) {
      final cols = t.columns.map((c) => '"${c.name}"').join(', ');
      final vals = t.columns.map((c) => _qval(r[c.name])).join(', ');
      await conn.execute('INSERT INTO "$name" ($cols) VALUES ($vals)');
    }
  }
  print('inserted rows');
  // fix serial sequences (seed inserts explicit ids; leave nextval past the max)
  for (final name in order) {
    final t = cat.tables[name]!;
    for (final c in t.columns.where((c) => c.ai)) {
      await conn.execute(
          "SELECT setval(pg_get_serial_sequence('$name', '${c.name}'), (SELECT max(${c.name}) FROM $name), true)");
    }
  }
  print('sequences synchronized');

  // views (v_top_rated uses a MySQL-only alias in HAVING; Postgres needs COUNT)
  const pgViewOverrides = {
    'v_top_rated':
        "CREATE VIEW v_top_rated AS\nSELECT p.name, AVG(r.rating) avg_rating, COUNT(*) reviews\n"
            "FROM products p JOIN reviews r ON p.product_id = r.product_id\n"
            'GROUP BY p.name HAVING COUNT(*) > 3;',
  };
  for (final v in cat.views) {
    final def = pgViewOverrides[v['name']] ?? v['definition'] as String;
    await execAll(conn, 'DROP VIEW IF EXISTS "${v['name']}" CASCADE;\n$def');
  }
  print('created ${cat.views.length} views');

  // functions (plpgsql equivalents of the MySQL definitions)
  await execAll(conn, r'''
CREATE OR REPLACE FUNCTION GetDiscountMultiplier(user_role VARCHAR(20))
RETURNS numeric(3,2) LANGUAGE plpgsql AS $$
BEGIN
  IF user_role = 'VIP' THEN RETURN 0.90; ELSE RETURN 1.00; END IF;
END;$$''');
  await execAll(conn, r'''
CREATE OR REPLACE FUNCTION OrderItemCount(o_id INT)
RETURNS INT LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT COUNT(*) FROM order_items WHERE order_id = o_id);
END;$$''');

  // procedures
  await execAll(conn, r'''
CREATE OR REPLACE PROCEDURE CalculateTotalSales()
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM SUM(total_amount) FROM orders;
END;$$''');
  await execAll(conn, r'''
CREATE OR REPLACE PROCEDURE UpdateProductStock(p_id INT, qty INT)
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE products SET stock = stock - qty WHERE product_id = p_id;
END;$$''');
  await execAll(conn, r'''
CREATE OR REPLACE PROCEDURE ArchiveDormantUsers()
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE users SET status = 'Archived' WHERE status = 'Dormant';
END;$$''');

  // triggers
  await execAll(conn, r'''
CREATE OR REPLACE FUNCTION fn_after_order_item_inserted() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE products SET stock = stock - NEW.quantity WHERE product_id = NEW.product_id;
  RETURN NEW;
END;$$''');
  await execAll(conn, 'DROP TRIGGER IF EXISTS after_order_item_inserted ON order_items;\n'
      "CREATE TRIGGER after_order_item_inserted AFTER INSERT ON order_items "
      'FOR EACH ROW EXECUTE FUNCTION fn_after_order_item_inserted();');
  await execAll(conn, r'''
CREATE OR REPLACE FUNCTION fn_before_review_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.rating > 5 THEN NEW.rating := 5; END IF;
  RETURN NEW;
END;$$''');
  await execAll(conn, 'DROP TRIGGER IF EXISTS before_review_insert ON reviews;\n'
      "CREATE TRIGGER before_review_insert BEFORE INSERT ON reviews "
      'FOR EACH ROW EXECUTE FUNCTION fn_before_review_insert();');

  await conn.close();
  print('seeded $_db OK');
}
