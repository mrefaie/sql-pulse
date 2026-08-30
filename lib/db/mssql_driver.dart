// SQL Pulse — SQL Server driver via a minimal pure-Dart TDS 7.4 client.
// Works against servers that allow unencrypted login (ENCRYPT_NOT_SUP/OFF on the
// local container). No native deps — implements PRELOGIN, LOGIN7, SQL_BATCH and
// parses the response token stream for common column types.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../data/models.dart';
import 'db_driver.dart';

class _Writer {
  final BytesBuilder _b = BytesBuilder();
  void u8(int v) => _b.addByte(v & 0xff);
  void u16le(int v) => _b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32le(int v) =>
      _b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void bytes(List<int> v) => _b.add(v);
  void ucs2(String s) {
    for (final u in s.codeUnits) {
      _b.add([u & 0xff, (u >> 8) & 0xff]);
    }
  }

  Uint8List take() => _b.toBytes();
  int get length => _b.length;
}

class _Reader {
  final Uint8List d;
  int p = 0;
  _Reader(this.d);
  bool get eof => p >= d.length;
  int u8() => d[p++];
  int u16() => d[p++] | (d[p++] << 8);
  int u16be() => (d[p++] << 8) | d[p++];
  int u32() => d[p++] | (d[p++] << 8) | (d[p++] << 16) | (d[p++] << 24);
  int i32() {
    final v = u32();
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  int u64() {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v |= d[p++] << (8 * i);
    }
    return v;
  }

  List<int> take(int n) {
    final r = d.sublist(p, p + n);
    p += n;
    return r;
  }

  String ucs2(int chars) {
    final units = <int>[];
    for (var i = 0; i < chars; i++) {
      units.add(d[p++] | (d[p++] << 8));
    }
    return String.fromCharCodes(units);
  }

  String bVarchar() => ucs2(u8());
  String usVarchar() => ucs2(u16());
}

/// Reads complete TDS messages (one or more packets until EOM) from a socket.
class _PacketStream {
  final StreamIterator<Uint8List> _it;
  final List<int> _buf = [];
  _PacketStream(Stream<Uint8List> s) : _it = StreamIterator(s);

  Future<Uint8List> _need(int n) async {
    while (_buf.length < n) {
      if (!await _it.moveNext())
        throw DbException('SQL Server connection closed');
      _buf.addAll(_it.current);
    }
    final out = Uint8List.fromList(_buf.sublist(0, n));
    _buf.removeRange(0, n);
    return out;
  }

  Future<Uint8List> readMessage() async {
    final payload = BytesBuilder();
    while (true) {
      final head = await _need(8);
      final status = head[1];
      final len = (head[2] << 8) | head[3];
      final body = await _need(len - 8);
      payload.add(body);
      if (status & 0x01 != 0) break; // EOM
    }
    return payload.toBytes();
  }

  Future<void> cancel() => _it.cancel();
}

class MssqlDriver extends DbDriver {
  Socket? _sock;
  _PacketStream? _stream;
  String _currentDb = '';
  String _version = 'Microsoft SQL Server';

  @override
  String get serverVersion => _version;

  @override
  String get txBegin => 'BEGIN TRANSACTION';
  @override
  String get txCommit => 'COMMIT TRANSACTION';
  @override
  String get txRollback => 'ROLLBACK TRANSACTION';

  Future<void> _send(int type, Uint8List payload) async {
    const maxData = 4096 - 8;
    var off = 0;
    while (true) {
      final end = (off + maxData < payload.length)
          ? off + maxData
          : payload.length;
      final chunk = payload.sublist(off, end);
      final eom = end >= payload.length;
      final len = 8 + chunk.length;
      final header = [
        type,
        eom ? 0x01 : 0x00,
        (len >> 8) & 0xff,
        len & 0xff,
        0,
        0,
        1,
        0,
      ];
      _sock!.add(header);
      _sock!.add(chunk);
      off = end;
      if (eom) break;
    }
    await _sock!.flush();
  }

  @override
  Future<void> connect(Profile p) async {
    _currentDb = p.catalog;
    _sock = await Socket.connect(
      p.host,
      p.port,
      timeout: const Duration(seconds: 12),
    );
    _sock!.setOption(SocketOption.tcpNoDelay, true);
    _stream = _PacketStream(_sock!.cast<Uint8List>());

    await _send(0x12, _prelogin());
    final pre = await _stream!.readMessage();
    final enc = _preloginEncryption(pre);
    if (enc == 1 || enc == 3) {
      throw DbException(
        'This SQL Server requires TLS encryption, which this lightweight driver does not support. Set the server to allow unencrypted connections, or use it on a platform with a native driver.',
      );
    }

    await _send(0x10, _login7(p));
    final loginResp = await _stream!.readMessage();
    _parseLogin(loginResp);
  }

  Uint8List _prelogin() {
    final w = _Writer();
    // option table: VERSION(0x00)@11 len6, ENCRYPTION(0x01)@17 len1, TERMINATOR
    w.bytes([0x00, 0, 11, 0, 6]);
    w.bytes([0x01, 0, 17, 0, 1]);
    w.u8(0xFF);
    w.bytes([0x10, 0x00, 0x10, 0x36, 0x00, 0x00]); // version
    w.u8(0x02); // ENCRYPT_NOT_SUP
    return w.take();
  }

  int _preloginEncryption(Uint8List msg) {
    var i = 0;
    while (i + 5 <= msg.length && msg[i] != 0xFF) {
      final type = msg[i];
      final off = (msg[i + 1] << 8) | msg[i + 2];
      if (type == 0x01) return msg[off];
      i += 5;
    }
    return 2;
  }

  Uint8List _login7(Profile p) {
    final host = 'sqlpulse';
    final user = p.user;
    final pass = '${p.options['password'] ?? ''}';
    final app = 'SQL Pulse';
    final server = p.host;
    final clt = 'dart-tds';
    final db = p.catalog;

    Uint8List enc16(String s) {
      final b = Uint8List(s.codeUnits.length * 2);
      var j = 0;
      for (final u in s.codeUnits) {
        b[j++] = u & 0xff;
        b[j++] = (u >> 8) & 0xff;
      }
      return b;
    }

    final hostB = enc16(host);
    final userB = enc16(user);
    final passB = enc16(pass);
    // obfuscate password: swap nibbles then XOR 0xA5
    for (var i = 0; i < passB.length; i++) {
      final b = passB[i];
      passB[i] = (((b << 4) | (b >> 4)) & 0xff) ^ 0xA5;
    }
    final appB = enc16(app);
    final serverB = enc16(server);
    final cltB = enc16(clt);
    final dbB = enc16(db);

    const headerLen = 36;
    const offBlock = 58;
    var dataOff = headerLen + offBlock; // 94
    final data = BytesBuilder();
    int put(Uint8List b) {
      final at = dataOff;
      data.add(b);
      dataOff += b.length;
      return at;
    }

    final hostAt = put(hostB);
    final userAt = put(userB);
    final passAt = put(passB);
    final appAt = put(appB);
    final serverAt = put(serverB);
    final cltAt = put(cltB);
    final dbAt = put(dbB);

    final body = _Writer();
    // fixed header
    final total = headerLen + offBlock + data.length;
    body.u32le(total);
    body.u32le(0x74000004); // TDS 7.4
    body.u32le(4096); // packet size
    body.u32le(7); // client prog ver
    body.u32le(0); // pid
    body.u32le(0); // connection id
    body.u8(0xE0); // optionFlags1
    body.u8(0x03); // optionFlags2 (fLanguage + fODBC)
    body.u8(0x00); // typeFlags
    body.u8(0x00); // optionFlags3
    body.u32le(0); // client time zone
    body.u32le(0x00000409); // LCID en-US
    // offset/length block
    void ol(int off, int chars) {
      body.u16le(off);
      body.u16le(chars);
    }

    ol(hostAt, host.length);
    ol(userAt, user.length);
    ol(passAt, pass.length);
    ol(appAt, app.length);
    ol(serverAt, server.length);
    ol(0, 0); // unused/extension
    ol(cltAt, clt.length);
    ol(0, 0); // language
    ol(dbAt, db.length);
    body.bytes([0, 0, 0, 0, 0, 0]); // ClientID (MAC)
    ol(0, 0); // SSPI
    ol(0, 0); // AtchDBFile
    ol(0, 0); // ChangePassword
    body.u32le(0); // cbSSPILong
    body.bytes(data.toBytes());
    return body.take();
  }

  void _parseLogin(Uint8List msg) {
    final r = _Reader(msg);
    while (!r.eof) {
      final token = r.u8();
      if (token == 0xAD) {
        // LOGINACK
        final len = r.u16();
        final end = r.p + len;
        r.u8(); // interface
        r.take(4); // tds version
        final prog = r.bVarchar();
        final major = r.u8();
        final minor = r.u8();
        final build = r.u16be();
        _version = 'Microsoft SQL Server ($prog $major.$minor.$build)';
        r.p = end;
      } else if (token == 0xAA) {
        throw DbException(_readError(r));
      } else if (token == 0xAB) {
        _readError(r); // INFO, ignore
      } else if (token == 0xE3) {
        final len = r.u16();
        r.p += len;
      } else if (token == 0xFD || token == 0xFE || token == 0xFF) {
        r.take(12); // DONE
      } else if (token == 0x79) {
        r.u32(); // RETURNSTATUS
      } else {
        break;
      }
    }
  }

  String _readError(_Reader r) {
    final len = r.u16();
    final end = r.p + len;
    r.u32(); // number
    r.u8(); // state
    r.u8(); // class
    final msg = r.usVarchar();
    r.p = end;
    return msg;
  }

  @override
  Future<void> close() async {
    await _stream?.cancel();
    await _sock?.close();
    _sock = null;
  }

  Future<void> _use(String db) async {
    if (db.isNotEmpty && db != _currentDb) {
      await execute('USE [$db]');
      _currentDb = db;
    }
  }

  Uint8List _sqlBatch(String sql) {
    final w = _Writer();
    // ALL_HEADERS with a transaction descriptor header
    w.u32le(22); // total length
    w.u32le(18); // header length
    w.u16le(0x0002); // type = transaction descriptor
    w.bytes([0, 0, 0, 0, 0, 0, 0, 0]); // transaction descriptor
    w.u32le(1); // outstanding request count
    w.ucs2(sql);
    return w.take();
  }

  @override
  Future<QueryResult> execute(String sql, {String? catalog}) async {
    if (catalog != null) await _use(catalog);
    final sw = Stopwatch()..start();
    try {
      await _send(0x01, _sqlBatch(sql));
      final resp = await _stream!.readMessage();
      final parsed = _parseResult(resp);
      final ms = (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999);
      if (parsed.headers != null) {
        return QueryResult(
          ms: ms,
          headers: parsed.headers,
          rows: parsed.rows,
          comment:
              '${parsed.rows!.length} row${parsed.rows!.length == 1 ? '' : 's'} in set.',
        );
      }
      final verb = sql.trimLeft().split(RegExp(r'\s')).first.toUpperCase();
      return QueryResult(
        ms: ms,
        status: true,
        statementType: verb,
        comment: 'Query OK · ${parsed.affected} row(s) affected.',
      );
    } on DbException catch (e) {
      return QueryResult(
        ms: (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999),
        error: true,
        message: e.message,
      );
    } catch (e) {
      return QueryResult(
        ms: (sw.elapsedMicroseconds / 1000).round().clamp(1, 99999),
        error: true,
        message: e.toString(),
      );
    }
  }

  ({List<String>? headers, List<List<Object?>>? rows, int affected})
  _parseResult(Uint8List msg) {
    final r = _Reader(msg);
    List<_Col>? cols;
    List<String>? headers;
    final rows = <List<Object?>>[];
    var affected = 0;
    String? error;
    while (!r.eof) {
      final token = r.u8();
      switch (token) {
        case 0x81: // COLMETADATA
          cols = _readColMeta(r);
          headers = cols.map((c) => c.name).toList();
          break;
        case 0xD1: // ROW
          rows.add([for (final c in cols!) _readValue(r, c)]);
          break;
        case 0xD2: // NBCROW
          final n = cols!.length;
          final bitmapLen = (n + 7) ~/ 8;
          final bitmap = r.take(bitmapLen);
          final out = <Object?>[];
          for (var i = 0; i < n; i++) {
            final isNull = (bitmap[i ~/ 8] & (1 << (i % 8))) != 0;
            out.add(isNull ? null : _readValue(r, cols[i]));
          }
          rows.add(out);
          break;
        case 0xAA: // ERROR
          error = _readError(r);
          break;
        case 0xAB: // INFO
          _readError(r);
          break;
        case 0xE3: // ENVCHANGE
          final len = r.u16();
          r.p += len;
          break;
        case 0x79: // RETURNSTATUS
          r.u32();
          break;
        case 0xFD:
        case 0xFE:
        case 0xFF: // DONE
          r.u16(); // status
          r.u16(); // curcmd
          affected = r.u64();
          break;
        case 0xA9: // ORDER
          final len = r.u16();
          r.p += len;
          break;
        default:
          // unknown token — stop to avoid desync
          r.p = r.d.length;
      }
    }
    if (error != null && headers == null) throw DbException(error);
    return (
      headers: headers,
      rows: headers != null ? rows : null,
      affected: affected,
    );
  }

  List<_Col> _readColMeta(_Reader r) {
    final count = r.u16();
    final cols = <_Col>[];
    if (count == 0xFFFF) return cols;
    for (var i = 0; i < count; i++) {
      r.u32(); // user type
      r.u16(); // flags
      final c = _readTypeInfo(r);
      c.name = r.bVarchar();
      cols.add(c);
    }
    return cols;
  }

  _Col _readTypeInfo(_Reader r) {
    final type = r.u8();
    final c = _Col()..type = type;
    switch (type) {
      // fixed-length
      case 0x1F:
      case 0x30:
        c.len = 1;
        break; // NULL/INT1
      case 0x32:
        c.len = 1;
        break; // BIT
      case 0x34:
        c.len = 2;
        break; // INT2
      case 0x38:
        c.len = 4;
        break; // INT4
      case 0x3A:
        c.len = 4;
        break; // MONEY4? (SMALLMONEY)
      case 0x3B:
        c.len = 4;
        break; // FLT4
      case 0x3C:
        c.len = 8;
        break; // MONEY
      case 0x3D:
        c.len = 8;
        break; // DATETIME
      case 0x3E:
        c.len = 8;
        break; // FLT8
      case 0x7F:
        c.len = 8;
        break; // INT8
      // variable: length byte
      case 0x26:
        c.len = r.u8();
        break; // INTN
      case 0x68:
        c.len = r.u8();
        break; // BITN
      case 0x6D:
        c.len = r.u8();
        break; // FLTN
      case 0x6E:
        c.len = r.u8();
        break; // MONEYN
      case 0x6F:
        c.len = r.u8();
        break; // DATETIMN
      case 0x24:
        c.len = r.u8();
        break; // GUID
      case 0x6A: // DECIMALN
      case 0x6C: // NUMERICN
        c.len = r.u8();
        c.precision = r.u8();
        c.scale = r.u8();
        break;
      case 0x28:
        c.len = 3;
        break; // DATEN (no scale, 3 bytes, but length sent per-row)
      case 0x29:
        c.scale = r.u8();
        break; // TIMEN
      case 0x2A:
        c.scale = r.u8();
        break; // DATETIME2
      case 0x2B:
        c.scale = r.u8();
        break; // DATETIMEOFFSET
      case 0xA5: // BIGVARBIN
      case 0xA7: // BIGVARCHAR
      case 0xAD: // BIGBINARY
      case 0xAF: // BIGCHAR
        c.len = r.u16();
        if (type == 0xA7 || type == 0xAF) r.take(5); // collation
        break;
      case 0xE7: // NVARCHAR
      case 0xEF: // NCHAR
        c.len = r.u16();
        r.take(5); // collation
        break;
      case 0x63: // NTEXT
      case 0x23: // TEXT
        c.len = r.u32();
        if (type == 0x63 || type == 0x23) r.take(5); // collation
        final parts = r.u8();
        for (var i = 0; i < parts; i++) {
          r.ucs2(r.u16());
        }
        break;
      case 0xF1: // XML
        if (r.u8() == 1) {
          r.ucs2(r.u8()); // dbname
          r.ucs2(r.u8()); // owner
          r.ucs2(r.u16()); // schema collection
        }
        break;
      default:
        c.len = 0;
    }
    return c;
  }

  Object? _readValue(_Reader r, _Col c) {
    switch (c.type) {
      case 0x38:
        return r.i32();
      case 0x34:
        {
          final v = r.u16();
          return v >= 0x8000 ? v - 0x10000 : v;
        }
      case 0x30:
        return r.u8();
      case 0x32:
        return r.u8() != 0;
      case 0x7F:
        return r.u64();
      case 0x3B:
        return _float(r.take(4));
      case 0x3E:
        return _double(r.take(8));
      case 0x3D:
        return _datetime(r.take(8)); // DATETIME
      case 0x26:
        {
          // INTN
          final n = r.u8();
          if (n == 0) return null;
          return _intLE(r.take(n));
        }
      case 0x68:
        {
          final n = r.u8();
          return n == 0 ? null : r.u8() != 0;
        }
      case 0x6D:
        {
          final n = r.u8();
          if (n == 0) return null;
          return n == 4 ? _float(r.take(4)) : _double(r.take(8));
        }
      case 0x6E:
      case 0x3C:
      case 0x3A:
        {
          final n = c.type == 0x6E ? r.u8() : c.len;
          if (n == 0) return null;
          return _money(r.take(n));
        }
      case 0x6F:
        {
          final n = r.u8();
          return n == 0 ? null : _datetime(r.take(n));
        }
      case 0x24:
        {
          final n = r.u8();
          return n == 0 ? null : _guid(r.take(n));
        }
      case 0x6A:
      case 0x6C:
        {
          // DECIMALN/NUMERICN
          final n = r.u8();
          if (n == 0) return null;
          final sign = r.u8();
          final mag = r.take(n - 1);
          return _decimal(mag, sign, c.scale);
        }
      case 0x28:
        {
          final n = r.u8();
          return n == 0 ? null : _date(r.take(n));
        }
      case 0x29:
        {
          final n = r.u8();
          return n == 0 ? null : _timeStr(r.take(n), c.scale);
        }
      case 0x2A:
        {
          final n = r.u8();
          return n == 0 ? null : _datetime2(r.take(n), c.scale);
        }
      case 0x2B:
        {
          final n = r.u8();
          if (n == 0) return null;
          r.take(n);
          return '<datetimeoffset>';
        }
      case 0xE7:
      case 0xEF:
        {
          // NVARCHAR/NCHAR (incl. NVARCHAR(MAX) = PLP)
          if (c.len == 0xFFFF) {
            final b = _readPlp(r);
            return b == null ? null : String.fromCharCodes(_u16pairs(b));
          }
          final n = r.u16();
          if (n == 0xFFFF) return null;
          return r.ucs2(n ~/ 2);
        }
      case 0xA7:
      case 0xAF:
        {
          // BIGVARCHAR/BIGCHAR (incl. VARCHAR(MAX) = PLP)
          if (c.len == 0xFFFF) {
            final b = _readPlp(r);
            return b == null ? null : latin1.decode(b, allowInvalid: true);
          }
          final n = r.u16();
          if (n == 0xFFFF) return null;
          return latin1.decode(r.take(n), allowInvalid: true);
        }
      case 0xA5:
      case 0xAD:
        {
          if (c.len == 0xFFFF) {
            final b = _readPlp(r);
            return b == null ? null : '<binary ${b.length}b>';
          }
          final n = r.u16();
          if (n == 0xFFFF) return null;
          r.take(n);
          return '<binary ${n}b>';
        }
      case 0x63:
      case 0x23:
        {
          // NTEXT/TEXT (PLP-ish: textptr)
          final ptrLen = r.u8();
          if (ptrLen == 0) return null;
          r.take(ptrLen); // textptr
          r.take(8); // timestamp
          final dataLen = r.u32();
          final bytes = r.take(dataLen);
          return c.type == 0x63
              ? String.fromCharCodes(_u16pairs(bytes))
              : latin1.decode(bytes, allowInvalid: true);
        }
      default:
        return null;
    }
  }

  /// Read a Partially Length-Prefixed (PLP) value: 8-byte total length
  /// (0xFFFF…FF = NULL, 0xFFFF…FE = unknown) followed by length-prefixed chunks
  /// terminated by a zero-length chunk. Used for VARCHAR(MAX)/NVARCHAR(MAX)/etc.
  List<int>? _readPlp(_Reader r) {
    final lo = r.u32();
    final hi = r.u32();
    if (lo == 0xFFFFFFFF && hi == 0xFFFFFFFF) return null; // PLP_NULL
    final out = <int>[];
    while (true) {
      final chunkLen = r.u32();
      if (chunkLen == 0) break;
      out.addAll(r.take(chunkLen));
    }
    return out;
  }

  List<int> _u16pairs(List<int> b) {
    final out = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      out.add(b[i] | (b[i + 1] << 8));
    }
    return out;
  }

  int _intLE(List<int> b) {
    var v = 0;
    for (var i = 0; i < b.length; i++) {
      v |= b[i] << (8 * i);
    }
    // sign-extend
    if (b.isNotEmpty && (b.last & 0x80) != 0) {
      v -= 1 << (8 * b.length);
    }
    return v;
  }

  double _float(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getFloat32(0, Endian.little);
  double _double(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getFloat64(0, Endian.little);

  Object _money(List<int> b) {
    if (b.length == 4) {
      final v = ByteData.sublistView(
        Uint8List.fromList(b),
      ).getInt32(0, Endian.little);
      return v / 10000.0;
    }
    final hi = ByteData.sublistView(
      Uint8List.fromList(b.sublist(0, 4)),
    ).getInt32(0, Endian.little);
    final lo = ByteData.sublistView(
      Uint8List.fromList(b.sublist(4, 8)),
    ).getUint32(0, Endian.little);
    return ((hi << 32) | lo) / 10000.0;
  }

  Object _decimal(List<int> mag, int sign, int scale) {
    var v = BigInt.zero;
    for (var i = mag.length - 1; i >= 0; i--) {
      v = (v << 8) | BigInt.from(mag[i]);
    }
    if (sign == 0) v = -v;
    if (scale == 0) {
      final n = v.toInt();
      return n;
    }
    final s = v.toString();
    final neg = s.startsWith('-');
    final digits = neg ? s.substring(1) : s;
    final padded = digits.padLeft(scale + 1, '0');
    final intPart = padded.substring(0, padded.length - scale);
    final frac = padded.substring(padded.length - scale);
    final str = '${neg ? '-' : ''}$intPart.$frac';
    return double.tryParse(str) ?? str;
  }

  String _date(List<int> b) {
    var days = 0;
    for (var i = 0; i < b.length; i++) {
      days |= b[i] << (8 * i);
    }
    final d = DateTime(1, 1, 1).add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _timeStr(List<int> b, int scale) {
    var ticks = 0;
    for (var i = 0; i < b.length; i++) {
      ticks |= b[i] << (8 * i);
    }
    final seconds = ticks / _pow10(scale);
    final s = seconds.floor();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _datetime2(List<int> b, int scale) {
    final timeBytes = b.length - 3;
    final t = _timeStr(b.sublist(0, timeBytes), scale);
    final d = _date(b.sublist(timeBytes));
    return '$d $t';
  }

  String _datetime(List<int> b) {
    // DATETIME: 4 bytes days since 1900-01-01, 4 bytes 1/300s ticks
    final days = ByteData.sublistView(
      Uint8List.fromList(b.sublist(0, 4)),
    ).getInt32(0, Endian.little);
    final ticks = ByteData.sublistView(
      Uint8List.fromList(b.sublist(4, 8)),
    ).getUint32(0, Endian.little);
    final base = DateTime(
      1900,
      1,
      1,
    ).add(Duration(days: days, milliseconds: (ticks * 1000 / 300).round()));
    return '${base.year.toString().padLeft(4, '0')}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')} '
        '${base.hour.toString().padLeft(2, '0')}:${base.minute.toString().padLeft(2, '0')}:${base.second.toString().padLeft(2, '0')}';
  }

  num _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  String _guid(List<int> b) {
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(3)}${h(2)}${h(1)}${h(0)}-${h(5)}${h(4)}-${h(7)}${h(6)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  @override
  Future<QueryResult> explain(String sql, {String? catalog}) async {
    if (catalog != null) await _use(catalog);
    final body = sql
        .replaceFirst(RegExp(r'^\s*explain\s+', caseSensitive: false), '')
        .trim();
    // SHOWPLAN_ALL replaces execution with the estimated plan; it must be its
    // own batch, so we toggle it around the query in three round-trips.
    await execute('SET SHOWPLAN_ALL ON');
    final r = await execute(body);
    await execute('SET SHOWPLAN_ALL OFF');
    return r;
  }

  @override
  Future<List<String>> listCatalogs() async {
    final r = await execute('SELECT name FROM sys.databases ORDER BY name');
    return (r.rows ?? []).map((row) => '${row.first}').toList();
  }

  @override
  Future<Catalog> introspect(String catalog) async {
    await _use(catalog);
    final cols = await execute(
      '''SELECT t.name AS tbl, c.name AS col, ty.name AS typ, c.max_length, c.precision, c.scale,
        c.is_nullable, c.is_identity FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id
        JOIN sys.types ty ON ty.user_type_id=c.user_type_id ORDER BY t.name, c.column_id''',
    );
    final tables = <String, TableDef>{};
    for (final row in cols.rows ?? []) {
      final tn = '${row[0]}';
      final typ = '${row[2]}';
      final maxLen = row[3] is num ? (row[3] as num).toInt() : 0;
      var typeStr = typ;
      if (RegExp(r'char|binary').hasMatch(typ) && maxLen > 0) {
        final l = typ.startsWith('n') ? maxLen ~/ 2 : maxLen;
        typeStr = '$typ($l)';
      } else if (RegExp(r'decimal|numeric').hasMatch(typ)) {
        typeStr = '$typ(${row[4]},${row[5]})';
      }
      tables
          .putIfAbsent(tn, () => TableDef(name: tn, columns: [], rows: []))
          .columns
          .add(
            ColumnDef(
              name: '${row[1]}',
              type: typeStr,
              nullable: row[6] == true || row[6] == 1,
              ai: row[7] == true || row[7] == 1,
            ),
          );
    }
    final pks = await execute(
      '''SELECT t.name, c.name FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
        JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
        JOIN sys.tables t ON t.object_id=i.object_id WHERE i.is_primary_key=1''',
    );
    for (final row in pks.rows ?? []) {
      tables['${row[0]}']?.columns
          .where((c) => c.name == '${row[1]}')
          .forEach((c) => c.pk = true);
    }
    final fks = await execute(
      '''SELECT tp.name, cp.name, tr.name, cr.name FROM sys.foreign_key_columns fkc
        JOIN sys.tables tp ON tp.object_id=fkc.parent_object_id
        JOIN sys.columns cp ON cp.object_id=fkc.parent_object_id AND cp.column_id=fkc.parent_column_id
        JOIN sys.tables tr ON tr.object_id=fkc.referenced_object_id
        JOIN sys.columns cr ON cr.object_id=fkc.referenced_object_id AND cr.column_id=fkc.referenced_column_id''',
    );
    for (final row in fks.rows ?? []) {
      tables['${row[0]}']?.columns.where((c) => c.name == '${row[1]}').forEach((
        c,
      ) {
        c.fkTable = '${row[2]}';
        c.fkCol = '${row[3]}';
      });
    }
    final est = await execute(
      '''SELECT t.name, SUM(p.rows) FROM sys.tables t
        JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1) GROUP BY t.name''',
    );
    for (final row in est.rows ?? []) {
      final t = tables['${row[0]}'];
      if (t != null) t.rowEstimate = (row[1] as num?)?.toInt() ?? 0;
    }
    final views = await execute(
      "SELECT name, OBJECT_DEFINITION(object_id) FROM sys.views",
    );
    final procs = await execute(
      "SELECT name, OBJECT_DEFINITION(object_id) FROM sys.procedures",
    );
    final fns = await execute(
      "SELECT name, OBJECT_DEFINITION(object_id) FROM sys.objects WHERE type IN ('FN','IF','TF')",
    );
    final trigs = await execute(
      "SELECT tr.name, OBJECT_NAME(tr.parent_id), OBJECT_DEFINITION(tr.object_id) FROM sys.triggers tr WHERE tr.parent_id <> 0",
    );

    final cat = Catalog(
      label: catalog,
      tables: tables,
      views: (views.rows ?? [])
          .map((r) => {'name': '${r[0]}', 'definition': '${r[1]}'})
          .toList(),
      procedures: (procs.rows ?? [])
          .map(
            (r) => {'name': '${r[0]}', 'params': '', 'definition': '${r[1]}'},
          )
          .toList(),
      functions: (fns.rows ?? [])
          .map(
            (r) => {
              'name': '${r[0]}',
              'params': '',
              'returns': '',
              'definition': '${r[1]}',
            },
          )
          .toList(),
      triggers: (trigs.rows ?? [])
          .map(
            (r) => {
              'name': '${r[0]}',
              'event': 'TRIGGER',
              'target': '${r[1]}',
              'definition': '${r[2]}',
            },
          )
          .toList(),
    );
    cat.relations = buildRelations(tables);
    cat.er = autoErLayout(tables.keys);
    return cat;
  }

  @override
  Future<List<RowMap>> preview(
    String catalog,
    String table,
    int limit, {
    List<String>? orderBy,
  }) async {
    await _use(catalog);
    final ord = orderBy == null || orderBy.isEmpty
        ? ''
        : ' ORDER BY ${orderBy.map((c) => '[$c]').join(', ')}';
    final r = await execute('SELECT TOP $limit * FROM [$table]$ord');
    final headers = r.headers ?? [];
    return (r.rows ?? []).map((row) {
      final m = <String, Object?>{};
      for (var i = 0; i < headers.length; i++) {
        m[headers[i]] = i < row.length ? row[i] : null;
      }
      return m;
    }).toList();
  }
}

class _Col {
  int type = 0;
  int len = 0;
  int precision = 0;
  int scale = 0;
  String name = '';
}
