// Vertragstests der Speicherschicht: Dieselben Fälle laufen gegen den lokalen
// Ordner und gegen einen WebDAV-Server im Test (E3). Geprüft werden Ergebnisse
// und der Inhalt auf der Platte, nie die Innenleben der Klassen.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/speicher.dart';
import 'package:contextmanager/src/webdav.dart';

import 'harness.dart';
import 'webdav_server.dart';

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

void main() {
  for (final art in Ortsart.values) {
    group('Speicher ${art.name}', () => _vertrag(art));
  }
}

void _vertrag(Ortsart art) {
  late Directory ordner;
  late String root;
  late Kontextspeicher speicher;
  WebDavTestServer? server;

  setUp(() async {
    ordner = await tempOrdner('vertrag');
    root = p.join(ordner.path, 'kontext');
    await Directory(root).create();
    if (art == Ortsart.lokal) {
      speicher = await LokalerSpeicher.oeffnen(root);
    } else {
      server = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await server!.starten();
      speicher = await WebDavSpeicher.oeffnen(
        adresse: server!.adresse,
        benutzer: testBenutzer,
        geheimnis: testPasswort,
        zeitlimit: const Duration(seconds: 10),
      );
    }
  });

  tearDown(() async {
    await server?.beenden();
    await ordner.delete(recursive: true);
  });

  String datei(String relativ) => p.join(root, relativ);

  group('verschiebeDatei: nie überschreiben, nur mit dem gelesenen Stand', () {
    test('ein vorhandenes Ziel bleibt unangetastet, die Quelle auch', () async {
      await File(datei('a.md')).writeAsString('quelle\n');
      await File(datei('b.md')).writeAsString('ziel\n');
      await expectLater(
        speicher.verschiebeDatei('a.md', 'b.md', erwartet: _sha('quelle\n')),
        throwsA(isA<KontextKonflikt>()),
      );
      expect(File(datei('a.md')).readAsStringSync(), 'quelle\n');
      expect(File(datei('b.md')).readAsStringSync(), 'ziel\n');
    });

    test('eine Quelle mit anderem Stand wird nicht verschoben', () async {
      await File(datei('a.md')).writeAsString('neu\n');
      await expectLater(
        speicher.verschiebeDatei('a.md', 'b.md', erwartet: _sha('alt\n')),
        throwsA(isA<KontextKonflikt>()),
      );
      expect(File(datei('a.md')).readAsStringSync(), 'neu\n');
      expect(File(datei('b.md')).existsSync(), isFalse);
    });

    test('mit dem gelesenen Stand wird verschoben, der Inhalt bleibt gleich', () async {
      await File(datei('a.md')).writeAsString('inhalt\n');
      await speicher.verschiebeDatei('a.md', 'archiv/b.md', erwartet: _sha('inhalt\n'));
      expect(File(datei('a.md')).existsSync(), isFalse);
      expect(File(datei('archiv/b.md')).readAsStringSync(), 'inhalt\n');
    });
  });

  test('die Liste zeigt Dateien und Ordner, sortiert nach Namen', () async {
    await File(datei('b.md')).writeAsString('b');
    await Directory(datei('a')).create();
    await File(datei('c.txt')).writeAsString('c');

    final eintraege = await speicher.liste('');

    expect(
      [for (final e in eintraege) (e.name, e.istOrdner)],
      [('a', true), ('b.md', false), ('c.txt', false)],
    );
  });

  test(
    'ein Inhalt kommt mit seiner Version: die Prüfsumme der Bytes',
    () async {
      await File(datei('plan.md')).writeAsString('hallo\n');

      final inhalt = await speicher.holeInhalt('plan.md');

      expect(inhalt, isNotNull);
      expect(inhalt!.version, _sha('hallo\n'));
      expect(utf8.decode(inhalt.bytes), 'hallo\n');
    },
  );

  test('eine fehlende Datei ist kein Inhalt, sondern null', () async {
    expect(await speicher.holeInhalt('fehlt.md'), isNull);
  });

  test('ein Ordner ist kein Inhalt und wird genannt', () async {
    await Directory(datei('ordner')).create();

    expect(
      () => speicher.holeInhalt('ordner'),
      throwsA(
        isA<KontextFehler>().having(
          (f) => f.meldung,
          'meldung',
          contains('is a folder'),
        ),
      ),
    );
  });

  test(
    'neu anlegen ohne Version, danach ersetzen nur mit der gelesenen Version',
    () async {
      final angelegt = await speicher.schreibe(
        'plan.md',
        'eins\n',
        erwartet: null,
      );
      expect(angelegt.verifiziert, isTrue);
      expect(await File(datei('plan.md')).readAsString(), 'eins\n');

      final ersetzt = await speicher.schreibe(
        'plan.md',
        'zwei\n',
        erwartet: angelegt.version,
      );

      expect(ersetzt.verifiziert, isTrue);
      expect(ersetzt.version, _sha('zwei\n'));
      expect(await File(datei('plan.md')).readAsString(), 'zwei\n');
    },
  );

  test(
    'ohne Version darf eine vorhandene Datei nicht ersetzt werden',
    () async {
      await File(datei('plan.md')).writeAsString('alt\n');

      await expectLater(
        speicher.schreibe('plan.md', 'neu\n', erwartet: null),
        throwsA(isA<KontextKonflikt>()),
      );
      expect(await File(datei('plan.md')).readAsString(), 'alt\n');
    },
  );

  test(
    'eine veraltete Version wird abgewiesen und nichts geschrieben',
    () async {
      await File(datei('plan.md')).writeAsString('alt\n');
      final gelesen = await speicher.holeInhalt('plan.md');
      await File(datei('plan.md')).writeAsString('von jemand anderem\n');

      await expectLater(
        speicher.ablegen(
          'plan.md',
          utf8.encode('mein Text\n'),
          erwartet: gelesen!.version,
        ),
        throwsA(isA<KontextKonflikt>()),
      );
      expect(
        await File(datei('plan.md')).readAsString(),
        'von jemand anderem\n',
      );
    },
  );

  test(
    'anhängen liest zurück und trennt die Einträge durch ein Zeilenende',
    () async {
      await File(datei('journal.md')).writeAsString('erster\n');
      final gelesen = await speicher.holeInhalt('journal.md');

      final ergebnis = await speicher.haengeAn(
        'journal.md',
        'zweiter',
        erwartet: gelesen!.version,
      );

      expect(ergebnis.verifiziert, isTrue);
      expect(
        await File(datei('journal.md')).readAsString(),
        'erster\nzweiter\n',
      );
    },
  );

  test('anhängen ohne Version legt die Datei an', () async {
    final ergebnis = await speicher.haengeAn(
      'neu/tag.md',
      'eins',
      erwartet: null,
    );

    expect(ergebnis.verifiziert, isTrue);
    expect(await File(datei('neu/tag.md')).readAsString(), 'eins\n');
  });

  test('ein Pfad, der aus der Wurzel führt, wird abgewiesen, bevor etwas geschieht', () async {
    for (final pfad in ['../x.md', '/etc/x.md', '~/x.md']) {
      await expectLater(
        speicher.schreibe(pfad, 'x', erwartet: null),
        throwsA(isA<KontextFehler>()),
        reason: pfad,
      );
      await expectLater(
        speicher.holeInhalt(pfad),
        throwsA(isA<KontextFehler>()),
        reason: pfad,
      );
    }
    expect(await Directory(root).list().toList(), isEmpty);
  });

  test('verschieben innerhalb der Wurzel legt den Zielordner an', () async {
    await File(datei('woche.md')).writeAsString('inhalt\n');
    final gelesen = await speicher.holeInhalt('woche.md');

    await speicher.verschiebe(
      'woche.md',
      'archiv/2026/woche.md',
      erwartet: gelesen!.version,
    );

    expect(File(datei('woche.md')).existsSync(), isFalse);
    expect(
      await File(datei('archiv/2026/woche.md')).readAsString(),
      'inhalt\n',
    );
  });

  test('verschieben auf ein vorhandenes Ziel geschieht nicht', () async {
    await File(datei('a.md')).writeAsString('a\n');
    await File(datei('b.md')).writeAsString('b\n');
    final gelesen = await speicher.holeInhalt('a.md');

    await expectLater(
      speicher.verschiebe('a.md', 'b.md', erwartet: gelesen!.version),
      throwsA(isA<KontextKonflikt>()),
    );
    expect(await File(datei('a.md')).readAsString(), 'a\n');
    expect(await File(datei('b.md')).readAsString(), 'b\n');
  });

  test('ein Journal wandert nicht, auch nicht zu einem anderen Ort', () async {
    await File(datei('journal/2026-11-17.md')).create(recursive: true);
    await File(datei('journal/2026-11-17.md')).writeAsString('tag\n');
    final gelesen = await speicher.holeInhalt('journal/2026-11-17.md');

    await expectLater(
      speicher.verschiebe(
        'journal/2026-11-17.md',
        'archiv/tag.md',
        erwartet: gelesen!.version,
      ),
      throwsA(isA<KontextFehler>()),
    );
    expect(await File(datei('journal/2026-11-17.md')).readAsString(), 'tag\n');
  });
}
