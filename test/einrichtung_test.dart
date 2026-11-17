// Tests der Einrichtung des Kontextbereichs (E8): das Schreiben der
// Einstellungsdatei, die Prüfung der Eingaben, die Verbindungsprüfung und die
// deutschen Meldungen. Der Schlüsselbund ist ein Ersatz im Test, der echte wird
// nie benutzt. Die Verbindungsprüfung läuft gegen den WebDAV-Server des Tests.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/einrichtung.dart';
import 'package:contextmanager/src/einstellungen.dart';
import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/schluesselbund.dart';

import 'harness.dart';
import 'webdav_server.dart';

void main() {
  _pruefungen();
  _verbindung();
  _speichern();

  late Directory ordner;

  setUp(() async {
    ordner = await tempOrdner('einrichtung');
  });

  tearDown(() async {
    await ordner.delete(recursive: true);
  });

  group('Einstellungsdatei schreiben', () {
    test('ein lokaler Ordner steht als Art und Pfad in der Datei und liest sich wieder', () async {
      final datei = File(p.join(ordner.path, 'einstellungen.json'));

      await schreibeEinstellungen(datei, Einstellungen.lokal('/abs/kontext'));

      expect(jsonDecode(datei.readAsStringSync()), {
        'art': 'lokal',
        'pfad': '/abs/kontext',
      });
      final gelesen = await leseEinstellungen(datei);
      expect(gelesen.art, 'lokal');
      expect(gelesen.pfad, '/abs/kontext');
    });

    test('WebDAV steht mit Adresse und Benutzer in der Datei, nie mit dem Passwort', () async {
      final datei = File(p.join(ordner.path, 'einstellungen.json'));

      await schreibeEinstellungen(
        datei,
        Einstellungen.webdav(
          adresse: Uri.parse('https://cloud.example.org/dav/kontext/'),
          benutzer: 'name',
        ),
      );

      expect(jsonDecode(datei.readAsStringSync()), {
        'art': 'webdav',
        'adresse': 'https://cloud.example.org/dav/kontext/',
        'benutzer': 'name',
      });
    });

    test('die Datei wird ersetzt, ohne dass ein Rest im Ordner bleibt', () async {
      final datei = File(p.join(ordner.path, 'einstellungen.json'));
      await datei.writeAsString('{"art":"lokal","pfad":"/alt"}');

      await schreibeEinstellungen(datei, Einstellungen.lokal('/neu'));

      expect((await leseEinstellungen(datei)).pfad, '/neu');
      expect(
        ordner.listSync().map((e) => p.basename(e.path)).toList(),
        ['einstellungen.json'],
      );
    });
  });
}

void _pruefungen() {
  group('Eingaben prüfen', () {
    test('lokal ohne Ordner: der Ordner ist das Feld, die Meldung ist deutsch', () {
      expect(
        () => pruefeEinrichtung(Einrichtung(art: 'lokal')),
        throwsA(
          isA<EinrichtungsFehler>()
              .having((f) => f.feld, 'feld', 'pfad')
              .having((f) => f.meldung, 'meldung', 'Bitte einen Ordner wählen.'),
        ),
      );
    });

    test('lokal mit relativem Pfad wird abgewiesen', () {
      expect(
        () => pruefeEinrichtung(Einrichtung(art: 'lokal', pfad: 'kontext')),
        throwsA(
          isA<EinrichtungsFehler>().having(
            (f) => f.meldung,
            'meldung',
            'Der Ordner muss mit einem vollständigen Pfad angegeben werden.',
          ),
        ),
      );
    });

    test('WebDAV ohne Adresse, Benutzer: jedes Feld nennt sich selbst', () {
      expect(
        () => pruefeEinrichtung(Einrichtung(art: 'webdav')),
        throwsA(isA<EinrichtungsFehler>().having((f) => f.feld, 'feld', 'adresse')),
      );
      expect(
        () => pruefeEinrichtung(
          Einrichtung(art: 'webdav', adresse: 'https://cloud.example.org/dav/'),
        ),
        throwsA(
          isA<EinrichtungsFehler>()
              .having((f) => f.feld, 'feld', 'benutzer')
              .having((f) => f.meldung, 'meldung', 'Bitte den Benutzer eintragen.'),
        ),
      );
    });

    test('eine Adresse ohne https (außer zur Schleife) wird auf Deutsch abgewiesen', () {
      expect(
        () => pruefeEinrichtung(
          Einrichtung(
            art: 'webdav',
            adresse: 'http://cloud.example.org/dav/',
            benutzer: 'name',
          ),
        ),
        throwsA(
          isA<EinrichtungsFehler>()
              .having((f) => f.feld, 'feld', 'adresse')
              .having(
                (f) => f.meldung,
                'meldung',
                'Die Adresse muss mit https:// beginnen. Nur 127.0.0.1 und localhost dürfen http:// verwenden.',
              ),
        ),
      );
    });

    test('Zugangsdaten in der Adresse werden abgewiesen', () {
      expect(
        () => pruefeEinrichtung(
          Einrichtung(
            art: 'webdav',
            adresse: 'https://name:geheim@cloud.example.org/dav/',
            benutzer: 'name',
          ),
        ),
        throwsA(
          isA<EinrichtungsFehler>().having(
            (f) => f.meldung,
            'meldung',
            'Die Adresse darf keinen Benutzer und kein Passwort enthalten; sie stehen in den Feldern darunter.',
          ),
        ),
      );
    });

    test('eine gültige WebDAV-Eingabe ergibt die Einstellungen ohne Passwort', () {
      final e = pruefeEinrichtung(
        Einrichtung(
          art: 'webdav',
          adresse: 'https://cloud.example.org/dav/kontext/',
          benutzer: 'name',
          passwort: 'geheim',
        ),
      );

      expect(e.art, 'webdav');
      expect(e.adresse.toString(), 'https://cloud.example.org/dav/kontext/');
      expect(e.benutzer, 'name');
      expect(e.alsJson().toString(), isNot(contains('geheim')));
    });
  });
}

/// Ein Schlüsselbund im Speicher: nur für Tests, der echte wird nie benutzt.
class _SpeicherSchluesselbund implements Schluesselbund {
  _SpeicherSchluesselbund([Map<String, String>? eintraege])
    : eintraege = eintraege ?? {};

  final Map<String, String> eintraege;
  final List<String> geschrieben = [];

  @override
  Future<String> geheimnis(String konto) async {
    final wert = eintraege[konto];
    if (wert == null) {
      throw const KontextFehler(
        'No password for the WebDAV location in the system keyring (or the '
        'keyring is locked). Enter it in the settings window; nothing was written.',
      );
    }
    return wert;
  }

  @override
  Future<void> speichere(String konto, String geheimnis) async {
    geschrieben.add(konto);
    eintraege[konto] = geheimnis;
  }
}

void _verbindung() {
  group('Verbindung prüfen', () {
    late Directory ordner;
    late String root;
    WebDavTestServer? server;

    setUp(() async {
      ordner = await tempOrdner('verbindung');
      root = p.join(ordner.path, 'kontext');
      await Directory(root).create();
    });

    tearDown(() async {
      await server?.beenden();
      server = null;
      await ordner.delete(recursive: true);
    });

    Future<WebDavTestServer> webdav() async {
      final s = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await s.starten();
      server = s;
      return s;
    }

    test('ein lokaler Ordner, der da ist, meldet Erfolg', () async {
      final ergebnis = await pruefeVerbindung(
        Einrichtung(art: 'lokal', pfad: root),
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gelungen, isTrue);
      expect(ergebnis.meldung, 'Verbindung in Ordnung: Der Kontextbereich antwortet.');
    });

    test('ein lokaler Ordner, der fehlt, nennt den Grund auf Deutsch', () async {
      final ergebnis = await pruefeVerbindung(
        Einrichtung(art: 'lokal', pfad: p.join(ordner.path, 'gibt-es-nicht')),
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gelungen, isFalse);
      expect(ergebnis.meldung, 'Der Ordner existiert nicht.');
    });

    test('ein WebDAV-Server mit eingetragenem Passwort meldet Erfolg', () async {
      final s = await webdav();

      final ergebnis = await pruefeVerbindung(
        Einrichtung(
          art: 'webdav',
          adresse: s.adresse.toString(),
          benutzer: testBenutzer,
          passwort: testPasswort,
        ),
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gelungen, isTrue);
      expect(ergebnis.meldung, startsWith('Verbindung in Ordnung'));
    });

    test('ein falsches Passwort wird als Anmeldefehler auf Deutsch gemeldet', () async {
      final s = await webdav();

      final ergebnis = await pruefeVerbindung(
        Einrichtung(
          art: 'webdav',
          adresse: s.adresse.toString(),
          benutzer: testBenutzer,
          passwort: 'falsch',
        ),
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gelungen, isFalse);
      expect(ergebnis.meldung, 'Der Server lehnt Benutzer oder Passwort ab. Bitte beides prüfen.');
    });

    test('ein Server, der nicht antwortet, wird auf Deutsch gemeldet', () async {
      final s = await webdav();
      final adresse = s.adresse.toString();
      await s.anhalten();

      final ergebnis = await pruefeVerbindung(
        Einrichtung(
          art: 'webdav',
          adresse: adresse,
          benutzer: testBenutzer,
          passwort: testPasswort,
        ),
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gelungen, isFalse);
      expect(ergebnis.meldung, 'Der Server antwortet nicht. Adresse und Netzverbindung prüfen.');
    });

    test('ohne eingetragenes Passwort liest die Prüfung den Schlüsselbund', () async {
      final s = await webdav();
      final konto = '$testBenutzer@${s.adresse}';

      final mitEintrag = await pruefeVerbindung(
        Einrichtung(art: 'webdav', adresse: s.adresse.toString(), benutzer: testBenutzer),
        schluesselbund: _SpeicherSchluesselbund({konto: testPasswort}),
      );
      final ohneEintrag = await pruefeVerbindung(
        Einrichtung(art: 'webdav', adresse: s.adresse.toString(), benutzer: testBenutzer),
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(mitEintrag.gelungen, isTrue);
      expect(ohneEintrag.gelungen, isFalse);
      expect(ohneEintrag.meldung, 'Im Schlüsselbund ist kein Passwort zu diesem Konto. Bitte eintragen.');
    });
  });
}

/// Ein Schlüsselbund, der beim Eintragen scheitert.
class _DefektSchluesselbund extends _SpeicherSchluesselbund {
  @override
  Future<void> speichere(String konto, String geheimnis) async =>
      throw const KontextFehler(
        'The password could not be stored in the system keyring. '
        'Nothing was written; check that the keyring is unlocked.',
      );
}

void _speichern() {
  group('Speichern', () {
    late Directory ordner;
    late File datei;

    setUp(() async {
      ordner = await tempOrdner('speichern');
      datei = File(p.join(ordner.path, 'einstellungen.json'));
    });

    tearDown(() async {
      await ordner.delete(recursive: true);
    });

    test('WebDAV: das Passwort geht in den Schlüsselbund, die Datei ohne Passwort', () async {
      final sb = _SpeicherSchluesselbund();

      final ergebnis = await speichereEinrichtung(
        Einrichtung(
          art: 'webdav',
          adresse: 'https://cloud.example.org/dav/kontext/',
          benutzer: 'name',
          passwort: 'geheim',
        ),
        datei: datei,
        schluesselbund: sb,
      );

      expect(ergebnis.gespeichert, isTrue);
      expect(sb.geschrieben, ['name@https://cloud.example.org/dav/kontext/']);
      expect(sb.eintraege.values, ['geheim']);
      expect(jsonDecode(datei.readAsStringSync()), {
        'art': 'webdav',
        'adresse': 'https://cloud.example.org/dav/kontext/',
        'benutzer': 'name',
      });
    });

    test('scheitert der Schlüsselbund, bleibt die Datei unberührt und die Meldung ist deutsch', () async {
      await datei.writeAsString('{"art":"lokal","pfad":"/alt"}');

      final ergebnis = await speichereEinrichtung(
        Einrichtung(
          art: 'webdav',
          adresse: 'https://cloud.example.org/dav/kontext/',
          benutzer: 'name',
          passwort: 'geheim',
        ),
        datei: datei,
        schluesselbund: _DefektSchluesselbund(),
      );

      expect(ergebnis.gespeichert, isFalse);
      expect(
        ergebnis.meldung,
        'Das Passwort konnte nicht im Schlüsselbund gespeichert werden. Nichts wurde geschrieben.',
      );
      expect(datei.readAsStringSync(), '{"art":"lokal","pfad":"/alt"}');
    });

    test('ohne eingetragenes Passwort bleibt der Schlüsselbund unberührt', () async {
      final sb = _SpeicherSchluesselbund({'name@https://cloud.example.org/dav/': 'alt'});

      final ergebnis = await speichereEinrichtung(
        Einrichtung(
          art: 'webdav',
          adresse: 'https://cloud.example.org/dav/',
          benutzer: 'name',
        ),
        datei: datei,
        schluesselbund: sb,
      );

      expect(ergebnis.gespeichert, isTrue);
      expect(sb.geschrieben, isEmpty);
      expect(datei.existsSync(), isTrue);
    });

    test('lokal: nur die Datei, der Schlüsselbund wird nicht angefasst', () async {
      final sb = _SpeicherSchluesselbund();

      final ergebnis = await speichereEinrichtung(
        Einrichtung(art: 'lokal', pfad: p.join(ordner.path, 'kontext')),
        datei: datei,
        schluesselbund: sb,
      );

      expect(ergebnis.gespeichert, isTrue);
      expect(sb.geschrieben, isEmpty);
      expect(jsonDecode(datei.readAsStringSync()), {
        'art': 'lokal',
        'pfad': p.join(ordner.path, 'kontext'),
      });
    });

    test('ist der Datenordner nicht beschreibbar, kommt eine deutsche Meldung und keine Ausnahme', () async {
      // Der Datenordner ist hier eine Datei: Anlegen der Einstellungen scheitert.
      final blocker = File(p.join(ordner.path, 'kein-ordner'));
      await blocker.writeAsString('x');
      final ziel = File(p.join(blocker.path, 'einstellungen.json'));

      final ergebnis = await speichereEinrichtung(
        Einrichtung(art: 'lokal', pfad: p.join(ordner.path, 'kontext')),
        datei: ziel,
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gespeichert, isFalse);
      expect(ergebnis.meldung, startsWith('Die Einstellungen konnten nicht gespeichert werden.'));
    });

    test('eine ungültige Eingabe wird nicht gespeichert und nennt das Feld', () async {
      final ergebnis = await speichereEinrichtung(
        Einrichtung(art: 'lokal'),
        datei: datei,
        schluesselbund: _SpeicherSchluesselbund(),
      );

      expect(ergebnis.gespeichert, isFalse);
      expect(ergebnis.feld, 'pfad');
      expect(datei.existsSync(), isFalse);
    });
  });
}
