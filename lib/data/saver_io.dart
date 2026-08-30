// SQL Pulse — file export on native platforms (desktop/mobile).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<String> saveBytes(String filename, String text) async {
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export $filename',
      fileName: filename,
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (path != null) {
      final f = File.fromUri(path);
      if (!await f.exists() || (await f.length()) == 0) {
        await f.writeAsString(text);
      }
      return 'saved';
    }
  } catch (_) {}
  return 'cancelled';
}
