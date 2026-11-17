import 'dart:convert';

/// Vergleicht den Kopf einer Anfrage mit dem erwarteten Wert, ohne früher
/// aufzuhören, wenn ein Byte abweicht: Ein Vergleich mit `==` endet beim
/// ersten Unterschied, und an der Zeit ließe sich der Schlüssel Zeichen für
/// Zeichen erraten. Übernommen aus dem Beispiel-Plugin von moocp.
bool gleichInKonstanterZeit(String? kopf, String erwartet) {
  if (kopf == null) return false;
  final a = utf8.encode(kopf);
  final b = utf8.encode(erwartet);
  var unterschied = a.length ^ b.length;
  for (var i = 0; i < b.length; i++) {
    unterschied |= (i < a.length ? a[i] : 0) ^ b[i];
  }
  return unterschied == 0;
}
