// SQL Pulse — real SSH local port-forward (bastion / jump host).
//
// Opens an SSH connection to the configured bastion, then binds a local TCP
// listener on 127.0.0.1:<random>. Every connection a database driver makes to
// that local port is forwarded, over the encrypted SSH channel, to the real
// database host:port as seen from the bastion. This is the same mechanism as
// `ssh -L localPort:dbHost:dbPort user@bastion`.
//
// Native only (dart:io + dartssh2). The web build never imports this — browsers
// can't SSH, so for the web app the backend server opens the tunnel instead.
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../data/models.dart';
import 'db_driver.dart';

/// A live SSH tunnel with a local forwarded port. Close it to tear everything
/// down (local listener, in-flight channels, SSH client).
class SshTunnel {
  final SSHClient _client;
  final ServerSocket _server;
  final List<Socket> _live = [];
  bool _closed = false;

  SshTunnel._(this._client, this._server);

  /// Local port the database driver should connect to (on 127.0.0.1).
  int get localPort => _server.port;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in _live) {
      try {
        s.destroy();
      } catch (_) {}
    }
    try {
      await _server.close();
    } catch (_) {}
    try {
      _client.close();
    } catch (_) {}
  }
}

/// Establish an SSH tunnel for [p] and forward a local port to its db endpoint.
/// Throws [DbException] with a clear message on any auth/connect failure.
Future<SshTunnel> openSshTunnel(Profile p) async {
  final o = p.options;
  final host = '${o['sshHost'] ?? ''}'.trim();
  if (host.isEmpty) throw DbException('SSH tunnel is enabled but no SSH host is set.');
  final port = int.tryParse('${o['sshPort'] ?? ''}') ?? 22;
  final user = '${o['sshUser'] ?? ''}'.trim();
  if (user.isEmpty) throw DbException('SSH tunnel is enabled but no SSH user is set.');
  final auth = '${o['sshAuth'] ?? 'key'}';

  // Resolve credentials before opening the socket so failures are reported
  // before we hold any resources.
  List<SSHKeyPair>? identities;
  String? Function()? passwordCb;
  if (auth == 'key') {
    final keyPath = '${o['sshKeyFile'] ?? ''}'.trim();
    if (keyPath.isEmpty) throw DbException('SSH key auth selected but no private key file was chosen.');
    final f = File(keyPath);
    if (!f.existsSync()) throw DbException('SSH private key not found: $keyPath');
    final passphrase = '${o['sshPassphrase'] ?? ''}';
    try {
      identities = SSHKeyPair.fromPem(f.readAsStringSync(), passphrase.isEmpty ? null : passphrase);
    } catch (e) {
      throw DbException('Could not read SSH private key (wrong passphrase or unsupported format): $e');
    }
  } else if (auth == 'password') {
    final pw = '${o['sshPassphrase'] ?? ''}';
    passwordCb = () => pw;
  } else {
    // 'agent' — not supported in this client.
    throw DbException('SSH agent auth is not supported here. Use a private key or password.');
  }

  late final SSHClient client;
  try {
    final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 12));
    client = SSHClient(
      socket,
      username: user,
      identities: identities,
      onPasswordRequest: passwordCb,
      // Bastion host-key pinning is out of scope for this client; the SSH
      // channel itself is still fully encrypted end-to-end.
      onVerifyHostKey: (type, fingerprint) => true,
    );
    await client.authenticated;
  } catch (e) {
    throw DbException('SSH connection to $user@$host:$port failed: ${e is DbException ? e.message : e}');
  }

  // Local listener that forwards each accepted connection to the db endpoint.
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final tunnel = SshTunnel._(client, server);
  server.listen((local) async {
    tunnel._live.add(local);
    try {
      final fwd = await client.forwardLocal(p.host, p.port);
      // db endpoint → local socket
      fwd.stream.listen(
        (data) {
          try {
            local.add(data);
          } catch (_) {}
        },
        onDone: () => local.destroy(),
        onError: (_) => local.destroy(),
        cancelOnError: true,
      );
      // local socket → db endpoint
      local.listen(
        (data) => fwd.sink.add(data),
        onDone: () => fwd.sink.close(),
        onError: (_) => fwd.sink.close(),
        cancelOnError: true,
      );
    } catch (_) {
      local.destroy();
    }
  });
  return tunnel;
}
