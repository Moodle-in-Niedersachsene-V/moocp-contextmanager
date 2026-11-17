// Tests am MCP-Seam für das Lesen langer Dateien: Ab 100 Zeilen liefert
// context_read nur das Inhaltsverzeichnis, ein Abschnitt wird über seine
// Überschrift angefordert, die ganze Datei nur auf ausdrückliche Bitte.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

/// Eine Datei mit den angegebenen Zeilen, wie sie auf der Platte liegt.
String datei(List<String> zeilen) => '${zeilen.join('\n')}\n';

/// Eine Datei mit 101 Zeilen: Überschrift `##` in Zeile 3, `###` in Zeile 11,
/// `##` in Zeile 21. Jede andere Zeile heißt „Zeile n“.
List<String> langeDatei() => [
  for (var n = 1; n <= 101; n++)
    if (n == 1)
      '# Plan'
    else if (n == 3)
      '## Woche 1: Einstieg'
    else if (n == 11)
      '### Montag'
    else if (n == 21)
      '## Woche 2: Vertiefung'
    else
      'Zeile $n',
];

String sha256Von(String text) => sha256.convert(utf8.encode(text)).toString();

void main() => fuerJedenOrt(_tests);

void _tests(Ortsart art) {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('inhalt');
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

  Future<void> schreibe(String relativ, String inhalt) =>
      File(pfad.join(root, relativ)).writeAsString(inhalt);

  group('Dateien bis 100 Zeilen', () {
    test('werden ganz zurückgegeben', () async {
      final zeilen = [
        for (var n = 1; n <= 100; n++) n == 1 ? '## Erster' : 'Zeile $n',
      ];
      await schreibe('kurz.md', datei(zeilen));
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'kurz.md'});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('version: ${sha256Von(datei(zeilen))}'));
      expect(text, endsWith(datei(zeilen)));
    });
  });

  group('Dateien über 100 Zeilen', () {
    test(
      'liefern das Inhaltsverzeichnis mit Zeilenbereichen, nicht den Text',
      () async {
        await schreibe('plan.md', datei(langeDatei()));
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_read', {'pfad': 'plan.md'});
        expect(ergebnis['isError'], isNot(true));
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('lines: 101'));
        expect(text, contains('version: ${sha256Von(datei(langeDatei()))}'));
        expect(text, contains('## Woche 1: Einstieg (lines 3-20)'));
        expect(text, contains('### Montag (lines 11-20)'));
        expect(text, contains('## Woche 2: Vertiefung (lines 21-101)'));
        // Die Überschrift der Ebene 1 steht nicht im Verzeichnis, der Text auch nicht.
        expect(text, isNot(contains('# Plan (lines')));
        expect(text, isNot(contains('Zeile 50')));
        // Der Hinweis nennt, wie ein Abschnitt und die ganze Datei gelesen werden.
        expect(text, contains("'abschnitt'"));
        expect(text, contains("'ganz': true"));
      },
    );

    test(
      'Überschriften in einem Codeblock zählen nicht als Abschnitt',
      () async {
        final zeilen = langeDatei();
        zeilen[30] = '```';
        zeilen[31] = '## Kein Abschnitt';
        zeilen[32] = '```';
        await schreibe('plan.md', datei(zeilen));
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_read', {'pfad': 'plan.md'});
        final text = PluginProzess.text(ergebnis);
        expect(text, isNot(contains('Kein Abschnitt')));
        expect(text, contains('## Woche 2: Vertiefung (lines 21-101)'));
      },
    );

    test(
      'ein Codeblock mit ``` schließt sich nur mit ``` und nicht mit ~~~',
      () async {
        final zeilen = langeDatei();
        zeilen[30] = '```';
        zeilen[31] = '~~~';
        zeilen[32] = '## Kein Abschnitt';
        zeilen[33] = '```';
        await schreibe('plan.md', datei(zeilen));
        final p = await laufendesPlugin();
        final text = PluginProzess.text(
          await p.werkzeug('context_read', {'pfad': 'plan.md'}),
        );
        expect(text, isNot(contains('Kein Abschnitt')));
        expect(text, contains('## Woche 2: Vertiefung (lines 21-101)'));
      },
    );

    test(
      'ein Codeblock mit vier Backticks schließt sich nicht mit drei',
      () async {
        final zeilen = langeDatei();
        zeilen[30] = '````';
        zeilen[31] = '```';
        zeilen[32] = '## Kein Abschnitt';
        zeilen[33] = '````';
        await schreibe('plan.md', datei(zeilen));
        final p = await laufendesPlugin();
        final text = PluginProzess.text(
          await p.werkzeug('context_read', {'pfad': 'plan.md'}),
        );
        expect(text, isNot(contains('Kein Abschnitt')));
        expect(text, contains('## Woche 2: Vertiefung (lines 21-101)'));
      },
    );

    test(
      'ein Codeblock, der nicht geschlossen wird, reicht bis zum Dateiende',
      () async {
        final zeilen = langeDatei();
        zeilen[12] = '~~~';
        zeilen[13] = '## Kein Abschnitt';
        await schreibe('plan.md', datei(zeilen));
        final p = await laufendesPlugin();
        final text = PluginProzess.text(
          await p.werkzeug('context_read', {'pfad': 'plan.md'}),
        );
        expect(text, isNot(contains('Kein Abschnitt')));
        expect(text, isNot(contains('Woche 2')));
        expect(text, contains('## Woche 1: Einstieg (lines 3-101)'));
      },
    );

    test('ein Abschnitt wird über seine Überschrift gelesen', () async {
      await schreibe('plan.md', datei(langeDatei()));
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {
        'pfad': 'plan.md',
        'abschnitt': 'montag',
      });
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('section: ### Montag'));
      expect(text, contains('lines: 11-20'));
      expect(text, contains('Zeile 19'));
      expect(text, isNot(contains('Zeile 21')));
      expect(text, isNot(contains('Zeile 5\n')));
      // Die Version gehört zur ganzen Datei, damit context_write damit arbeiten kann.
      expect(text, contains('version: ${sha256Von(datei(langeDatei()))}'));
    });

    test(
      'ein übergeordneter Abschnitt enthält seine Unterabschnitte',
      () async {
        await schreibe('plan.md', datei(langeDatei()));
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_read', {
          'pfad': 'plan.md',
          'abschnitt': 'Woche 1: Einstieg',
        });
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('Zeile 4'));
        expect(text, contains('Zeile 19'));
        expect(text, isNot(contains('Zeile 21')));
      },
    );

    test(
      'eine unbekannte Überschrift nennt alle Überschriften der Datei',
      () async {
        await schreibe('plan.md', datei(langeDatei()));
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_read', {
          'pfad': 'plan.md',
          'abschnitt': 'Woche 9',
        });
        expect(ergebnis['isError'], isTrue);
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('Woche 1: Einstieg'));
        expect(text, contains('Montag'));
        expect(text, contains('Woche 2: Vertiefung'));
      },
    );

    test('ein Abschnitt darf mit seiner Markierung angefordert werden („## Woche 2“)', () async {
      await schreibe('plan.md', datei(langeDatei()));
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {
        'pfad': 'plan.md',
        'abschnitt': '## Woche 2: Vertiefung',
      });
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('section: ## Woche 2: Vertiefung'));
      expect(text, contains('lines: 21-101'));
    });

    test(
      'eine mehrdeutige Überschrift wird abgewiesen und nennt die Zeilen',
      () async {
        final zeilen = langeDatei();
        zeilen[20] = '## Woche 1: Einstieg';
        await schreibe('plan.md', datei(zeilen));
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_read', {
          'pfad': 'plan.md',
          'abschnitt': 'Woche 1: Einstieg',
        });
        expect(ergebnis['isError'], isTrue);
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('2 times'));
        expect(text, contains('lines 3, 21'));
      },
    );

    test('ganz: true liefert die ganze Datei', () async {
      await schreibe('plan.md', datei(langeDatei()));
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {
        'pfad': 'plan.md',
        'ganz': true,
      });
      expect(ergebnis['isError'], isNot(true));
      expect(PluginProzess.text(ergebnis), endsWith(datei(langeDatei())));
    });

    test('abschnitt und ganz zusammen sind ein Fehler', () async {
      await schreibe('plan.md', datei(langeDatei()));
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {
        'pfad': 'plan.md',
        'abschnitt': 'Montag',
        'ganz': true,
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains("not both"));
    });

    test(
      'eine lange Datei ohne Überschriften sagt das, statt leer zu sein',
      () async {
        final zeilen = [for (var n = 1; n <= 101; n++) 'Zeile $n'];
        await schreibe('notizen.md', datei(zeilen));
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_read', {
          'pfad': 'notizen.md',
        });
        expect(ergebnis['isError'], isNot(true));
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('no headings'));
        expect(text, contains("'ganz': true"));
        expect(text, isNot(contains('Zeile 50')));
      },
    );

    test('die Version eines Abschnitts reicht für context_write auf die ganze Datei', () async {
      await schreibe('plan.md', datei(langeDatei()));
      final p = await laufendesPlugin();
      final gelesen = await p.werkzeug('context_read', {
        'pfad': 'plan.md',
        'abschnitt': 'Montag',
      });
      final version = RegExp(r'version: (\S+)')
          .firstMatch(PluginProzess.text(gelesen))!
          .group(1)!;
      final geschrieben = await p.werkzeug('context_write', {
        'pfad': 'plan.md',
        'inhalt': 'ersetzt\n',
        'art': 'correction',
        'zusammenfassung': 'Tippfehler im Plan.',
        'version': version,
      });
      expect(geschrieben['isError'], isNot(true));
      expect(PluginProzess.text(geschrieben), startsWith('verified'));
      expect(
        await File(pfad.join(root, 'plan.md')).readAsString(),
        'ersetzt\n',
      );
    });
  });
}
