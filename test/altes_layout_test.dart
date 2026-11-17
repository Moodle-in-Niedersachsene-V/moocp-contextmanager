// Tests am MCP-Seam für das alte Layout (Coursepilot): CONTEXT.md als Index, wenn
// index.md fehlt, status.md und journal-*.md. Die Dateien werden wie neue gelesen
// und aufgelistet; das Journal bleibt nur anhängbar. Geprüft werden Antworten und
// die Dateien auf der Platte.
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

void main() => fuerJedenOrt(_tests);

void _tests(Ortsart art) {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('altes-layout');
    root = pfad.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin() async {
    plugin = await PluginProzess.starten(ordner: ordner, ort: art);
    await plugin!.initialisieren();
    return plugin!;
  }

  Future<void> schreibe(String relativ, String inhalt) async {
    final datei = File(pfad.join(root, relativ));
    await datei.parent.create(recursive: true);
    await datei.writeAsString(inhalt);
  }

  group('altes Layout: Auflisten und Lesen', () {
    test('CONTEXT.md, status.md und journal-*.md erscheinen wie neue Dateien', () async {
      await schreibe('CONTEXT.md', '# Ebene\n');
      await schreibe('status.md', '# Stand\n');
      await schreibe('journal-2026-10-01.md', '# Tag\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_list', {'pfad': ''});
      expect(ergebnis['isError'], isNot(true));
      expect(
        PluginProzess.text(ergebnis),
        'CONTEXT.md\njournal-2026-10-01.md\nstatus.md',
      );
    });

    test('context_read liefert CONTEXT.md mit Version', () async {
      await schreibe('CONTEXT.md', 'Ebene Mathematik\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'CONTEXT.md'});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('Ebene Mathematik'));
      expect(text, matches(RegExp(r'version: [0-9a-f]{64}')));
    });

    test('ein altes Journal wird angehängt, nie ersetzt', () async {
      await schreibe('journal-2026-10-01.md', 'erster Eintrag\n');
      final p = await laufendesPlugin();
      final gelesen = await p.werkzeug('context_read', {
        'pfad': 'journal-2026-10-01.md',
      });
      final version = RegExp(r'version: (\w+)')
          .firstMatch(PluginProzess.text(gelesen))!
          .group(1)!;

      final ersetzt = await p.werkzeug('context_write', {
        'pfad': 'journal-2026-10-01.md',
        'inhalt': 'ersetzt',
        'art': 'correction',
        'zusammenfassung': 'Versuch zu ersetzen',
        'version': version,
      });
      expect(ersetzt['isError'], isTrue);

      final angehaengt = await p.werkzeug('context_append', {
        'pfad': 'journal-2026-10-01.md',
        'inhalt': 'zweiter Eintrag',
        'art': 'journal',
        'zusammenfassung': 'Eintrag ergänzt',
        'version': version,
      });
      expect(PluginProzess.text(angehaengt), startsWith('verified'));
      expect(
        File(pfad.join(root, 'journal-2026-10-01.md')).readAsStringSync(),
        'erster Eintrag\nzweiter Eintrag\n',
      );
    });
  });

  group('Journale auf jeder Ebene (E1): nur anhängen', () {
    test('<projekt>/journal/x.md wird ersetzt abgewiesen, Anhängen geht', () async {
      await schreibe('klassen/7b/mathe/journal/2026-11-17.md', 'erster Eintrag\n');
      final p = await laufendesPlugin();
      final gelesen = await p.werkzeug('context_read', {
        'pfad': 'klassen/7b/mathe/journal/2026-11-17.md',
      });
      final version = RegExp(r'version: (\w+)')
          .firstMatch(PluginProzess.text(gelesen))!
          .group(1)!;

      final ersetzt = await p.werkzeug('context_write', {
        'pfad': 'klassen/7b/mathe/journal/2026-11-17.md',
        'inhalt': 'ersetzt',
        'art': 'correction',
        'zusammenfassung': 'Versuch zu ersetzen',
        'version': version,
      });
      expect(ersetzt['isError'], isTrue, reason: PluginProzess.text(ersetzt));
      expect(
        File(pfad.join(root, 'klassen', '7b', 'mathe', 'journal', '2026-11-17.md'))
            .readAsStringSync(),
        'erster Eintrag\n',
      );

      final angehaengt = await p.werkzeug('context_append', {
        'pfad': 'klassen/7b/mathe/journal/2026-11-17.md',
        'inhalt': 'zweiter Eintrag',
        'art': 'journal',
        'zusammenfassung': 'Eintrag ergänzt',
        'version': version,
      });
      expect(PluginProzess.text(angehaengt), startsWith('verified'));
    });

    test('ein journal-*.md auf Projektebene wird ersetzt abgewiesen', () async {
      await schreibe('klassen/7b/mathe/journal-2026-10-01.md', 'alt\n');
      final p = await laufendesPlugin();
      final gelesen = await p.werkzeug('context_read', {
        'pfad': 'klassen/7b/mathe/journal-2026-10-01.md',
      });
      final version = RegExp(r'version: (\w+)')
          .firstMatch(PluginProzess.text(gelesen))!
          .group(1)!;
      final ersetzt = await p.werkzeug('context_write', {
        'pfad': 'klassen/7b/mathe/journal-2026-10-01.md',
        'inhalt': 'ersetzt',
        'art': 'correction',
        'zusammenfassung': 'Versuch zu ersetzen',
        'version': version,
      });
      expect(ersetzt['isError'], isTrue, reason: PluginProzess.text(ersetzt));
      expect(
        File(pfad.join(root, 'klassen', '7b', 'mathe', 'journal-2026-10-01.md'))
            .readAsStringSync(),
        'alt\n',
      );
    });
  });

  group('altes Layout: context_start', () {
    test('ohne index.md liest context_start die CONTEXT.md der Wurzel als Index', () async {
      await schreibe('CONTEXT.md', 'Index aus dem alten Layout\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_start', {});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('--- CONTEXT.md (old layout'));
      expect(text, contains('Index aus dem alten Layout'));
      expect(text, isNot(contains('--- index.md ---\nmissing')));
    });

    test('mit index.md gewinnt index.md; CONTEXT.md wird dann nicht gelesen', () async {
      await schreibe('index.md', 'Neuer Index\n');
      await schreibe('CONTEXT.md', 'Alter Index\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(text, contains('--- index.md ---'));
      expect(text, contains('Neuer Index'));
      expect(text, isNot(contains('Alter Index')));
      expect(text, isNot(contains('CONTEXT.md')));
    });

    test('ohne index.md und ohne CONTEXT.md steht index.md als missing da', () async {
      final p = await laufendesPlugin();
      final text = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(text, contains('--- index.md ---\nmissing'));
    });
  });
}
