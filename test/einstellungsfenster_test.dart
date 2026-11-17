// Tests des Startens des Einstellungsfensters (E8): wann das Plugin es öffnet
// (beim ersten Start ohne Einstellungen, einmal je Ausfall, auf Wunsch), dass es
// nie zwei Fenster gleichzeitig startet und dass es nur den Pfad der
// Einstellungen übergibt. Das Fenster selbst ist im Test ein Skript, das sofort
// endet oder wartet.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/einstellungsfenster.dart';

import 'harness.dart';

void main() {
  late Directory ordner;
  late File einstellungen;
  final gestartet = <List<String>>[];
  final prozesse = <Process>[];

  setUp(() async {
    ordner = await tempOrdner('fenster');
    einstellungen = File(p.join(ordner.path, 'einstellungen.json'));
    gestartet.clear();
    prozesse.clear();
  });

  tearDown(() async {
    for (final prozess in prozesse) {
      prozess.kill();
    }
    await ordner.delete(recursive: true);
  });

  /// Ein Fensterstarter, der aufzeichnet und einen Prozess liefert, der wartet,
  /// bis der Test ihn beendet (wie ein offenes Fenster).
  Future<Process> wartender(String programm, List<String> argumente) async {
    gestartet.add([programm, ...argumente]);
    final prozess = await Process.start('/bin/sh', ['-c', 'sleep 30']);
    prozesse.add(prozess);
    return prozess;
  }

  Einstellungsfenster fenster({
    Future<Process> Function(String, List<String>)? starten,
    String programm = '/gibt/es/nicht/fenster',
    Future<String?> Function(int pid)? befehlszeile,
  }) => Einstellungsfenster(
    programm: programm,
    einstellungen: einstellungen,
    starten: starten ?? wartender,
    befehlszeile: befehlszeile,
  );

  File pidDatei() => File(p.join(ordner.path, 'fenster.pid'));

  test('auf Wunsch öffnet es das Fenster mit dem Pfad der Einstellungen und sonst nichts', () async {
    final f = fenster(programm: '/fenster/kontext_einstellungen');

    final ergebnis = await f.oeffnen();

    expect(ergebnis.stand, FensterStand.geoeffnet);
    expect(gestartet, [
      ['/fenster/kontext_einstellungen', '--einstellungen', einstellungen.path],
    ]);
  });

  test(
    'ein zweiter Aufruf, während das Fenster offen ist, startet kein zweites',
    () async {
      final f = fenster();
      await f.oeffnen();

      final zweiter = await f.oeffnen();

      expect(zweiter.stand, FensterStand.lauft);
      expect(gestartet, hasLength(1));
    },
  );

  test('zwei gleichzeitige Aufrufe öffnen nur ein Fenster', () async {
    final f = fenster();

    final ergebnisse = await Future.wait([f.oeffnen(), f.oeffnen()]);

    expect(gestartet, hasLength(1));
    expect(
      ergebnisse.map((e) => e.stand),
      unorderedEquals([FensterStand.geoeffnet, FensterStand.lauft]),
    );
  });

  test(
    'beim Ausfall öffnet es nur einmal, bis der Ort wieder antwortet',
    () async {
      final f = fenster();

      await f.beiAusfall();
      prozesse.last.kill();
      await prozesse.last.exitCode;
      await f.beiAusfall();

      expect(
        gestartet,
        hasLength(1),
        reason: 'derselbe Ausfall öffnet nicht erneut',
      );

      f.ausfallVorbei();
      await f.beiAusfall();

      expect(
        gestartet,
        hasLength(2),
        reason: 'ein neuer Ausfall öffnet es wieder',
      );
    },
  );

  test('fehlt das Programm des Fensters, scheitert das mit dem Grund und nie mit einer Ausnahme', () async {
    // Ohne Ersatz-Starter: der echte Start scheitert am fehlenden Programm.
    final f = Einstellungsfenster(
      programm: p.join(ordner.path, 'es-gibt-kein-fenster'),
      einstellungen: einstellungen,
    );

    final ergebnis = await f.oeffnen();
    await f.beiAusfall();

    expect(ergebnis.stand, FensterStand.nichtGestartet);
    expect(ergebnis.meldung, contains('could not be started'));
    expect(
      ergebnis.meldung,
      isNot(contains(ordner.path)),
      reason: 'der Pfad des Programms steht nicht in der Meldung an die KI',
    );
  });

  test(
    'beenden schließt das offene Fenster und räumt die Pid-Datei auf',
    () async {
      final f = fenster();
      await f.oeffnen();
      final prozess = prozesse.single;
      expect(pidDatei().readAsStringSync().trim(), '${prozess.pid}');

      await f.beenden();

      await prozess.exitCode.timeout(const Duration(seconds: 5));
      expect(pidDatei().existsSync(), isFalse);
    },
  );

  test('beenden ohne offenes Fenster ist harmlos', () async {
    await fenster().beenden();
  });

  test(
    'ein Rest eines früheren Laufs wird beendet, bevor das neue Fenster öffnet',
    () async {
      final rest = await Process.start('/bin/sh', ['-c', 'sleep 30']);
      prozesse.add(rest);
      pidDatei().writeAsStringSync('${rest.pid}');
      final f = fenster(
        programm: '/fenster/kontext_einstellungen',
        befehlszeile: (pid) async =>
            '/fenster/kontext_einstellungen --einstellungen x',
      );

      await f.oeffnen();

      await rest.exitCode.timeout(const Duration(seconds: 5));
      expect(gestartet, hasLength(1));
      expect(pidDatei().readAsStringSync().trim(), '${prozesse.last.pid}');
    },
  );

  test('ein fremder Prozess unter der alten Pid wird nie beendet', () async {
    final fremd = await Process.start('/bin/sh', ['-c', 'sleep 30']);
    prozesse.add(fremd);
    pidDatei().writeAsStringSync('${fremd.pid}');
    final f = fenster(
      programm: '/fenster/kontext_einstellungen',
      befehlszeile: (pid) async => '/usr/bin/etwas-anderes',
    );

    await f.oeffnen();

    var beendet = false;
    unawaited(fremd.exitCode.then((_) => beendet = true));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(beendet, isFalse);
    expect(gestartet, hasLength(1));
  });

  test('eine kaputte Pid-Datei stört das Öffnen nicht', () async {
    pidDatei().writeAsStringSync('kein-pid');

    final ergebnis = await fenster().oeffnen();

    expect(ergebnis.stand, FensterStand.geoeffnet);
  });

  test('das Standardprogramm liegt neben dem Plugin, im Ordner einstellungsfenster', () {
    final pfad = standardFensterProgramm();

    expect(p.basename(pfad), 'kontext_einstellungen');
    expect(p.basename(p.dirname(pfad)), 'einstellungsfenster');
  }, skip: Platform.isLinux ? null : 'nur für Linux geprüft');
}
