import 'dart:convert';
import 'dart:io';

import 'art.dart';
import 'fehler.dart';

/// Der Ausgang einer Freigabe, wie moocp ihn meldet (E4, E20).
enum Freigabeausgang { freigegeben, abgelehnt, abgebrochen }

/// Der Weg zur App für Plugins (E35): Freigaben und Dialoge über `/v1/…`, angemeldet
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
    final json = await _anMoocp('/v1/freigabe', {
      'titel': titel,
      'zusammenfassung': zusammenfassung,
      'ab': ab.name,
    }, aufruf: aufruf);
    final ausgang = json['ausgang'];
    return switch (ausgang) {
      'freigegeben' => Freigabeausgang.freigegeben,
      'abgelehnt' => Freigabeausgang.abgelehnt,
      'abgebrochen' => Freigabeausgang.abgebrochen,
      _ => throw const KontextFehler(
        'moocp gave an unknown approval result; nothing was written.',
      ),
    };
  }

  /// Lässt die Lehrkraft in moocp einen Ordner wählen (`/v1/dialog/pfad`, E35).
  /// Liefert den absoluten Pfad des gewählten Ordners, null bei Abbruch. Den Pfad
  /// bestimmt allein die Lehrkraft: Die KI nennt keinen Ordner.
  Future<String?> ordnerWaehlen({
    required String? aufruf,
    required String titel,
  }) async {
    final json = await _anMoocp('/v1/dialog/pfad', {
      'titel': titel,
      'art': 'ordner',
    }, aufruf: aufruf);
    if (json['abgebrochen'] == true) return null;
    final pfad = json['pfad'];
    if (pfad is! String || pfad.isEmpty) {
      throw const KontextFehler('moocp gave no folder; nothing was written.');
    }
    return pfad;
  }

  /// Eine Anfrage an die App für Plugins: Der Schlüssel des Plugins und das Token
  /// des Aufrufs gehen nur an diese Adresse. Liefert die Antwort als Objekt.
  Future<Map<String, dynamic>> _anMoocp(
    String pfad,
    Map<String, Object?> daten, {
    required String? aufruf,
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
      final anfrage = await http.postUrl(ziel.resolve(pfad));
      anfrage.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $schluessel')
        ..set('Moocp-Aufruf', aufruf)
        ..contentType = ContentType.json;
      anfrage.add(utf8.encode(jsonEncode(daten)));
      final antwort = await anfrage.close();
      final text = await utf8.decoder.bind(antwort).join();
      if (antwort.statusCode != HttpStatus.ok) {
        throw KontextFehler(
          'moocp refused the request (HTTP ${antwort.statusCode}); nothing was written.',
        );
      }
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        throw const KontextFehler(
          'moocp gave an unreadable answer; nothing was written.',
        );
      }
      if (json is! Map) {
        throw const KontextFehler(
          'moocp gave an unreadable answer; nothing was written.',
        );
      }
      return json.cast<String, dynamic>();
    } on IOException {
      throw const KontextFehler(
        'moocp is not reachable at its address for plugins; nothing was written.',
      );
    } finally {
      http.close(force: true);
    }
  }
}
