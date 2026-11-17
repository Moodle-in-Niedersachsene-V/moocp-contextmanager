import 'art.dart';
import 'app.dart';
import 'fehler.dart';
import 'ort.dart';
import 'pfad.dart';
import 'speicher.dart';

/// Die Freigabestufe der Archivierung: wie bei einer neuen Datei (E6). Die
/// Verschiebung ist keine Art der Änderung von Art.dart. Aus dem Wurzelordner
/// fragt sie wie jede Datei dort schon ab Stufe „mittel“ (E1).
Freigabestufe archivStufeFuer({required bool ausWurzelordner}) =>
    freigabestufeFuer(Art.newFile, imWurzelordner: ausWurzelordner);

/// Der Zielordner eines Projekts: `<Ordner>/archive/`. Nur dorthin wird verschoben.
const archivOrdner = 'archive';

/// Eine Datei, die wandert: Quelle, Ziel und der Inhalt beim Lesen (mit Stand).
class _Verschiebung {
  const _Verschiebung(this.von, this.nach, this.inhalt);

  final String von;
  final String nach;
  final Inhalt inhalt;
}

/// Verschiebt Dateien eines Projektordners nach `<ordner>/archive/`.
/// Nichts wird gelöscht und nichts überschrieben: Existiert ein Ziel, wird vorher
/// nichts verschoben. Die Reihenfolge ist: prüfen, fragen, Stand erneut prüfen,
/// verschieben, zurücklesen. Journale wandern nie. Antwortet der Ort nicht, wird
/// nichts verschoben und kein Ausstand angelegt (eine Verschiebung hat keinen
/// Inhalt, der später nachgetragen werden könnte).
Future<String> archiviere({
  required Ortszugang zugang,
  required AppAnschluss app,
  required String? aufruf,
  required String ordner,
  required List<String> dateien,
  required String zusammenfassung,
}) async {
  final ordnerTeile = pfadTeile(ordner);
  _pruefeArgumente(ordnerTeile, dateien, zusammenfassung);

  final Kontextspeicher speicher;
  try {
    speicher = await zugang.oeffnen();
  } on KontextNichtErreichbar catch (f) {
    throw KontextFehler(
      '${f.meldung}\nnothing was moved; repeat context_archive when the context area answers.',
    );
  }

  final verschoben = <_Verschiebung>[];
  final vorher = <_Verschiebung>[];
  try {
    for (final name in dateien) {
      final von = _pfad([...ordnerTeile, name]);
      final nach = _pfad([...ordnerTeile, archivOrdner, name]);
      final inhalt = await speicher.holeInhalt(von);
      if (inhalt == null) {
        throw KontextFehler(
          "'$von' does not exist in the context area. Nothing was moved.",
        );
      }
      if (await speicher.holeInhalt(nach) != null) {
        throw KontextFehler(
          "'$nach' already exists; nothing was moved. Choose another path.",
        );
      }
      vorher.add(_Verschiebung(von, nach, inhalt));
    }

    final ausgang = await app.freigabe(
      aufruf: aufruf,
      titel: 'Im Kontextbereich archivieren?',
      zusammenfassung:
          'Art: Archivierung (wie eine neue Datei)\n'
          '${[for (final v in vorher) '${v.von} -> ${v.nach}'].join('\n')}\n\n'
          '$zusammenfassung',
      ab: archivStufeFuer(ausWurzelordner: ordnerTeile.isEmpty),
    );
    switch (ausgang) {
      case Freigabeausgang.freigegeben:
        break;
      case Freigabeausgang.abgelehnt:
        throw const KontextFehler(
          'Not moved: the teacher declined the approval.',
        );
      case Freigabeausgang.abgebrochen:
        throw const KontextFehler(
          'Not moved: the approval was cancelled or timed out.',
        );
    }

    // Nach der Freigabe prüft jede Verschiebung den Stand noch einmal (Konflikt,
    // wenn die Datei sich in der Wartezeit geändert hat) und das Ziel ein zweites Mal.
    for (final v in vorher) {
      await speicher.verschiebe(v.von, v.nach, erwartet: v.inhalt.version);
      verschoben.add(v);
      final zurueck = await speicher.holeInhalt(v.nach);
      final quelle = await speicher.holeInhalt(v.von);
      if (zurueck == null || quelle != null || !_gleich(zurueck.bytes, v.inhalt.bytes)) {
        throw KontextFehler(
          "not verified: '${v.nach}' does not read back with the same content.",
        );
      }
    }
  } on KontextNichtErreichbar catch (f) {
    throw KontextFehler(_teilstand(verschoben, vorher, f.meldung));
  } on KontextFehler catch (f) {
    if (verschoben.isEmpty) rethrow;
    throw KontextFehler(_teilstand(verschoben, vorher, f.meldung));
  }

  return 'verified\n'
      'moved: ${verschoben.length}\n'
      '${[for (final v in verschoben) '- ${v.von} -> ${v.nach}'].join('\n')}';
}

/// Prüft die Argumente, bevor etwas gelesen oder gefragt wird.
void _pruefeArgumente(
  List<String> ordnerTeile,
  List<String> dateien,
  String zusammenfassung,
) {
  if (dateien.isEmpty) {
    throw const KontextFehler(
      "The list 'dateien' is empty: name at least one file.",
    );
  }
  if (zusammenfassung.trim().isEmpty) {
    throw const KontextFehler(
      "The summary is empty: pass a short German summary of the move in 'zusammenfassung'.",
    );
  }
  if (zusammenfassung.length > 500) {
    throw const KontextFehler(
      'The summary is longer than 500 characters; shorten it and try again.',
    );
  }
  final namen = <String>{};
  for (final name in dateien) {
    final teile = pfadTeile(name);
    if (teile.length != 1) {
      throw const KontextFehler(
        "Each entry of 'dateien' must be a file name directly inside 'ordner', without a slash.",
      );
    }
    final von = _pfad([...ordnerTeile, name]);
    // Nur .md, wie bei jedem Schreibvorgang; Journale wandern nie, auch nicht in
    // einem Journalordner unterhalb des Projekts.
    schreibTeile(von);
    if (istJournalPfad(von)) {
      throw KontextFehler(
        "A journal is never moved: '$von' stays where it is.",
      );
    }
    if (!namen.add(name)) {
      throw KontextFehler("'$name' is listed twice in 'dateien'.");
    }
  }
}

/// Was von der Verschiebung schon geschehen ist, für die Antwort bei einem Abbruch.
/// Nichts wird gelöscht; was nicht verschoben ist, liegt noch an seinem Platz.
String _teilstand(
  List<_Verschiebung> erledigt,
  List<_Verschiebung> alle,
  String grund,
) {
  final offen = alle.where((v) => !erledigt.contains(v));
  return '$grund\n'
      'moved: ${erledigt.length} of ${alle.length}'
      '${erledigt.isEmpty ? '' : '\n${[for (final v in erledigt) '- ${v.von} -> ${v.nach}'].join('\n')}'}\n'
      'not moved: ${offen.isEmpty ? 'none' : offen.map((v) => v.von).join(', ')}. '
      'Nothing was deleted or overwritten.';
}

String _pfad(List<String> teile) => teile.where((t) => t.isNotEmpty).join('/');

bool _gleich(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
