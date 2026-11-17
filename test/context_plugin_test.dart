// Tests am MCP-Seam: das Plugin startet wie unter moocp, die Werkzeuge werden
// über MCP aufgerufen, geprüft werden Antworten und Zustand im Ordner.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

/// sha256 von `hallo\n`, mit `sha256sum` ermittelt (unabhängige Quelle).
const versionHallo =
    '622cb3371c1a08096eaac564fb59acccda1fcdbe13a9dd10b486e6463c8c2525';

String einstellungen(String root) => jsonEncode({'art': 'lokal', 'pfad': root});

bool _lesbar(File datei) {
  try {
    datei.readAsStringSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

void main() {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('test');
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

  group('Start und Zugang (E35)', () {
    test(
      'ohne den richtigen Schlüssel weist das Plugin jede Anfrage ab',
      () async {
        final p = await laufendesPlugin();
        final ergebnis = await p.anfragen(
          'tools/list',
          {},
          schluessel: 'falsch',
        );
        // Abgewiesen mit 401 oder 403, je nach Antwort des MCP-Pakets; wichtig ist,
        // dass keine Werkzeugliste herauskommt.
        expect(ergebnis['_status'], anyOf(401, 403));
        expect(ergebnis.containsKey('tools'), isFalse);
      },
    );

    test('ohne Authorization-Kopf weist es ab', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.anfragen('tools/list', {}, schluessel: null);
      // Abgewiesen mit 401 oder 403, je nach Antwort des MCP-Pakets; wichtig ist,
      // dass keine Werkzeugliste herauskommt.
      expect(ergebnis['_status'], anyOf(401, 403));
      expect(ergebnis.containsKey('tools'), isFalse);
    });

    test(
      'meldet sich als „context“ und bietet die vier Werkzeuge an',
      () async {
        final p = await laufendesPlugin();
        final liste = await p.anfragen('tools/list', {});
        final werkzeuge = (liste['tools'] as List).cast<Map<String, dynamic>>();
        final namen = werkzeuge.map((w) => w['name']).toSet();
        expect(namen, {
          'context_list',
          'context_read',
          'context_write',
          'context_append',
        });
        for (final w in werkzeuge) {
          expect(w['name'], startsWith('context_'));
          // Beschreibungen auf Englisch: Das Plugin spricht mit der KI.
          expect(w['description'], isNotEmpty);
          expect(w['description'], isNot(contains('Ordner')));
        }
      },
    );

    test('ohne Port beendet sich das Programm mit Exitcode 2', () async {
      final kurz = await PluginProzess.starten(
        ordner: ordner,
        einstellungenInhalt: einstellungen(root),
        mitPort: false,
      );
      expect(await kurz.prozess.exitCode, 2);
      await kurz.appServer.close(force: true);
    });

    test(
      'ohne Schlüssel in der Umgebung beendet es sich mit Exitcode 2',
      () async {
        final kurz = await PluginProzess.starten(
          ordner: ordner,
          einstellungenInhalt: einstellungen(root),
          schluessel: null,
        );
        expect(await kurz.prozess.exitCode, 2);
        await kurz.appServer.close(force: true);
      },
    );

    test('endet, wenn die Standardeingabe endet', () async {
      final p = await laufendesPlugin();
      await p.prozess.stdin.close();
      expect(await p.prozess.exitCode.timeout(const Duration(seconds: 10)), 0);
    });

    test(
      'mit --entwicklung läuft es weiter, auch wenn die Standardeingabe endet',
      () async {
        plugin = await PluginProzess.starten(
          ordner: ordner,
          einstellungenInhalt: einstellungen(root),
          mitEntwicklung: true,
        );
        final p = plugin!;
        await p.initialisieren();
        await p.prozess.stdin.close();
        await Future<void>.delayed(const Duration(seconds: 1));
        final liste = await p.anfragen('tools/list', {});
        expect(liste.containsKey('tools'), isTrue);
      },
    );
  });

  group('context_list', () {
    test(
      'listet Dateien und Ordner unterhalb der Wurzel, Ordner mit Schrägstrich',
      () async {
        await File(pfad.join(root, 'index.md')).writeAsString('x');
        await Directory(pfad.join(root, 'unterricht')).create();
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_list', {'pfad': ''});
        expect(ergebnis['isError'], isNot(true));
        expect(PluginProzess.text(ergebnis), 'index.md\nunterricht/');
      },
    );

    test('listet einen Unterordner', () async {
      await Directory(pfad.join(root, 'klasse', 'plan'))
          .create(recursive: true);
      await File(pfad.join(root, 'klasse', 'plan', 'woche-1.md'))
          .writeAsString('x');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_list', {
        'pfad': 'klasse/plan',
      });
      expect(PluginProzess.text(ergebnis), 'woche-1.md');
    });

    test('ein leerer Ordner sagt, dass er leer ist', () async {
      await Directory(pfad.join(root, 'leer')).create();
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_list', {'pfad': 'leer'});
      expect(PluginProzess.text(ergebnis), contains('empty'));
    });

    test('ein fehlender Ordner ist ein Fehler, keine leere Liste', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_list', {
        'pfad': 'gibt-es-nicht',
      });
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('does not exist'));
    });
  });

  group('context_read', () {
    test('liefert Inhalt und Version (sha256 des Inhalts)', () async {
      await File(pfad.join(root, 'index.md')).writeAsString('hallo\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'index.md'});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('version: $versionHallo'));
      expect(text, contains('hallo\n'));
    });

    test('die Version ändert sich mit dem Inhalt', () async {
      final datei = File(pfad.join(root, 'index.md'));
      await datei.writeAsString('hallo\n');
      final p = await laufendesPlugin();
      final vorher = PluginProzess.text(
        await p.werkzeug('context_read', {'pfad': 'index.md'}),
      );
      await datei.writeAsString('anders\n');
      final nachher = PluginProzess.text(
        await p.werkzeug('context_read', {'pfad': 'index.md'}),
      );
      expect(vorher, isNot(nachher));
    });

    test('ein Ordner ist kein Dateiinhalt', () async {
      await Directory(pfad.join(root, 'klasse')).create();
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'klasse'});
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('folder'));
    });

    test('eine Datei, die kein UTF-8-Text ist, wird abgelehnt', () async {
      await File(pfad.join(root, 'bild.bin'))
          .writeAsBytes([0xff, 0xfe, 0x00, 0xc3]);
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'bild.bin'});
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('UTF-8'));
    });

    test('eine fehlende Datei ist ein Fehler', () async {
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'fehlt.md'});
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('does not exist'));
    });
  });

  group('Grenze der Wurzel (A2)', () {
    test('ein Pfad mit .. wird abgewiesen, für Liste und Lesen', () async {
      final draussen = File(pfad.join(ordner.path, 'geheim.md'));
      await draussen.writeAsString('geheim');
      final p = await laufendesPlugin();
      for (final ergebnis in [
        await p.werkzeug('context_read', {'pfad': '../geheim.md'}),
        await p.werkzeug('context_list', {'pfad': '..'}),
        await p.werkzeug('context_read', {'pfad': 'a/../../geheim.md'}),
      ]) {
        expect(ergebnis['isError'], isTrue);
        expect(
          PluginProzess.text(ergebnis),
          contains('outside the context area'),
        );
        expect(PluginProzess.text(ergebnis), isNot(contains('geheim')));
      }
    });

    test('ein absoluter Pfad wird abgewiesen', () async {
      final draussen = File(pfad.join(ordner.path, 'geheim.md'));
      await draussen.writeAsString('geheim');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {
        'pfad': draussen.path,
      });
      expect(ergebnis['isError'], isTrue);
      expect(
        PluginProzess.text(ergebnis),
        contains('outside the context area'),
      );
    });

    test(
      'eine Verknüpfung nach draussen wird abgewiesen, für Datei und Ordner',
      () async {
        final draussen = Directory(pfad.join(ordner.path, 'draussen'));
        await draussen.create();
        await File(pfad.join(draussen.path, 'geheim.md'))
            .writeAsString('geheim');
        await Link(pfad.join(root, 'link-datei.md'))
            .create(pfad.join(draussen.path, 'geheim.md'));
        await Link(pfad.join(root, 'link-ordner')).create(draussen.path);
        final p2 = await laufendesPlugin();

        final lesen = await p2.werkzeug('context_read', {
          'pfad': 'link-datei.md',
        });
        expect(lesen['isError'], isTrue);
        expect(PluginProzess.text(lesen), contains('outside the context area'));

        final liste = await p2.werkzeug('context_list', {
          'pfad': 'link-ordner',
        });
        expect(liste['isError'], isTrue);
        expect(PluginProzess.text(liste), contains('outside the context area'));
      },
    );

    test(
      'eine Verknüpfung, die innerhalb der Wurzel bleibt, ist erlaubt',
      () async {
        await Directory(pfad.join(root, 'echt')).create();
        await File(pfad.join(root, 'echt', 'a.md')).writeAsString('hallo\n');
        await Link(pfad.join(root, 'verweis')).create(pfad.join(root, 'echt'));
        final p2 = await laufendesPlugin();
        final ergebnis = await p2.werkzeug('context_read', {
          'pfad': 'verweis/a.md',
        });
        expect(ergebnis['isError'], isNot(true));
        expect(PluginProzess.text(ergebnis), contains('hallo'));
      },
    );

    test('die App wird für Dateizugriffe nicht angefragt', () async {
      await File(pfad.join(root, 'index.md')).writeAsString('x');
      final p2 = await laufendesPlugin();
      await p2.werkzeug('context_read', {'pfad': 'index.md'});
      expect(p2.appAnfragen, isEmpty);
    });
  });

  group('Fehler nennen die Ursache (A5)', () {
    test(
      'ohne Einstellungsdatei ein klarer Fehler, kein leeres Ergebnis',
      () async {
        plugin = await PluginProzess.starten(ordner: ordner);
        await plugin!.initialisieren();
        final ergebnis = await plugin!.werkzeug('context_list', {'pfad': ''});
        expect(ergebnis['isError'], isTrue);
        expect(PluginProzess.text(ergebnis), contains('not been set up'));
      },
    );

    test('eine kaputte Einstellungsdatei nennt den Grund', () async {
      final p = await laufendesPlugin(einstellungenInhalt: '{kaputt');
      final ergebnis = await p.werkzeug('context_list', {'pfad': ''});
      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('settings file'));
    });

    test(
      'ein nicht unterstützter Ort in den Einstellungen wird genannt',
      () async {
        final p = await laufendesPlugin(
          einstellungenInhalt: jsonEncode({'art': 'webdav'}),
        );
        final ergebnis = await p.werkzeug('context_list', {'pfad': ''});
        expect(ergebnis['isError'], isTrue);
        expect(PluginProzess.text(ergebnis), contains('webdav'));
      },
    );

    test('eine nicht lesbare Einstellungsdatei hat einen eigenen Fehler, nicht den für ungültiges JSON', () async {
      final p = await laufendesPlugin();
      final datei = p.einstellungen;
      await datei.writeAsString(einstellungen(root));
      final chmod = Process.runSync('chmod', ['000', datei.path]);
      expect(chmod.exitCode, 0);
      if (datei.existsSync() && _lesbar(datei)) {
        // Läuft der Test als Root, lässt sich die Datei trotz Rechten lesen.
        markTestSkipped(
          'die Datei ist auch ohne Rechte lesbar (vermutlich Root)',
        );
        return;
      }
      final ergebnis = await p.werkzeug('context_list', {'pfad': ''});
      expect(ergebnis['isError'], isTrue);
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('settings file cannot be read'));
      expect(text, isNot(contains('JSON')));
      Process.runSync('chmod', ['600', datei.path]);
    });

    test(
      'ein relativer Pfad in den Einstellungen wird mit Grund abgewiesen',
      () async {
        final p = await laufendesPlugin(
          einstellungenInhalt: jsonEncode({'art': 'lokal', 'pfad': 'kontext'}),
        );
        final ergebnis = await p.werkzeug('context_list', {'pfad': ''});
        expect(ergebnis['isError'], isTrue);
        expect(PluginProzess.text(ergebnis), contains('absolute'));
      },
    );

    test(
      'ohne Einstellungsdatei sagt die Antwort, was die Lehrkraft tun soll',
      () async {
        plugin = await PluginProzess.starten(ordner: ordner);
        await plugin!.initialisieren();
        final ergebnis = await plugin!.werkzeug('context_list', {'pfad': ''});
        expect(PluginProzess.text(ergebnis), contains('plugin settings'));
      },
    );

    test('eine fehlende Wurzel wird als fehlender Ordner benannt', () async {
      final plug = await laufendesPlugin(
        einstellungenInhalt: einstellungen(pfad.join(ordner.path, 'weg')),
      );
      final ergebnis = await plug.werkzeug('context_list', {'pfad': ''});
      expect(ergebnis['isError'], isTrue);
      expect(
        PluginProzess.text(ergebnis),
        contains('root folder does not exist'),
      );
    });
  });
}
