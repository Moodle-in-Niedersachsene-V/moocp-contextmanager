import 'dart:convert';
import 'dart:io';

import 'art.dart';
import 'fehler.dart';

/// Der Ausgang einer Freigabe, wie moocp ihn meldet (E4, E20).
enum Freigabeausgang { freigegeben, abgelehnt, abgebrochen }

/// Der Weg zur App für Plugins (E35): Freigaben über `/v1/freigabe`, angemeldet
/// mit dem Schlüssel des Plugins und dem Token des laufenden Aufrufs. Ohne
/// Token gibt es keine Freigabe; die Adresse nennt moocp beim Verbinden.
class AppAnschluss {
  AppAnschluss({required this.adresse, required this.schluessel});

  /// Die Adresse aus dem `initialize` dieser Sitzung; null, wenn moocp keine nannte.
  final Uri? Function() adresse;

  final String schluessel;

  /// Fragt die Lehrkraft um eine Freigabe. [ab] nennt die Stufe, ab der gefragt
  /// wird; liegt die Stufe der Lehrkraft darunter, ist die Freigabe erteilt,
  /// ohne Frage.
  Future<Freigabeausgang> freigabe({
    required String? aufruf,
    required String titel,
    required String zusammenfassung,
    required Freigabestufe ab,
  }) async {
    final ziel = adresse();
    if (ziel == null) {
      throw const KontextFehler(
        'moocp named no address for plugins; nothing was written.',
      );
    }
    if (aufruf == null || aufruf.isEmpty) {
      throw const KontextFehler(
        'The call carries no token from moocp; nothing was written.',
      );
    }
    final http = HttpClient();
    try {
      final anfrage = await http.postUrl(ziel.resolve('/v1/freigabe'));
      anfrage.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $schluessel')
        ..set('Moocp-Aufruf', aufruf)
        ..contentType = ContentType.json;
      anfrage.add(
        utf8.encode(
          jsonEncode({
            'titel': titel,
            'zusammenfassung': zusammenfassung,
            'ab': ab.name,
          }),
        ),
      );
      final antwort = await anfrage.close();
      final text = await utf8.decoder.bind(antwort).join();
      if (antwort.statusCode != HttpStatus.ok) {
        throw KontextFehler(
          'moocp refused the approval request (HTTP ${antwort.statusCode}); nothing was written.',
        );
      }
      final json = jsonDecode(text);
      final ausgang = json is Map ? json['ausgang'] : null;
      return switch (ausgang) {
        'freigegeben' => Freigabeausgang.freigegeben,
        'abgelehnt' => Freigabeausgang.abgelehnt,
        'abgebrochen' => Freigabeausgang.abgebrochen,
        _ => throw const KontextFehler(
          'moocp gave an unknown approval result; nothing was written.',
        ),
      };
    } on IOException {
      throw const KontextFehler(
        'moocp is not reachable at its address for plugins; nothing was written.',
      );
    } finally {
      http.close(force: true);
    }
  }
}
