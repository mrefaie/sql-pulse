// SQL Pulse — web driver: proxies all DB work to the backend API over HTTP.
// (Browsers can't open raw TCP, so the real drivers run server-side.)
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models.dart';
import 'db_driver.dart';
import 'api_json.dart';

class HttpDriver extends DbDriver {
  String? _session;
  String _version = '';

  @override
  String get serverVersion => _version;

  Uri _u(String path) => Uri.base.resolve(path);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(_u(path), headers: {'content-type': 'application/json'}, body: jsonEncode(body));
    final j = r.body.isNotEmpty ? jsonDecode(r.body) as Map<String, dynamic> : <String, dynamic>{};
    if (r.statusCode >= 400 || j['ok'] == false) {
      throw DbException(j['error'] as String? ?? 'HTTP ${r.statusCode}');
    }
    return j;
  }

  @override
  Future<void> connect(Profile p) async {
    final j = await _post('api/connect', {'profile': p.toJson()});
    _session = j['session'] as String;
    _version = j['version'] as String? ?? '';
  }

  @override
  Future<void> close() async {
    if (_session == null) return;
    try {
      await _post('api/close', {'session': _session});
    } catch (_) {}
    _session = null;
  }

  @override
  Future<List<String>> listCatalogs() async {
    final j = await _post('api/catalogs', {'session': _session});
    return (j['catalogs'] as List).cast<String>();
  }

  @override
  Future<Catalog> introspect(String catalog) async {
    final j = await _post('api/introspect', {'session': _session, 'catalog': catalog});
    return catalogFromJson(j['catalog'] as Map);
  }

  @override
  Future<QueryResult> execute(String sql, {String? catalog}) async {
    final j = await _post('api/execute', {'session': _session, 'sql': sql, 'catalog': catalog});
    return resultFromJson(j['result'] as Map);
  }

  @override
  Future<QueryResult> explain(String sql, {String? catalog}) async {
    final j = await _post('api/explain', {'session': _session, 'sql': sql, 'catalog': catalog});
    return resultFromJson(j['result'] as Map);
  }

  @override
  Future<QueryResult?> runTransaction(List<String> stmts, {String? catalog}) async {
    if (stmts.isEmpty) return null;
    final j = await _post('api/txbatch', {'session': _session, 'stmts': stmts, 'catalog': catalog});
    final res = j['result'];
    return res == null ? null : resultFromJson(res as Map);
  }

  @override
  Future<List<RowMap>> preview(String catalog, String table, int limit) async {
    final j = await _post('api/preview', {'session': _session, 'catalog': catalog, 'table': table, 'limit': limit});
    return rowsFromJson(j['rows'] as List);
  }
}
