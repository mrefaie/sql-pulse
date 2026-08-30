// SQL Pulse — sensitive-column masking (prod safety). Ported from mask.js.
final RegExp _sensitiveRe = RegExp(
  r'(email|e_mail|password|passwd|pwd|secret|token|ssn|social|credit|card|cvv|iban|phone|mobile|salary|dob|birth|api_?key|access_?key)',
  caseSensitive: false,
);

bool isSensitiveCol(String name) => _sensitiveRe.hasMatch(name);

String maskValue(Object? v, String colName) {
  if (v == null || v == '') return v?.toString() ?? '';
  final s = v.toString();
  if (RegExp(r'email|e_mail', caseSensitive: false).hasMatch(colName)) {
    final at = s.indexOf('@');
    if (at > 0) return '${s[0]}•••${s.substring(at)}';
    return '•••';
  }
  if (s.length <= 2) return '••';
  final mid = (s.length - 2).clamp(3, 8);
  return s[0] + '•' * mid + s[s.length - 1];
}
