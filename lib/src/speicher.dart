import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'fehler.dart';
import 'pfad.dart';

/// Ein Eintrag eines Ordners im Kontextbereich.
class Eintrag {
  const Eintrag(this.name, {required this.istOrdner});

  final String name;
  final bool istOrdner;
}

/// Der Inhalt einer Datei mit ihrer Version. Die Version ist ein Stand-Merkmal
/// des Ortes (E3): beim lokalen Ordner der sha256-Wert des Inhalts, beim
/// WebDAV-Server das ETag. Ein Schreibvorgang vergleicht sie vor dem Ändern.
class Gelesen {
  const Gelesen(this.text, this.version);

  final String text;
  final String version;
}

/// Die rohen Bytes einer Datei mit ihrer Version, wie der Ort sie liefert.
/// Schreibvorgänge arbeiten mit Bytes, damit kein Zeichensatz etwas verändert.
class Inhalt {
  const Inhalt(this.bytes, this.version);

  final List<int> bytes;
  final String version;
}

/// Wer die Bedingung „die Datei hat noch den gelesenen Stand“ beim Schreiben
/// durchgesetzt hat (A3, ADR 0009). Das Plugin behauptet nie mehr, als geschah.
enum Bedingung {
  /// Der lokale Ordner: Das Plugin prüft unmittelbar vor dem Schreiben (E1).
  lokal,

  /// Der Server hat die Bedingung geprüft (`If-Match`, `If-None-Match`, E3).
  vomServer,

  /// Der Server sendet kein starkes ETag. Das Plugin hat den Stand selbst
  /// unmittelbar vor dem Schreiben verglichen; dazwischen ist ein Wettlauf möglich.
  nurVomPlugin,
}

/// Der Hinweis in der Antwort, wenn der Server die Bedingung nicht erzwungen hat.
const hinweisNichtErzwungen =
    'check: not enforced by the server. It sends no ETag, so the plugin compared '
    'the version itself just before writing. A change made by someone else in that '
    'short window would have been overwritten unnoticed; the read-back only shows '
    'that the written bytes are there.';

/// Das Präfix einer Version, die aus der Prüfsumme der Bytes entstand, weil der
/// Server kein starkes ETag sendet (ADR 0009). Sie unterscheidet diese Version
/// von einem ETag und von der Prüfsumme des lokalen Ortes.
const inhaltsVersionPraefix = 'sha256:';

/// Das Ergebnis eines Schreibvorgangs. [verifiziert] ist das Urteil des
/// Plugins: Der Inhalt, den es zurückgelesen hat, ist der geschriebene.
class Geschrieben {
  const Geschrieben(
    this.version, {
    required this.verifiziert,
    this.bedingung = Bedingung.lokal,
  });

  final String version;
  final bool verifiziert;
  final Bedingung bedingung;

  /// Die Zeile für die Antwort, wenn der Server nichts erzwungen hat; sonst null.
  String? get hinweis =>
      bedingung == Bedingung.nurVomPlugin ? hinweisNichtErzwungen : null;
}

/// Der Kontextbereich an einem Ort, unabhängig davon, wo er liegt (E3). Die
/// Regeln für Pfade und Schreibarten stehen hier einmal; ein Ort liefert nur
/// das Lesen, das Ablegen und das Verschieben seiner Dateien.
///
/// Jeder Vorgang bleibt unterhalb der Wurzel. Schreiben und Anhängen lesen
/// zurück und melden erst bei Gleichheit `verifiziert`.
abstract class Kontextspeicher {
  /// Die Einträge eines Ordners, sortiert nach Namen.
  Future<List<Eintrag>> liste(String relativ);

  /// Der Inhalt einer Datei mit Version; null, wenn es die Datei nicht gibt.
  /// Ein Ordner ist ein Fehler.
  Future<Inhalt?> holeInhalt(String relativ);

  /// Legt die Bytes an oder ersetzt sie. [erwartet] ist die Version, die die KI
  /// gelesen hat; null heißt: die Datei soll neu entstehen. Die Bedingung gilt
  /// an jedem Ort: Ist der Stand nicht mehr der erwartete, wirft es
  /// [KontextKonflikt] und schreibt nichts. Ohne Rücklesen. Das Ergebnis sagt,
  /// wer die Bedingung durchgesetzt hat.
  Future<Bedingung> ablegen(
    String relativ,
    List<int> bytes, {
    required String? erwartet,
  });

  /// Verschiebt eine Datei innerhalb der Wurzel, nur wenn ihr Stand noch [erwartet]
  /// ist. Ein vorhandenes Ziel wird nie ersetzt: Dann wirft es [KontextKonflikt]
  /// und lässt beide Namen, wie sie waren. Die Prüfung am Ort geschieht im selben
  /// Schritt wie das Verschieben, nicht davor (siehe ADR 0006). Das Ergebnis sagt,
  /// wer die Bedingung durchgesetzt hat.
  Future<Bedingung> verschiebeDatei(
    String von,
    String nach, {
    required String erwartet,
  });

  /// Ob ein Eintrag (Datei oder Ordner) unter der Wurzel existiert; die Wurzel
  /// selbst existiert. Ein fehlender Elternordner oder ein Pfad, der hinausführt,
  /// heißt nein. Ein Ausfall des Ortes bleibt ein Ausfall und wird weitergereicht.
  Future<bool> existiert(String relativ) async {
    final teile = pfadTeile(relativ);
    if (teile.isEmpty) return true;
    try {
      final eltern = teile.sublist(0, teile.length - 1).join('/');
      final eintraege = await liste(eltern);
      return eintraege.any((e) => e.name == teile.last);
    } on KontextNichtErreichbar {
      rethrow;
    } on KontextFehler {
      return false;
    }
  }

  /// Liest eine Textdatei mit Version (für `context_read`).
  Future<Gelesen> lese(String relativ) async {
    final inhalt = await holeInhalt(relativ);
    if (inhalt == null) {
      throw KontextFehler("'$relativ' does not exist in the context area.");
    }
    final String text;
    try {
      text = utf8.decode(inhalt.bytes);
    } on FormatException {
      throw KontextFehler(
        "'$relativ' is not UTF-8 text; only text files can be read.",
      );
    }
    return Gelesen(text, inhalt.version);
  }

  /// Prüft vor einem Schreibvorgang, ob die Datei noch den Stand hat, den die KI
  /// gelesen hat. [erwartet] null heißt: die Datei soll neu entstehen und darf
  /// nicht existieren. Ohne Schreiben; wirft [KontextKonflikt].
  Future<void> pruefeStand(String relativ, {required String? erwartet}) async {
    final aktuell = (await holeInhalt(relativ))?.version;
    if (erwartet == null && aktuell != null) {
      throw KontextKonflikt(
        "'$relativ' already exists. Read it and pass its version to replace it, "
        'or choose another path.',
      );
    }
    if (erwartet != null && aktuell == null) {
      throw KontextKonflikt(
        "'$relativ' does not exist (any more). Pass no version to create it.",
      );
    }
    if (erwartet != null && aktuell != erwartet) {
      throw KontextKonflikt(
        "'$relativ' changed since it was read. Read it again and check the "
        'change before writing.',
      );
    }
  }

  /// Schreibt die Datei (neu oder ersetzt) und liest sie danach zurück.
  Future<Geschrieben> schreibe(
    String relativ,
    String inhalt, {
    required String? erwartet,
  }) {
    // Die Bindung an den Pfad gilt hier, unabhängig von der Art, die die KI nennt.
    if (istJournalPfad(relativ)) {
      throw KontextFehler(
        "A journal is only appended, never replaced: use context_append for '$relativ'.",
      );
    }
    final neu = utf8.encode(inhalt);
    return _speichern(relativ, erwartet: erwartet, neuerInhalt: (_) => neu);
  }

  /// Hängt [text] an die Datei an und liest sie danach zurück. Fehlt die Datei
  /// und ist [erwartet] null, entsteht sie mit dem Text. Ein Zeilenende vor
  /// und nach dem Text sorgt dafür, dass Einträge nicht zusammenlaufen.
  Future<Geschrieben> haengeAn(
    String relativ,
    String text, {
    required String? erwartet,
  }) {
    final anhang = utf8.encode(text.endsWith('\n') ? text : '$text\n');
    return _speichern(
      relativ,
      erwartet: erwartet,
      neuerInhalt: (alt) {
        final trenner = alt.isEmpty || alt.last == 0x0a ? <int>[] : <int>[0x0a];
        return [...alt, ...trenner, ...anhang];
      },
    );
  }

  /// Verschiebt eine Datei innerhalb der Wurzel, nachdem der Stand der Quelle
  /// geprüft ist. Journale wandern nicht: Sie werden nur angehängt.
  Future<Bedingung> verschiebe(
    String von,
    String nach, {
    required String erwartet,
  }) async {
    schreibTeile(von);
    schreibTeile(nach);
    if (istJournalPfad(von) || istJournalPfad(nach)) {
      throw KontextFehler(
        "A journal is never moved: '$von' stays where it is.",
      );
    }
    await pruefeStand(von, erwartet: erwartet);
    if (await holeInhalt(nach) != null) {
      throw KontextKonflikt(
        "'$nach' already exists; nothing was moved. Choose another path.",
      );
    }
    return verschiebeDatei(von, nach, erwartet: erwartet);
  }

  Future<Geschrieben> _speichern(
    String relativ, {
    required String? erwartet,
    required List<int> Function(List<int> alt) neuerInhalt,
  }) async {
    schreibTeile(relativ);
    await pruefeStand(relativ, erwartet: erwartet);
    final alt = (await holeInhalt(relativ))?.bytes ?? const <int>[];
    final neu = neuerInhalt(alt);
    var bedingung = await ablegen(relativ, neu, erwartet: erwartet);
    final zurueck = await holeInhalt(relativ);
    if (zurueck == null) {
      return Geschrieben('', verifiziert: false, bedingung: bedingung);
    }
    // Eine neue Datei wird mit `If-None-Match: *` angelegt; ob der Server das
    // erzwingt, zeigt sich daran, ob er für die Datei ein ETag kennt (ADR 0009).
    if (bedingung == Bedingung.vomServer &&
        zurueck.version.startsWith(inhaltsVersionPraefix)) {
      bedingung = Bedingung.nurVomPlugin;
    }
    return Geschrieben(
      zurueck.version,
      verifiziert: _gleich(zurueck.bytes, neu),
      bedingung: bedingung,
    );
  }

  static bool _gleich(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Der Kontextbereich in einem lokalen Ordner. Liest und schreibt nur
/// unterhalb der Wurzel; eine Verknüpfung, die aus der Wurzel führt, wird
/// abgewiesen, bevor etwas gelesen oder geschrieben wird.
class LokalerSpeicher extends Kontextspeicher {
  LokalerSpeicher._(this._wurzel);

  /// Die Wurzel mit aufgelösten Verknüpfungen; Grundlage aller Prüfungen.
  final String _wurzel;

  /// Öffnet die Wurzel. Fehlt sie, ist das ein Fehler mit diesem Grund.
  static Future<LokalerSpeicher> oeffnen(String pfad) async {
    if (await FileSystemEntity.type(pfad) != FileSystemEntityType.directory) {
      throw const KontextNichtErreichbar(
        'The context root folder does not exist.',
      );
    }
    try {
      return LokalerSpeicher._(await Directory(pfad).resolveSymbolicLinks());
    } on FileSystemException {
      throw const KontextNichtErreichbar(
        'The context root folder cannot be read.',
      );
    }
  }

  @override
  Future<List<Eintrag>> liste(String relativ) async {
    final ziel = await _aufloesen(relativ);
    if (await FileSystemEntity.type(ziel) != FileSystemEntityType.directory) {
      throw KontextFehler("'$relativ' is not a folder.");
    }
    try {
      final eintraege = <Eintrag>[];
      await for (final e in Directory(ziel).list(followLinks: false)) {
        final name = p.basename(e.path);
        final istOrdner = await FileSystemEntity.isDirectory(e.path);
        eintraege.add(Eintrag(name, istOrdner: istOrdner));
      }
      eintraege.sort((a, b) => a.name.compareTo(b.name));
      return eintraege;
    } on FileSystemException {
      throw KontextFehler("The folder '$relativ' cannot be read.");
    }
  }

  @override
  Future<Inhalt?> holeInhalt(String relativ) async {
    final teile = pfadTeile(relativ);
    if (teile.isEmpty) {
      throw KontextFehler(
        "'$relativ' is a folder; use context_list for folders.",
      );
    }
    final ziel = await _zielDatei(teile);
    if (ziel == null) return null;
    if (await FileSystemEntity.type(ziel) == FileSystemEntityType.directory) {
      throw KontextFehler(
        "'$relativ' is a folder; use context_list for folders.",
      );
    }
    try {
      final bytes = await File(ziel).readAsBytes();
      return Inhalt(bytes, _version(bytes));
    } on FileSystemException {
      throw KontextFehler("The file '$relativ' cannot be read.");
    }
  }

  @override
  Future<Bedingung> ablegen(
    String relativ,
    List<int> bytes, {
    required String? erwartet,
  }) async {
    final teile = schreibTeile(relativ);
    await pruefeStand(relativ, erwartet: erwartet);
    var ziel = await _zielDatei(teile);
    ziel ??= await _anlegen(teile);
    try {
      await File(ziel).writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      throw KontextFehler("The file '$relativ' cannot be written.");
    }
    return Bedingung.lokal;
  }

  /// Verschiebt ohne Überschreiben: Zuerst bekommt das Ziel einen zweiten Namen
  /// für dieselbe Datei (`ln` ohne `-f`; `link(2)` scheitert atomar, wenn der
  /// Name schon existiert). Danach wird der Stand des Inhalts unter dem neuen
  /// Namen geprüft; passt er nicht, wird nur der neue Name entfernt. Erst dann
  /// verschwindet der alte Name. Gibt es keine harten Verknüpfungen, scheitert
  /// es mit Grund; es wird dann nichts verschoben und nichts überschrieben.
  @override
  Future<Bedingung> verschiebeDatei(
    String von,
    String nach, {
    required String erwartet,
  }) async {
    final quelle = await _zielDatei(pfadTeile(von));
    if (quelle == null) {
      throw KontextFehler("'$von' does not exist in the context area.");
    }
    final ziel = await _anlegen(pfadTeile(nach));
    final ergebnis = await Process.run('ln', ['--', quelle, ziel]);
    if (ergebnis.exitCode != 0) {
      if (await FileSystemEntity.type(ziel, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw KontextKonflikt(
          "'$nach' already exists; nothing was moved. Choose another path.",
        );
      }
      throw KontextFehler(
        "'$von' cannot be moved to '$nach' without overwriting: hard links are not available here. Nothing was moved.",
      );
    }
    final List<int> bytes;
    try {
      bytes = await File(ziel).readAsBytes();
    } on FileSystemException {
      await _entferneNamen(ziel);
      throw KontextFehler("'$von' cannot be read after the move; nothing was moved.");
    }
    if (_version(bytes) != erwartet) {
      await _entferneNamen(ziel);
      throw KontextKonflikt(
        "'$von' changed since it was read. Read it again and check the change before moving.",
      );
    }
    try {
      await File(quelle).delete();
    } on FileSystemException {
      throw KontextFehler(
        "'$von' was copied to '$nach', but the original could not be removed. Both names exist; nothing was overwritten.",
      );
    }
    return Bedingung.lokal;
  }

  /// Entfernt einen Namen, den dieser Aufruf selbst angelegt hat. Die Datei
  /// dahinter bleibt, weil die Quelle sie noch hält.
  static Future<void> _entferneNamen(String pfad) async {
    try {
      await File(pfad).delete();
    } on FileSystemException {
      // Der Name bleibt bestehen; die Antwort nennt den Fehler trotzdem.
    }
  }

  /// Prüft einen relativen Pfad und löst ihn unter der Wurzel auf. Der Pfad
  /// darf nur hinab führen; jede Auflösung, die aus der Wurzel führt, endet
  /// hier mit einem Fehler.
  Future<String> _aufloesen(String relativ) async {
    final teile = pfadTeile(relativ);
    final kandidat = p.joinAll([_wurzel, ...teile]);
    if (await FileSystemEntity.type(kandidat, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw KontextFehler("'$relativ' does not exist in the context area.");
    }
    return _echt(kandidat);
  }

  /// Der echte Pfad der Datei, wenn sie existiert; sonst null. Ein fehlender
  /// Ordner heißt: die Datei fehlt. Eine Verknüpfung nach außen wird abgewiesen.
  Future<String?> _zielDatei(List<String> teile) async {
    var ordner = _wurzel;
    for (final t in teile.sublist(0, teile.length - 1)) {
      final kandidat = p.join(ordner, t);
      if (await FileSystemEntity.type(kandidat, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return null;
      }
      ordner = await _ordner(kandidat, t);
    }
    final kandidat = p.join(ordner, teile.last);
    if (await FileSystemEntity.type(kandidat, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    return _echt(kandidat);
  }

  /// Legt die fehlenden Ordner des Pfads unter der Wurzel an und liefert den
  /// Pfad der Datei. Jeder Ordner wird vor dem Anlegen darauf geprüft, dass er
  /// unter der Wurzel bleibt.
  Future<String> _anlegen(List<String> teile) async {
    var ordner = _wurzel;
    for (final t in teile.sublist(0, teile.length - 1)) {
      final kandidat = p.join(ordner, t);
      if (await FileSystemEntity.type(kandidat, followLinks: false) ==
          FileSystemEntityType.notFound) {
        try {
          await Directory(kandidat).create();
        } on FileSystemException {
          throw KontextFehler("The folder '$t' cannot be created.");
        }
      }
      ordner = await _ordner(kandidat, t);
    }
    return p.join(ordner, teile.last);
  }

  /// Ein Ordner des Pfads, aufgelöst; er muss ein Ordner unter der Wurzel sein.
  Future<String> _ordner(String kandidat, String name) async {
    final echt = await _echt(kandidat);
    if (await FileSystemEntity.type(echt) != FileSystemEntityType.directory) {
      throw KontextFehler("'$name' is not a folder.");
    }
    return echt;
  }

  /// Löst einen vorhandenen Pfad auf und prüft, dass er unter der Wurzel liegt.
  Future<String> _echt(String pfad) async {
    final String echt;
    try {
      final eintrag = await FileSystemEntity.isDirectory(pfad)
          ? Directory(pfad)
          : File(pfad);
      echt = await eintrag.resolveSymbolicLinks();
    } on FileSystemException {
      // Eine Verknüpfung, deren Ziel fehlt, kann auf etwas außerhalb zeigen.
      throw const KontextFehler(meldungAusserhalb);
    }
    if (echt != _wurzel && !p.isWithin(_wurzel, echt)) {
      throw const KontextFehler(meldungAusserhalb);
    }
    return echt;
  }

  static String _version(List<int> bytes) => sha256.convert(bytes).toString();
}
