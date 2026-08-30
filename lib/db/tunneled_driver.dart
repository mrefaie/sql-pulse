// SQL Pulse — driver decorator that adds a real SSH tunnel.
//
// Wraps any real [DbDriver]. If the profile has SSH enabled, it opens an SSH
// local port-forward (see ssh_tunnel.dart) and connects the inner driver to the
// loopback end of the tunnel instead of the real host; everything else is
// delegated unchanged. Closing tears the tunnel down too.
//
// Native only (the tunnel uses dart:io). The web build proxies to the backend,
// which wraps its drivers the same way.
import '../data/models.dart';
import 'db_driver.dart';
import 'ssh_tunnel.dart';

class TunneledDriver extends DbDriver {
  final DbDriver _inner;
  SshTunnel? _tunnel;

  TunneledDriver(this._inner);

  @override
  Future<void> connect(Profile p) async {
    if (!p.ssh) return _inner.connect(p);
    final tunnel = await openSshTunnel(p);
    _tunnel = tunnel;
    // Point the inner driver at the local end of the tunnel.
    final local = p.clone()
      ..host = '127.0.0.1'
      ..port = tunnel.localPort
      ..ssh = false;
    try {
      await _inner.connect(local);
    } catch (e) {
      await tunnel.close();
      _tunnel = null;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _inner.close();
    } finally {
      await _tunnel?.close();
      _tunnel = null;
    }
  }

  @override
  String get serverVersion => _inner.serverVersion;
  @override
  Future<List<String>> listCatalogs() => _inner.listCatalogs();
  @override
  Future<Catalog> introspect(String catalog) => _inner.introspect(catalog);
  @override
  Future<QueryResult> execute(String sql, {String? catalog}) => _inner.execute(sql, catalog: catalog);
  @override
  Future<QueryResult> explain(String sql, {String? catalog}) => _inner.explain(sql, catalog: catalog);
  @override
  Future<List<RowMap>> preview(String catalog, String table, int limit) => _inner.preview(catalog, table, limit);
  @override
  Future<QueryResult?> runTransaction(List<String> stmts, {String? catalog}) => _inner.runTransaction(stmts, catalog: catalog);
}
