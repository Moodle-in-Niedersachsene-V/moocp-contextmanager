import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'fehler.dart';

/// Ein Eintrag eines Ordners im Kontextbereich.
class Eintrag {
  const Eintrag(this.name, {required this.istOrdner});

  final String name;
  final bool istOrdner;
}

/// Der Inhalt einer Datei mit ihrer Version. Die Version ist der sha256-Wert
/// des Inhalts; ein Schreibvorgang vergleicht sie vor dem Ändern.
class Gelesen {
  const Gelesen(this.text, this.version);

  final String text;
  final String version;
}

/// Das Ergebnis eines Schreibvorgangs. [verifiziert] ist das Urteil des
/// Plugins: Der Inhalt, den es zurückgelesen hat, ist der geschriebene.
class Geschrieben {
  const Geschrieben(this.version, {required this.verifiziert});

  final String version;
  final bool verifiziert;
}

/// Der Kontextbereich in einem lokalen Ordner. Liest und schreibt nur
/// unterhalb der Wurzel: Ein Pfad, der hinausführt (`..`, absolut,
/// Verknüpfung nach außen), wird abgewiesen, bevor etwas gelesen oder
/// geschrieben wird.
class LokalerSpeicher {
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

  /// Die Einträge eines Ordners, sortiert nach Namen. Ordner tragen am Ende
  /// einen Schrägstrich (wird vom Aufrufer angehängt).
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

  /// Der Inhalt einer Textdatei mit ihrer Version.
  Future<Gelesen> lese(String relativ) async {
    final ziel = await _aufloesen(relativ);
    if (await FileSystemEntity.type(ziel) == FileSystemEntityType.directory) {
      throw KontextFehler(
        "'$relativ' is a folder; use context_list for folders.",
      );
    }
    final List<int> bytes;
    try {
      bytes = await File(ziel).readAsBytes();
    } on FileSystemException {
      throw KontextFehler("The file '$relativ' cannot be read.");
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw KontextFehler(
        "'$relativ' is not UTF-8 text; only text files can be read.",
      );
    }
    return Gelesen(text, _version(bytes));
  }

  /// Prüft vor einem Schreibvorgang, ob die Datei noch den Stand hat, den die KI
  /// gelesen hat. [erwartet] null heißt: die Datei soll neu entstehen und darf
  /// nicht existieren. Ohne Schreiben; wirft [KontextKonflikt].
  Future<void> pruefeStand(String relativ, {required String? erwartet}) async {
    final ziel = await _zielDatei(_schreibTeile(relativ));
    final aktuell = ziel == null
        ? null
        : _version(await File(ziel).readAsBytes());
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

  Future<Geschrieben> _speichern(
    String relativ, {
    required String? erwartet,
    required List<int> Function(List<int> alt) neuerInhalt,
  }) async {
    await pruefeStand(relativ, erwartet: erwartet);
    final teile = _schreibTeile(relativ);
    var ziel = await _zielDatei(teile);
    final alt = ziel == null ? <int>[] : await File(ziel).readAsBytes();
    final neu = neuerInhalt(alt);
    ziel ??= await _anlegen(teile);
    await File(ziel).writeAsBytes(neu, flush: true);
    final zurueck = await File(ziel).readAsBytes();
    return Geschrieben(_version(zurueck), verifiziert: _gleich(zurueck, neu));
  }

  /// Prüft den relativen Pfad und löst ihn unter der Wurzel auf. Der Pfad
  /// darf nur hinab führen; jede Auflösung, die aus der Wurzel führt, endet
  /// hier mit einem Fehler.
  Future<String> _aufloesen(String relativ) async {
    final teile = _teile(relativ);
    final kandidat = p.joinAll([_wurzel, ...teile]);
    if (await FileSystemEntity.type(kandidat, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw KontextFehler("'$relativ' does not exist in the context area.");
    }
    return _echt(kandidat);
  }

  /// Prüft einen Schreibpfad allein am Text, ohne die Wurzel zu öffnen: Ein
  /// Auftrag mit einem Pfad, der hinausführt, kommt nie in den Ausstand.
  static void pruefeSchreibPfad(String relativ) => _schreibTeile(relativ);

  /// Der Pfad für einen Schreibvorgang: wie beim Lesen, dazu nur `.md`-Dateien.
  static List<String> _schreibTeile(String relativ) {
    final teile = _teile(relativ);
    if (teile.isEmpty || teile.last == '.md' || !teile.last.endsWith('.md')) {
      throw const KontextFehler(
        'Only .md files can be written; the path must end in .md.',
      );
    }
    return teile;
  }

  /// Die Bestandteile eines relativen Pfads. Absolute Pfade, `~` und `..`
  /// werden abgewiesen, bevor etwas auf der Platte geschieht.
  static List<String> _teile(String relativ) {
    // Steuerzeichen (auch Zeilenende und Tab) haben in einem Dateinamen nichts zu suchen.
    if (relativ.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      throw const KontextFehler(
        'The path contains a control character and is not valid.',
      );
    }
    if (p.posix.isAbsolute(relativ) ||
        p.windows.isAbsolute(relativ) ||
        relativ.startsWith('~')) {
      throw const KontextFehler(_ausserhalb);
    }
    final teile = relativ
        .split('/')
        .where((t) => t.isNotEmpty && t != '.')
        .toList();
    if (teile.contains('..')) {
      throw const KontextFehler(_ausserhalb);
    }
    return teile;
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
    final echt = await _echt(kandidat);
    if (await FileSystemEntity.type(echt) == FileSystemEntityType.directory) {
      throw KontextFehler(
        "'${p.joinAll(teile)}' is a folder; only files can be written.",
      );
    }
    return echt;
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
      throw const KontextFehler(_ausserhalb);
    }
    if (echt != _wurzel && !p.isWithin(_wurzel, echt)) {
      throw const KontextFehler(_ausserhalb);
    }
    return echt;
  }

  static String _version(List<int> bytes) => sha256.convert(bytes).toString();

  static bool _gleich(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const _ausserhalb =
      'The path is outside the context area and is refused.';
}

/// Ob ein Pfad zum Journal gehört: Einträge unter `journal/` und das alte
/// Journal im Wurzelordner (`journal-*.md`, Coursepilot). Das Journal wird nur
/// angehängt, unabhängig davon, welche Art die KI angibt. Der Pfad allein
/// entscheidet, nicht die Art.
///
/// Der Vergleich ignoriert Groß- und Kleinschreibung: Auf macOS und Windows
/// ist `Journal/x.md` dieselbe Datei wie `journal/x.md`, und die Sperre
/// darf nicht über die Schreibweise umgangen werden.
bool istJournalPfad(String relativ) {
  final teile = relativ
      .split('/')
      .where((t) => t.isNotEmpty && t != '.')
      .map((t) => t.toLowerCase())
      .toList();
  if (teile.isEmpty) return false;
  if (teile.length > 1) return teile.first == 'journal';
  return teile.first.startsWith('journal-') && teile.first.endsWith('.md');
}
