// Tests des Fensterarchivs auf dem Mac (E11): Das Einstellungsfenster liegt als
// Archiv im Plugin-Ordner, und das Plugin packt es vor jedem Öffnen frisch in
// seinen Datenordner aus. Nur macOS: Das Auspacken benutzt `ditto`.
@TestOn('mac-os')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/fensterarchiv.dart';

import 'harness.dart';

void main() {
  late Directory ordner;
  late File archiv;
  late Directory ziel;

  /// Ein Archiv wie aus bauen.sh: ein Bündel mit Programm und einer Verknüpfung
  /// darin (wie `Versions/Current` in einem Framework).
  Future<void> baueArchiv(String inhalt) async {
    final quelle = Directory(
      p.join(ordner.path, 'quelle', 'kontext_einstellungen.app'),
    );
    final macos = Directory(p.join(quelle.path, 'Contents', 'MacOS'));
    await macos.create(recursive: true);
    await File(p.join(macos.path, 'kontext_einstellungen'))
        .writeAsString(inhalt);
    await Link(p.join(quelle.path, 'Contents', 'Aktuell')).create('MacOS');
    if (archiv.existsSync()) await archiv.delete();
    final r = await Process.run('ditto', [
      '-c',
      '-k',
      '--keepParent',
      quelle.path,
      archiv.path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    await Directory(p.join(ordner.path, 'quelle')).delete(recursive: true);
  }

  File programm() => File(fensterProgrammIn(ziel));

  setUp(() async {
    ordner = await tempOrdner('fensterarchiv');
    archiv = File(p.join(ordner.path, 'plugin', 'einstellungsfenster.zip'));
    await archiv.parent.create();
    ziel = Directory(p.join(ordner.path, 'daten', 'einstellungsfenster'));
  });

  tearDown(() async {
    await ordner.delete(recursive: true);
  });

  test(
    'packt das Fenster in den Datenordner aus, samt Verknüpfungen im Bündel',
    () async {
      await baueArchiv('fenster 1');

      await packeFensterAus(archiv: archiv, ziel: ziel);

      expect(programm().readAsStringSync(), 'fenster 1');
      expect(
        FileSystemEntity.isLinkSync(
          p.join(ziel.path, 'kontext_einstellungen.app', 'Contents', 'Aktuell'),
        ),
        isTrue,
      );
    },
  );

  test('ersetzt einen früheren Stand ganz, auch Dateien, die das neue Archiv nicht hat', () async {
    await baueArchiv('fenster 1');
    await packeFensterAus(archiv: archiv, ziel: ziel);
    final fremd = File(
      p.join(ziel.path, 'kontext_einstellungen.app', 'untergeschoben'),
    );
    await fremd.writeAsString('x');
    await programm().writeAsString('verändert');
    await baueArchiv('fenster 2');

    await packeFensterAus(archiv: archiv, ziel: ziel);

    expect(programm().readAsStringSync(), 'fenster 2');
    expect(fremd.existsSync(), isFalse);
  });

  test(
    'eine Verknüpfung an der Stelle des Zielordners wird ersetzt, nie gefolgt',
    () async {
      await baueArchiv('fenster 1');
      final woanders = Directory(p.join(ordner.path, 'woanders'));
      await woanders.create();
      final bleibt = File(p.join(woanders.path, 'bleibt.txt'));
      await bleibt.writeAsString('unberührt');
      await ziel.parent.create(recursive: true);
      await Link(ziel.path).create(woanders.path);

      await packeFensterAus(archiv: archiv, ziel: ziel);

      expect(FileSystemEntity.isLinkSync(ziel.path), isFalse);
      expect(bleibt.readAsStringSync(), 'unberührt');
      expect(woanders.listSync(), hasLength(1));
      expect(programm().readAsStringSync(), 'fenster 1');
    },
  );

  test('fehlt das Archiv, scheitert es mit dem Grund und lässt keinen alten Stand stehen', () async {
    await baueArchiv('fenster 1');
    await packeFensterAus(archiv: archiv, ziel: ziel);
    await archiv.delete();

    await expectLater(
      packeFensterAus(archiv: archiv, ziel: ziel),
      throwsA(isA<FensterarchivFehler>()),
    );
    expect(
      programm().existsSync(),
      isFalse,
      reason: 'ein Fenster, das nicht aus dem zugestimmten Archiv stammt, startet nie',
    );
  });

  test(
    'ein Archiv ohne das Programm des Fensters scheitert mit dem Grund',
    () async {
      final leer = Directory(p.join(ordner.path, 'leer', 'anderes.app'));
      await leer.create(recursive: true);
      await File(p.join(leer.path, 'x')).writeAsString('x');
      final r = await Process.run('ditto', [
        '-c',
        '-k',
        '--keepParent',
        leer.path,
        archiv.path,
      ]);
      expect(r.exitCode, 0);

      await expectLater(
        packeFensterAus(archiv: archiv, ziel: ziel),
        throwsA(isA<FensterarchivFehler>()),
      );
    },
  );
}
