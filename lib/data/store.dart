// SQL Pulse — local persistence + export helpers (on-device, no cloud).
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'saver_io.dart' if (dart.library.html) 'saver_web.dart' as saver;

class Store {
  static const _key = 'sqlpulse.v1';
  static SharedPreferences? _prefs;
  static Map<String, dynamic> _cache = {};

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null) {
      try {
        _cache = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        _cache = {};
      }
    }
  }

  static Map<String, dynamic> load() => _cache;

  static void save(Map<String, dynamic> patch) {
    _cache = {..._cache, ...patch};
    try {
      _prefs?.setString(_key, jsonEncode(_cache));
    } catch (_) {}
  }

  static Future<void> reset() async {
    _cache = {};
    await _prefs?.remove(_key);
  }

  // ---- export ----
  static String _esc(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static String toCsv(List<String> headers, List<List<Object?>> rows) {
    final head = headers.map(_esc).join(',');
    final body = rows.map((r) => r.map(_esc).join(',')).join('\n');
    return '$head\n$body';
  }

  static String toJsonStr(List<String> headers, List<List<Object?>> rows) {
    final objs = rows.map((r) {
      final o = <String, Object?>{};
      for (var i = 0; i < headers.length; i++) {
        o[headers[i]] = i < r.length ? r[i] : null;
      }
      return o;
    }).toList();
    return const JsonEncoder.withIndent('  ').convert(objs);
  }

  static String toInserts(String table, List<String> headers, List<List<Object?>> rows) {
    String q(Object? v) => v == null
        ? 'NULL'
        : (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v.toString())
            ? v.toString()
            : "'${v.toString().replaceAll("'", "''")}'");
    return rows
        .map((r) =>
            'INSERT INTO $table (${headers.join(', ')}) VALUES (${r.map(q).join(', ')});')
        .join('\n');
  }

  /// Save text to a file (native: save dialog; web: browser download).
  static Future<String> shareOrDownload(String filename, String text) =>
      saver.saveBytes(filename, text);

  static Future<bool> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }
}
