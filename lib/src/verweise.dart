import 'dart:async';
import 'dart:convert';

import 'fehler.dart';
import 'speicher.dart';

/// Die Obergrenzen der Suche nach Verweisen auf verschobene Dateien (ADR 0010).
/// Was darüber hinausgeht, wird nicht geprüft; die Antwort sagt es dann
/// ausdrücklich. Die Suche darf den Ort nicht hängen lassen: Das Zeitlimit
/// liegt unter den 20 Sekunden, die moocp einem Werkzeugaufruf lässt.
const verweisHoechstTiefe = 10;
const verweisHoechstOrdner = 300;
const verweisHoechstDateien = 100;
const verweisHoechstBytes = 1024 * 1024;
const verweisZeitlimit = Duration(seconds: 8);
const verweisParallel = 8;

/// Die Namen der Indexdateien einer Ebene, klein geschrieben verglichen (E6).
const _indexNamen = {'index.md', 'context.md'};

/// Ein Verweis in einer Indexdatei auf eine verschobene Datei.
class Verweis {
  const Verweis({
    required this.datei,
    required this.zeile,
    required this.text,
    required this.von,
    required this.nach,
  });

  /// Die Indexdatei, relativ zur Wurzel.
  final String datei;

  /// 1-basiert.
  final int zeile;

  /// Der Pfad, wie er in der Datei steht.
  final String text;

  /// Die verschobene Datei vorher und nachher.
  final String von;
  final String nach;
}

/// Das Ergebnis der Suche. [vollstaendig] ist nur wahr, wenn jede Ebene darüber
/// und darunter geprüft ist und nichts begrenzt wurde oder fehlschlug.
class VerweisSuche {
  const VerweisSuche({
    required this.funde,
    required this.indexDateien,
    required this.ordner,
    required this.unvollstaendigGrund,
    this.ungeprueft = const [],
  });

  final List<Verweis> funde;
  final int indexDateien;
  final int ordner;

  /// Null, wenn die Suche vollständig war; sonst der Grund in einem Satz.
  final String? unvollstaendigGrund;

  /// Ordner und Dateien, die nicht geprüft werden konnten (gekürzt).
  final List<String> ungeprueft;

  bool get vollstaendig => unvollstaendigGrund == null;
}

/// Der gemeinsame Stand der Suche, damit ein Zeitablauf die bisherigen Funde
/// behält. Der Zähler `abgebrochen` stoppt eine Suche, die nach dem Zeitablauf
/// noch läuft.
class _Stand {
  final funde = <Verweis>[];
  final ungeprueft = <String>[];
  var indexDateien = 0;
  var ordner = 0;
  var abgebrochen = false;
  final gruende = <String>[];

  void grund(String g) {
    if (!gruende.contains(g)) gruende.add(g);
  }
}

/// Sucht in den Indexdateien (`index.md`, `CONTEXT.md`) der Ebene [ordner],
/// aller Ebenen darüber bis zur Wurzel und aller Ebenen darunter nach Verweisen
/// auf die verschobenen Dateien ([verschoben]: Quelle -> Ziel, relativ zur Wurzel).
/// Ordner `archive` darunter werden übergangen: Dort liegt, was schon archiviert ist.
///
/// Wirft nie: Ein Ort, der nicht antwortet, eine unlesbare Datei, eine Grenze oder
/// der Zeitablauf machen die Suche unvollständig, und das steht im Ergebnis. Die
/// Suche liest nur.
Future<VerweisSuche> sucheVerweise(
  Kontextspeicher speicher, {
  required List<String> ordnerTeile,
  required Map<String, String> verschoben,
  Duration zeitlimit = verweisZeitlimit,
  int hoechstOrdner = verweisHoechstOrdner,
  int hoechstDateien = verweisHoechstDateien,
}) async {
  final stand = _Stand();
  Future<void> lauf() => _suche(
    speicher,
    stand,
    ordnerTeile,
    verschoben,
    hoechstOrdner,
    hoechstDateien,
  );
  try {
    await lauf().timeout(zeitlimit);
  } on TimeoutException {
    stand.abgebrochen = true;
    stand.grund(
      'the search stopped after ${zeitlimit.inSeconds} seconds '
      '(the context area is slow)',
    );
  } on Object catch (f) {
    stand.abgebrochen = true;
    stand.grund(
      f is KontextFehler ? f.meldung : 'the search failed unexpectedly',
    );
  }
  stand.abgebrochen = true;
  return VerweisSuche(
    funde: List.of(stand.funde),
    indexDateien: stand.indexDateien,
    ordner: stand.ordner,
    unvollstaendigGrund: stand.gruende.isEmpty ? null : stand.gruende.join('; '),
    ungeprueft: List.of(stand.ungeprueft),
  );
}

Future<void> _suche(
  Kontextspeicher speicher,
  _Stand stand,
  List<String> ordnerTeile,
  Map<String, String> verschoben,
  int hoechstOrdner,
  int hoechstDateien,
) async {
  // Erst die Ebenen darüber (Wurzel bis zur Ebene selbst), dann breit nach unten.
  final warteschlange = <(String, int, bool)>[
    for (var n = 0; n < ordnerTeile.length; n++)
      (ordnerTeile.sublist(0, n).join('/'), 0, false),
    (ordnerTeile.join('/'), 0, true),
  ];
  while (warteschlange.isNotEmpty && !stand.abgebrochen) {
    final platz = hoechstOrdner - stand.ordner;
    if (platz <= 0) {
      stand.grund('more than $hoechstOrdner folders (limit reached)');
      stand.ungeprueft.addAll(warteschlange.map((e) => _kurz(e.$1)));
      return;
    }
    final stueck = warteschlange
        .take(platz < verweisParallel ? platz : verweisParallel)
        .toList();
    warteschlange.removeRange(0, stueck.length);
    stand.ordner += stueck.length;
    final ergebnisse = await Future.wait([
      for (final (ordner, _, _) in stueck) _liesEbene(speicher, ordner),
    ]);
    if (stand.abgebrochen) return;
    for (var n = 0; n < stueck.length; n++) {
      final (ordner, tiefe, hinunter) = stueck[n];
      final e = ergebnisse[n];
      if (e.fehler != null) {
        stand.grund('a folder could not be read');
        stand.ungeprueft.add('${_kurz(ordner)}: ${e.fehler}');
        continue;
      }
      for (final datei in e.indizes) {
        if (stand.indexDateien >= hoechstDateien) {
          stand.grund('more than $hoechstDateien index files (limit reached)');
          stand.ungeprueft.add(datei);
          continue;
        }
        stand.indexDateien++;
        try {
          final inhalt = await speicher.holeInhalt(datei);
          if (inhalt == null) continue;
          if (inhalt.bytes.length > verweisHoechstBytes) {
            stand.grund('an index file is larger than 1 MiB');
            stand.ungeprueft.add('$datei: larger than 1 MiB');
            continue;
          }
          stand.funde.addAll(
            findeVerweise(
              datei,
              utf8.decode(inhalt.bytes, allowMalformed: true),
              verschoben,
            ),
          );
        } on KontextNichtErreichbar catch (f) {
          stand.grund('the context area did not answer');
          stand.ungeprueft.add('$datei: ${f.meldung}');
        } on KontextFehler catch (f) {
          stand.grund('an index file could not be read');
          stand.ungeprueft.add('$datei: ${f.meldung}');
        }
      }
      if (!hinunter) continue;
      for (final unter in e.unterordner) {
        if (tiefe + 1 > verweisHoechstTiefe) {
          stand.grund('folders deeper than $verweisHoechstTiefe levels');
          stand.ungeprueft.add('${_kurz(unter)}/');
          continue;
        }
        warteschlange.add((unter, tiefe + 1, true));
      }
    }
  }
}

String _kurz(String ordner) => ordner.isEmpty ? '(root)' : ordner;

/// Liest die Einträge einer Ebene: Pfade der Indexdateien und der Unterordner
/// (ohne `archive`). Antwortet der Ort nicht oder ist der Ordner unlesbar, steht
/// der Grund im Ergebnis.
Future<({List<String> indizes, List<String> unterordner, String? fehler})>
_liesEbene(Kontextspeicher speicher, String ordner) async {
  try {
    final eintraege = await speicher.liste(ordner);
    String pfad(String name) => ordner.isEmpty ? name : '$ordner/$name';
    return (
      indizes: [
        for (final e in eintraege)
          if (!e.istOrdner && _indexNamen.contains(e.name.toLowerCase()))
            pfad(e.name),
      ],
      unterordner: [
        for (final e in eintraege)
          if (e.istOrdner && e.name.toLowerCase() != 'archive') pfad(e.name),
      ],
      fehler: null,
    );
  } on KontextNichtErreichbar catch (f) {
    return (indizes: <String>[], unterordner: <String>[], fehler: f.meldung);
  } on KontextFehler catch (f) {
    return (indizes: <String>[], unterordner: <String>[], fehler: f.meldung);
  }
}

/// Die Verweise in [text] (Inhalt der Indexdatei [datei]) auf eine der
/// verschobenen Dateien. Ein Verweis ist jedes pfadartige Stück einer Zeile:
/// Ziel eines Markdown-Links, Backtick-Pfad oder Wort im Text. Ein Pfad zählt,
/// wenn er relativ zum Ordner der Indexdatei oder relativ zur Wurzel (auch mit
/// führendem `/`) auf die Datei zeigt; `#Anker` und `?…` fallen weg, `%20`
/// wird aufgelöst, Groß- und Kleinschreibung zählt nicht. Eher zu viel melden
/// als zu wenig: Ein Treffer ist ein Hinweis, den die KI prüft.
List<Verweis> findeVerweise(
  String datei,
  String text,
  Map<String, String> verschoben,
) {
  final ordner = datei.contains('/')
      ? datei.substring(0, datei.lastIndexOf('/'))
      : '';
  final ziele = {
    for (final e in verschoben.entries) e.key.toLowerCase(): e,
  };
  final funde = <Verweis>[];
  final zeilen = const LineSplitter().convert(text);
  for (var n = 0; n < zeilen.length; n++) {
    final gemeldet = <String>{};
    for (final kandidat in _kandidaten(zeilen[n])) {
      final relativ = _normiere(kandidat, ordner);
      final wurzel = _normiere(kandidat, '');
      for (final pfad in {relativ, wurzel}) {
        final ziel = pfad == null ? null : ziele[pfad.toLowerCase()];
        if (ziel == null || !gemeldet.add('${ziel.key}|$kandidat')) continue;
        funde.add(
          Verweis(
            datei: datei,
            zeile: n + 1,
            text: kandidat,
            von: ziel.key,
            nach: ziel.value,
          ),
        );
      }
    }
  }
  return funde;
}

/// Alle pfadartigen Stücke einer Zeile: Link-Ziele (auch mit Leerzeichen in
/// `<…>`), Backtick-Inhalte und jedes Wort ohne Leerzeichen und Klammern.
Iterable<String> _kandidaten(String zeile) sync* {
  final aus = <String>{};
  for (final m in RegExp(r'\]\(\s*<([^>]*)>').allMatches(zeile)) {
    aus.add(m.group(1)!);
  }
  for (final m in RegExp(r'\]\(\s*([^)\s]*)').allMatches(zeile)) {
    aus.add(m.group(1)!);
  }
  for (final m in RegExp(r'`([^`]+)`').allMatches(zeile)) {
    aus.add(m.group(1)!);
  }
  for (final m in RegExp(r'[^\s()\[\]<>`"' "'" r'|*,;]+').allMatches(zeile)) {
    aus.add(m.group(0)!);
  }
  for (final k in aus) {
    final s = k.trim();
    if (s.isNotEmpty && s.length <= 300) yield s;
  }
}

/// Der Pfad eines Verweises, aufgelöst gegen [basis] (Ordner relativ zur
/// Wurzel); null, wenn er hinausführt, eine Adresse mit Schema ist oder nichts
/// übrig bleibt.
String? _normiere(String roh, String basis) {
  var s = roh;
  final schema = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').firstMatch(s);
  if (schema != null) return null;
  for (final trenner in ['#', '?']) {
    final i = s.indexOf(trenner);
    if (i >= 0) s = s.substring(0, i);
  }
  s = s.replaceAll(RegExp(r'[.:!]+$'), '');
  try {
    s = Uri.decodeFull(s);
  } on ArgumentError {
    // Kein gültiges %-Zeichen: der Pfad bleibt, wie er ist.
  }
  s = s.replaceAll('\\', '/');
  final absolut = s.startsWith('/');
  final teile = <String>[
    if (!absolut && basis.isNotEmpty) ...basis.split('/'),
  ];
  for (final t in s.split('/')) {
    if (t.isEmpty || t == '.') continue;
    if (t == '..') {
      if (teile.isEmpty) return null;
      teile.removeLast();
    } else {
      teile.add(t);
    }
  }
  return teile.isEmpty ? null : teile.join('/');
}

/// Der Abschnitt der Antwort. Sagt immer, ob die Suche vollständig war.
String verweisBericht(VerweisSuche suche) {
  final buf = StringBuffer();
  final f = suche.funde;
  if (f.isEmpty) {
    buf.write(
      suche.vollstaendig
          ? 'references: none found in ${suche.indexDateien} index file(s) '
                'of ${suche.ordner} folder(s) checked (this level, all levels above, '
                'all levels below).'
          : 'references: none found so far, but the search is INCOMPLETE '
                '(${suche.unvollstaendigGrund}). Checked ${suche.indexDateien} '
                'index file(s) in ${suche.ordner} folder(s).',
    );
  } else {
    buf.writeln(
      'references: ${f.length} in index files point to a moved file. Do not '
      'leave them: fix every one now, in this same step, with context_read and '
      'context_write (kind plan_change for the root index.md, otherwise at '
      'least plan_change; the teacher approves each write). Point each to the '
      'new path under archive/ or remove the line.',
    );
    for (final v in f) {
      buf.writeln(
        "- '${v.datei}' line ${v.zeile}: '${v.text}' (moved: '${v.von}' -> '${v.nach}')",
      );
    }
    if (!suche.vollstaendig) {
      buf.write(
        'The search is INCOMPLETE (${suche.unvollstaendigGrund}); there may be '
        'more references.',
      );
    } else {
      buf.write(
        'Searched ${suche.indexDateien} index file(s) in ${suche.ordner} folder(s).',
      );
    }
  }
  if (!suche.vollstaendig) {
    final liste = suche.ungeprueft.take(10).join('; ');
    buf.write(
      '\nNot checked: ${suche.ungeprueft.isEmpty ? 'the rest' : liste}'
      '${suche.ungeprueft.length > 10 ? ' (and ${suche.ungeprueft.length - 10} more)' : ''}. '
      'Check these index files yourself with context_list and context_read '
      'before you tell the teacher that nothing points to a moved file.',
    );
  }
  return buf.toString();
}
