// Tests des Schlüsselbund-Zugangs (ADR 0004). Der echte Schlüsselbund wird nie
// benutzt: Das Werkzeug kommt als Parameter, im Test ist es ein Skript im
// temporären Ordner oder ein Pfad, den es nicht gibt.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/schluesselbund.dart';

import 'harness.dart';

void main() {
  late Directory ordner;

  setUp(() async {
    ordner = await tempOrdner('schluesselbund');
  });

  tearDown(() async {
    await ordner.delete(recursive: true);
  });

  /// Ein Ersatz für das Werkzeug: gibt [ausgabe] aus und endet mit [exitCode].
  Future<String> ersatz({
    required String ausgabe,
    required int exitCode,
  }) async {
    final datei = File(p.join(ordner.path, 'werkzeug'));
    await datei.writeAsString(
      '#!/bin/sh\n'
      "printf '%s' '$ausgabe'\n"
      'exit $exitCode\n',
    );
    Process.runSync('chmod', ['755', datei.path]);
    return datei.path;
  }

  test('das Passwort kommt unverändert vom Werkzeug', () async {
    final werkzeug = await ersatz(ausgabe: testPasswort, exitCode: 0);

    final geheimnis = await SystemSchluesselbund(werkzeug: werkzeug)
        .geheimnis('nutzer@adresse');

    expect(geheimnis, testPasswort);
  });

  test('fehlt das Werkzeug, ist das ein Fehler mit Grund, kein Ersatz über eine Datei', () async {
    final fehlt = p.join(ordner.path, 'es-gibt-kein-werkzeug');

    await expectLater(
      SystemSchluesselbund(werkzeug: fehlt).geheimnis('nutzer@adresse'),
      throwsA(
        isA<KontextFehler>().having(
          (f) => f.meldung,
          'meldung',
          contains('is not installed'),
        ),
      ),
    );
  });

  test(
    'ohne Eintrag (Werkzeug endet mit Fehler) gibt es kein Passwort',
    () async {
      final werkzeug = await ersatz(ausgabe: '', exitCode: 1);

      await expectLater(
        SystemSchluesselbund(werkzeug: werkzeug).geheimnis('nutzer@adresse'),
        throwsA(
          isA<KontextFehler>().having(
            (f) => f.meldung,
            'meldung',
            allOf(contains('No password'), isNot(contains(testPasswort))),
          ),
        ),
      );
    },
  );

  test('antwortet der Schlüsselbund nicht in der Zeit (etwa gesperrt), ist das ein Fehler', () async {
    final datei = File(p.join(ordner.path, 'langsam'));
    await datei.writeAsString('#!/bin/sh\nsleep 5\n');
    Process.runSync('chmod', ['755', datei.path]);

    await expectLater(
      SystemSchluesselbund(
        werkzeug: datei.path,
        zeitlimit: const Duration(milliseconds: 300),
      ).geheimnis('nutzer@adresse'),
      throwsA(
        isA<KontextFehler>().having(
          (f) => f.meldung,
          'meldung',
          contains('did not answer in time'),
        ),
      ),
    );
  });

  test('speichern: das Passwort geht über die Standardeingabe, nie in die Kommandozeile', () async {
    final argumente = p.join(ordner.path, 'argumente');
    final eingabe = p.join(ordner.path, 'eingabe');
    final datei = File(p.join(ordner.path, 'werkzeug'));
    await datei.writeAsString(
      '#!/bin/sh\n'
      'printf "%s\\n" "\$@" > "$argumente"\n'
      'cat > "$eingabe"\n'
      'exit 0\n',
    );
    Process.runSync('chmod', ['755', datei.path]);

    await SystemSchluesselbund(werkzeug: datei.path)
        .speichere('nutzer@adresse', testPasswort);

    expect(File(eingabe).readAsStringSync(), testPasswort);
    final zeilen = File(argumente).readAsLinesSync();
    expect(zeilen, containsAll(['moocp-contextmanager', 'nutzer@adresse']));
    expect(zeilen.join(' '), isNot(contains(testPasswort)));
  });

  test('speichern: scheitert das Werkzeug, ist das ein Fehler mit Grund ohne Passwort', () async {
    final werkzeug = await ersatz(ausgabe: '', exitCode: 1);

    await expectLater(
      SystemSchluesselbund(werkzeug: werkzeug)
          .speichere('nutzer@adresse', testPasswort),
      throwsA(
        isA<KontextFehler>().having(
          (f) => f.meldung,
          'meldung',
          allOf(contains('could not be stored'), isNot(contains(testPasswort))),
        ),
      ),
    );
  });

  test('speichern: Steuerzeichen (Zeilenende) in Passwort oder Konto werden vor dem Werkzeug abgewiesen', () async {
    final marker = p.join(ordner.path, 'gestartet');
    final datei = File(p.join(ordner.path, 'werkzeug'));
    await datei.writeAsString('#!/bin/sh\ntouch "$marker"\ncat > /dev/null\nexit 0\n');
    Process.runSync('chmod', ['755', datei.path]);
    final schluesselbund = SystemSchluesselbund(werkzeug: datei.path);

    for (final (konto, geheimnis) in [
      ('nutzer@adresse', 'geheim\nzweite Zeile'),
      ('nutzer@adresse\r', testPasswort),
      ('nutzer\t@adresse', testPasswort),
    ]) {
      await expectLater(
        schluesselbund.speichere(konto, geheimnis),
        throwsA(
          isA<KontextFehler>().having(
            (f) => f.meldung,
            'meldung',
            allOf(contains('control characters'), isNot(contains('geheim'))),
          ),
        ),
      );
    }
    expect(File(marker).existsSync(), isFalse, reason: 'das Werkzeug läuft nie');
  });

  test('ein leerer Eintrag zählt als fehlend', () async {
    final werkzeug = await ersatz(ausgabe: '', exitCode: 0);

    await expectLater(
      SystemSchluesselbund(werkzeug: werkzeug).geheimnis('nutzer@adresse'),
      throwsA(isA<KontextFehler>()),
    );
  });
}
