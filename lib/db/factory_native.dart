// SQL Pulse — native driver factory (desktop/mobile/server; uses dart:io drivers).
import 'db_driver.dart';
import 'postgres_driver.dart';
import 'mysql_driver.dart';
import 'sqlite_driver.dart';
import 'mssql_driver.dart';
import 'tunneled_driver.dart';

DbDriver makeDriver(String engine) {
  switch (engine) {
    case 'postgres':
      return TunneledDriver(PostgresDriver());
    case 'mysql':
      return TunneledDriver(MySqlDriver());
    case 'mariadb':
      return TunneledDriver(MySqlDriver(maria: true));
    case 'mssql':
      return TunneledDriver(MssqlDriver());
    case 'sqlite':
      return SqliteDriver(); // local file — no tunnel
    default:
      return TunneledDriver(PostgresDriver());
  }
}
