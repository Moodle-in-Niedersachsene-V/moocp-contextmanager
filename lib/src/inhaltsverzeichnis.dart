import 'dart:convert';

import 'fehler.dart';
import 'speicher.dart';

/// Ab dieser Zeilenzahl gibt `context_read` nur das Inhaltsverzeichnis zurück,
/// es sei denn, die KI fordert einen Abschnitt oder die ganze Datei an.
const grenzeZeilen = 100;

/// Eine Überschrift `##` oder `###` der Datei. [zeile] ist 1-basiert.
class _Kopf {
  const _Kopf({required this.zeile, required this.ebene, required this.titel});

  final int zeile;
  final int ebene;
  final String titel;

  /// Die Überschrift mit ihrer Markierung, wie sie in der Datei steht.
  String get markiert => '${'#' * ebene} $titel';
}

/// Ein Abschnitt: eine Überschrift samt allem bis zur nächsten Überschrift
/// gleicher oder höherer Ebene. Ein `##`-Abschnitt enthält seine `###`-Teile.
/// Zeilen sind 1-basiert, beide Enden eingeschlossen.
class _Abschnitt {
  const _Abschnitt({required this.kopf, required this.von, required this.bis});

  final _Kopf kopf;
  final int von;
  final int bis;
}

/// Die Überschrift, die nur Markdown-Ebene 2 und 3 zählt. Vier und mehr
/// Rauten sowie Zeilen ohne Leerzeichen nach den Rauten zählen nicht.
final _ueberschrift = RegExp(r'^(#{2,3}) +(\S.*?)\s*$');

/// Der Text, den `context_read` für eine Datei liefert. Bis 100 Zeilen die
/// ganze Datei; darüber das Inhaltsverzeichnis, ein Abschnitt über
/// [abschnitt] (Überschrift) oder die ganze Datei mit [ganz]. Die Version
/// gehört immer zur ganzen Datei, damit `context_write` darauf aufsetzen kann.
/// Wirft [KontextFehler], wenn die Anfrage nicht passt; die Meldung nennt den
/// nächsten Schritt.
String leseAusschnitt(
  String pfad,
  Gelesen gelesen, {
  String? abschnitt,
  required bool ganz,
}) {
  if (abschnitt != null && ganz) {
    throw const KontextFehler("Pass either 'abschnitt' or 'ganz', not both.");
  }
  final kopf = 'path: $pfad\nversion: ${gelesen.version}\n';
  final zeilen = const LineSplitter().convert(gelesen.text);
  if (ganz || (abschnitt == null && zeilen.length <= grenzeZeilen)) {
    return '$kopf\n${gelesen.text}';
  }

  final abschnitte = _gliedere(zeilen);
  if (abschnitt != null) {
    final gewaehlt = _finde(pfad, abschnitte, abschnitt);
    final text = zeilen.sublist(gewaehlt.von - 1, gewaehlt.bis).join('\n');
    return '$kopf'
        'section: ${gewaehlt.kopf.markiert}\n'
        'lines: ${gewaehlt.von}-${gewaehlt.bis}\n'
        '\n'
        '$text\n';
  }

  final buf = StringBuffer('${kopf}lines: ${zeilen.length}\n\n');
  buf.write('This file is longer than $grenzeZeilen lines. ');
  if (abschnitte.isEmpty) {
    buf.write(
      "It has no headings (## or ###), so there is no table of contents. "
      "To read the whole file, pass 'ganz': true.",
    );
    return buf.toString();
  }
  buf.write(
    'Table of contents (headings ## and ### with the lines each one covers):\n',
  );
  for (final a in abschnitte) {
    buf.write('${a.kopf.markiert} (lines ${a.von}-${a.bis})\n');
  }
  buf.write(
    "\nTo read one section, call context_read again with 'abschnitt' set to "
    'its heading text, for example "${abschnitte.first.kopf.titel}". '
    "To read the whole file, pass 'ganz': true.",
  );
  return buf.toString();
}

/// Die Abschnitte der Datei in der Reihenfolge ihrer Überschriften. Zeilen in
/// Codeblöcken zählen nicht, sonst würde ein `## ` im Beispiel einen Abschnitt
/// vortäuschen.
List<_Abschnitt> _gliedere(List<String> zeilen) {
  final kopfe = <_Kopf>[];
  // Der Zaun, der den offenen Codeblock eröffnet hat (z. B. "````" oder "~~~").
  String? offenerZaun;
  for (var i = 0; i < zeilen.length; i++) {
    final zeile = zeilen[i];
    if (offenerZaun != null) {
      if (_schliesstZaun(zeile, offenerZaun)) offenerZaun = null;
      continue;
    }
    final zaun = _zaunOeffnung.firstMatch(zeile);
    if (zaun != null) {
      offenerZaun = zaun.group(1);
      continue;
    }
    final m = _ueberschrift.firstMatch(zeile);
    if (m == null) continue;
    kopfe.add(
      _Kopf(zeile: i + 1, ebene: m.group(1)!.length, titel: m.group(2)!),
    );
  }

  return [
    for (var k = 0; k < kopfe.length; k++)
      _Abschnitt(
        kopf: kopfe[k],
        von: kopfe[k].zeile,
        bis: _ende(kopfe, k, zeilen.length),
      ),
  ];
}

/// Eröffnet eine Zeile einen Codeblock? Die Gruppe ist der Zaun, aus Backticks
/// oder Tilden, mindestens drei Zeichen lang.
final _zaunOeffnung = RegExp(r'^\s*(`{3,}|~{3,})');

/// Schließt eine Zeile den Codeblock mit dem Zaun [offen]? Nur derselbe Zeichen-
/// typ in mindestens gleicher Länge, sonst nichts außer Leerraum (CommonMark).
bool _schliesstZaun(String zeile, String offen) {
  final m = RegExp(r'^\s*(`{3,}|~{3,})\s*$').firstMatch(zeile);
  if (m == null) return false;
  final zaun = m.group(1)!;
  return zaun[0] == offen[0] && zaun.length >= offen.length;
}

/// Die letzte Zeile des Abschnitts k: vor der nächsten Überschrift gleicher
/// oder höherer Ebene, sonst am Dateiende.
int _ende(List<_Kopf> kopfe, int k, int zeilenAnzahl) {
  for (var j = k + 1; j < kopfe.length; j++) {
    if (kopfe[j].ebene <= kopfe[k].ebene) return kopfe[j].zeile - 1;
  }
  return zeilenAnzahl;
}

/// Sucht den Abschnitt zur Überschrift [gesucht]. Groß- und Kleinschreibung und
/// mehrfache Leerzeichen zählen nicht. Eine Überschrift, die es zweimal gibt,
/// ist ein Fehler, weil sich der Abschnitt dann nicht eindeutig bestimmen lässt.
_Abschnitt _finde(String pfad, List<_Abschnitt> abschnitte, String gesucht) {
  final wunsch = _norm(_ohneMarkierung(gesucht));
  final treffer = [
    for (final a in abschnitte)
      if (_norm(a.kopf.titel) == wunsch) a,
  ];
  if (treffer.length == 1) return treffer.single;
  if (treffer.length > 1) {
    final zeilen = treffer.map((a) => a.von).join(', ');
    throw KontextFehler(
      "The heading '$gesucht' occurs ${treffer.length} times (lines $zeilen) "
      "in '$pfad'. Pass 'ganz': true to read the whole file.",
    );
  }
  if (abschnitte.isEmpty) {
    throw KontextFehler(
      "No heading '$gesucht' in '$pfad': the file has no headings (## or ###). "
      "Pass 'ganz': true to read the whole file.",
    );
  }
  final namen = abschnitte.map((a) => a.kopf.titel).join('; ');
  throw KontextFehler(
    "No heading '$gesucht' in '$pfad'. The headings are: $namen. "
    "Pass one of them as 'abschnitt'.",
  );
}

/// Die Rauten am Anfang, die eine Überschrift in der Datei trägt. Die KI darf
/// sie mit angeben („## Woche 2“); gesucht wird der Text dahinter.
final _markierung = RegExp(r'^#{1,6}\s+');

String _ohneMarkierung(String text) =>
    text.trimLeft().replaceFirst(_markierung, '');

String _norm(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
