// SQL Pulse — backend API + static web host.
// Browsers can't open raw TCP, so the web app proxies DB work here, where the
// real dart:io drivers run and can reach the (Docker) databases.
//
// Run:  dart run bin/server.dart [port]
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:sql_pulse/data/models.dart';
import 'package:sql_pulse/db/db_driver.dart';
import 'package:sql_pulse/db/api_json.dart';
// Only the networked, pure-Dart drivers (no Flutter/path_provider, so `dart run`
// works). SQLite is a local-file engine and isn't exposed over the web API.
import 'package:sql_pulse/db/postgres_driver.dart';
import 'package:sql_pulse/db/mysql_driver.dart';
import 'package:sql_pulse/db/mssql_driver.dart';
import 'package:sql_pulse/db/tunneled_driver.dart';

DbDriver makeServerDriver(String engine) {
  // Wrap in TunneledDriver so SSH-tunnel profiles work over the web too (the
  // browser can't SSH, so the bastion hop happens here, server-side).
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
      throw DbException(
        'SQLite is a local-file engine and is not available over the web. Use the desktop app, or a networked engine (PostgreSQL / MySQL / MariaDB / SQL Server).',
      );
    default:
      return TunneledDriver(PostgresDriver());
  }
}

final Map<String, DbDriver> _sessions = {};
int _seq = 0;

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 8088 : 8088;

  final router = Router();

  Future<Response> handle(
    Request req,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body) fn,
  ) async {
    try {
      final raw = await req.readAsString();
      final body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final out = await fn(body);
      return _json({'ok': true, ...out});
    } catch (e) {
      return _json({
        'ok': false,
        'error': e is DbException ? e.message : e.toString(),
      });
    }
  }

  DbDriver session(Map<String, dynamic> b) {
    final d = _sessions[b['session']];
    if (d == null) throw DbException('Session expired — reconnect.');
    return d;
  }

  router.post(
    '/api/connect',
    (Request r) => handle(r, (b) async {
      final p = Profile.fromJson((b['profile'] as Map).cast<String, dynamic>());
      final d = makeServerDriver(p.engine);
      await d.connect(p);
      final id = 's${_seq++}_${DateTime.now().microsecondsSinceEpoch}';
      _sessions[id] = d;
      return {'session': id, 'version': d.serverVersion};
    }),
  );

  router.post(
    '/api/catalogs',
    (Request r) => handle(r, (b) async {
      return {'catalogs': await session(b).listCatalogs()};
    }),
  );

  router.post(
    '/api/introspect',
    (Request r) => handle(r, (b) async {
      final cat = await session(b).introspect(b['catalog'] as String);
      return {'catalog': catalogToJson(cat)};
    }),
  );

  router.post(
    '/api/execute',
    (Request r) => handle(r, (b) async {
      final res = await session(
        b,
      ).execute(b['sql'] as String, catalog: b['catalog'] as String?);
      return {'result': resultToJson(res)};
    }),
  );

  router.post(
    '/api/explain',
    (Request r) => handle(r, (b) async {
      final res = await session(
        b,
      ).explain(b['sql'] as String, catalog: b['catalog'] as String?);
      return {'result': resultToJson(res)};
    }),
  );

  router.post(
    '/api/txbatch',
    (Request r) => handle(r, (b) async {
      final stmts = (b['stmts'] as List).cast<String>();
      final res = await session(
        b,
      ).runTransaction(stmts, catalog: b['catalog'] as String?);
      return {'result': res == null ? null : resultToJson(res)};
    }),
  );

  router.post(
    '/api/preview',
    (Request r) => handle(r, (b) async {
      final rows = await session(b).preview(
        b['catalog'] as String,
        b['table'] as String,
        (b['limit'] as num?)?.toInt() ?? 60,
        orderBy: (b['orderBy'] as List?)?.cast<String>() ?? const [],
      );
      return {'rows': rows};
    }),
  );

  router.post(
    '/api/close',
    (Request r) => handle(r, (b) async {
      final d = _sessions.remove(b['session']);
      await d?.close();
      return {};
    }),
  );

  router.get(
    '/api/health',
    (Request r) => _json({'ok': true, 'sessions': _sessions.length}),
  );

  // static web build (Flutter)
  final webDir = Directory('build/web');
  final staticHandler = webDir.existsSync()
      ? createStaticHandler('build/web', defaultDocument: 'index.html')
      : (Request r) => Response.notFound('Run `flutter build web` first.');

  // SPA fallback: unknown non-API GET paths serve index.html
  Handler spa(Handler next) => (Request req) async {
    final res = await next(req);
    if (res.statusCode == 404 &&
        req.method == 'GET' &&
        !req.url.path.startsWith('api/')) {
      return createStaticHandler('build/web', defaultDocument: 'index.html')(
        req.change(path: ''),
      );
    }
    return res;
  };

  final cascade = Cascade().add(router.call).add(staticHandler);

  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(_log())
      .addHandler(spa(cascade.handler));

  // NOTE: do NOT enable server.autoCompress — shelf_static keeps the
  // uncompressed Content-Length, which then mismatches the gzipped body and
  // makes browsers stall on large assets (main.dart.js). cloudflared compresses
  // at the edge with correct headers instead.
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'SQL Pulse server on http://0.0.0.0:${server.port}  (web: ${webDir.existsSync() ? 'ready' : 'MISSING build/web'})',
  );
}

Response _json(Map<String, dynamic> body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

Middleware _cors() =>
    (Handler inner) => (Request req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await inner(req);
      return res.change(headers: {...res.headers, ..._corsHeaders});
    };

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};

Middleware _log() =>
    (Handler inner) => (Request req) async {
      final res = await inner(req);
      if (req.url.path.startsWith('api/')) {
        stdout.writeln('${req.method} /${req.url.path} -> ${res.statusCode}');
      }
      return res;
    };
