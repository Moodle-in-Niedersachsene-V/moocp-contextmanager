import 'dart:async';
import 'dart:io';

import 'fehler.dart';

/// Das Passwort eines entfernten Speichers aus dem Schlüsselbund des Systems
/// (ADR 0004). Das Plugin liest nur; eingetragen wird es im Einstellungsfenster.
abstract class Schluesselbund {
  /// Das Passwort zu [konto]. Fehlt es oder ist der Schlüsselbund nicht
  /// erreichbar, wirft es mit dem Grund. Es gibt keinen Ersatz über eine Datei.
  Future<String> geheimnis(String konto);

  /// Trägt das Passwort zu [konto] ein (oder ersetzt es). Scheitert das, bleibt
  /// der Schlüsselbund, wie er war, und es wird nichts geschrieben (E8).
  Future<void> speichere(String konto, String geheimnis);
}

/// Der Schlüsselbund des Betriebssystems über dessen Werkzeuge: `secret-tool`
/// (Linux, libsecret) und `security` (macOS). Das Passwort kommt auf der
/// Standardausgabe; es steht nie in einer Kommandozeile und nie in einer Meldung.
class SystemSchluesselbund implements Schluesselbund {
  SystemSchluesselbund({
    String? werkzeug,
    Duration zeitlimit = const Duration(seconds: 15),
  }) : _werkzeug = werkzeug,
       _zeitlimit = zeitlimit;

  /// Das Programm, das anstelle des Standards läuft; nur für Tests und
  /// ungewöhnliche Installationen.
  final String? _werkzeug;

  /// Wie lange das Werkzeug antworten darf. Ein gesperrter Schlüsselbund fragt
  /// nach dem Entsperren und wartet sonst unbegrenzt.
  final Duration _zeitlimit;

  /// Der Dienstname, unter dem das Plugin seine Passwörter führt.
  static const dienst = 'moocp-contextmanager';

  @override
  Future<String> geheimnis(String konto) async {
    final ProcessResult ergebnis;
    final String programm;
    final List<String> argumente;
    if (Platform.isMacOS) {
      programm = _werkzeug ?? 'security';
      argumente = ['find-generic-password', '-s', dienst, '-a', konto, '-w'];
    } else if (Platform.isLinux) {
      programm = _werkzeug ?? 'secret-tool';
      argumente = ['lookup', 'service', dienst, 'account', konto];
    } else {
      throw const KontextFehler(
        'The system keyring is not supported on this system; nothing was read.',
      );
    }
    try {
      ergebnis = await Process.run(programm, argumente).timeout(_zeitlimit);
    } on ProcessException {
      throw KontextFehler(
        'The system keyring tool ($programm) is not installed. On Linux it is '
        'the package libsecret-tools. The password was not read; nothing was written.',
      );
    } on TimeoutException {
      throw const KontextFehler(
        'The system keyring did not answer in time (it may be locked). '
        'The password was not read; nothing was written.',
      );
    }
    var geheimnis = ergebnis.stdout is String ? ergebnis.stdout as String : '';
    // `security -w` schließt mit einem Zeilenende ab, das nicht zum Passwort gehört.
    if (Platform.isMacOS && geheimnis.endsWith('\n')) {
      geheimnis = geheimnis.substring(0, geheimnis.length - 1);
    }
    if (ergebnis.exitCode != 0 || geheimnis.isEmpty) {
      throw const KontextFehler(
        'No password for the WebDAV location in the system keyring (or the '
        'keyring is locked). Enter it in the settings window; nothing was written.',
      );
    }
    return geheimnis;
  }

  @override
  Future<void> speichere(String konto, String geheimnis) async {
    final String programm;
    final List<String> argumente;
    if (Platform.isMacOS) {
      // `security add-generic-password -w` nähme das Passwort als Argument;
      // deshalb läuft `security -i` und liest den Befehl von der Standardeingabe.
      programm = _werkzeug ?? 'security';
      argumente = ['-i'];
    } else if (Platform.isLinux) {
      programm = _werkzeug ?? 'secret-tool';
      argumente = [
        'store',
        '--label=$dienst',
        'service',
        dienst,
        'account',
        konto,
      ];
    } else {
      throw const KontextFehler(
        'The system keyring is not supported on this system; nothing was written.',
      );
    }
    final Process prozess;
    try {
      prozess = await Process.start(programm, argumente);
    } on ProcessException {
      throw KontextFehler(
        'The system keyring tool ($programm) is not installed. On Linux it is '
        'the package libsecret-tools. The password was not stored; nothing was written.',
      );
    }
    // Das Passwort geht über die Standardeingabe; die Ausgabe des Werkzeugs
    // wird verworfen, sie könnte den Eintrag zeigen.
    prozess.stdout.drain<void>();
    prozess.stderr.drain<void>();
    final String eingabe = Platform.isMacOS
        ? 'add-generic-password -U -s $dienst -a ${_zitiert(konto)} '
              '-w ${_zitiert(geheimnis)}\n'
        : geheimnis;
    try {
      // Endet das Werkzeug vor dem Lesen, bricht hier die Leitung ab; der
      // Exitcode unten sagt, ob es geklappt hat.
      try {
        prozess.stdin.write(eingabe);
        await prozess.stdin.close();
      } on IOException {
        // siehe oben
      }
      final ende = await prozess.exitCode.timeout(_zeitlimit);
      if (ende != 0) throw const _Gescheitert();
    } on TimeoutException {
      prozess.kill();
      throw const KontextFehler(
        'The system keyring did not answer in time (it may be locked). '
        'The password was not stored; nothing was written.',
      );
    } on _Gescheitert {
      throw const KontextFehler(
        'The password could not be stored in the system keyring. '
        'Nothing was written; check that the keyring is unlocked.',
      );
    }
  }

  /// Ein Befehlsargument für `security -i`, in doppelte Anführungszeichen gesetzt.
  static String _zitiert(String wert) =>
      '"${wert.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

class _Gescheitert implements Exception {
  const _Gescheitert();
}
