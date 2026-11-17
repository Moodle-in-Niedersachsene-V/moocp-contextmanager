// Tests des WebDAV-Ortes: Ausfall, Zeitlimit, Anmeldung, Adressregeln und die
// Zusicherung, dass das Passwort in keiner Antwort und keinem Ordner steht (A6).
// Die Ausfälle werden am echten HTTP-Pfad erzeugt: ein gestoppter Server und
// ein Server, der nie antwortet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/einstellungen.dart';
import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/webdav.dart';

import 'harness.dart';
import 'webdav_server.dart';

void main() {
  late Directory ordner;
  late String root;
  WebDavTestServer? server;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('webdav');
    root = p.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await server?.beenden();
    server = null;
    await ordner.delete(recursive: true);
  });

  Future<WebDavSpeicher> oeffnen({
    String? passwort = testPasswort,
    Duration zeitlimit = const Duration(seconds: 10),
    Uri? adresse,
  }) async {
    return WebDavSpeicher.oeffnen(
      adresse: adresse ?? server!.adresse,
      benutzer: testBenutzer,
      geheimnis: passwort!,
      zeitlimit: zeitlimit,
    );
  }

  group('Ausfall und Zeitlimit: der Ort antwortet nicht', () {
    test(
      'ein gestoppter Server ist nicht erreichbar, und das ist ein Ausfall',
      () async {
        server = WebDavTestServer(
          ordner: Directory(root),
          benutzer: testBenutzer,
          passwort: testPasswort,
        );
        await server!.starten();
        final adresse = server!.adresse;
        await server!.anhalten();

        await expectLater(
          WebDavSpeicher.oeffnen(
            adresse: adresse,
            benutzer: testBenutzer,
            geheimnis: testPasswort,
            zeitlimit: const Duration(seconds: 10),
          ),
          throwsA(
            isA<KontextNichtErreichbar>().having(
              (f) => f.meldung,
              'meldung',
              contains('cannot be reached'),
            ),
          ),
        );
      },
    );

    test(
      'ein Server, der nicht antwortet, läuft in die Zeit und gilt als Ausfall',
      () async {
        final stumm = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => stumm.close());
        final adresse = Uri.parse('http://127.0.0.1:${stumm.port}/kontext/');

        await expectLater(
          WebDavSpeicher.oeffnen(
            adresse: adresse,
            benutzer: testBenutzer,
            geheimnis: testPasswort,
            zeitlimit: const Duration(milliseconds: 300),
          ),
          throwsA(
            isA<KontextNichtErreichbar>().having(
              (f) => f.meldung,
              'meldung',
              contains('in time'),
            ),
          ),
        );
      },
    );
  });

  group('Anmeldung und Ursachen, die sichtbar bleiben', () {
    test('ein falsches Passwort wird abgewiesen, ist kein Ausfall und nennt das Passwort nicht', () async {
      server = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await server!.starten();

      final fehler = await oeffnen(passwort: 'falsches-passwort-xyz')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(fehler, isA<KontextFehler>());
      expect(fehler, isNot(isA<KontextNichtErreichbar>()));
      final meldung = (fehler as KontextFehler).meldung;
      expect(meldung, contains('refused the user or the password'));
      expect(meldung, isNot(contains('falsches-passwort-xyz')));
    });

    test(
      'eine Wurzel, die es auf dem Server nicht gibt, ist ein Fehler mit Grund',
      () async {
        server = WebDavTestServer(
          ordner: Directory(p.join(ordner.path, 'weg')),
          benutzer: testBenutzer,
          passwort: testPasswort,
        );
        await server!.starten();

        await expectLater(
          oeffnen(),
          throwsA(
            isA<KontextFehler>()
                .having((f) => f, 'typ', isNot(isA<KontextNichtErreichbar>()))
                .having(
                  (f) => f.meldung,
                  'meldung',
                  contains('does not exist'),
                ),
          ),
        );
      },
    );
  });

  group('Adressen', () {
    test('https ist erlaubt, http nur zu einer Schleife', () {
      expect(pruefeAdresse('https://cloud.example.org/dav/').scheme, 'https');
      expect(pruefeAdresse('http://127.0.0.1:8080/dav/').host, '127.0.0.1');
      expect(pruefeAdresse('http://localhost:8080/dav/').host, 'localhost');
    });

    test('http zu einem anderen Rechner wird abgewiesen, weil das Passwort offen ginge', () {
      expect(
        () => pruefeAdresse('http://cloud.example.org/dav/'),
        throwsA(
          isA<KontextFehler>().having(
            (f) => f.meldung,
            'meldung',
            contains('must use https'),
          ),
        ),
      );
    });

    test('Zugangsdaten in der Adresse werden abgewiesen', () {
      expect(
        () => pruefeAdresse('https://nutzer:geheim@cloud.example.org/dav/'),
        throwsA(
          isA<KontextFehler>().having(
            (f) => f.meldung,
            'meldung',
            allOf(contains('must not contain'), isNot(contains('geheim'))),
          ),
        ),
      );
    });

    test('eine Adresse ohne Rechner wird abgewiesen', () {
      expect(() => pruefeAdresse('dav/kontext'), throwsA(isA<KontextFehler>()));
    });
  });

  group('am WebDAV-Ort im Plugin', () {
    test('fehlt das Passwort im Schlüsselbund, nennt die Antwort den Schlüsselbund und speichert nichts in eine Datei', () async {
      plugin = await PluginProzess.starten(
        ordner: ordner,
        ort: Ortsart.webdav,
        webdavPasswort: null,
      );
      await plugin!.initialisieren();

      final ergebnis = await plugin!.werkzeug('context_list', {'pfad': ''});

      expect(ergebnis['isError'], isTrue);
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('system keyring'));
      expect(await _dateienMit(ordner, testPasswort), isEmpty);
    });

    test(
      'ein falsches Passwort lässt Schreibvorgänge nicht im Ausstand landen',
      () async {
        plugin = await PluginProzess.starten(
          ordner: ordner,
          ort: Ortsart.webdav,
          webdavPasswort: 'falsch-gespeichert-abc',
        );
        await plugin!.initialisieren();
        plugin!.app.stufe = 'alle';

        final ergebnis = await plugin!.werkzeug('context_write', {
          'pfad': 'plan.md',
          'inhalt': 'x\n',
          'art': 'plan_change',
          'zusammenfassung': 'Plan.',
        });

        expect(ergebnis['isError'], isTrue);
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('refused the user or the password'));
        expect(text, isNot(startsWith('not saved yet')));
        expect(
          Directory(p.join(ordner.path, 'ausstand')).existsSync(),
          isFalse,
        );
        expect(File(p.join(root, 'plan.md')).existsSync(), isFalse);
      },
    );

    test('das Passwort steht in keiner Antwort und in keiner Datei außerhalb des Testschlüsselbundes', () async {
      plugin = await PluginProzess.starten(ordner: ordner, ort: Ortsart.webdav);
      await plugin!.initialisieren();
      plugin!.app.stufe = 'alle';
      final antworten = [
        await plugin!.werkzeug('context_start', {}),
        await plugin!.werkzeug('context_list', {'pfad': ''}),
        await plugin!.werkzeug('context_write', {
          'pfad': 'plan.md',
          'inhalt': 'x\n',
          'art': 'plan_change',
          'zusammenfassung': 'Plan.',
        }),
        await plugin!.werkzeug('context_read', {'pfad': 'plan.md'}),
      ];

      for (final antwort in antworten) {
        expect(PluginProzess.text(antwort), isNot(contains(testPasswort)));
      }
      expect(await _dateienMit(ordner, testPasswort), isEmpty);
    });
  });
}

/// Die Dateien unter [ordner], die [text] enthalten. Der Ersatz für secret-tool
/// (im Ordner `schluesselbund`) trägt das Passwort der Testanlage und zählt nicht.
Future<List<String>> _dateienMit(Directory ordner, String text) async {
  final treffer = <String>[];
  final werkzeuge = p.join(ordner.path, 'schluesselbund');
  await for (final e in ordner.list(recursive: true)) {
    if (e is! File || p.isWithin(werkzeuge, e.path)) continue;
    try {
      if (utf8
          .decode(await e.readAsBytes(), allowMalformed: true)
          .contains(text)) {
        treffer.add(e.path);
      }
    } on FileSystemException {
      // Nicht lesbare Dateien enthalten kein Passwort, das die Tests finden.
    }
  }
  return treffer;
}
