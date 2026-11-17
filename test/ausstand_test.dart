// Tests am MCP-Seam für den Ausstand (E2): Ein Schreibvorgang, den der Ort
// nicht annimmt, wird mit Inhalt, Ziel, Vorgang und Version gehalten und mit
// derselben Stand-Prüfung und Freigabe wiederholt. Geprüft werden Antworten,
// Freigabeanfragen, der Inhalt der Dateien und der Ausstand auf der Platte.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

/// sha256 von `hallo\n`.
const versionHallo =
    '622cb3371c1a08096eaac564fb59acccda1fcdbe13a9dd10b486e6463c8c2525';

String einstellungen(String root) => jsonEncode({'art': 'lokal', 'pfad': root});

void main() {
  late Directory ordner;
  late String root;
  late String ausstandOrdner;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('ausstand');
    root = pfad.join(ordner.path, 'kontext');
    ausstandOrdner = pfad.join(ordner.path, 'ausstand');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin({
    String stufe = 'mittel',
    String antwort = 'freigegeben',
  }) async {
    plugin = await PluginProzess.starten(
      ordner: ordner,
      einstellungenInhalt: einstellungen(root),
    );
    await plugin!.initialisieren();
    plugin!.app.stufe = stufe;
    plugin!.app.antwort = antwort;
    return plugin!;
  }

  String datei(String relativ) => pfad.join(root, relativ);

  /// Die Dateien im Ausstand (je Vorgang eine), sortiert nach Name.
  List<File> ausstandDateien() {
    final dir = Directory(ausstandOrdner);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  Map<String, dynamic> einzigerVorgang() =>
      (jsonDecode(ausstandDateien().single.readAsStringSync()) as Map)
          .cast<String, dynamic>();

  /// Der Ort antwortet nicht: der Wurzelordner fehlt.
  Future<void> ortAusfallen() => Directory(root).delete(recursive: true);

  Future<void> ortWiederherstellen() => Directory(root).create();

  Map<String, Object?> schreiben({
    required String pfadArg,
    required String inhalt,
    required String art,
    String? version,
    String zusammenfassung = 'Kurze Zusammenfassung.',
  }) => {
    'pfad': pfadArg,
    'inhalt': inhalt,
    'art': art,
    'zusammenfassung': zusammenfassung,
    if (version != null) 'version': version,
  };

  group('Ausfall des Ortes: der Auftrag wird zurückgestellt', () {
    test('ein Schreiben bei fehlender Wurzel ist nicht gespeichert, steht im Ausstand und fragt nicht', () async {
      await ortAusfallen();
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'plan.md', inhalt: 'hallo\n', art: 'plan_change'),
      );
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('not saved yet'));
      expect(text, contains('does not exist'));
      expect(text, contains('Do not write it again'));
      expect(p.app.freigaben, isEmpty);

      expect(ausstandDateien(), hasLength(1));
      final vorgang = einzigerVorgang();
      expect(vorgang['pfad'], 'plan.md');
      expect(vorgang['inhalt'], 'hallo\n');
      expect(vorgang['art'], 'plan_change');
      expect(vorgang['version'], isNull);
      expect(vorgang['anhaengen'], isFalse);
      expect(text, contains(vorgang['id'] as String));
      expect(Directory(root).existsSync(), isFalse);
    });

    test('ein Anhängen ohne Wurzel wird als Anhängen gehalten', () async {
      await ortAusfallen();
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug(
        'context_append',
        schreiben(
          pfadArg: 'journal/2026-11-17.md',
          inhalt: 'Eintrag\n',
          art: 'journal',
        ),
      );
      expect(PluginProzess.text(ergebnis), startsWith('not saved yet'));
      expect(einzigerVorgang()['anhaengen'], isTrue);
    });

    test('Wiederholen nach Wiederherstellung schreibt nach neuer Freigabe und räumt den Ausstand auf', () async {
      await ortAusfallen();
      final p = await laufendesPlugin(stufe: 'mittel');
      await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'plan.md', inhalt: 'hallo\n', art: 'plan_change'),
      );
      await ortWiederherstellen();

      final start = await p.werkzeug('context_start', {'wiederholen': true});
      final text = PluginProzess.text(start);
      expect(text, contains('written and verified'));
      expect(text, contains('version: $versionHallo'));
      expect(await File(datei('plan.md')).readAsString(), 'hallo\n');
      expect(ausstandDateien(), isEmpty);

      expect(p.app.freigaben, hasLength(1));
      expect(p.app.freigaben.single['ab'], 'mittel');
      expect(
        p.app.freigaben.single['zusammenfassung'],
        contains('Aus dem Ausstand'),
      );
    });

    test(
      'Wiederholen eines Journaleintrags hängt an, wenn die Datei noch fehlt',
      () async {
        await ortAusfallen();
        final p = await laufendesPlugin(stufe: 'alle');
        await p.werkzeug(
          'context_append',
          schreiben(
            pfadArg: 'journal/2026-11-17.md',
            inhalt: 'Eintrag\n',
            art: 'journal',
          ),
        );
        await ortWiederherstellen();
        await p.werkzeug('context_start', {'wiederholen': true});
        expect(
          await File(datei('journal/2026-11-17.md')).readAsString(),
          'Eintrag\n',
        );
        expect(ausstandDateien(), isEmpty);
      },
    );

    test('Wiederholen ersetzt nicht, wenn die Datei seit dem Zurückstellen geändert wurde', () async {
      await ortAusfallen();
      final p = await laufendesPlugin(stufe: 'alle');
      await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'plan.md',
          inhalt: 'neu\n',
          art: 'plan_change',
          version: versionHallo,
        ),
      );
      await ortWiederherstellen();
      await File(datei('plan.md')).writeAsString('anders\n');

      final text = PluginProzess.text(
        await p.werkzeug('context_start', {'wiederholen': true}),
      );
      expect(text, contains('changed since it was read'));
      expect(text, contains('kept'));
      expect(await File(datei('plan.md')).readAsString(), 'anders\n');
      expect(ausstandDateien(), hasLength(1));
      expect(p.app.freigaben, isEmpty, reason: 'ein Konflikt fragt nicht');
    });

    test(
      'ein Konflikt hält nur seinen Vorgang an, die anderen werden geschrieben',
      () async {
        await ortAusfallen();
        final p = await laufendesPlugin(stufe: 'alle');
        await p.werkzeug(
          'context_write',
          schreiben(pfadArg: 'a.md', inhalt: 'a\n', art: 'new_file'),
        );
        await p.werkzeug(
          'context_write',
          schreiben(pfadArg: 'b.md', inhalt: 'b\n', art: 'new_file'),
        );
        await ortWiederherstellen();
        await File(datei('a.md')).writeAsString('schon da\n');

        final text = PluginProzess.text(
          await p.werkzeug('context_start', {'wiederholen': true}),
        );
        expect(text, contains('already exists'));
        expect(text, contains('written and verified'));
        expect(await File(datei('a.md')).readAsString(), 'schon da\n');
        expect(await File(datei('b.md')).readAsString(), 'b\n');
        expect(ausstandDateien(), hasLength(1));
        expect(einzigerVorgang()['pfad'], 'a.md');
      },
    );

    test(
      'eine Ablehnung beim Wiederholen entfernt den Vorgang, ohne zu schreiben',
      () async {
        await ortAusfallen();
        final p = await laufendesPlugin(stufe: 'mittel', antwort: 'abgelehnt');
        await p.werkzeug(
          'context_write',
          schreiben(pfadArg: 'plan.md', inhalt: 'hallo\n', art: 'plan_change'),
        );
        await ortWiederherstellen();

        final text = PluginProzess.text(
          await p.werkzeug('context_start', {'wiederholen': true}),
        );
        expect(text, contains('declined'));
        expect(text, contains('removed'));
        expect(File(datei('plan.md')).existsSync(), isFalse);
        expect(ausstandDateien(), isEmpty);
      },
    );

    test('eine abgebrochene Freigabe beim Wiederholen lässt den Vorgang im Ausstand', () async {
      await ortAusfallen();
      final p = await laufendesPlugin(stufe: 'mittel');
      await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'plan.md', inhalt: 'hallo\n', art: 'plan_change'),
      );
      await ortWiederherstellen();
      p.app.antwort = 'abgebrochen';

      final text = PluginProzess.text(
        await p.werkzeug('context_start', {'wiederholen': true}),
      );
      expect(text, contains('cancelled or timed out'));
      expect(File(datei('plan.md')).existsSync(), isFalse);
      expect(ausstandDateien(), hasLength(1));
    });

    test('auf Stufe „keine“ wird ein Vorgang beim Wiederholen ohne Frage geschrieben', () async {
      await ortAusfallen();
      final p = await laufendesPlugin(stufe: 'keine');
      await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'plan.md', inhalt: 'hallo\n', art: 'plan_change'),
      );
      await ortWiederherstellen();
      await p.werkzeug('context_start', {'wiederholen': true});
      expect(p.app.freigabeAntworten.single['ohneFrage'], isTrue);
      expect(await File(datei('plan.md')).readAsString(), 'hallo\n');
    });
  });

  group('Was nicht in den Ausstand kommt', () {
    test('ein Pfad, der aus der Wurzel führt, wird auch bei Ausfall abgewiesen und nicht gehalten', () async {
      await ortAusfallen();
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(pfadArg: '../x.md', inhalt: 'x\n', art: 'new_file'),
      );
      expect(ergebnis['isError'], isTrue);
      expect(ausstandDateien(), isEmpty);
    });

    test('eine leere Zusammenfassung wird auch bei Ausfall abgewiesen und nicht gehalten', () async {
      await ortAusfallen();
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'plan.md',
          inhalt: 'x\n',
          art: 'plan_change',
          zusammenfassung: '  ',
        ),
      );
      expect(ergebnis['isError'], isTrue);
      expect(ausstandDateien(), isEmpty);
    });

    test(
      'ein Journal, das ersetzt werden soll, wird auch bei Ausfall abgewiesen',
      () async {
        await ortAusfallen();
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'journal/2026-11-17.md',
            inhalt: 'x\n',
            art: 'journal',
          ),
        );
        expect(ergebnis['isError'], isTrue);
        expect(ausstandDateien(), isEmpty);
      },
    );

    test(
      'ein Konflikt bei erreichbarem Ort wird nicht zurückgestellt',
      () async {
        await File(datei('plan.md')).writeAsString('anders\n');
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'plan.md',
            inhalt: 'neu\n',
            art: 'plan_change',
            version: versionHallo,
          ),
        );
        expect(ergebnis['isError'], isTrue);
        expect(ausstandDateien(), isEmpty);
      },
    );

    test('eine Datei aus dem Ausstand wird nie als Kontext gelesen', () async {
      await ortAusfallen();
      final p = await laufendesPlugin(stufe: 'mittel');
      await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'plan.md', inhalt: 'hallo\n', art: 'plan_change'),
      );
      await ortWiederherstellen();

      final gelesen = await p.werkzeug('context_read', {'pfad': 'plan.md'});
      expect(gelesen['isError'], isTrue);
      final liste = await p.werkzeug('context_list', {'pfad': ''});
      expect(PluginProzess.text(liste), 'The folder is empty.');
      expect(ausstandDateien(), hasLength(1));
    });
  });
}
