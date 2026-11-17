import 'app.dart';
import 'art.dart';
import 'speicher.dart';

/// Ein Schreibvorgang der KI, wie er gestellt wurde. Er ist die Einheit, die
/// entweder in den Kontextbereich gelangt oder im Ausstand wartet (E2).
class Schreibauftrag {
  const Schreibauftrag({
    required this.pfad,
    required this.inhalt,
    required this.art,
    required this.zusammenfassung,
    required this.version,
    required this.anhaengen,
  });

  final String pfad;
  final String inhalt;
  final Art art;
  final String zusammenfassung;

  /// Die Version, die die KI gelesen hat; null, wenn die Datei neu entstehen soll.
  final String? version;

  /// true für `context_append`, false für `context_write`.
  final bool anhaengen;

  /// Ob der Pfad direkt am Wurzelordner liegt (ohne Ordner davor).
  bool get imWurzelordner =>
      pfad.split('/').where((t) => t.isNotEmpty && t != '.').length == 1;

  /// Die Freigabestufe, ab der die Lehrkraft gefragt wird.
  Freigabestufe get stufe =>
      freigabestufeFuer(art, imWurzelordner: imWurzelordner);

  Map<String, Object?> alsJson() => {
    'pfad': pfad,
    'inhalt': inhalt,
    'art': art.wert,
    'zusammenfassung': zusammenfassung,
    'version': version,
    'anhaengen': anhaengen,
  };

  /// Liest einen Auftrag aus der Datei des Ausstands. Ist etwas nicht lesbar,
  /// wirft es, statt einen Teil zu erfinden.
  static Schreibauftrag ausJson(Map<String, Object?> json) {
    final wert = json['art'];
    final art = wert is String ? Art.aus(wert) : null;
    final pfad = json['pfad'];
    final inhalt = json['inhalt'];
    final zusammenfassung = json['zusammenfassung'];
    final version = json['version'];
    final anhaengen = json['anhaengen'];
    if (art == null ||
        pfad is! String ||
        inhalt is! String ||
        zusammenfassung is! String ||
        (version != null && version is! String) ||
        anhaengen is! bool) {
      throw const FormatException('ein Eintrag ist unvollständig');
    }
    return Schreibauftrag(
      pfad: pfad,
      inhalt: inhalt,
      art: art,
      zusammenfassung: zusammenfassung,
      version: version as String?,
      anhaengen: anhaengen,
    );
  }
}

/// Schreibt den Auftrag am Ort und liest zurück (über den Speicher). Die Prüfung
/// des Stands läuft im Speicher, unmittelbar vor dem Schreiben.
Future<Geschrieben> schreibeAuftrag(
  LokalerSpeicher speicher,
  Schreibauftrag auftrag,
) {
  return auftrag.anhaengen
      ? speicher.haengeAn(
          auftrag.pfad,
          auftrag.inhalt,
          erwartet: auftrag.version,
        )
      : speicher.schreibe(
          auftrag.pfad,
          auftrag.inhalt,
          erwartet: auftrag.version,
        );
}

/// Fragt die Lehrkraft in moocp nach der Freigabe. [titel] sagt, was geschieht;
/// [vermerk] ergänzt die Zusammenfassung um den Zusammenhang (etwa „aus dem Ausstand“).
Future<Freigabeausgang> frageFreigabe(
  AppAnschluss app,
  String? aufruf,
  Schreibauftrag auftrag, {
  required String titel,
  String? vermerk,
}) {
  return app.freigabe(
    aufruf: aufruf,
    titel: titel,
    zusammenfassung:
        'Datei: ${auftrag.pfad}\nArt: ${auftrag.art.bezeichnung}'
        '${vermerk == null ? '' : '\n$vermerk'}\n\n${auftrag.zusammenfassung}',
    ab: auftrag.stufe,
  );
}
