import 'dart:io';

import 'einstellungen.dart';
import 'einstellungsfenster.dart';
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
    this.fenster,
  });

  final File einstellungen;
  final Schluesselbund schluesselbund;

  /// Das Einstellungsfenster: fehlen die Einstellungen oder antwortet der Ort
  /// nicht, öffnet es die Lehrkraft einmal je Ausfall (E8).
  final Einstellungsfenster? fenster;

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
    try {
      final e = await leseEinstellungen(einstellungen);
      final speicher = await oeffneOrt(
        e,
        schluesselbund: schluesselbund,
        zeitlimit: zeitlimit,
      );
      fenster?.ausfallVorbei();
      return speicher;
    } on KontextFehler {
      await fenster?.beiAusfall();
      rethrow;
    }
  }
}

/// Öffnet den Ort zu [einstellungen], ohne sie aus einer Datei zu lesen. Das
/// Einstellungsfenster prüft damit eine Eingabe, bevor sie gespeichert ist (E8).
Future<Kontextspeicher> oeffneOrt(
  Einstellungen einstellungen, {
  required Schluesselbund schluesselbund,
  required Duration zeitlimit,
}) async {
  if (einstellungen.art == 'webdav') {
    final geheimnis = await schluesselbund.geheimnis(einstellungen.konto);
    return WebDavSpeicher.oeffnen(
      adresse: einstellungen.adresse!,
      benutzer: einstellungen.benutzer!,
      geheimnis: geheimnis,
      zeitlimit: zeitlimit,
    );
  }
  return LokalerSpeicher.oeffnen(einstellungen.pfad!);
}
