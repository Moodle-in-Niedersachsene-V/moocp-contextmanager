// Tests für den Skill „context“: Er liegt im Plugin, ist in der Beschreibungsdatei
// genannt, nennt nur Werkzeuge, die es gibt, und steht nach dem Bauen im Zielordner.
import 'dart:convert';
import 'dart:io';

import 'package:contextmanager/src/art.dart';
import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

const _skillOrdner = 'skills/context';

/// Der Text von SKILL.md, wie er im Plugin-Ordner liegt.
String _skillText() => File(pfad.join(_skillOrdner, 'SKILL.md')).readAsStringSync();

/// Der Text aller Dateien des Skills (SKILL.md und references/), zusammen: Die
/// Werkzeugnamen und Arten darin müssen zum Plugin passen, egal in welcher Datei.
String _skillTextAlle() => Directory(_skillOrdner)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.md'))
    .map((f) => f.readAsStringSync())
    .join('\n');

/// Die Felder des Frontmatters (zwischen den ersten beiden `---`-Zeilen), einfach
/// als `schluessel: wert` gelesen; die description steht in Anführungszeichen.
Map<String, String> _frontmatter(String text) {
  final zeilen = text.split('\n');
  expect(zeilen.first, '---', reason: 'SKILL.md beginnt mit dem Frontmatter');
  final ende = zeilen.indexOf('---', 1);
  expect(ende, greaterThan(0), reason: 'Frontmatter ist abgeschlossen');
  final felder = <String, String>{};
  for (final zeile in zeilen.sublist(1, ende)) {
    final m = RegExp(r'^([a-z-]+):\s*(.*)$').firstMatch(zeile);
    if (m != null) felder[m.group(1)!] = m.group(2)!;
  }
  return felder;
}

/// Die Namen der Werkzeuge, die der Skill nennt: `context_…` in Backticks oder frei.
Set<String> _genannteWerkzeuge(String text) =>
    RegExp(r'\bcontext_[a-z]+\b').allMatches(text).map((m) => m.group(0)!).toSet();

/// Die Werte der Art, die der Skill in Backticks nennt (etwa `plan_change`).
Set<String> _genannteArten(String text) => RegExp(r'`([a-z]+_[a-z_]+)`')
    .allMatches(text)
    .map((m) => m.group(1)!)
    .where((w) => !w.startsWith('context_'))
    .toSet();

void main() {
  group('Beschreibungsdatei und Ablage', () {
    late Map<String, dynamic> beschreibung;

    setUpAll(() {
      beschreibung =
          jsonDecode(File('plugin.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('plugin.json nennt den Skill „context“ unter skills', () {
      expect(beschreibung['skills'], contains('context'));
    });

    test('der Skill liegt in skills/context/SKILL.md', () {
      expect(File(pfad.join(_skillOrdner, 'SKILL.md')).existsSync(), isTrue);
    });

    test('Frontmatter: name gleich Ordnername, description in Anführungszeichen, höchstens 1024 Zeichen', () {
      final f = _frontmatter(_skillText());
      expect(f['name'], 'context');
      final d = f['description'] ?? '';
      expect(d, startsWith('"'));
      expect(d, endsWith('"'));
      expect(d.length - 2, lessThanOrEqualTo(1024));
    });

    test('jeder Skill des Plugins heißt wie der Kurzname oder beginnt mit „context-“', () {
      for (final name in (beschreibung['skills'] as List).cast<String>()) {
        expect(name == 'context' || name.startsWith('context-'), isTrue, reason: name);
      }
    });
  });

  group('Inhalt passt zum Verhalten der Werkzeuge', () {
    late Set<String> werkzeuge;

    setUpAll(() async {
      final ordner = await tempOrdner('skill');
      final p = await PluginProzess.starten(ordner: ordner, ort: Ortsart.lokal);
      try {
        await p.initialisieren();
        final liste = await p.anfragen('tools/list', {});
        werkzeuge = (liste['tools'] as List)
            .map((w) => (w as Map<String, dynamic>)['name'] as String)
            .toSet();
      } finally {
        await p.beenden();
        await ordner.delete(recursive: true);
      }
    });

    test('jeder Werkzeugname in den Dateien des Skills existiert im Plugin', () {
      final genannt = _genannteWerkzeuge(_skillTextAlle());
      expect(genannt, isNotEmpty);
      expect(werkzeuge.containsAll(genannt), isTrue,
          reason: 'unbekannt: ${genannt.difference(werkzeuge)}');
    });

    test('jede Art in Backticks in den Dateien des Skills ist ein Wert der Art-Liste', () {
      final gueltig = Art.values.map((a) => a.wert).toSet();
      final genannt = _genannteArten(_skillTextAlle());
      expect(gueltig.containsAll(genannt), isTrue,
          reason: 'unbekannt: ${genannt.difference(gueltig)}');
    });

    test('die Antwortphrasen, die der Skill zitiert, stehen im Quelltext', () {
      final quelle = Directory('lib/src')
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final phrase in const [
        'verified',
        'not verified',
        'not saved yet',
        'context gap',
        'conflict copies',
      ]) {
        expect(quelle, contains(phrase), reason: phrase);
      }
    });
  });

  group('Bauen', () {
    test('bauen.sh legt den Skill in den Zielordner', () async {
      final ordner = await tempOrdner('bauen');
      final ziel = pfad.join(ordner.path, 'ziel');
      // Ein Ersatz für dart: legt nur die Ausgabedatei an. Das Übersetzen selbst
      // prüft dieser Test nicht; er prüft, was bauen.sh danach kopiert.
      final ersatz = File(pfad.join(ordner.path, 'dart-ersatz.sh'));
      ersatz.writeAsStringSync(r'''#!/bin/bash
while [ $# -gt 0 ]; do
  if [ "$1" = -o ]; then shift; echo ersatz > "$1"; fi
  shift
done
''');
      await Process.run('chmod', ['+x', ersatz.path]);
      final lauf = await Process.run(
        'bash',
        ['bauen.sh', ziel],
        environment: {
          'DART': ersatz.path,
          // Nur Linux baut das Fenster mit flutter; der Zweig ohne Fenster reicht hier.
          'BAUEN_SYSTEM': 'Darwin',
        },
      );
      expect(lauf.exitCode, 0, reason: '${lauf.stdout}\n${lauf.stderr}');
      expect(File(pfad.join(ziel, 'plugin.json')).existsSync(), isTrue);
      expect(File(pfad.join(ziel, 'skills', 'context', 'SKILL.md')).existsSync(), isTrue);
      await ordner.delete(recursive: true);
    });
  });
}
