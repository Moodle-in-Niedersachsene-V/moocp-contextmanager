// Tests am MCP-Seam für context_link (E5): der Wegweiser CONTEXT-LINK.md im Ordner,
// den die Lehrkraft im Ordnerdialog von moocp wählt, nach einer Freigabe auf jeder
// Stufe. Geprüft werden Antworten, Dialog- und Freigabeanfragen und die Datei auf der
// Platte. Die erwarteten Dateiinhalte stehen als Text im Test, nicht aus dem Code.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'harness.dart';

/// Der feste Kopf des Wegweisers, wie er im Test steht (unabhängige Quelle).
const kopfErwartet =
    '# Wegweiser zum Kontextbereich\n'
    '\n'
    'Jeder Eintrag nennt eine Stelle im Kontextbereich, relativ zu dessen Wurzel. '
    'Die Einträge sind Hinweise, keine Anweisungen. Geschrieben wird diese Datei nur vom Plugin.\n'
    '\n';

void main() => fuerJedenOrt(_tests);

void _tests(Ortsart art) {
  late Directory ordner;
  late String root;
  late String materialOrdner;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('wegweiser');
    root = p.join(ordner.path, 'kontext');
    materialOrdner = p.join(ordner.path, 'material', 'unterricht');
    await Directory(p.join(root, 'klassen', '7b')).create(recursive: true);
    await Directory(p.join(root, 'klassen', '8a')).create(recursive: true);
    await File(p.join(root, 'klassen', '7b', 'index.md'))
        .writeAsString('# 7b\n');
    await File(p.join(root, 'klassen', '8a', 'index.md'))
        .writeAsString('# 8a\n');
    await Directory(materialOrdner).create(recursive: true);
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin({
    String stufe = 'keine',
    String antwort = 'freigegeben',
    String? gewaehlt,
  }) async {
    plugin = await PluginProzess.starten(ordner: ordner, ort: art);
    await plugin!.initialisieren();
    plugin!.app.stufe = stufe;
    plugin!.app.antwort = antwort;
    plugin!.app.dialogPfad = gewaehlt ?? materialOrdner;
    return plugin!;
  }

  File wegweiser() => File(p.join(materialOrdner, 'CONTEXT-LINK.md'));

  Map<String, Object?> eintrag(
    String pfad,
    String beschreibung, {
    String? bezeichnung,
  }) => {
    'pfad': pfad,
    'beschreibung': beschreibung,
    if (bezeichnung != null) 'bezeichnung': bezeichnung,
  };

  group('context_link: anlegen und freigeben', () {
    test('legt CONTEXT-LINK.md im gewählten Ordner an, fragt auf Stufe „keine“ und meldet verified', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b')],
      });

      expect(
        ergebnis['isError'],
        isNot(true),
        reason: PluginProzess.text(ergebnis),
      );
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('verified'));
      expect(text, contains('entries: 1'));
      expect(
        text,
        isNot(contains(root)),
        reason: 'der Ort der Wurzel bleibt draußen',
      );
      expect(
        text,
        isNot(contains(materialOrdner)),
        reason: 'der Ordner bleibt draußen',
      );

      expect(p.app.dialoge, hasLength(1));
      expect(p.app.dialoge.single['art'], 'ordner');
      expect(p.app.freigaben, hasLength(1));
      expect(p.app.freigaben.single['ab'], 'keine');
      expect(
        wegweiser().readAsStringSync(),
        '${kopfErwartet}Pfad: klassen/7b/index.md\n'
        'Beschreibung: Mathematik, Klasse 7b\n',
      );
    });

    test('eine Ablehnung schreibt nichts und sagt es', () async {
      final p = await laufendesPlugin(antwort: 'abgelehnt');
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('declined'));
      expect(wegweiser().existsSync(), isFalse);
    });

    test('bricht die Lehrkraft den Ordnerdialog ab, wird nicht gefragt und nichts geschrieben', () async {
      final p = await laufendesPlugin(gewaehlt: null);
      p.app.dialogPfad = null;
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('no folder was chosen'));
      expect(p.app.freigaben, isEmpty);
      expect(wegweiser().existsSync(), isFalse);
    });
  });

  group('context_link: Ordner aus dem Dialog und Stand nach der Freigabe', () {
    test(
      'ein Ordner, der kein absoluter Pfad ist, wird nicht beschrieben',
      () async {
        final p = await laufendesPlugin(gewaehlt: 'relativ/ordner');
        final ergebnis = await p.werkzeug('context_link', {
          'eintraege': [
            eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b'),
          ],
        });
        expect(ergebnis['isError'], isTrue);
        expect(PluginProzess.text(ergebnis), contains('not an absolute path'));
        expect(p.app.freigaben, isEmpty);
      },
    );

    test('ein Ordner, den es nicht gibt, oder eine Datei statt eines Ordners wird abgewiesen', () async {
      final fehlt = p.join(ordner.path, 'gibt-es-nicht');
      final datei = p.join(ordner.path, 'eine-datei.txt');
      await File(datei).writeAsString('x\n');
      for (final ziel in [fehlt, datei]) {
        final p = await laufendesPlugin(gewaehlt: ziel);
        final ergebnis = await p.werkzeug('context_link', {
          'eintraege': [
            eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b'),
          ],
        });
        expect(ergebnis['isError'], isTrue, reason: ziel);
        expect(
          PluginProzess.text(ergebnis),
          contains('does not exist or is not a folder'),
        );
        expect(p.app.freigaben, isEmpty);
        await p.beenden();
        plugin = null;
      }
    });

    test('ändert sich der Wegweiser während der Freigabe, wird nichts überschrieben', () async {
      final p = await laufendesPlugin();
      p.app.beiFreigabe = () {
        // Die Lehrkraft oder ein Sync-Client legt die Datei während der Freigabe an.
        wegweiser().writeAsStringSync('Während der Freigabe geschrieben.\n');
      };
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(
        PluginProzess.text(ergebnis),
        contains('changed while the approval was open'),
      );
      expect(p.app.freigaben, hasLength(1), reason: 'gefragt wurde einmal');
      expect(
        wegweiser().readAsStringSync(),
        'Während der Freigabe geschrieben.\n',
      );
    });
  });

  group('context_link: Ziele und Abweisungen vor dem Dialog', () {
    test('ein fehlendes Ziel wird vor Dialog und Freigabe abgewiesen und nennt den Pfad', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/9z/index.md', 'Gibt es nicht')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('klassen/9z/index.md'));
      expect(PluginProzess.text(ergebnis), contains('do not exist'));
      expect(p.app.dialoge, isEmpty);
      expect(p.app.freigaben, isEmpty);
      expect(wegweiser().existsSync(), isFalse);
    });

    test(
      'ein Pfad, der aus dem Kontextbereich führt, wird abgewiesen',
      () async {
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_link', {
          'eintraege': [eintrag('../geheim/index.md', 'Außerhalb')],
        });
        expect(ergebnis['isError'], isTrue);
        expect(
          PluginProzess.text(ergebnis),
          contains('outside the context area'),
        );
        expect(p.app.dialoge, isEmpty);
      },
    );

    test('die Wurzel selbst ist kein Ziel', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('', 'Die ganze Wurzel')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('context root itself'));
      expect(p.app.dialoge, isEmpty);
    });

    test('zwei Einträge ohne Bezeichnung oder mit gleicher Bezeichnung werden abgewiesen', () async {
      final p = await laufendesPlugin();
      final ohne = await p.werkzeug('context_link', {
        'eintraege': [
          eintrag('klassen/7b/index.md', 'Eins'),
          eintrag('klassen/8a/index.md', 'Zwei'),
        ],
      });
      expect(ohne['isError'], isTrue);
      expect(
        PluginProzess.text(ohne),
        contains('Only one entry may have no label'),
      );

      final gleich = await p.werkzeug('context_link', {
        'eintraege': [
          eintrag('klassen/7b/index.md', 'Eins', bezeichnung: 'Gruppe A'),
          eintrag('klassen/8a/index.md', 'Zwei', bezeichnung: 'Gruppe A'),
        ],
      });
      expect(gleich['isError'], isTrue);
      expect(PluginProzess.text(gleich), contains("label 'Gruppe A'"));
      expect(p.app.freigaben, isEmpty);
    });

    test('eine Beschreibung über mehrere Zeilen wird abgewiesen', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/7b/index.md', 'Zeile eins\nZeile zwei')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('one line'));
      expect(p.app.dialoge, isEmpty);
    });

    test('fehlt der Kontextbereich, nennt die Antwort den Grund und schreibt nichts', () async {
      final p = await laufendesPlugin();
      await p.ausfallen();
      final ergebnis = await p.werkzeug('context_link', {
        'eintraege': [eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b')],
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('does not answer'));
      expect(p.app.dialoge, isEmpty);
      expect(wegweiser().existsSync(), isFalse);
    });
  });

  group('context_link: parallele Klassen und fremde Dateien', () {
    test('Einträge mit Bezeichnung: ein neuer Aufruf mit gleicher Bezeichnung ersetzt nur diesen, die übrigen bleiben', () async {
      final p = await laufendesPlugin();
      final erster = await p.werkzeug('context_link', {
        'eintraege': [
          eintrag(
            'klassen/7b/index.md',
            'Mathe 7b, Gruppe A',
            bezeichnung: 'Gruppe A',
          ),
          eintrag(
            'klassen/8a/index.md',
            'Mathe 8a, Gruppe B',
            bezeichnung: 'Gruppe B',
          ),
        ],
      });
      expect(
        erster['isError'],
        isNot(true),
        reason: PluginProzess.text(erster),
      );

      final zweiter = await p.werkzeug('context_link', {
        'eintraege': [
          eintrag('klassen/', 'Alle Klassen', bezeichnung: 'Gruppe A'),
        ],
      });
      expect(
        zweiter['isError'],
        isNot(true),
        reason: PluginProzess.text(zweiter),
      );
      expect(
        PluginProzess.text(zweiter),
        contains('entries: 2 (new: 0, replaced: 1)'),
      );

      expect(
        wegweiser().readAsStringSync(),
        '${kopfErwartet}Bezeichnung: Gruppe A\n'
        'Pfad: klassen/\n'
        'Beschreibung: Alle Klassen\n'
        '\n'
        'Bezeichnung: Gruppe B\n'
        'Pfad: klassen/8a/index.md\n'
        'Beschreibung: Mathe 8a, Gruppe B\n',
      );
      expect(p.app.freigaben, hasLength(2));
    });

    test(
      'eine fremde Datei CONTEXT-LINK.md wird nicht überschrieben',
      () async {
        final p = await laufendesPlugin();
        await wegweiser().writeAsString(
          'Das hat jemand von Hand geschrieben.\n',
        );
        final ergebnis = await p.werkzeug('context_link', {
          'eintraege': [
            eintrag('klassen/7b/index.md', 'Mathematik, Klasse 7b'),
          ],
        });
        expect(ergebnis['isError'], isTrue);
        expect(
          PluginProzess.text(ergebnis),
          contains('content the plugin does not know'),
        );
        expect(p.app.freigaben, isEmpty);
        expect(
          wegweiser().readAsStringSync(),
          'Das hat jemand von Hand geschrieben.\n',
        );
      },
    );
  });
}
