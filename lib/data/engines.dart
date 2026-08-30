// SQL Pulse — engine registry (MySQL · MariaDB · PostgreSQL · SQL Server · SQLite)
// Pure data + dialect helpers. Ported from engines.js.
import 'models.dart';

/// A schema-driven option field descriptor used by the connection editor.
class OptField {
  final String key;
  final String label;
  final String? hint;
  final String type; // text | password | number | chips | file | toggle
  final List<String> options;
  final bool mono;
  final bool half;
  final String? sub;
  final String? placeholder;
  final String? accept;
  final bool Function(Map<String, Object?>)? showIf;
  OptField({
    required this.key,
    this.label = '',
    this.hint,
    this.type = 'text',
    this.options = const [],
    this.mono = false,
    this.half = false,
    this.sub,
    this.placeholder,
    this.accept,
    this.showIf,
  });
}

/// A group of toggles in the advanced section.
class OptGroup {
  final List<OptField> items;
  OptGroup(this.items);
}

class TlsSpec {
  final String title;
  final String toggleLabel;
  final String? modeKey;
  final List<String> modes;
  final bool modeMono;
  final String? toggleKey;
  final List<OptField> extraToggles;
  final List<OptField> files;
  TlsSpec({
    required this.title,
    required this.toggleLabel,
    this.modeKey,
    this.modes = const [],
    this.modeMono = false,
    this.toggleKey,
    this.extraToggles = const [],
    this.files = const [],
  });
}

class EngineDef {
  final String id;
  final String label;
  final String short;
  final int color; // 0xFFRRGGBB
  final int port;
  final List<String> q; // open/close quote
  final String limitStyle; // limit | top
  final String serverVersion;
  final String schemaTerm;
  final String identifierTip;
  final bool fileBased;
  final List<String> types;
  final String? aiKeyword;
  final String? aiType;
  final Map<String, String> objectLabels;
  final List<List<String>> snippets; // [label, sql]
  final Map<String, Object?> defaults;
  final List<OptField> auth;
  final TlsSpec? tls;
  final bool noSsh;
  final List<Object> advanced; // OptField | OptGroup

  EngineDef({
    required this.id,
    required this.label,
    required this.short,
    required this.color,
    required this.port,
    required this.q,
    required this.limitStyle,
    required this.serverVersion,
    required this.schemaTerm,
    required this.identifierTip,
    this.fileBased = false,
    required this.types,
    this.aiKeyword,
    this.aiType,
    required this.objectLabels,
    required this.snippets,
    required this.defaults,
    this.auth = const [],
    this.tls,
    this.noSsh = false,
    this.advanced = const [],
  });
}

const Map<String, Object?> kSharedDefaults = {
  'password': '',
  'sshHost': '', 'sshPort': 22, 'sshUser': '', 'sshAuth': 'key',
  'sshKeyFile': '', 'sshPassphrase': '', 'sshKnownHosts': '~/.ssh/known_hosts',
  'caFile': '', 'certFile': '', 'keyFile': '', 'readOnly': false,
};

final Map<String, EngineDef> kEngines = {
  'mysql': EngineDef(
    id: 'mysql', label: 'MySQL', short: 'MySQL', color: 0xFF0E7C99,
    port: 3306, q: ['`', '`'], limitStyle: 'limit', serverVersion: 'MySQL 8.0.36',
    schemaTerm: 'database', identifierTip: 'backtick',
    types: ['INT', 'BIGINT', 'TINYINT(1)', 'DECIMAL(10,2)', 'DOUBLE', 'VARCHAR(255)', 'CHAR(2)', 'TEXT', 'DATE', 'DATETIME', 'TIMESTAMP', 'JSON', 'BLOB'],
    aiKeyword: 'AUTO_INCREMENT',
    objectLabels: {'tables': 'Tables', 'views': 'Views', 'procedures': 'Procedures', 'functions': 'Functions', 'triggers': 'Triggers'},
    snippets: [
      ['SELECT *', 'SELECT * FROM users LIMIT 10;'],
      ['JOIN', 'SELECT u.username, o.total_amount\nFROM users u\nJOIN orders o ON u.id = o.user_id;'],
      ['SHOW TABLES', 'SHOW TABLES;'],
      ['DESCRIBE', 'DESCRIBE users;'],
      ['CREATE VIEW', "CREATE VIEW v_active AS SELECT * FROM users WHERE role = 'Customer';"],
    ],
    defaults: {'authPlugin': 'caching_sha2_password', 'sslMode': 'PREFERRED', 'timeout': 30, 'maxPacket': 64, 'charset': 'utf8mb4', 'collation': 'utf8mb4_0900_ai_ci', 'timezone': 'SYSTEM', 'sqlMode': 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION', 'compression': false, 'keepAlive': true, 'autoReconnect': true, 'multiStatements': false},
    auth: [
      OptField(key: 'password', label: 'Password', type: 'password', hint: 'stored in keychain', placeholder: '••••••••'),
      OptField(key: 'authPlugin', label: 'Auth plugin', type: 'chips', options: ['caching_sha2_password', 'mysql_native_password', 'sha256_password'], mono: true),
    ],
    tls: TlsSpec(
      title: 'SSL / TLS', toggleLabel: 'Encrypt connection with TLS',
      modeKey: 'sslMode', modes: ['DISABLED', 'PREFERRED', 'REQUIRED', 'VERIFY_CA', 'VERIFY_IDENTITY'],
      files: [
        OptField(key: 'caFile', label: 'CA certificate', type: 'file', accept: '.pem,.crt,.cert'),
        OptField(key: 'certFile', label: 'Client certificate', type: 'file', hint: 'for mutual TLS', accept: '.pem,.crt,.cert'),
        OptField(key: 'keyFile', label: 'Client key', type: 'file', accept: '.pem,.key'),
      ],
    ),
    advanced: [
      OptField(key: 'timeout', label: 'Timeout', hint: 'sec', type: 'number', half: true),
      OptField(key: 'maxPacket', label: 'Max packet', hint: 'MB', type: 'number', half: true),
      OptField(key: 'charset', label: 'Charset', type: 'chips', options: ['utf8mb4', 'utf8', 'latin1', 'ascii'], mono: true),
      OptField(key: 'collation', label: 'Collation', type: 'text'),
      OptField(key: 'timezone', label: 'Time zone', type: 'text', placeholder: 'SYSTEM / +00:00'),
      OptField(key: 'sqlMode', label: 'SQL mode', type: 'text'),
      OptGroup([
        OptField(key: 'compression', label: 'Compression', sub: 'zlib wire protocol', type: 'toggle'),
        OptField(key: 'keepAlive', label: 'Keep-alive', sub: 'TCP keep-alive packets', type: 'toggle'),
        OptField(key: 'autoReconnect', label: 'Auto-reconnect', type: 'toggle'),
        OptField(key: 'readOnly', label: 'Read-only session', sub: 'block writes & DDL', type: 'toggle'),
        OptField(key: 'multiStatements', label: 'Allow multi-statements', sub: 'run ; separated batches', type: 'toggle'),
      ]),
    ],
  ),
  'postgres': EngineDef(
    id: 'postgres', label: 'PostgreSQL', short: 'Postgres', color: 0xFF3E6FA6,
    port: 5432, q: ['"', '"'], limitStyle: 'limit', serverVersion: 'PostgreSQL 16.2',
    schemaTerm: 'schema', identifierTip: 'double-quote',
    types: ['integer', 'bigint', 'smallint', 'numeric(10,2)', 'double precision', 'varchar(255)', 'char(2)', 'text', 'boolean', 'date', 'timestamp', 'timestamptz', 'jsonb', 'uuid'],
    aiType: 'serial',
    objectLabels: {'tables': 'Tables', 'views': 'Views', 'procedures': 'Routines', 'functions': 'Functions', 'triggers': 'Triggers'},
    snippets: [
      ['SELECT *', 'SELECT * FROM users LIMIT 10;'],
      ['JOIN', 'SELECT u.username, o.total_amount\nFROM users u\nJOIN orders o ON u.id = o.user_id;'],
      ['\\dt tables', "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = 'public';"],
      ['columns', "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users';"],
      ['CREATE VIEW', "CREATE VIEW v_active AS SELECT * FROM users WHERE role = 'Customer';"],
    ],
    defaults: {'authMethod': 'scram-sha-256', 'pgSslMode': 'prefer', 'searchPath': 'public', 'appName': 'sql_pulse', 'statementTimeout': 0, 'connectTimeout': 10, 'targetSession': 'any', 'sslCompression': false, 'keepAlive': true},
    auth: [
      OptField(key: 'password', label: 'Password', type: 'password', hint: 'stored in keychain', placeholder: '••••••••'),
      OptField(key: 'authMethod', label: 'Auth method', type: 'chips', options: ['scram-sha-256', 'md5', 'password', 'peer'], mono: true),
    ],
    tls: TlsSpec(
      title: 'SSL', toggleLabel: 'Use SSL connection',
      modeKey: 'pgSslMode', modes: ['disable', 'allow', 'prefer', 'require', 'verify-ca', 'verify-full'], modeMono: true,
      files: [
        OptField(key: 'caFile', label: 'Root certificate', type: 'file', hint: 'sslrootcert', accept: '.pem,.crt'),
        OptField(key: 'certFile', label: 'Client certificate', type: 'file', hint: 'sslcert', accept: '.pem,.crt'),
        OptField(key: 'keyFile', label: 'Client key', type: 'file', hint: 'sslkey', accept: '.pem,.key'),
      ],
    ),
    advanced: [
      OptField(key: 'searchPath', label: 'Schema search_path', type: 'text', placeholder: 'public'),
      OptField(key: 'appName', label: 'application_name', type: 'text', placeholder: 'sql_pulse'),
      OptField(key: 'statementTimeout', label: 'statement_timeout', hint: 'ms · 0 = off', type: 'number', half: true),
      OptField(key: 'connectTimeout', label: 'connect_timeout', hint: 'sec', type: 'number', half: true),
      OptField(key: 'targetSession', label: 'target_session_attrs', type: 'chips', options: ['any', 'read-write', 'read-only'], mono: true),
      OptGroup([
        OptField(key: 'sslCompression', label: 'SSL compression', type: 'toggle'),
        OptField(key: 'keepAlive', label: 'TCP keep-alive', type: 'toggle'),
        OptField(key: 'readOnly', label: 'Read-only session', sub: 'default_transaction_read_only', type: 'toggle'),
      ]),
    ],
  ),
  'mssql': EngineDef(
    id: 'mssql', label: 'SQL Server', short: 'MSSQL', color: 0xFFC0392F,
    port: 1433, q: ['[', ']'], limitStyle: 'top', serverVersion: 'Microsoft SQL Server 2022 (16.0)',
    schemaTerm: 'database', identifierTip: 'bracket',
    types: ['INT', 'BIGINT', 'TINYINT', 'DECIMAL(10,2)', 'FLOAT', 'NVARCHAR(255)', 'VARCHAR(255)', 'NCHAR(2)', 'NTEXT', 'BIT', 'DATE', 'DATETIME2', 'UNIQUEIDENTIFIER'],
    aiKeyword: 'IDENTITY(1,1)',
    objectLabels: {'tables': 'Tables', 'views': 'Views', 'procedures': 'Stored procedures', 'functions': 'Functions', 'triggers': 'Triggers'},
    snippets: [
      ['SELECT TOP', 'SELECT TOP 10 * FROM users;'],
      ['JOIN', 'SELECT u.username, o.total_amount\nFROM users u\nJOIN orders o ON u.id = o.user_id;'],
      ['sys.tables', 'SELECT name FROM sys.tables ORDER BY name;'],
      ['sp_help', "EXEC sp_help 'users';"],
      ['paging', 'SELECT * FROM users\nORDER BY id\nOFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;'],
    ],
    defaults: {'mssqlAuth': 'SQL Login', 'domain': '', 'encrypt': true, 'trustServerCert': false, 'instance': '', 'appIntent': 'ReadWrite', 'connectTimeout': 15, 'requestTimeout': 30, 'appName': 'SQL Pulse', 'multiSubnet': false, 'mars': false},
    auth: [
      OptField(key: 'mssqlAuth', label: 'Authentication', type: 'chips', options: ['SQL Login', 'Windows (Integrated)', 'Azure AD Password', 'Azure AD MFA']),
      OptField(key: 'domain', label: 'Domain', hint: 'Windows auth', type: 'text', placeholder: 'CORP', showIf: (o) => o['mssqlAuth'] == 'Windows (Integrated)'),
      OptField(key: 'password', label: 'Password', type: 'password', placeholder: '••••••••', showIf: (o) => o['mssqlAuth'] != 'Windows (Integrated)' && o['mssqlAuth'] != 'Azure AD MFA'),
    ],
    tls: TlsSpec(
      title: 'Encryption', toggleLabel: 'Encrypt connection',
      toggleKey: 'encrypt',
      extraToggles: [OptField(key: 'trustServerCert', label: 'Trust server certificate', sub: 'skip CA validation — dev only')],
      files: [OptField(key: 'caFile', label: 'CA certificate', type: 'file', accept: '.pem,.crt,.cer')],
    ),
    advanced: [
      OptField(key: 'instance', label: 'Instance name', hint: 'optional', type: 'text', placeholder: 'SQLEXPRESS'),
      OptField(key: 'appIntent', label: 'ApplicationIntent', type: 'chips', options: ['ReadWrite', 'ReadOnly']),
      OptField(key: 'connectTimeout', label: 'Connect timeout', hint: 'sec', type: 'number', half: true),
      OptField(key: 'requestTimeout', label: 'Request timeout', hint: 'sec', type: 'number', half: true),
      OptField(key: 'appName', label: 'Application name', type: 'text', placeholder: 'SQL Pulse'),
      OptGroup([
        OptField(key: 'multiSubnet', label: 'MultiSubnetFailover', sub: 'AlwaysOn listeners', type: 'toggle'),
        OptField(key: 'mars', label: 'Multiple Active Result Sets', sub: 'MARS', type: 'toggle'),
        OptField(key: 'readOnly', label: 'Read-only intent', type: 'toggle'),
      ]),
    ],
  ),
  'mariadb': EngineDef(
    id: 'mariadb', label: 'MariaDB', short: 'MariaDB', color: 0xFFA4583A,
    port: 3306, q: ['`', '`'], limitStyle: 'limit', serverVersion: 'MariaDB 11.4.2',
    schemaTerm: 'database', identifierTip: 'backtick',
    types: ['INT', 'BIGINT', 'TINYINT(1)', 'DECIMAL(10,2)', 'DOUBLE', 'VARCHAR(255)', 'CHAR(2)', 'TEXT', 'DATE', 'DATETIME', 'TIMESTAMP', 'JSON', 'UUID', 'BLOB'],
    aiKeyword: 'AUTO_INCREMENT',
    objectLabels: {'tables': 'Tables', 'views': 'Views', 'procedures': 'Procedures', 'functions': 'Functions', 'triggers': 'Triggers'},
    snippets: [
      ['SELECT *', 'SELECT * FROM users LIMIT 10;'],
      ['JOIN', 'SELECT u.username, o.total_amount\nFROM users u\nJOIN orders o ON u.id = o.user_id;'],
      ['SHOW TABLES', 'SHOW TABLES;'],
      ['DESCRIBE', 'DESCRIBE users;'],
      ['RETURNING', "INSERT INTO users (username) VALUES ('neo') RETURNING id;"],
    ],
    defaults: {'authPlugin': 'mysql_native_password', 'sslMode': 'PREFERRED', 'timeout': 30, 'maxPacket': 64, 'charset': 'utf8mb4', 'collation': 'utf8mb4_uca1400_ai_ci', 'timezone': 'SYSTEM', 'sqlMode': 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO', 'compression': false, 'keepAlive': true, 'autoReconnect': true, 'multiStatements': false},
    auth: [
      OptField(key: 'password', label: 'Password', type: 'password', hint: 'stored in keychain', placeholder: '••••••••'),
      OptField(key: 'authPlugin', label: 'Auth plugin', type: 'chips', options: ['mysql_native_password', 'ed25519', 'gssapi', 'pam'], mono: true),
    ],
    tls: TlsSpec(
      title: 'SSL / TLS', toggleLabel: 'Encrypt connection with TLS',
      modeKey: 'sslMode', modes: ['DISABLED', 'PREFERRED', 'REQUIRED', 'VERIFY_CA', 'VERIFY_IDENTITY'],
      files: [
        OptField(key: 'caFile', label: 'CA certificate', type: 'file', accept: '.pem,.crt,.cert'),
        OptField(key: 'certFile', label: 'Client certificate', type: 'file', hint: 'for mutual TLS', accept: '.pem,.crt,.cert'),
        OptField(key: 'keyFile', label: 'Client key', type: 'file', accept: '.pem,.key'),
      ],
    ),
    advanced: [
      OptField(key: 'timeout', label: 'Timeout', hint: 'sec', type: 'number', half: true),
      OptField(key: 'maxPacket', label: 'Max packet', hint: 'MB', type: 'number', half: true),
      OptField(key: 'charset', label: 'Charset', type: 'chips', options: ['utf8mb4', 'utf8', 'latin1', 'ascii'], mono: true),
      OptField(key: 'collation', label: 'Collation', type: 'text'),
      OptField(key: 'timezone', label: 'Time zone', type: 'text', placeholder: 'SYSTEM / +00:00'),
      OptField(key: 'sqlMode', label: 'SQL mode', type: 'text'),
      OptGroup([
        OptField(key: 'compression', label: 'Compression', sub: 'zlib wire protocol', type: 'toggle'),
        OptField(key: 'keepAlive', label: 'Keep-alive', sub: 'TCP keep-alive packets', type: 'toggle'),
        OptField(key: 'autoReconnect', label: 'Auto-reconnect', type: 'toggle'),
        OptField(key: 'readOnly', label: 'Read-only session', sub: 'block writes & DDL', type: 'toggle'),
        OptField(key: 'multiStatements', label: 'Allow multi-statements', sub: 'run ; separated batches', type: 'toggle'),
      ]),
    ],
  ),
  'sqlite': EngineDef(
    id: 'sqlite', label: 'SQLite', short: 'SQLite', color: 0xFF1F7FC4,
    port: 0, q: ['"', '"'], limitStyle: 'limit', serverVersion: 'SQLite 3.45.1',
    schemaTerm: 'database', identifierTip: 'double-quote', fileBased: true,
    types: ['INTEGER', 'REAL', 'TEXT', 'NUMERIC', 'BLOB', 'BOOLEAN', 'DATE', 'DATETIME'],
    aiKeyword: 'AUTOINCREMENT',
    objectLabels: {'tables': 'Tables', 'views': 'Views', 'procedures': '—', 'functions': '—', 'triggers': 'Triggers'},
    snippets: [
      ['SELECT *', 'SELECT * FROM users LIMIT 10;'],
      ['JOIN', 'SELECT u.username, o.total_amount\nFROM users u\nJOIN orders o ON u.id = o.user_id;'],
      ['tables', "SELECT name FROM sqlite_master WHERE type = 'table';"],
      ['schema', "SELECT sql FROM sqlite_master WHERE name = 'users';"],
      ['PRAGMA', 'PRAGMA table_info(users);'],
    ],
    defaults: {'dbFile': '', 'journalMode': 'WAL', 'busyTimeout': 5000, 'foreignKeys': true, 'readOnly': false},
    auth: [],
    tls: null,
    noSsh: true,
    advanced: [
      OptField(key: 'journalMode', label: 'Journal mode', type: 'chips', options: ['DELETE', 'WAL', 'MEMORY', 'TRUNCATE'], mono: true),
      OptField(key: 'busyTimeout', label: 'Busy timeout', hint: 'ms', type: 'number'),
      OptGroup([
        OptField(key: 'foreignKeys', label: 'Enforce foreign keys', sub: 'PRAGMA foreign_keys = ON', type: 'toggle'),
        OptField(key: 'readOnly', label: 'Open read-only', sub: 'immutable / query-only', type: 'toggle'),
      ]),
    ],
  ),
};

const List<String> kEngineOrder = ['mysql', 'mariadb', 'postgres', 'mssql', 'sqlite'];

EngineDef eng(String? id) => kEngines[id] ?? kEngines['mysql']!;

Map<String, Object?> defaultsFor(String id) =>
    {...kSharedDefaults, ...eng(id).defaults};

String quoteId(String id, String engineId) {
  final e = eng(engineId);
  if (id == '*') return '*';
  return e.q[0] + id + e.q[1];
}

String quoteCol(String table, String col, bool qualify, String engineId) {
  if (col == '*') return qualify ? '${quoteId(table, engineId)}.*' : '*';
  return qualify
      ? '${quoteId(table, engineId)}.${quoteId(col, engineId)}'
      : quoteId(col, engineId);
}

// ---- DDL generation (CREATE / ALTER) ----
String _colSql(ColumnDef c, String engineId) {
  final e = eng(engineId);
  String q(String id) => quoteId(id, engineId);
  var type = c.type;
  if (c.ai && e.aiType == 'serial') {
    type = RegExp(r'bigint', caseSensitive: false).hasMatch(c.type) ? 'bigserial' : 'serial';
  }
  var s = '${q(c.name)} $type';
  if (c.ai && e.aiKeyword != null) s += ' ${e.aiKeyword}';
  s += c.nullable ? ' NULL' : ' NOT NULL';
  if (c.def.isNotEmpty) {
    s += ' DEFAULT ${RegExp(r'^-?\d+(\.\d+)?$').hasMatch(c.def) ? c.def : "'${c.def}'"}';
  }
  return s;
}

String createTableSql(String name, List<ColumnDef> cols, List<IndexDef> indexes, String engineId) {
  String q(String id) => quoteId(id, engineId);
  final lines = cols.map((c) => '  ${_colSql(c, engineId)}').toList();
  final pks = cols.where((c) => c.pk).map((c) => q(c.name)).toList();
  if (pks.isNotEmpty) lines.add('  PRIMARY KEY (${pks.join(', ')})');
  for (final c in cols.where((c) => c.fkTable != null && c.fkTable!.isNotEmpty)) {
    lines.add('  FOREIGN KEY (${q(c.name)}) REFERENCES ${q(c.fkTable!)} (${q(c.fkCol ?? 'id')})');
  }
  for (final ix in indexes.where((ix) => ix.unique)) {
    lines.add('  UNIQUE (${ix.columns.map(q).join(', ')})');
  }
  var sql = 'CREATE TABLE ${q(name)} (\n${lines.join(',\n')}\n);';
  for (final ix in indexes.where((ix) => !ix.unique)) {
    sql += '\nCREATE INDEX ${q(ix.name)} ON ${q(name)} (${ix.columns.map(q).join(', ')});';
  }
  return sql;
}

/// before/after columns carry a synthetic `_id` for stable diffing.
String alterDiffSql(String name, List<ColumnDef> before, List<ColumnDef> after,
    Map<ColumnDef, String> ids, String engineId) {
  String q(String id) => quoteId(id, engineId);
  final e = eng(engineId);
  final out = <String>[];
  String keyOf(ColumnDef c) => ids[c] ?? c.name;
  final byKeyBefore = {for (final c in before) keyOf(c): c};
  for (final b in before) {
    if (!after.any((a) => keyOf(a) == keyOf(b))) {
      out.add('ALTER TABLE ${q(name)} DROP COLUMN ${q(b.name)};');
    }
  }
  for (final a in after) {
    final b = byKeyBefore[keyOf(a)];
    if (b == null) {
      out.add('ALTER TABLE ${q(name)} ADD COLUMN ${_colSql(a, engineId)};');
      continue;
    }
    final renamed = b.name != a.name;
    final changed = renamed || b.type != a.type || b.nullable != a.nullable;
    if (changed) {
      if (e.id == 'postgres') {
        if (renamed) out.add('ALTER TABLE ${q(name)} RENAME COLUMN ${q(b.name)} TO ${q(a.name)};');
        if (b.type != a.type) out.add('ALTER TABLE ${q(name)} ALTER COLUMN ${q(a.name)} TYPE ${a.type};');
        if (b.nullable != a.nullable) {
          out.add('ALTER TABLE ${q(name)} ALTER COLUMN ${q(a.name)} ${a.nullable ? 'DROP NOT NULL' : 'SET NOT NULL'};');
        }
      } else if (e.id == 'mssql') {
        if (renamed) out.add("EXEC sp_rename '$name.${b.name}', '${a.name}', 'COLUMN';");
        out.add('ALTER TABLE ${q(name)} ALTER COLUMN ${_colSql(a, engineId)};');
      } else {
        out.add('ALTER TABLE ${q(name)} CHANGE ${q(b.name)} ${_colSql(a, engineId)};');
      }
    }
  }
  return out.join('\n');
}
