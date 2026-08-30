// Role-based access control: verifies AppState.roleBlock enforces each role's
// contract (the real enforcement now wired into run/runScript/_exec/commit).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sql_pulse/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState s;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    s = AppState();
  });

  String? block(String role, String sql) {
    s.role = role;
    return s.roleBlock(sql);
  }

  test('Admin can run anything', () {
    for (final q in ['SELECT 1', 'INSERT INTO t VALUES (1)', 'DROP TABLE t', 'GRANT ALL TO u', 'CREATE USER x']) {
      expect(block('Admin', q), isNull, reason: q);
    }
  });

  test('ReadOnly allows only reads', () {
    expect(block('ReadOnly', 'SELECT * FROM users'), isNull);
    expect(block('ReadOnly', 'WITH a AS (SELECT 1) SELECT * FROM a'), isNull);
    expect(block('ReadOnly', 'SHOW TABLES'), isNull);
    expect(block('ReadOnly', 'EXPLAIN SELECT 1'), isNull);
    for (final q in ['INSERT INTO t VALUES (1)', 'UPDATE t SET a=1', 'DELETE FROM t', 'DROP TABLE t', 'CREATE TABLE t(a int)', 'TRUNCATE t']) {
      expect(block('ReadOnly', q), isNotNull, reason: q);
    }
    // a write hidden inside a CTE is still blocked
    expect(block('ReadOnly', 'WITH x AS (DELETE FROM t RETURNING *) SELECT * FROM x'), isNotNull);
  });

  test('Analyst allows DML but blocks DDL and grants', () {
    expect(block('Analyst', 'INSERT INTO t VALUES (1)'), isNull);
    expect(block('Analyst', 'UPDATE t SET a=1 WHERE id=2'), isNull);
    expect(block('Analyst', 'DELETE FROM t WHERE id=2'), isNull);
    expect(block('Analyst', 'SELECT * FROM t'), isNull);
    for (final q in ['CREATE TABLE t(a int)', 'ALTER TABLE t ADD b int', 'DROP TABLE t', 'TRUNCATE t', 'GRANT SELECT ON t TO u']) {
      expect(block('Analyst', q), isNotNull, reason: q);
    }
  });

  test('Developer allows DDL+DML but blocks user/permission management', () {
    expect(block('Developer', 'CREATE TABLE t(a int)'), isNull);
    expect(block('Developer', 'ALTER TABLE t ADD b int'), isNull);
    expect(block('Developer', 'INSERT INTO t VALUES (1)'), isNull);
    for (final q in ['GRANT SELECT ON t TO u', 'REVOKE SELECT ON t FROM u', 'CREATE USER bob', 'ALTER ROLE r', 'DROP USER bob']) {
      expect(block('Developer', q), isNotNull, reason: q);
    }
  });
}
