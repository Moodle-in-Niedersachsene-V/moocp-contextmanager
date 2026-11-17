// Tests am MCP-Seam für context_write und context_append: Das Plugin startet wie
// unter moocp, die Werkzeuge werden über MCP aufgerufen, die falsche App
// beantwortet Freigaben nach der Stufe der Lehrkraft (E20). Geprüft werden
// Antworten, Freigabeanfragen und der Inhalt der Dateien danach.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

/// sha256 von `hallo\n` (mit `sha256sum` ermittelt, unabhängige Quelle).
const versionHallo =
    '622cb3371c1a08096eaac564fb59acccda1fcdbe13a9dd10b486e6463c8c2525';

/// Die Meldung eines fehlgeschlagenen Aufrufs: der Text eines Ergebnisses mit
/// `isError`, oder die Meldung des Fehlers, den der Server schon vor dem Werkzeug
/// zurückgibt (Prüfung gegen das Schema).
String fehlerMeldung(Map<String, dynamic> ergebnis) {
  expect(
    ergebnis['isError'] == true || ergebnis.containsKey('_fehler'),
    isTrue,
    reason: 'erwartet: Fehler, bekommen: $ergebnis',
  );
  if (ergebnis.containsKey('_fehler'))
    return '${(ergebnis['_fehler'] as Map)['message']}';
  return PluginProzess.text(ergebnis);
}

String einstellungen(String root) => jsonEncode({'art': 'lokal', 'pfad': root});

void main() {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('schreiben');
    root = pfad.join(ordner.path, 'kontext');
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

  Future<void> schreibeDatei(String relativ, String inhalt) async {
    final f = File(datei(relativ));
    await f.parent.create(recursive: true);
    await f.writeAsString(inhalt);
  }

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

  group('context_write: anlegen und ersetzen', () {
    test('legt eine neue Datei an, fragt auf Stufe alle und meldet verified mit der Version', () async {
      final p = await laufendesPlugin(stufe: 'alle');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'unterricht/notizen.md',
          inhalt: 'hallo\n',
          art: 'new_file',
        ),
      );
      expect(ergebnis['isError'], isNot(true));
      expect(PluginProzess.text(ergebnis), startsWith('verified'));
      expect(PluginProzess.text(ergebnis), contains('version: $versionHallo'));
      expect(
        await File(datei('unterricht/notizen.md')).readAsString(),
        'hallo\n',
      );
      expect(p.app.freigaben, hasLength(1));
      expect(p.app.freigaben.single['ab'], 'alle');
    });

    test('ersetzt eine Datei nur mit der Version, die gelesen wurde', () async {
      await schreibeDatei('plan.md', 'hallo\n');
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
      expect(ergebnis['isError'], isNot(true));
      expect(PluginProzess.text(ergebnis), startsWith('verified'));
      expect(await File(datei('plan.md')).readAsString(), 'neu\n');
    });

    test('bricht mit Konflikt ab, wenn die Datei seit dem Lesen geändert wurde, und fragt nicht', () async {
      await schreibeDatei('plan.md', 'anders\n');
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
      expect(
        PluginProzess.text(ergebnis),
        contains('changed since it was read'),
      );
      expect(await File(datei('plan.md')).readAsString(), 'anders\n');
      expect(p.app.freigaben, isEmpty);
    });

    test(
      'verweigert das Anlegen über eine bestehende Datei ohne Version',
      () async {
        await schreibeDatei('plan.md', 'hallo\n');
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(pfadArg: 'plan.md', inhalt: 'neu\n', art: 'plan_change'),
        );
        expect(ergebnis['isError'], isTrue);
        expect(PluginProzess.text(ergebnis), contains('already exists'));
        expect(await File(datei('plan.md')).readAsString(), 'hallo\n');
        expect(p.app.freigaben, isEmpty);
      },
    );

    test('ein Journal wird nie ersetzt, nur angehängt', () async {
      await schreibeDatei('journal/2026-11-17.md', 'hallo\n');
      final p = await laufendesPlugin(stufe: 'alle');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'journal/2026-11-17.md',
          inhalt: 'neu\n',
          art: 'journal',
          version: versionHallo,
        ),
      );
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('context_append'));
      expect(
        await File(datei('journal/2026-11-17.md')).readAsString(),
        'hallo\n',
      );
    });

    test(
      'ein Journal wird auch bei anderer Groß- und Kleinschreibung nie ersetzt',
      () async {
        final p = await laufendesPlugin(stufe: 'alle');
        // Auf macOS und Windows zeigen diese Pfade auf das Journal. Die Bindung
        // hängt deshalb nicht an der Schreibweise, und jeder Pfad wird abgewiesen,
        // bevor etwas geschrieben oder gefragt wird.
        for (final pfadArg in [
          'Journal/2026-11-17.md',
          'JOURNAL/2026-11-17.md',
          'Journal-2026-11-17.md',
          'JOURNAL-2026-11-17.md',
        ]) {
          final ergebnis = await p.werkzeug(
            'context_write',
            schreiben(pfadArg: pfadArg, inhalt: 'neu\n', art: 'correction'),
          );
          expect(ergebnis['isError'], isTrue, reason: pfadArg);
          expect(PluginProzess.text(ergebnis), contains('context_append'));
          expect(File(datei(pfadArg)).existsSync(), isFalse, reason: pfadArg);
        }
        expect(p.app.freigaben, isEmpty);
      },
    );

    test(
      'die Art root_file wird für eine Datei in einem Ordner abgewiesen',
      () async {
        final p = await laufendesPlugin(stufe: 'alle');
        final falsch = await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'unterricht/x.md',
            inhalt: 'x\n',
            art: 'root_file',
          ),
        );
        expect(falsch['isError'], isTrue);
        expect(File(datei('unterricht/x.md')).existsSync(), isFalse);
        expect(p.app.freigaben, isEmpty);
      },
    );

    test('ein Journal wird auch mit einer anderen Art nicht ersetzt', () async {
      await schreibeDatei('journal/2026-11-17.md', 'hallo\n');
      final p = await laufendesPlugin(stufe: 'alle');
      for (final art in ['correction', 'new_file', 'plan_change']) {
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'journal/2026-11-17.md',
            inhalt: 'neu\n',
            art: art,
            version: versionHallo,
          ),
        );
        expect(ergebnis['isError'], isTrue, reason: art);
        expect(
          PluginProzess.text(ergebnis),
          contains('context_append'),
          reason: art,
        );
      }
      expect(
        await File(datei('journal/2026-11-17.md')).readAsString(),
        'hallo\n',
      );
      expect(p.app.freigaben, isEmpty);
    });

    test(
      'auch das alte Journal im Wurzelordner (journal-*.md) wird nicht ersetzt',
      () async {
        await schreibeDatei('journal-2026-11-17.md', 'hallo\n');
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'journal-2026-11-17.md',
            inhalt: 'neu\n',
            art: 'correction',
            version: versionHallo,
          ),
        );
        expect(ergebnis['isError'], isTrue);
        expect(
          await File(datei('journal-2026-11-17.md')).readAsString(),
          'hallo\n',
        );
        expect(p.app.freigaben, isEmpty);
      },
    );

    test('eine leere Zusammenfassung wird vor der Freigabe abgewiesen und nennt den nächsten Schritt', () async {
      final p = await laufendesPlugin(stufe: 'alle');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'unterricht/notizen.md',
          inhalt: 'hallo\n',
          art: 'new_file',
          zusammenfassung: '',
        ),
      );
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('zusammenfassung'));
      expect(PluginProzess.text(ergebnis), contains('summary'));
      expect(p.app.freigaben, isEmpty);
      expect(File(datei('unterricht/notizen.md')).existsSync(), isFalse);
    });

    test(
      'Steuerzeichen im Pfad werden abgewiesen, bevor etwas geschieht',
      () async {
        final p = await laufendesPlugin(stufe: 'alle');
        for (final pfadArg in ['notiz\nx.md', 'tab\tx.md']) {
          final ergebnis = await p.werkzeug(
            'context_write',
            schreiben(pfadArg: pfadArg, inhalt: 'x\n', art: 'new_file'),
          );
          expect(ergebnis['isError'], isTrue, reason: pfadArg);
        }
        expect(p.app.freigaben, isEmpty);
        expect(Directory(root).listSync(), isEmpty);
      },
    );

    test(
      'die Beschreibung der Schreibwerkzeuge verweist auf die Freigabestufe',
      () async {
        final p = await laufendesPlugin();
        final liste = await p.anfragen('tools/list', {});
        final werkzeuge = (liste['tools'] as List).cast<Map<String, dynamic>>();
        for (final name in ['context_write', 'context_append']) {
          final beschreibung =
              werkzeuge.firstWhere((w) => w['name'] == name)['description']
                  as String;
          expect(beschreibung, contains('approval level'), reason: name);
          expect(
            beschreibung,
            isNot(contains('Every write asks')),
            reason: name,
          );
        }
      },
    );
  });

  group('context_append', () {
    test('legt eine fehlende Datei ohne Version an', () async {
      final p = await laufendesPlugin(stufe: 'alle');
      final ergebnis = await p.werkzeug(
        'context_append',
        schreiben(
          pfadArg: 'journal/2026-11-17.md',
          inhalt: 'Erster Eintrag',
          art: 'journal',
        ),
      );
      expect(PluginProzess.text(ergebnis), startsWith('verified'));
      expect(
        await File(datei('journal/2026-11-17.md')).readAsString(),
        'Erster Eintrag\n',
      );
    });

    test(
      'hängt mit der gelesenen Version an und behält den alten Inhalt',
      () async {
        await schreibeDatei('notizen.md', 'hallo\n');
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_append',
          schreiben(
            pfadArg: 'notizen.md',
            inhalt: 'zwei\n',
            art: 'correction',
            version: versionHallo,
          ),
        );
        expect(PluginProzess.text(ergebnis), startsWith('verified'));
        expect(await File(datei('notizen.md')).readAsString(), 'hallo\nzwei\n');
      },
    );

    test(
      'bricht mit Konflikt ab, wenn die Datei seit dem Lesen geändert wurde',
      () async {
        await schreibeDatei('notizen.md', 'anders\n');
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_append',
          schreiben(
            pfadArg: 'notizen.md',
            inhalt: 'zwei\n',
            art: 'correction',
            version: versionHallo,
          ),
        );
        expect(ergebnis['isError'], isTrue);
        expect(
          PluginProzess.text(ergebnis),
          contains('changed since it was read'),
        );
        expect(await File(datei('notizen.md')).readAsString(), 'anders\n');
        expect(p.app.freigaben, isEmpty);
      },
    );
  });

  group('Freigabe nach Stufe der Lehrkraft (E20)', () {
    test(
      'Stufe alle: jedes Schreiben wird gefragt, auch das Journal',
      () async {
        final p = await laufendesPlugin(stufe: 'alle');
        await p.werkzeug(
          'context_append',
          schreiben(
            pfadArg: 'journal/2026-11-17.md',
            inhalt: 'Eintrag',
            art: 'journal',
          ),
        );
        expect(p.app.freigabeAntworten.single['ohneFrage'], isFalse);
        expect(
          await File(datei('journal/2026-11-17.md')).readAsString(),
          'Eintrag\n',
        );
      },
    );

    test(
      'Stufe mittel: Journal ohne Frage, Planänderung wird gefragt',
      () async {
        await schreibeDatei('plan.md', 'hallo\n');
        final p = await laufendesPlugin(stufe: 'mittel');
        await p.werkzeug(
          'context_append',
          schreiben(
            pfadArg: 'journal/2026-11-17.md',
            inhalt: 'Eintrag',
            art: 'journal',
          ),
        );
        await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'plan.md',
            inhalt: 'neu\n',
            art: 'plan_change',
            version: versionHallo,
          ),
        );
        expect(p.app.freigabeAntworten[0]['ohneFrage'], isTrue);
        expect(p.app.freigaben[1]['ab'], 'mittel');
        expect(p.app.freigabeAntworten[1]['ohneFrage'], isFalse);
        expect(await File(datei('plan.md')).readAsString(), 'neu\n');
      },
    );

    test(
      'Stufe keine: nichts wird gefragt, Schreiben geht ohne Frage durch',
      () async {
        await schreibeDatei('plan.md', 'hallo\n');
        final p = await laufendesPlugin(stufe: 'keine');
        await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'plan.md',
            inhalt: 'neu\n',
            art: 'plan_addition',
            version: versionHallo,
          ),
        );
        expect(p.app.freigabeAntworten, hasLength(1));
        expect(p.app.freigabeAntworten.single['ohneFrage'], isTrue);
        expect(await File(datei('plan.md')).readAsString(), 'neu\n');
      },
    );

    test('die Art bestimmt die Stufe, ab der gefragt wird', () async {
      await schreibeDatei('plan.md', 'hallo\n');
      await schreibeDatei('unterricht/notizen.md', 'hallo\n');
      final p = await laufendesPlugin(stufe: 'alle');
      await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'plan.md',
          inhalt: 'a\n',
          art: 'plan_change',
          version: versionHallo,
        ),
      );
      await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'unterricht/neu.md', inhalt: 'b\n', art: 'new_file'),
      );
      // Eine Datei direkt am Wurzelordner gilt wie root_file, auch wenn ihre Art es nicht verlangt.
      await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'wurzel.md', inhalt: 'c\n', art: 'new_file'),
      );
      await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'unterricht/x.md',
          inhalt: 'd\n',
          art: 'plan_addition',
        ),
      );
      await p.werkzeug(
        'context_append',
        schreiben(
          pfadArg: 'unterricht/notizen.md',
          inhalt: 'e\n',
          art: 'correction',
          version: versionHallo,
        ),
      );
      // root_file ist nur für Dateien direkt am Wurzelordner zulässig: Hier wird nichts gefragt.
      final falsch = await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'unterricht/y.md', inhalt: 'f\n', art: 'root_file'),
      );
      expect(falsch['isError'], isTrue);
      expect(p.app.freigaben.map((f) => f['ab']).toList(), [
        'mittel',
        'alle',
        'mittel',
        'mittel',
        'alle',
      ]);
    });

    test('eine Ablehnung schreibt nichts und sagt es', () async {
      final p = await laufendesPlugin(stufe: 'alle', antwort: 'abgelehnt');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(
          pfadArg: 'unterricht/notizen.md',
          inhalt: 'hallo\n',
          art: 'new_file',
        ),
      );
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('Not written'));
      expect(File(datei('unterricht/notizen.md')).existsSync(), isFalse);
    });

    test(
      'ohne Aufruf-Token gibt es keine Freigabe und nichts wird geschrieben',
      () async {
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(
            pfadArg: 'unterricht/notizen.md',
            inhalt: 'hallo\n',
            art: 'new_file',
          ),
          aufruf: null,
        );
        expect(ergebnis['isError'], isTrue);
        expect(File(datei('unterricht/notizen.md')).existsSync(), isFalse);
      },
    );
  });

  group('Prüfung der Ziele', () {
    test('nur .md-Dateien werden geschrieben', () async {
      final p = await laufendesPlugin(stufe: 'alle');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben(pfadArg: 'notiz.txt', inhalt: 'x\n', art: 'new_file'),
      );
      expect(ergebnis['isError'], isTrue);
      expect(File(datei('notiz.txt')).existsSync(), isFalse);
      expect(p.app.freigaben, isEmpty);
    });

    test('ein Pfad, der aus der Wurzel führt, wird abgewiesen, auch über eine Verknüpfung', () async {
      final draussen = Directory(pfad.join(ordner.path, 'draussen'));
      await draussen.create();
      await Link(datei('link')).create(draussen.path);
      final p = await laufendesPlugin(stufe: 'alle');
      for (final pfadArg in ['../draussen.md', 'link/x.md']) {
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(pfadArg: pfadArg, inhalt: 'x\n', art: 'new_file'),
        );
        expect(ergebnis['isError'], isTrue, reason: pfadArg);
        expect(
          PluginProzess.text(ergebnis),
          contains('outside the context area'),
        );
      }
      expect(File(pfad.join(draussen.path, 'x.md')).existsSync(), isFalse);
      expect(File(pfad.join(ordner.path, 'draussen.md')).existsSync(), isFalse);
      expect(p.app.freigaben, isEmpty);
    });
  });

  group('Fehler bei falschen Argumenten (K8)', () {
    test('ein Argument mit falschem Typ ist ein Ergebnis mit Fehler, keine Ausnahme', () async {
      final p = await laufendesPlugin(stufe: 'alle');
      final schreibfehler = await p.werkzeug('context_write', {
        'pfad': 5,
        'inhalt': 'x',
        'art': 'new_file',
        'zusammenfassung': 'z',
      });
      expect(fehlerMeldung(schreibfehler), contains('pfad'));
      final lesefehler = await p.werkzeug('context_read', {'pfad': 5});
      expect(fehlerMeldung(lesefehler), contains('pfad'));
      // Der Server bleibt danach ansprechbar.
      final liste = await p.werkzeug('context_list', {'pfad': ''});
      expect(liste['isError'], isNot(true));
    });

    test(
      'eine unbekannte Art wird abgewiesen und nennt das Argument',
      () async {
        final p = await laufendesPlugin(stufe: 'alle');
        final ergebnis = await p.werkzeug(
          'context_write',
          schreiben(pfadArg: 'x.md', inhalt: 'x', art: 'egal'),
        );
        expect(fehlerMeldung(ergebnis), contains('art'));
        expect(File(datei('x.md')).existsSync(), isFalse);
      },
    );
  });
}
