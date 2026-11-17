// Tests am MCP-Seam für context_archive (Spec #10): Dateien eines Ordners wandern
// nach `<Ordner>/archive/`. Nie gelöscht, nie überschrieben, Journale bleiben, und
// jede Verschiebung braucht die Freigabe wie eine neue Datei (Stufe „alle“).
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

void main() => fuerJedenOrt(_tests);

void _tests(Ortsart art) {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  Future<void> schreibe(String relativ, String inhalt) async {
    final datei = File(pfad.join(root, relativ));
    await datei.parent.create(recursive: true);
    await datei.writeAsString(inhalt);
  }

  setUp(() async {
    ordner = await tempOrdner('archiv');
    root = pfad.join(ordner.path, 'kontext');
    await Directory(pfad.join(root, 'klassen', '7b', 'mathe')).create(recursive: true);
    await schreibe('klassen/7b/mathe/plan.md', 'Plan\n');
    await schreibe('klassen/7b/mathe/status.md', 'Stand\n');
    await schreibe('klassen/7b/mathe/journal-2026-10-01.md', 'Tag\n');
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin({String stufe = 'alle', String antwort = 'freigegeben'}) async {
    plugin = await PluginProzess.starten(ordner: ordner, ort: art);
    await plugin!.initialisieren();
    plugin!.app.stufe = stufe;
    plugin!.app.antwort = antwort;
    return plugin!;
  }

  bool da(String relativ) => File(pfad.join(root, relativ)).existsSync();

  Future<Map<String, dynamic>> archiv(
    PluginProzess p, {
    required String ordner,
    required List<String> dateien,
    String zusammenfassung = 'Altes Layout ins Archiv',
  }) => p.werkzeug('context_archive', {
    'ordner': ordner,
    'dateien': dateien,
    'zusammenfassung': zusammenfassung,
  });

  group('context_archive: verschieben', () {
    test('verschiebt in archive/ des Ordners, Inhalt unverändert, verified', () async {
      final p = await laufendesPlugin();
      final ergebnis = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md']);
      expect(ergebnis['isError'], isNot(true), reason: PluginProzess.text(ergebnis));
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('verified'));
      expect(text, contains('klassen/7b/mathe/plan.md -> klassen/7b/mathe/archive/plan.md'));
      expect(da('klassen/7b/mathe/plan.md'), isFalse);
      expect(
        File(pfad.join(root, 'klassen', '7b', 'mathe', 'archive', 'plan.md')).readAsStringSync(),
        'Plan\n',
      );
    });

    test('fragt mit Stufe „alle“ und nennt nur Pfade im Kontextbereich', () async {
      final p = await laufendesPlugin();
      await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md']);
      expect(p.app.freigaben, hasLength(1));
      expect(p.app.freigaben.single['ab'], 'alle');
      expect(p.app.freigaben.single['zusammenfassung'], isNot(contains(root)));
    });

    test('auf Stufe „mittel“ wird wie bei einer neuen Datei nicht gefragt, verschoben wird trotzdem', () async {
      final p = await laufendesPlugin(stufe: 'mittel');
      final ergebnis = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md']);
      expect(ergebnis['isError'], isNot(true));
      expect(p.app.freigabeAntworten.single['ohneFrage'], isTrue);
      expect(da('klassen/7b/mathe/archive/plan.md'), isTrue);
    });

    test('mehrere Dateien in einem Aufruf: eine Freigabe, alle verschoben', () async {
      final p = await laufendesPlugin();
      final ergebnis = await archiv(
        p,
        ordner: 'klassen/7b/mathe',
        dateien: ['plan.md', 'status.md'],
      );
      expect(ergebnis['isError'], isNot(true), reason: PluginProzess.text(ergebnis));
      expect(p.app.freigaben, hasLength(1));
      expect(da('klassen/7b/mathe/archive/plan.md'), isTrue);
      expect(da('klassen/7b/mathe/archive/status.md'), isTrue);
      expect(da('klassen/7b/mathe/plan.md'), isFalse);
      expect(da('klassen/7b/mathe/status.md'), isFalse);
    });

    test('im Wurzelordner („ordner“ leer) geht es in den archive/ der Wurzel', () async {
      await schreibe('CONTEXT.md', 'Ebene\n');
      final p = await laufendesPlugin();
      final ergebnis = await archiv(p, ordner: '', dateien: ['CONTEXT.md']);
      expect(ergebnis['isError'], isNot(true), reason: PluginProzess.text(ergebnis));
      expect(da('archive/CONTEXT.md'), isTrue);
      expect(da('CONTEXT.md'), isFalse);
    });
  });

  group('context_archive: nichts geht verloren', () {
    test('eine Ablehnung verschiebt nichts', () async {
      final p = await laufendesPlugin(antwort: 'abgelehnt');
      final ergebnis = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md']);
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('declined'));
      expect(da('klassen/7b/mathe/plan.md'), isTrue);
      expect(da('klassen/7b/mathe/archive/plan.md'), isFalse);
    });

    test('existiert das Ziel schon, wird nichts verschoben und nicht gefragt', () async {
      await schreibe('klassen/7b/mathe/archive/plan.md', 'alt\n');
      final p = await laufendesPlugin();
      final ergebnis = await archiv(
        p,
        ordner: 'klassen/7b/mathe',
        dateien: ['plan.md', 'status.md'],
      );
      expect(ergebnis['isError'], isTrue);
      expect(p.app.freigaben, isEmpty);
      expect(da('klassen/7b/mathe/plan.md'), isTrue);
      expect(da('klassen/7b/mathe/status.md'), isTrue);
      expect(
        File(pfad.join(root, 'klassen', '7b', 'mathe', 'archive', 'plan.md')).readAsStringSync(),
        'alt\n',
      );
    });

    test('fehlt eine Datei, wird nichts verschoben und nicht gefragt', () async {
      final p = await laufendesPlugin();
      final ergebnis = await archiv(
        p,
        ordner: 'klassen/7b/mathe',
        dateien: ['plan.md', 'fehlt.md'],
      );
      expect(ergebnis['isError'], isTrue);
      expect(p.app.freigaben, isEmpty);
      expect(da('klassen/7b/mathe/plan.md'), isTrue);
    });

    test('ändert sich eine Datei während der Freigabe, bricht es ab und verschiebt nichts', () async {
      final p = await laufendesPlugin();
      p.app.beiFreigabe = () {
        File(pfad.join(root, 'klassen', '7b', 'mathe', 'plan.md'))
            .writeAsStringSync('Plan, von Hand geändert\n');
      };
      final ergebnis = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md']);
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('changed'));
      expect(
        File(pfad.join(root, 'klassen', '7b', 'mathe', 'plan.md')).readAsStringSync(),
        'Plan, von Hand geändert\n',
      );
      expect(da('klassen/7b/mathe/archive/plan.md'), isFalse);
    });

    test('ohne Kontextbereich wird nichts verschoben, der Grund steht da, kein Ausstand', () async {
      final p = await laufendesPlugin();
      await p.ausfallen();
      final ergebnis = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md']);
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('nothing was moved'));
      expect(Directory(pfad.join(ordner.path, 'ausstand')).existsSync(), isFalse);
      expect(p.app.freigaben, isEmpty);
    });
  });

  group('context_archive: Grenzen', () {
    test('Journale werden nie verschoben', () async {
      final p = await laufendesPlugin();
      final alt = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['journal-2026-10-01.md']);
      expect(alt['isError'], isTrue);
      await schreibe('klassen/7b/mathe/journal/2026-11-17.md', 'Eintrag\n');
      final neu = await archiv(p, ordner: 'klassen/7b/mathe/journal', dateien: ['2026-11-17.md']);
      expect(neu['isError'], isTrue);
      expect(da('klassen/7b/mathe/journal-2026-10-01.md'), isTrue);
      expect(da('klassen/7b/mathe/journal/2026-11-17.md'), isTrue);
      expect(p.app.freigaben, isEmpty);
    });

    test('Pfade, die hinausführen, und Namen mit Schrägstrich werden abgewiesen', () async {
      final p = await laufendesPlugin();
      final faelle = <(String, List<String>)>[
        ('../andere', ['plan.md']),
        ('klassen/7b/mathe', ['../plan.md']),
        ('klassen/7b/mathe', ['/plan.md']),
        ('klassen/7b/mathe', ['unter/plan.md']),
      ];
      for (final (ordnerArg, dateien) in faelle) {
        final ergebnis = await archiv(p, ordner: ordnerArg, dateien: dateien);
        expect(ergebnis['isError'], isTrue, reason: '$ordnerArg $dateien');
      }
      expect(p.app.freigaben, isEmpty);
      expect(da('klassen/7b/mathe/plan.md'), isTrue);
    });

    test('nur .md-Dateien', () async {
      await schreibe('klassen/7b/mathe/bild.png', 'x');
      final p = await laufendesPlugin();
      final ergebnis = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['bild.png']);
      expect(ergebnis['isError'], isTrue);
      expect(da('klassen/7b/mathe/bild.png'), isTrue);
    });

    test('doppelte Namen und leere Liste werden abgewiesen', () async {
      final p = await laufendesPlugin();
      final doppelt = await archiv(p, ordner: 'klassen/7b/mathe', dateien: ['plan.md', 'plan.md']);
      expect(doppelt['isError'], isTrue);
      // Das Schema verlangt mindestens einen Namen: mcp_dart weist die Liste als
      // JSON-RPC-Fehler ab, bevor das Werkzeug läuft; beides gilt als Abweisung.
      final leer = await archiv(p, ordner: 'klassen/7b/mathe', dateien: []);
      expect(leer.containsKey('_fehler') || leer['isError'] == true, isTrue, reason: '$leer');
      expect(da('klassen/7b/mathe/plan.md'), isTrue);
      expect(p.app.freigaben, isEmpty);
    });

    test('eine leere Zusammenfassung wird abgewiesen', () async {
      final p = await laufendesPlugin();
      final ergebnis = await archiv(
        p,
        ordner: 'klassen/7b/mathe',
        dateien: ['plan.md'],
        zusammenfassung: '  ',
      );
      expect(ergebnis['isError'], isTrue);
      expect(da('klassen/7b/mathe/plan.md'), isTrue);
    });
  });
}
