// Tests zu Antworten des WebDAV-Servers (401 und 403 getrennt, Namen und Größe
// einer Antwort), zum Wiederholen des Ausstands bei einem Fehler am Ort und zum
// Ausfall zwischen Öffnen und Stand-Prüfung (am MCP-Seam, nur am WebDAV-Ort
// herstellbar).
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/app.dart';
import 'package:contextmanager/src/art.dart';
import 'package:contextmanager/src/ausstand.dart';
import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/ort.dart';
import 'package:contextmanager/src/schluesselbund.dart';
import 'package:contextmanager/src/schreibauftrag.dart';
import 'package:contextmanager/src/webdav.dart';

import 'harness.dart';
import 'webdav_server.dart';

/// Ein Fehler des Kontextbereichs mit dem Teil seiner Meldung, und ohne dass er
/// ein Ausfall ist (der würde in den Ausstand führen).
Matcher kontextFehler(String teil) => isA<KontextFehler>()
    .having((f) => f is KontextNichtErreichbar, 'ist Ausfall', isFalse)
    .having((f) => f.meldung, 'meldung', contains(teil));

/// Ein Schlüsselbund, der nie etwas herausgibt (wie ein gesperrter).
class _GesperrterSchluesselbund implements Schluesselbund {
  @override
  Future<String> geheimnis(String konto) async =>
      throw const KontextFehler('The keyring is locked.');

  @override
  Future<void> speichere(String konto, String geheimnis) async =>
      throw const KontextFehler('The keyring is locked.');
}

void main() {
  _webdavTests();
  _ausstandTests();
  fuerJedenOrt(_mcpTests);
}

void _webdavTests() {
  late Directory ordner;
  late String root;
  WebDavTestServer? server;

  setUp(() async {
    ordner = await tempOrdner('pruefung7');
    root = p.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await server?.beenden();
    server = null;
    await ordner.delete(recursive: true);
  });

  Future<WebDavSpeicher> oeffnen() => WebDavSpeicher.oeffnen(
    adresse: server!.adresse,
    benutzer: testBenutzer,
    geheimnis: testPasswort,
    zeitlimit: const Duration(seconds: 10),
  );

  group('Antworten des WebDAV-Servers (Review #7)', () {
    test('401 heißt: Benutzer oder Passwort abgelehnt', () async {
      server = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await server!.starten();
      server!.erzwungenerStatus = HttpStatus.unauthorized;
      await expectLater(
        oeffnen(),
        throwsA(kontextFehler('user or the password (HTTP 401)')),
      );
    });

    test('403 heißt: keine Berechtigung, nicht Passwort', () async {
      server = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await server!.starten();
      server!.erzwungenerStatus = HttpStatus.forbidden;
      final f = await oeffnen().then<Object?>((_) => null, onError: (e) => e);
      expect(f, kontextFehler('no permission'));
      expect(f.toString(), isNot(contains('password')));
    });

    test('ein Name mit / in der Auflistung wird abgewiesen, die Auflistung nicht übergangen', () async {
      server = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await server!.starten();
      server!.zusaetzlicheNamen.add('a/b');
      final speicher = await oeffnen();
      await expectLater(
        speicher.liste(''),
        throwsA(kontextFehler('not allowed')),
      );
    });

    test(
      'ein Name mit Steuerzeichen in der Auflistung wird abgewiesen',
      () async {
        server = WebDavTestServer(
          ordner: Directory(root),
          benutzer: testBenutzer,
          passwort: testPasswort,
        );
        await server!.starten();
        server!.zusaetzlicheNamen.add('x\ny');
        final speicher = await oeffnen();
        await expectLater(
          speicher.liste(''),
          throwsA(kontextFehler('not allowed')),
        );
      },
    );

    test(
      'ein Name mit : im ersten Abschnitt wird kodiert und wieder gefunden',
      () async {
        server = WebDavTestServer(
          ordner: Directory(root),
          benutzer: testBenutzer,
          passwort: testPasswort,
        );
        await server!.starten();
        final speicher = await oeffnen();
        // Ein Doppelpunkt vor dem ersten `/` würde als Schema gelesen, wenn er nicht kodiert wird.
        await speicher.ablegen('a:b.md', utf8.encode('x\n'), erwartet: null);
        await speicher.ablegen('a:b/c.md', utf8.encode('y\n'), erwartet: null);

        expect(File(p.join(root, 'a:b.md')).readAsStringSync(), 'x\n');
        expect(File(p.join(root, 'a:b', 'c.md')).readAsStringSync(), 'y\n');
        final gelesen = await speicher.holeInhalt('a:b.md');
        expect(utf8.decode(gelesen!.bytes), 'x\n');
        final eintraege = await speicher.liste('');
        expect(eintraege.map((e) => e.name), containsAll(['a:b.md', 'a:b']));
      },
    );

    test(
      'eine Antwort über der Grenze wird nicht vollständig gelesen',
      () async {
        server = WebDavTestServer(
          ordner: Directory(root),
          benutzer: testBenutzer,
          passwort: testPasswort,
        );
        await server!.starten();
        await File(p.join(root, 'gross.md'))
            .writeAsBytes(List.filled(hoechstgroesseAntwort + 1, 0x61));
        final speicher = await oeffnen();
        await expectLater(
          speicher.holeInhalt('gross.md'),
          throwsA(kontextFehler('more data')),
        );
      },
    );
  });
}

void _ausstandTests() {
  late Directory ordner;

  setUp(() async {
    ordner = await tempOrdner('ausstand7');
  });

  tearDown(() async {
    await ordner.delete(recursive: true);
  });

  test('Wiederholen: schlägt das Öffnen des Ortes mit einem Fehler fehl, hält es an und wirft nicht (Review #7)', () async {
    final einstellungen = File(p.join(ordner.path, 'einstellungen.json'));
    await einstellungen.writeAsString(
      jsonEncode({
        'art': 'webdav',
        'adresse': 'http://127.0.0.1:9/kontext/',
        'benutzer': testBenutzer,
      }),
    );
    // Die Kennung liest nur die Einstellungen; geöffnet wird erst mit dem Passwort.
    final zugang = Ortszugang(
      einstellungen: einstellungen,
      schluesselbund: _GesperrterSchluesselbund(),
    );
    final ausstand = Ausstand(Directory(p.join(ordner.path, 'ausstand')));
    await ausstand.merke(
      Schreibauftrag(
        pfad: 'plan.md',
        inhalt: 'hallo\n',
        art: Art.planChange,
        zusammenfassung: 'Kurze Zusammenfassung.',
        version: null,
        anhaengen: false,
      ),
      ort: await zugang.kennung(),
    );

    final ergebnisse = await wiederholeAusstand(
      ausstand: ausstand,
      zugang: zugang,
      app: AppAnschluss(adresse: () => null, schluessel: 'testschluessel'),
      aufruf: testAufruf,
      vorgaenge: await ausstand.liste(),
    );

    expect(ergebnisse, hasLength(1));
    expect(ergebnisse.single.ausgang, WiederholungAusgang.fehler);
    expect(ergebnisse.single.meldung, contains('keyring is locked'));
    expect(await ausstand.liste(), hasLength(1), reason: 'der Vorgang bleibt');
  });
}

void _mcpTests(Ortsart art) {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('pruefung7mcp');
    root = p.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  test(
    'antwortet der Ort schon bei der Stand-Prüfung nicht, kommt der Vorgang in den Ausstand und fragt nicht (Review #7)',
    () async {
      plugin = await PluginProzess.starten(ordner: ordner, ort: art);
      await plugin!.initialisieren();
      plugin!.app.stufe = 'mittel';
      // Die Wurzel antwortet beim Öffnen; das Lesen der Datei für die Stand-Prüfung schlägt fehl.
      plugin!.webdav!.statusFuerLesen = HttpStatus.serviceUnavailable;

      final ergebnis = await plugin!.werkzeug('context_write', {
        'pfad': 'plan.md',
        'inhalt': 'hallo\n',
        'art': 'plan_change',
        'zusammenfassung': 'Kurze Zusammenfassung.',
      });

      expect(ergebnis['isError'], isNot(true));
      expect(PluginProzess.text(ergebnis), startsWith('not saved yet'));
      expect(
        plugin!.app.freigaben,
        isEmpty,
        reason: 'vor dem Ausfall wird nicht gefragt',
      );
      final ausstandDatei = Directory(p.join(ordner.path, 'ausstand'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'));
      expect(ausstandDatei, hasLength(1));
      expect(File(p.join(root, 'plan.md')).existsSync(), isFalse);
    },
    skip: art == Ortsart.lokal
        ? 'nur am WebDAV-Ort: ein Ausfall zwischen Öffnen und Stand-Prüfung ist lokal nicht herstellbar'
        : null,
  );
}
