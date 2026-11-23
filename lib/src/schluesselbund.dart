import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'fehler.dart';
import 'windows_anmeldeinfo.dart';

/// Das Passwort eines entfernten Speichers aus dem Schlüsselbund des Systems
/// (ADR 0004). Der MCP-Server liest nur; geschrieben wird es vom Einstellungsfenster.
abstract class Schluesselbund {
  /// Das Passwort zu [konto]. Fehlt es oder ist der Schlüsselbund nicht
  /// erreichbar, wirft es mit dem Grund. Es gibt keinen Ersatz über eine Datei.
  Future<String> geheimnis(String konto);

  /// Trägt das Passwort zu [konto] ein (oder ersetzt es). Scheitert das, bleibt
  /// der Schlüsselbund, wie er war, und es wird nichts geschrieben (E8).
  Future<void> speichere(String konto, String geheimnis);
}

/// Der Schlüsselbund des Betriebssystems über dessen Werkzeuge: `secret-tool`
/// (Linux, libsecret) und `security` (macOS); unter Windows die
/// Anmeldeinformationsverwaltung über die Systemschnittstelle (kein Werkzeug,
/// kein Prozess). Beim Lesen kommt das Passwort auf
/// der Standardausgabe des Werkzeugs, beim Speichern geht es über dessen
/// Standardeingabe. Es steht nie in einer Kommandozeile und nie in einer Meldung.
class SystemSchluesselbund implements Schluesselbund {
  SystemSchluesselbund({
    String? werkzeug,
    Duration zeitlimit = const Duration(seconds: 15),
    String dienstname = dienst,
  }) : _werkzeug = werkzeug,
       _zeitlimit = zeitlimit,
       _dienst = dienstname;

  /// Das Programm, das anstelle des Standards läuft; nur für Tests und
  /// ungewöhnliche Installationen.
  final String? _werkzeug;

  /// Wie lange das Werkzeug antworten darf. Ein gesperrter Schlüsselbund fragt
  /// nach dem Entsperren und wartet sonst unbegrenzt.
  final Duration _zeitlimit;

  /// Der Dienstname, unter dem das Plugin seine Passwörter führt.
  static const dienst = 'moocp-contextmanager';

  /// Der Dienstname dieses Zugangs: [dienst], im Test ein eigener, damit ein
  /// Test am echten Schlüsselbund keinen Eintrag des Plugins berührt.
  final String _dienst;

  @override
  Future<String> geheimnis(String konto) async {
    if (Platform.isWindows && _werkzeug == null) {
      return windowsGeheimnis(_dienst, konto);
    }
    final ProcessResult ergebnis;
    final String programm;
    final List<String> argumente;
    if (Platform.isMacOS) {
      programm = _werkzeug ?? 'security';
      // `-g` statt `-w`: `-w` gibt ein Passwort mit Zeichen außerhalb von
      // ASCII (Umlaute) als Hex aus, ununterscheidbar von einem Passwort aus
      // Hexziffern. `-g` schreibt `password: "…"` oder `password: 0x… "…"` auf
      // die Fehlerausgabe (passwortAusSecurity).
      argumente = ['find-generic-password', '-s', _dienst, '-a', konto, '-g'];
    } else if (Platform.isLinux) {
      programm = _werkzeug ?? 'secret-tool';
      argumente = ['lookup', 'service', _dienst, 'account', konto];
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
    final String geheimnis;
    if (Platform.isMacOS) {
      final fehlerausgabe = ergebnis.stderr is String ? ergebnis.stderr as String : '';
      geheimnis = passwortAusSecurity(fehlerausgabe) ?? '';
    } else {
      geheimnis = ergebnis.stdout is String ? ergebnis.stdout as String : '';
    }
    if (ergebnis.exitCode != 0 || geheimnis.isEmpty) {
      throw const KontextFehler(
        'No password for the WebDAV location in the system keyring (or the '
        'keyring is locked). Enter it in the settings window; nothing was written.',
      );
    }
    return geheimnis;
  }

  /// Steuerzeichen (auch Zeilenende) im Passwort oder Konto würden das
  /// Werkzeug und seinen Befehl zerbrechen; sie werden vor dem Start abgewiesen.
  static final _steuerzeichen = RegExp(r'[\x00-\x1f\x7f]');

  @override
  Future<void> speichere(String konto, String geheimnis) async {
    if (_steuerzeichen.hasMatch(konto) || _steuerzeichen.hasMatch(geheimnis)) {
      throw const KontextFehler(
        'The password or account contains control characters (such as a line break); nothing was stored.',
      );
    }
    if (Platform.isWindows && _werkzeug == null) {
      return windowsSpeichere(_dienst, konto, geheimnis);
    }
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
        '--label=$_dienst',
        'service',
        _dienst,
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
        ? 'add-generic-password -U -s $_dienst -a ${_zitiert(konto)} '
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

/// Das Passwort aus der Ausgabe von `security find-generic-password -g`
/// (macOS); null, wenn keine lesbare Passwortzeile darin steht. Druckbare
/// Passwörter stehen als `password: "…"` da (Anführungszeichen im Passwort
/// bleiben unmaskiert, deshalb gilt alles zwischen dem ersten und dem letzten),
/// andere als `password: 0x<Hex>  "…"` mit den Bytes in UTF-8.
String? passwortAusSecurity(String ausgabe) {
  const anfang = 'password: ';
  for (final zeile in const LineSplitter().convert(ausgabe)) {
    if (!zeile.startsWith(anfang)) continue;
    final wert = zeile.substring(anfang.length);
    final hex = RegExp(r'^0x((?:[0-9A-Fa-f]{2})+)(?:\s|$)').firstMatch(wert);
    if (hex != null) {
      final ziffern = hex.group(1)!;
      final bytes = [
        for (var i = 0; i < ziffern.length; i += 2)
          int.parse(ziffern.substring(i, i + 2), radix: 16),
      ];
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return null;
      }
    }
    if (wert.length >= 2 && wert.startsWith('"') && wert.endsWith('"')) {
      return wert.substring(1, wert.length - 1);
    }
    return null;
  }
  return null;
}

class _Gescheitert implements Exception {
  const _Gescheitert();
}
