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
    wartezeit: const Duration(milliseconds: 300),
  );

  File pidDatei() => File(p.join(ordner.path, 'fenster.pid'));

  /// Ein Rest eines früheren Laufs: ein Prozess, den [alsFenster] zeigt, solange
  /// er läuft (wie `ps`), mit seiner Pid in der Pid-Datei.
  Future<Process> rest(String alsFenster, {String skript = 'sleep 30'}) async {
    final prozess = await Process.start('/bin/sh', ['-c', skript]);
    prozesse.add(prozess);
    pidDatei().writeAsStringSync('${prozess.pid}');
    return prozess;
  }

  Future<String?> Function(int) zeigt(Process prozess, String zeile) {
    var beendet = false;
    unawaited(prozess.exitCode.then((_) => beendet = true));
    return (pid) async => beendet ? null : zeile;
  }

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

  test('zwei gleichzeitige Aufrufe öffnen nur ein Fenster', () async {
    final f = fenster();

    final ergebnisse = await Future.wait([f.oeffnen(), f.oeffnen()]);

    expect(gestartet, hasLength(1));
    expect(
      ergebnisse.map((e) => e.stand),
      unorderedEquals([FensterStand.geoeffnet, FensterStand.lauft]),
    );
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

  test('beenden schließt das offene Fenster und räumt die Pid-Datei auf', () async {
    final f = fenster();
    await f.oeffnen();
    final prozess = prozesse.single;
    expect(pidDatei().readAsStringSync().trim(), '${prozess.pid}');

    await f.beenden();

    await prozess.exitCode.timeout(const Duration(seconds: 5));
    expect(pidDatei().existsSync(), isFalse);
  });

  test('beenden ohne offenes Fenster ist harmlos', () async {
    await fenster().beenden();
  });

  test('ein Rest eines früheren Laufs wird beendet, bevor das neue Fenster öffnet', () async {
    const zeile = '/fenster/kontext_einstellungen --einstellungen x';
    final alt = await rest(zeile);
    final f = fenster(
      programm: '/fenster/kontext_einstellungen',
      befehlszeile: zeigt(alt, zeile),
    );

    await f.oeffnen();

    await alt.exitCode.timeout(const Duration(seconds: 5));
    expect(gestartet, hasLength(1));
    expect(pidDatei().readAsStringSync().trim(), '${prozesse.last.pid}');
  });

  test('ein fremder Prozess, dessen Kommandozeile nur den Pfad enthält, wird nie beendet', () async {
    const zeile = 'tail -f /fenster/kontext_einstellungen --einstellungen x';
    final fremd = await rest(zeile);
    final f = fenster(
      programm: '/fenster/kontext_einstellungen',
      befehlszeile: zeigt(fremd, zeile),
    );

    await f.oeffnen();

    var beendet = false;
    unawaited(fremd.exitCode.then((_) => beendet = true));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(beendet, isFalse);
    expect(gestartet, hasLength(1));
  });

  test('ein Prozess mit dem Pfad als Anfang, aber anderem Programmnamen, wird nie beendet', () async {
    const zeile = '/fenster/kontext_einstellungen2 --einstellungen x';
    final fremd = await rest(zeile);
    final f = fenster(
      programm: '/fenster/kontext_einstellungen',
      befehlszeile: zeigt(fremd, zeile),
    );

    await f.oeffnen();

    var beendet = false;
    unawaited(fremd.exitCode.then((_) => beendet = true));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(beendet, isFalse);
  });

  test('ein Rest, der SIGTERM überhört, wird mit SIGKILL beendet', () async {
    const zeile = '/fenster/kontext_einstellungen --einstellungen x';
    final alt = await rest(zeile, skript: 'trap "" TERM; sleep 30; sleep 30');
    // Die Shell braucht einen Moment, bis die Falle gesetzt ist.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final f = fenster(
      programm: '/fenster/kontext_einstellungen',
      befehlszeile: zeigt(alt, zeile),
    );

    await f.oeffnen();

    await alt.exitCode.timeout(const Duration(seconds: 5));
    expect(gestartet, hasLength(1));
  });

  test('lebt der Rest trotz SIGKILL, öffnet kein zweites Fenster und die Antwort nennt den Grund', () async {
    const zeile = '/fenster/kontext_einstellungen --einstellungen x';
    await rest(zeile);
    final f = fenster(
      programm: '/fenster/kontext_einstellungen',
      befehlszeile: (pid) async => zeile,
    );

    final ergebnis = await f.oeffnen();

    expect(ergebnis.stand, FensterStand.nichtGestartet);
    expect(ergebnis.meldung, contains('earlier settings window'));
    expect(gestartet, isEmpty);
  });

  test('fällt ps aus, öffnet kein zweites Fenster und die Antwort nennt den Grund', () async {
    pidDatei().writeAsStringSync('4242');
    final f = fenster(
      befehlszeile: (pid) async => throw const BefehlszeilenFehler(),
    );

    final ergebnis = await f.oeffnen();

    expect(ergebnis.stand, FensterStand.nichtGestartet);
    expect(ergebnis.meldung, contains('could not be checked'));
    expect(gestartet, isEmpty);
  });

  test('eine kaputte Pid-Datei stört das Öffnen nicht', () async {
    pidDatei().writeAsStringSync('kein-pid');

    final ergebnis = await fenster().oeffnen();

    expect(ergebnis.stand, FensterStand.geoeffnet);
  });

  test('endet das Plugin, während das Fenster startet, wird das Fenster beendet', () async {
    final freigabe = Completer<void>();
    final f = fenster(
      starten: (programm, argumente) async {
        await freigabe.future;
        return wartender(programm, argumente);
      },
    );

    final oeffnen = f.oeffnen();
    final ende = f.beenden();
    freigabe.complete();
    await ende;
    await oeffnen;

    await prozesse.single.exitCode.timeout(const Duration(seconds: 5));
    expect((await f.oeffnen()).stand, FensterStand.nichtGestartet,
        reason: 'nach dem Ende öffnet es kein Fenster mehr');
    expect(gestartet, hasLength(1));
  });

  test('die Pid-Datei folgt keiner Verknüpfung nach außen', () async {
    final ziel = File(p.join(ordner.path, 'ziel.txt'))..writeAsStringSync('unberührt');
    Link('${pidDatei().path}.tmp').createSync(ziel.path);

    await fenster().oeffnen();

    expect(ziel.readAsStringSync(), 'unberührt');
    expect(pidDatei().readAsStringSync().trim(), '${prozesse.single.pid}');
  });

  test('das Standardprogramm liegt neben dem Plugin, im Ordner einstellungsfenster', () {
    final pfad = Einstellungsfenster.standard(einstellungen: einstellungen).programm;

    expect(p.basename(pfad), 'kontext_einstellungen');
    expect(p.basename(p.dirname(pfad)), 'einstellungsfenster');
  }, skip: Platform.isLinux ? null : 'nur für Linux geprüft');

  test('auf dem Mac liegt das Standardprogramm ausgepackt im Datenordner, nicht im Plugin-Ordner', () {
    final f = Einstellungsfenster.standard(einstellungen: einstellungen);

    expect(
      f.programm,
      p.join(ordner.path, 'einstellungsfenster', 'kontext_einstellungen.app', 'Contents',
          'MacOS', 'kontext_einstellungen'),
    );
  }, skip: Platform.isMacOS ? null : 'nur für macOS geprüft');

  group('Vorbereiten (Fensterarchiv auf dem Mac, E11)', () {
    Einstellungsfenster mitVorbereiten(
      Future<void> Function() vorbereiten, {
      Future<String?> Function(int pid)? befehlszeile,
    }) => Einstellungsfenster(
      programm: '/fenster/kontext_einstellungen',
      einstellungen: einstellungen,
      starten: wartender,
      befehlszeile: befehlszeile,
      vorbereiten: vorbereiten,
      wartezeit: const Duration(milliseconds: 300),
    );

    test('vor jedem Start wird vorbereitet, auch beim zweiten Öffnen', () async {
      var vorbereitet = 0;
      final f = mitVorbereiten(() async => vorbereitet++);

      await f.oeffnen();
      expect(vorbereitet, 1);
      expect(gestartet, hasLength(1));
      prozesse.last.kill();
      await prozesse.last.exitCode;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await f.oeffnen();

      expect(vorbereitet, 2);
      expect(gestartet, hasLength(2));
    });

    test('scheitert das Vorbereiten, startet kein Fenster und die Antwort nennt den Grund ohne Pfad', () async {
      final f = mitVorbereiten(
        () async => throw const FensterVorbereitungsFehler('/geheim/pfad fehlt'),
      );

      final ergebnis = await f.oeffnen();

      expect(ergebnis.stand, FensterStand.nichtGestartet);
      expect(ergebnis.meldung, contains('could not be unpacked'));
      expect(ergebnis.meldung, isNot(contains('/geheim')));
      expect(gestartet, isEmpty);
    });

    test('ein Rest eines früheren Laufs endet, bevor vorbereitet wird', () async {
      const zeile = '/fenster/kontext_einstellungen --einstellungen x';
      final alt = await rest(zeile);
      var restLebteBeimVorbereiten = true;
      var beendet = false;
      unawaited(alt.exitCode.then((_) => beendet = true));
      final f = mitVorbereiten(
        () async => restLebteBeimVorbereiten = !beendet,
        befehlszeile: zeigt(alt, zeile),
      );

      await f.oeffnen();

      expect(restLebteBeimVorbereiten, isFalse,
          reason: 'das Auspacken ersetzt die Dateien, aus denen der Rest läuft');
    });
  });
}
