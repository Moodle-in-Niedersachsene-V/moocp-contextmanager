import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Das Einstellungsfenster (E8): ein eigenes Programm, das mit dem Plugin
/// ausgeliefert wird. Das Plugin startet es, wenn die Einstellungen fehlen, wenn
/// der Ort nicht antwortet (einmal je Ausfall) oder auf Wunsch der KI über
/// `context_settings`. Es übergibt nur den Pfad der Einstellungsdatei, nie Werte.
class Einstellungsfenster {
  Einstellungsfenster({
    required this.programm,
    required this.einstellungen,
    Future<Process> Function(String programm, List<String> argumente)? starten,
    File? pidDatei,
    Future<String?> Function(int pid)? befehlszeile,
  }) : _starten = starten ?? _echtStarten,
       _pidDatei =
           pidDatei ??
           File(p.join(p.dirname(einstellungen.path), 'fenster.pid')),
       _befehlszeile = befehlszeile ?? _echteBefehlszeile;

  /// Das Programm des Fensters.
  final String programm;

  /// Die Einstellungsdatei, deren Pfad das Fenster bekommt.
  final File einstellungen;

  final Future<Process> Function(String programm, List<String> argumente)
  _starten;

  /// Die Pid des offenen Fensters, im Datenordner neben den Einstellungen. Sie
  /// überlebt ein Plugin, das ohne aufzuräumen endet (Absturz, SIGKILL); der
  /// nächste Start beendet den Rest, bevor er ein Fenster öffnet.
  final File _pidDatei;

  /// Die Kommandozeile eines Prozesses (null: es gibt ihn nicht).
  final Future<String?> Function(int pid) _befehlszeile;

  /// Das laufende Fenster, solange es offen ist.
  Process? _prozess;

  /// Ob bei diesem Ausfall schon ein Fenster geöffnet wurde. Erst wenn der Ort
  /// wieder antwortet, gilt der nächste Ausfall als neuer.
  bool _ausfallOffen = false;

  /// Ob gerade ein Start läuft (zwischen Aufruf und Rückkehr des Startens).
  bool _startet = false;

  /// Auf Wunsch (`context_settings`): öffnet das Fenster, wenn es nicht offen ist.
  Future<FensterErgebnis> oeffnen() async {
    if (_prozess != null) {
      return const FensterErgebnis(
        FensterStand.lauft,
        'The settings window is already open.',
      );
    }
    return _start();
  }

  /// Beim Ausfall des Ortes: öffnet das Fenster einmal je Ausfall. Ein Fehler
  /// beim Starten geht nicht nach außen; die Antwort der KI nennt den Ausfall.
  Future<void> beiAusfall() async {
    if (_ausfallOffen) return;
    _ausfallOffen = true;
    await _start();
  }

  /// Der Ort antwortet wieder: der nächste Ausfall öffnet das Fenster erneut.
  void ausfallVorbei() {
    _ausfallOffen = false;
  }

  /// Das Plugin endet: ein offenes Fenster endet mit. Wird auf jedem Weg des
  /// Endes gerufen (Standardeingabe zu, SIGTERM, SIGINT) und ist wiederholbar.
  Future<void> beenden() async {
    final prozess = _prozess;
    _prozess = null;
    if (prozess != null) {
      prozess.kill();
      await prozess.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          prozess.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    await _loeschePid();
  }

  Future<void> _loeschePid() async {
    try {
      if (await _pidDatei.exists()) await _pidDatei.delete();
    } on FileSystemException {
      // Eine Pid-Datei, die bleibt, wird beim nächsten Start geprüft.
    }
  }

  /// Beendet ein Fenster aus einem früheren Lauf, das noch offen ist. Beendet
  /// wird nur, was unter der alten Pid wirklich das Programm des Fensters ist:
  /// Die Pid kann inzwischen einem fremden Prozess gehören.
  Future<void> _raeumeRestAuf() async {
    final int? pid;
    try {
      pid = int.tryParse((await _pidDatei.readAsString()).trim());
    } on FileSystemException {
      return;
    }
    if (pid != null && pid > 1) {
      final zeile = await _befehlszeile(pid);
      if (zeile != null && zeile.contains(programm)) {
        Process.killPid(pid);
        // Kurz warten, bis das alte Fenster fort ist, damit nie zwei offen sind.
        for (var i = 0; i < 30 && await _befehlszeile(pid) != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    await _loeschePid();
  }

  Future<FensterErgebnis> _start() async {
    if (_prozess != null || _startet) {
      return const FensterErgebnis(
        FensterStand.lauft,
        'The settings window is already open.',
      );
    }
    // Gesetzt, bevor das Programm startet: Ein zweiter Aufruf, der während des
    // Wartens hier ankommt, startet kein zweites Fenster.
    _startet = true;
    final Process prozess;
    try {
      await _raeumeRestAuf();
      prozess = await _starten(programm, [
        '--einstellungen',
        einstellungen.path,
      ]);
    } on ProcessException {
      _startet = false;
      return const FensterErgebnis(
        FensterStand.nichtGestartet,
        'The settings window could not be started. Ask the teacher to open it from the plugin folder.',
      );
    }
    _startet = false;
    _prozess = prozess;
    try {
      await _pidDatei.writeAsString('${prozess.pid}');
    } on FileSystemException {
      // Ohne Pid-Datei bleibt nur der Schutz beim geordneten Ende des Plugins.
    }
    // Die Ausgabe des Fensters wird verworfen, damit der Puffer nicht volläuft.
    prozess.stdout.drain<void>();
    prozess.stderr.drain<void>();
    unawaited(
      prozess.exitCode.then((_) {
        if (identical(_prozess, prozess)) {
          _prozess = null;
          unawaited(_loeschePid());
        }
      }),
    );
    return const FensterErgebnis(
      FensterStand.geoeffnet,
      'The settings window is open. The teacher enters the location and the password there; the assistant does not see or pass them.',
    );
  }
}

/// Ob das Fenster geöffnet wurde, schon offen war oder nicht startete.
enum FensterStand { geoeffnet, lauft, nichtGestartet }

/// Das Ergebnis mit [meldung] für die KI. Sie enthält nie Werte der Einstellungen.
class FensterErgebnis {
  const FensterErgebnis(this.stand, this.meldung);

  final FensterStand stand;
  final String meldung;
}

/// Das Programm des Fensters neben dem Plugin: im Ordner `einstellungsfenster`
/// des Plugin-Ordners, so wie `bauen.sh` es ablegt.
String standardFensterProgramm() {
  final ordner = p.dirname(Platform.resolvedExecutable);
  if (Platform.isMacOS) {
    return p.join(
      ordner,
      'einstellungsfenster',
      'kontext_einstellungen.app',
      'Contents',
      'MacOS',
      'kontext_einstellungen',
    );
  }
  return p.join(ordner, 'einstellungsfenster', 'kontext_einstellungen');
}

const _schluesselVariable = 'MOOCP_PLUGIN_SCHLUESSEL';

/// Das Fenster erbt die Umgebung ohne den Schlüssel des Plugins: es braucht ihn
/// nicht, und er gehört nicht in einen zweiten Prozess (A1).
Future<Process> _echtStarten(String programm, List<String> argumente) {
  final umgebung = Map<String, String>.of(Platform.environment)
    ..remove(_schluesselVariable);
  return Process.start(
    programm,
    argumente,
    environment: umgebung,
    includeParentEnvironment: false,
  );
}

/// Die Kommandozeile unter [pid] über `ps` (Linux und macOS); null, wenn es den
/// Prozess nicht gibt.
Future<String?> _echteBefehlszeile(int pid) async {
  try {
    final r = await Process.run('ps', ['-p', '$pid', '-o', 'args=']);
    final zeile = (r.stdout as String).trim();
    return r.exitCode == 0 && zeile.isNotEmpty ? zeile : null;
  } on ProcessException {
    return null;
  }
}
