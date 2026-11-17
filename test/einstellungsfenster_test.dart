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
  }) => Einstellungsfenster(
    programm: programm,
    einstellungen: einstellungen,
    starten: starten ?? wartender,
  );

  test('auf Wunsch öffnet es das Fenster mit dem Pfad der Einstellungen und sonst nichts', () async {
    final f = fenster(programm: '/fenster/kontext_einstellungen');

    final ergebnis = await f.oeffnen();

    expect(ergebnis.stand, FensterStand.geoeffnet);
    expect(gestartet, [
      ['/fenster/kontext_einstellungen', '--einstellungen', einstellungen.path],
    ]);
  });

  test('ein zweiter Aufruf, während das Fenster offen ist, startet kein zweites', () async {
    final f = fenster();
    await f.oeffnen();

    final zweiter = await f.oeffnen();

    expect(zweiter.stand, FensterStand.lauft);
    expect(gestartet, hasLength(1));
  });

  test('beim Ausfall öffnet es nur einmal, bis der Ort wieder antwortet', () async {
    final f = fenster();

    await f.beiAusfall();
    prozesse.last.kill();
    await prozesse.last.exitCode;
    await f.beiAusfall();

    expect(gestartet, hasLength(1), reason: 'derselbe Ausfall öffnet nicht erneut');

    f.ausfallVorbei();
    await f.beiAusfall();

    expect(gestartet, hasLength(2), reason: 'ein neuer Ausfall öffnet es wieder');
  });

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
    expect(ergebnis.meldung, isNot(contains(ordner.path)),
        reason: 'der Pfad des Programms steht nicht in der Meldung an die KI');
  });

  test('das Standardprogramm liegt neben dem Plugin, im Ordner einstellungsfenster', () {
    final pfad = standardFensterProgramm();

    expect(p.basename(pfad), 'kontext_einstellungen');
    expect(p.basename(p.dirname(pfad)), 'einstellungsfenster');
  }, skip: Platform.isLinux ? null : 'nur für Linux geprüft');
}
