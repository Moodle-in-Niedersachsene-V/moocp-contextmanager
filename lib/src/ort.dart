import 'dart:io';

import 'einstellungen.dart';
import 'fehler.dart';
import 'schluesselbund.dart';
import 'speicher.dart';
import 'webdav.dart';

/// Der Zugang zum Kontextbereich: Die Einstellungen werden bei jedem Aufruf
/// neu gelesen, damit eine Änderung der Lehrkraft sofort wirkt. Der Zugang
/// kennt den Ort (für den Ausstand) und öffnet ihn (für Lesen und Schreiben).
class Ortszugang {
  Ortszugang({
    required this.einstellungen,
    required this.schluesselbund,
    this.zeitlimit = const Duration(seconds: 20),
  });

  final File einstellungen;
  final Schluesselbund schluesselbund;

  /// Wie lange ein WebDAV-Server für eine Antwort braucht, bevor der Ort als
  /// nicht antwortend gilt.
  final Duration zeitlimit;

  /// Die Kennung des Ortes ohne Geheimnis; siehe [Einstellungen.kennung].
  Future<String> kennung() async =>
      (await leseEinstellungen(einstellungen)).kennung;

  /// Öffnet den Ort. Fehlt die Einstellungsdatei oder ist sie falsch, ist das
  /// ein [KontextFehler] mit dem Grund; antwortet der Ort nicht, ein
  /// [KontextNichtErreichbar].
  Future<Kontextspeicher> oeffnen() async {
    final e = await leseEinstellungen(einstellungen);
    if (e.art == 'webdav') {
      final geheimnis = await schluesselbund.geheimnis(e.konto);
      return WebDavSpeicher.oeffnen(
        adresse: e.adresse!,
        benutzer: e.benutzer!,
        geheimnis: geheimnis,
        zeitlimit: zeitlimit,
      );
    }
    return LokalerSpeicher.oeffnen(e.pfad!);
  }
}
