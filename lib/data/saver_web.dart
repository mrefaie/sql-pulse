// SQL Pulse — file export on web (triggers a browser download).
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<String> saveBytes(String filename, String text) async {
  final bytes = utf8.encode(text);
  final blob = html.Blob(<dynamic>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body!.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
  return 'downloaded';
}
