// Tests am MCP-Seam: wann das Plugin das Einstellungsfenster öffnet (E8) und
// dass `context_settings` der KI nie einen Wert der Einstellungen zeigt (A6).
// Jeder Ort läuft zweimal (fuerJedenOrt); das Fenster ist ein Skript, das die
// Aufrufe aufzeichnet (siehe harness.dart).
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
    ordner = await tempOrdner('fenstermcp');
    root = pfad.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufend({String? fenster, bool mitEinstellungen = true}) async {
    plugin = await PluginProzess.starten(
      ordner: ordner,
      ort: mitEinstellungen ? art : null,
      fenster: fenster,
    );
    await plugin!.initialisieren();
    return plugin!;
  }

  test('ohne Einstellungen öffnet das Plugin das Fenster beim Start, mit dem Pfad der Datei', () async {
    final p = await laufend(mitEinstellungen: false);

    // Der Start ist abgeschlossen, wenn das Plugin antwortet; das Öffnen läuft
    // unmittelbar danach, deshalb wird kurz auf den Aufruf gewartet.
    await _warteAuf(() => p.fensterAufrufe.isNotEmpty);

    expect(p.fensterAufrufe, ['--einstellungen ${p.einstellungen.path}']);
  });

  test('mit Einstellungen öffnet der Start kein Fenster', () async {
    final p = await laufend();

    await p.werkzeug('context_list', {'pfad': ''});

    expect(p.fensterAufrufe, isEmpty);
  });

  test('antwortet der Ort nicht, öffnet das Plugin das Fenster einmal, nicht bei jedem Aufruf', () async {
    final p = await laufend();
    await p.werkzeug('context_list', {'pfad': ''});
    await p.ausfallen();

    final erster = await p.werkzeug('context_list', {'pfad': ''});
    final zweiter = await p.werkzeug('context_list', {'pfad': ''});

    expect(erster['isError'], isTrue);
    expect(zweiter['isError'], isTrue);
    expect(p.fensterAufrufe, hasLength(1));
  });

  test('nach Wiederherstellung und einem neuen Ausfall öffnet es wieder', () async {
    final p = await laufend();
    await p.ausfallen();
    await p.werkzeug('context_list', {'pfad': ''});
    await p.wiederherstellen();
    final ok = await p.werkzeug('context_list', {'pfad': ''});
    expect(ok['isError'], isNot(isTrue));

    await p.ausfallen();
    await p.werkzeug('context_list', {'pfad': ''});

    expect(p.fensterAufrufe, hasLength(2));
  });

  group('context_settings', () {
    test('öffnet das Fenster, und die Antwort enthält keinen Wert der Einstellungen', () async {
      final p = await laufend();

      final ergebnis = await p.werkzeug('context_settings', {});

      expect(ergebnis['isError'], isNot(isTrue));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('settings window'));
      expect(text, isNot(contains(testPasswort)));
      expect(text, isNot(contains(testBenutzer)));
      expect(text, isNot(contains(root)));
      expect(text, isNot(contains(p.einstellungen.path)));
      if (art == Ortsart.webdav) {
        expect(text, isNot(contains(p.webdav!.adresse.toString())));
      }
      expect(p.fensterAufrufe, hasLength(1));
    });

    test('fehlt das Programm des Fensters, meldet die Antwort das als Fehler, ohne Pfad', () async {
      final p = await laufend(fenster: '/gibt/es/nicht/kontext_einstellungen');

      final ergebnis = await p.werkzeug('context_settings', {});

      expect(ergebnis['isError'], isTrue);
      expect(PluginProzess.text(ergebnis), contains('could not be started'));
      expect(PluginProzess.text(ergebnis), isNot(contains('/gibt/es/nicht')));
    });
  });
}

/// Wartet kurz, bis [bedingung] wahr ist, und scheitert nach zwei Sekunden.
Future<void> _warteAuf(bool Function() bedingung) async {
  final ende = DateTime.now().add(const Duration(seconds: 2));
  while (!bedingung()) {
    if (DateTime.now().isAfter(ende)) fail('Bedingung nicht erreicht');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
