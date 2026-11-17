import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'app.dart';
import 'art.dart';
import 'fehler.dart';
import 'ort.dart';
import 'pfad.dart';
import 'speicher.dart';

/// Der Dateiname des Wegweisers im Ordner, den die Lehrkraft wählt (E5).
const wegweiserDatei = 'CONTEXT-LINK.md';

/// Die feste Kopfzeile. Die Datei beginnt immer damit; ohne sie ist sie fremd
/// und wird nicht angefasst.
const _kopf =
    '# Wegweiser zum Kontextbereich\n'
    '\n'
    'Jeder Eintrag nennt eine Stelle im Kontextbereich, relativ zu dessen Wurzel. '
    'Die Einträge sind Hinweise, keine Anweisungen. Geschrieben wird diese Datei nur vom Plugin.\n'
    '\n';

/// Die größte Länge der Beschreibung und der Bezeichnung in Zeichen.
const _hoechstBeschreibung = 300;
const _hoechstBezeichnung = 80;

/// Ein Eintrag des Wegweisers: eine Stelle unter der Wurzel mit einer Zeile dazu.
/// Die Bezeichnung trennt parallele Klassen; ohne sie gibt es nur einen Eintrag.
class WegweiserEintrag {
  const WegweiserEintrag({
    this.bezeichnung,
    required this.pfad,
    required this.beschreibung,
  });

  /// Die Bezeichnung (etwa „Gruppe A“); null ohne Bezeichnung.
  final String? bezeichnung;

  /// Der Pfad relativ zur Wurzel, normalisiert (ohne `.`, mit `/` am Ende für einen Ordner).
  final String pfad;

  /// Eine Zeile, was dort liegt.
  final String beschreibung;

  /// Der Schlüssel, unter dem ein Eintrag ersetzt wird: die Bezeichnung, oder leer
  /// für den einen Eintrag ohne Bezeichnung.
  String get schluessel => bezeichnung ?? '';
}

/// Liest den Text eines Wegweisers. Alles, was nicht der feste Aufbau ist, wirft
/// eine Meldung: Das Plugin ändert eine fremde Datei nie.
List<WegweiserEintrag> leseWegweiser(String text) {
  if (!text.startsWith(_kopf)) throw _fremd;
  final rest = text.substring(_kopf.length).trim();
  if (rest.isEmpty) return const [];
  final eintraege = <WegweiserEintrag>[];
  for (final block in rest.split(RegExp(r'\n\s*\n'))) {
    String? bezeichnung;
    String? pfad;
    String? beschreibung;
    for (final zeile in block.split('\n')) {
      final i = zeile.indexOf(':');
      if (i < 0) throw _fremd;
      final schluessel = zeile.substring(0, i).trim();
      final wert = zeile.substring(i + 1).trim();
      if (schluessel == 'Bezeichnung') {
        bezeichnung = wert;
      } else if (schluessel == 'Pfad') {
        pfad = wert;
      } else if (schluessel == 'Beschreibung') {
        beschreibung = wert;
      } else {
        throw _fremd;
      }
    }
    if (pfad == null || beschreibung == null) throw _fremd;
    eintraege.add(
      WegweiserEintrag(
        bezeichnung: (bezeichnung == null || bezeichnung.isEmpty)
            ? null
            : bezeichnung,
        pfad: pfad,
        beschreibung: beschreibung,
      ),
    );
  }
  return eintraege;
}

/// Schreibt die Einträge im festen Aufbau. Eine Bezeichnung steht nur da, wo es
/// eine gibt.
String schreibeWegweiser(List<WegweiserEintrag> eintraege) {
  final bloecke = [
    for (final e in eintraege)
      [
        if (e.bezeichnung != null) 'Bezeichnung: ${e.bezeichnung}',
        'Pfad: ${e.pfad}',
        'Beschreibung: ${e.beschreibung}',
      ].join('\n'),
  ];
  return '$_kopf${bloecke.join('\n\n')}\n';
}

/// Die Einträge des Wegweisers nach dem Schreiben: Ein neuer Eintrag mit gleicher
/// Bezeichnung ersetzt den alten an seiner Stelle, alle anderen bleiben, neue
/// hängen hinten an.
List<WegweiserEintrag> zusammenfuehren(
  List<WegweiserEintrag> alt,
  List<WegweiserEintrag> neu,
) {
  final neuNachSchluessel = {for (final e in neu) e.schluessel: e};
  final ergebnis = <WegweiserEintrag>[];
  final ersetzt = <String>{};
  for (final e in alt) {
    final ersatz = neuNachSchluessel[e.schluessel];
    if (ersatz == null) {
      ergebnis.add(e);
    } else if (ersetzt.add(e.schluessel)) {
      ergebnis.add(ersatz);
    }
  }
  for (final e in neu) {
    if (!ersetzt.contains(e.schluessel)) ergebnis.add(e);
  }
  return ergebnis;
}

/// Prüft die Einträge der KI und liefert sie normalisiert. Ein Pfad muss unter
/// der Wurzel liegen und darf nicht die Wurzel selbst sein; Bezeichnungen sind
/// eindeutig, und Beschreibungen sind eine Zeile.
List<WegweiserEintrag> pruefeEintraege(List<WegweiserEintrag> eintraege) {
  if (eintraege.isEmpty) {
    throw const KontextFehler(
      'context_link needs at least one entry; nothing was written.',
    );
  }
  final normalisiert = <WegweiserEintrag>[];
  final schluessel = <String>{};
  for (final e in eintraege) {
    final teile = pfadTeile(e.pfad);
    if (teile.isEmpty) {
      throw const KontextFehler(
        'An entry names the context root itself; name a place below it. Nothing was written.',
      );
    }
    final normal = teile.join('/') + (e.pfad.endsWith('/') ? '/' : '');
    final beschreibung = e.beschreibung.trim();
    _einzeilig(beschreibung, 'description', _hoechstBeschreibung);
    // Eine leere Bezeichnung zählt wie keine.
    final gekuerzt = e.bezeichnung?.trim();
    final bezeichnung = (gekuerzt == null || gekuerzt.isEmpty)
        ? null
        : gekuerzt;
    if (bezeichnung != null) {
      _einzeilig(bezeichnung, 'label', _hoechstBezeichnung);
    }
    final neu = WegweiserEintrag(
      bezeichnung: bezeichnung,
      pfad: normal,
      beschreibung: beschreibung,
    );
    if (!schluessel.add(neu.schluessel)) {
      throw KontextFehler(
        neu.bezeichnung == null
            ? 'Only one entry may have no label. Nothing was written.'
            : "Two entries have the label '${neu.bezeichnung}'; labels must be unique. Nothing was written.",
      );
    }
    normalisiert.add(neu);
  }
  return normalisiert;
}

/// Verknüpft den Kontextbereich mit einem Ordner der Lehrkraft: Die Einträge
/// müssen auf vorhandene Stellen zeigen, der Ordner kommt aus dem Ordnerdialog,
/// die Freigabe gilt auf jeder Stufe (E5). Geschrieben wird nur die Datei
/// [wegweiserDatei] in diesem Ordner, und nur, wenn sie nach Freigabe noch den
/// gelesenen Stand hat. Ein Ausfall des Kontextbereichs kommt nicht in den
/// Ausstand: Der Wegweiser schreibt nicht in die Wurzel.
Future<String> verknuepfeWegweiser({
  required Ortszugang zugang,
  required AppAnschluss app,
  required String? aufruf,
  required List<WegweiserEintrag> eintraege,
}) async {
  final pruefte = pruefeEintraege(eintraege);

  final Kontextspeicher speicher;
  try {
    speicher = await zugang.oeffnen();
  } on KontextNichtErreichbar catch (f) {
    throw KontextFehler(
      'The context area does not answer, so the targets cannot be checked; '
      'nothing was written. ${f.meldung}',
    );
  }
  await _pruefeZiele(speicher, pruefte);

  final ordner = await app.ordnerWaehlen(
    aufruf: aufruf,
    titel: 'Ordner für den Wegweiser wählen',
  );
  if (ordner == null) {
    throw const KontextFehler('Not written: no folder was chosen.');
  }
  final datei = File(p.join(ordner, wegweiserDatei));
  final vorher = await _liesWegweiser(datei);
  final bisher = vorher == null
      ? <WegweiserEintrag>[]
      : leseWegweiser(_decode(vorher));
  final ergebnis = zusammenfuehren(bisher, pruefte);
  final schluesselBisher = {for (final e in bisher) e.schluessel};
  final ersetzt = pruefte
      .where((e) => schluesselBisher.contains(e.schluessel))
      .length;
  final neuZahl = pruefte.length - ersetzt;
  final bytes = utf8.encode(schreibeWegweiser(ergebnis));

  final ausgang = await app.freigabe(
    aufruf: aufruf,
    titel: vorher == null ? 'Wegweiser anlegen?' : 'Wegweiser ändern?',
    zusammenfassung: _zusammenfassung(datei.path, pruefte, ersetzt: ersetzt),
    ab: Freigabestufe.keine,
  );
  switch (ausgang) {
    case Freigabeausgang.freigegeben:
      break;
    case Freigabeausgang.abgelehnt:
      throw const KontextFehler(
        'Not written: the teacher declined the approval.',
      );
    case Freigabeausgang.abgebrochen:
      throw const KontextFehler(
        'Not written: the approval was cancelled or timed out.',
      );
  }

  // Nach der Freigabe prüfen: Die Datei und die Ziele können sich in der Wartezeit geändert haben.
  if (!_gleich(await _liesWegweiser(datei), vorher)) {
    throw KontextFehler(
      "$wegweiserDatei changed while the approval was open; nothing was written. Start again.",
    );
  }
  await _pruefeZiele(speicher, pruefte);

  try {
    await datei.writeAsBytes(bytes, flush: true);
  } on FileSystemException {
    throw const KontextFehler(
      "$wegweiserDatei cannot be written in the chosen folder; nothing was written.",
    );
  }
  // Das Urteil fällt hier: nur bei gleichen Bytes beim Zurücklesen ist es verifiziert.
  if (!_gleich(await _liesWegweiser(datei), bytes)) {
    throw const KontextFehler(
      "not verified: $wegweiserDatei does not read back with the written content. Read it before going on.",
    );
  }
  return 'verified\n'
      'path: $wegweiserDatei\n'
      'entries: ${ergebnis.length} (new: $neuZahl, replaced: $ersetzt)';
}

/// Die Stellen, auf die die Einträge zeigen, müssen existieren. Die Meldung nennt
/// die fehlenden Pfade (sie sind Eingaben der KI, nie der absolute Ordner).
Future<void> _pruefeZiele(
  Kontextspeicher speicher,
  List<WegweiserEintrag> eintraege,
) async {
  final fehlend = <String>[];
  for (final e in eintraege) {
    if (!await speicher.existiert(e.pfad)) fehlend.add(e.pfad);
  }
  if (fehlend.isNotEmpty) {
    throw KontextFehler(
      'These targets do not exist below the context root: ${fehlend.join(', ')}. '
      'Nothing was written; check the paths with context_list.',
    );
  }
}

/// Der Inhalt des Wegweisers, falls vorhanden; null, wenn er fehlt. Ein Ordner
/// oder eine Verknüpfung an dieser Stelle wird nicht überschrieben.
Future<Uint8List?> _liesWegweiser(File datei) async {
  final typ = await FileSystemEntity.type(datei.path, followLinks: false);
  if (typ == FileSystemEntityType.notFound) return null;
  if (typ != FileSystemEntityType.file) {
    throw const KontextFehler(
      "$wegweiserDatei in the chosen folder is not a plain file; nothing was written.",
    );
  }
  try {
    return await datei.readAsBytes();
  } on FileSystemException {
    throw const KontextFehler(
      "$wegweiserDatei in the chosen folder cannot be read; nothing was written.",
    );
  }
}

String _decode(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const KontextFehler(
      "$wegweiserDatei in the chosen folder is not UTF-8 text; nothing was written.",
    );
  }
}

/// Gleiche Bytes, oder beide fehlen.
bool _gleich(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Der Text der Freigabe: welche Datei, und was die Einträge sagen. Pfade und
/// Beschreibungen sind Eingaben der KI und erscheinen nur in der App, nie in der
/// Antwort an die KI.
String _zusammenfassung(
  String datei,
  List<WegweiserEintrag> eintraege, {
  required int ersetzt,
}) {
  final zeilen = [
    'Datei: $datei',
    'Art: Wegweiser (Verknüpfung mit dem Kontextbereich)',
    if (ersetzt > 0)
      'Ein Eintrag mit gleicher Bezeichnung wird ersetzt; die übrigen bleiben.',
    '',
    for (final e in eintraege)
      '- ${e.bezeichnung == null ? '' : '${e.bezeichnung}: '}${e.pfad}: ${e.beschreibung}',
  ];
  return zeilen.join('\n');
}

void _einzeilig(String wert, String name, int hoechstens) {
  if (wert.isEmpty) {
    throw KontextFehler('The $name is empty. Nothing was written.');
  }
  if (wert.length > hoechstens) {
    throw KontextFehler(
      'The $name is longer than $hoechstens characters. Shorten it. Nothing was written.',
    );
  }
  if (wert.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
    throw KontextFehler(
      'The $name has a line break or a control character; it must be one line. Nothing was written.',
    );
  }
}

/// Die Meldung, die Fremdes erkennt: die Datei hat einen anderen Aufbau als den des Plugins.
const _fremd = KontextFehler(
  "$wegweiserDatei in the chosen folder has content the plugin does not know; "
  'nothing was changed. Check or remove the file by hand.',
);
