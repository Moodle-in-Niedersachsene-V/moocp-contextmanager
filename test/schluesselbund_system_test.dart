// Prüft den echten Schlüsselbund des Systems mit einem eigenen Dienstnamen, nie
// mit dem des Plugins (ADR 0004). Läuft nur mit KONTEXT_SCHLUESSELBUND=1: im
// Workflow auf macOS und Windows, wo der Schlüsselbund der Sitzung ohne
// Rückfrage antwortet. Sonst übersprungen.
import 'dart:io';

import 'package:test/test.dart';

import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/schluesselbund.dart';
import 'package:contextmanager/src/windows_anmeldeinfo.dart';

void main() {
  final an = Platform.environment['KONTEXT_SCHLUESSELBUND'] == '1';
  final dienst = 'moocp-contextmanager-test-${DateTime.now().microsecondsSinceEpoch}';
  const konto = 'lehrkraft@https://example.invalid/dav';

  test(
    'Speichern und Lesen im Schlüsselbund des Systems, auch mit Umlauten',
    () async {
      final bund = SystemSchluesselbund(dienstname: dienst);
      await expectLater(
        bund.geheimnis(konto),
        throwsA(isA<KontextFehler>()),
        reason: 'vor dem Speichern gibt es kein Passwort',
      );
      await bund.speichere(konto, 'Käse & "Wein" 123');
      expect(await bund.geheimnis(konto), 'Käse & "Wein" 123');
      await bund.speichere(konto, 'neu');
      expect(await bund.geheimnis(konto), 'neu');
    },
    skip: an ? null : 'KONTEXT_SCHLUESSELBUND ist nicht gesetzt',
  );

  tearDown(() async {
    if (!an) return;
    if (Platform.isWindows) {
      await windowsLoesche(dienst, konto);
    } else if (Platform.isMacOS) {
      await Process.run('security', ['delete-generic-password', '-s', dienst, '-a', konto]);
    } else if (Platform.isLinux) {
      await Process.run('secret-tool', ['clear', 'service', dienst, 'account', konto]);
    }
  });
}
