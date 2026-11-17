// Prüft ein gebautes Plugin (bauen.sh) gegen den Testserver ohne ETag: Start,
// Lesen mit Version, Schreiben mit dem Hinweis. Läuft nur mit
// KONTEXT_PROGRAMM=<Pfad zum gebauten Programm>; sonst übersprungen.
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  final programm = Platform.environment['KONTEXT_PROGRAMM'];
  test(
    'das gebaute Plugin liest und schreibt auf einem Server ohne ETag',
    () async {
      final ordner = await tempOrdner('gebaut');
      final root = pfad.join(ordner.path, 'kontext');
      await Directory(root).create();
      await File(pfad.join(root, 'index.md')).writeAsString('hallo\n');
      final p = await PluginProzess.starten(
        ordner: ordner,
        ort: Ortsart.webdav,
        webdavSendetEtag: false,
      );
      addTearDown(() async {
        await p.beenden();
        await ordner.delete(recursive: true);
      });
      await p.initialisieren();
      p.app.stufe = 'alle';
      final start = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(start, contains('location: answers'));
      expect(start, contains('hallo'));
      final lesen = PluginProzess.text(
        await p.werkzeug('context_read', {'pfad': 'index.md'}),
      );
      expect(lesen, contains('version: sha256:'));
      final version = RegExp(r'version: (sha256:\w+)').firstMatch(lesen)!.group(1)!;
      final schreiben = PluginProzess.text(
        await p.werkzeug('context_write', {
          'pfad': 'index.md',
          'inhalt': 'neu\n',
          'art': 'plan_change',
          'zusammenfassung': 'Prüfung des Builds.',
          'version': version,
        }),
      );
      expect(schreiben, startsWith('verified'));
      expect(schreiben, contains('not enforced by the server'));
    },
    skip: programm == null ? 'KONTEXT_PROGRAMM ist nicht gesetzt' : null,
  );
}
