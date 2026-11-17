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
/// des Inhalts; ein Schreibvorgang (später) vergleicht sie vor dem Ändern.
class Gelesen {
  const Gelesen(this.text, this.version);

  final String text;
  final String version;
}

/// Der Kontextbereich in einem lokalen Ordner. Liest nur unterhalb der Wurzel:
/// Ein Pfad, der hinausführt (`..`, absolut, Verknüpfung nach außen), wird
/// abgewiesen, bevor etwas gelesen wird.
class LokalerSpeicher {
  LokalerSpeicher._(this._wurzel);

  /// Die Wurzel mit aufgelösten Verknüpfungen; Grundlage aller Prüfungen.
  final String _wurzel;

  /// Öffnet die Wurzel. Fehlt sie, ist das ein Fehler mit diesem Grund.
  static Future<LokalerSpeicher> oeffnen(String pfad) async {
    if (await FileSystemEntity.type(pfad) != FileSystemEntityType.directory) {
      throw const KontextFehler(
        'The context root folder does not exist.',
      );
    }
    try {
      return LokalerSpeicher._(await Directory(pfad).resolveSymbolicLinks());
    } on FileSystemException {
      throw const KontextFehler('The context root folder cannot be read.');
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
      throw KontextFehler("'$relativ' is a folder; use context_list for folders.");
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
      throw KontextFehler("'$relativ' is not UTF-8 text; only text files can be read.");
    }
    return Gelesen(text, sha256.convert(bytes).toString());
  }

  /// Prüft den relativen Pfad und löst ihn unter der Wurzel auf. Der Pfad
  /// darf nur hinab führen; jede Auflösung, die aus der Wurzel führt, endet
  /// hier mit einem Fehler.
  Future<String> _aufloesen(String relativ) async {
    if (relativ.contains('\u0000')) {
      throw const KontextFehler('The path is not valid.');
    }
    if (p.posix.isAbsolute(relativ) || p.windows.isAbsolute(relativ) || relativ.startsWith('~')) {
      throw const KontextFehler(_ausserhalb);
    }
    final teile = relativ.split('/').where((t) => t.isNotEmpty && t != '.').toList();
    if (teile.contains('..')) {
      throw const KontextFehler(_ausserhalb);
    }
    final kandidat = p.joinAll([_wurzel, ...teile]);
    if (await FileSystemEntity.type(kandidat, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw KontextFehler("'$relativ' does not exist in the context area.");
    }
    final String echt;
    try {
      final eintrag = await FileSystemEntity.isDirectory(kandidat)
          ? Directory(kandidat)
          : File(kandidat);
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

  static const _ausserhalb =
      'The path is outside the context area and is refused.';
}
