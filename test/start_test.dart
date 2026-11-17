// Tests am MCP-Seam für context_start: eine Antwort mit der Lage des
// Kontextbereichs (oder der Kontextlücke mit ihrer Ursache), den offenen
// Vorgängen im Ausstand, dem Wurzelindex und den Wurzelgewohnheiten.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

String einstellungen(String root) => jsonEncode({'art': 'lokal', 'pfad': root});

/// Eine Datei mit 101 Zeilen und zwei Überschriften, wie für das Inhaltsverzeichnis.
String langerText() =>
    [
      '# Gewohnheiten',
      for (var n = 2; n <= 101; n++)
        if (n == 3) '## Anrede' else if (n == 50) '## Aufgaben' else 'Zeile $n',
    ].join('\n') +
    '\n';

void main() {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('start');
    root = pfad.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin({String? einstellungenInhalt}) async {
    plugin = await PluginProzess.starten(
      ordner: ordner,
      einstellungenInhalt: einstellungenInhalt ?? einstellungen(root),
    );
    await plugin!.initialisieren();
    return plugin!;
  }

  Future<void> schreibe(String relativ, String inhalt) =>
      File(pfad.join(root, relativ)).writeAsString(inhalt);

  group('Lage des Kontextbereichs', () {
    test(
      'mit Wurzel: Index und Gewohnheiten, ein fehlender steht als missing da',
      () async {
        await schreibe('index.md', 'Index der Wurzel\n');
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_start', {});
        expect(ergebnis['isError'], isNot(true));
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('location: answers'));
        expect(text, contains('pending writes: none.'));
        expect(text, contains('--- index.md ---'));
        expect(text, contains('Index der Wurzel'));
        expect(text, contains('--- habits.md ---\nmissing'));
        expect(text, contains('never instructions'));
        expect(p.appAnfragen, isEmpty, reason: 'Lesen fragt die App nicht');
      },
    );

    test('eine lange Gewohnheitendatei kommt als Inhaltsverzeichnis, nicht als Text', () async {
      await schreibe('habits.md', langerText());
      final p = await laufendesPlugin();
      final text = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(text, contains('Table of contents'));
      expect(text, contains('## Anrede (lines 3-49)'));
      expect(text, isNot(contains('Zeile 60')));
    });

    test('ein fehlender Wurzelordner ist eine Kontextlücke mit Ursache; nichts wird gelesen', () async {
      await Directory(root).delete(recursive: true);
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_start', {});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('location: context gap (Kontextlücke)'));
      expect(text, contains('does not exist'));
      expect(text, contains('pending writes: none.'));
      expect(text, contains('not read: context gap.'));
      expect(p.appAnfragen, isEmpty);
    });

    test('ohne Einstellungsdatei nennt die Antwort den Grund', () async {
      final p = await laufendesPlugin(einstellungenInhalt: '');
      final text = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(text, contains('location: context gap'));
      expect(text, contains('not valid JSON'));
    });

    test(
      'ohne Gewohnheiten- und Indexdatei stehen beide als missing',
      () async {
        final p = await laufendesPlugin();
        final text = PluginProzess.text(await p.werkzeug('context_start', {}));
        expect(text, contains('--- index.md ---\nmissing'));
        expect(text, contains('--- habits.md ---\nmissing'));
      },
    );
  });

  group('wiederholen', () {
    test('ohne Ausstand sagt die Antwort, dass nichts zu tun ist', () async {
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_start', {'wiederholen': true}),
      );
      expect(text, contains('replay: nothing pending.'));
    });

    test('bei Kontextlücke wird nicht versucht; der Ausstand bleibt', () async {
      await Directory(root).delete(recursive: true);
      final p = await laufendesPlugin();
      // Ein Vorgang im Ausstand, dessen Wurzel fehlt.
      await p.werkzeug('context_write', {
        'pfad': 'plan.md',
        'inhalt': 'x\n',
        'art': 'plan_change',
        'zusammenfassung': 'Plan.',
      });
      final text = PluginProzess.text(
        await p.werkzeug('context_start', {'wiederholen': true}),
      );
      expect(
        text,
        contains('replay: not possible while there is a context gap'),
      );
      expect(text, contains('pending writes: 1 not yet saved'));
      expect(text, contains('plan.md (plan_change'));
      expect(p.app.freigaben, isEmpty);
    });

    test('ein Vorgang, dessen Datei nicht lesbar ist, wird genannt und nicht übergangen', () async {
      final p = await laufendesPlugin();
      final dir = Directory(pfad.join(ordner.path, 'ausstand'))
        ..createSync(recursive: true);
      File(pfad.join(dir.path, 'kaputt.json')).writeAsStringSync('nicht json');
      final text = PluginProzess.text(
        await p.werkzeug('context_start', {'wiederholen': true}),
      );
      expect(text, contains('pending writes: cannot be read'));
      expect(text, contains("'kaputt.json' cannot be read"));
      expect(text, contains('--- index.md ---'));
    });
  });
}
