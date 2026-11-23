import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'fensterarchiv.dart';

/// Das Einstellungsfenster (E8): ein eigenes Programm, das mit dem Plugin
/// ausgeliefert wird. Das Plugin startet es, wenn die Einstellungen fehlen, wenn
/// der Ort nicht antwortet (einmal je Ausfall) oder auf Wunsch der KI über
/// `context_settings`. Es übergibt nur den Pfad der Einstellungsdatei, nie Werte.
class Einstellungsfenster {
  Einstellungsfenster({
    required this.programm,
    required this.einstellungen,
    Future<Process> Function(String programm, List<String> argumente)? starten,
    Future<String?> Function(int pid)? befehlszeile,
    Future<void> Function()? vorbereiten,
    this.wartezeit = const Duration(seconds: 3),
  }) : _starten = starten ?? _echtStarten,
       _befehlszeile = befehlszeile ?? _echteBefehlszeile,
       _vorbereiten = vorbereiten,
       _pidDatei = File(p.join(p.dirname(einstellungen.path), 'fenster.pid'));

  /// Das Fenster, wie das Plugin es ausliefert. Unter Linux liegt es als Bündel
  /// im Ordner `einstellungsfenster` neben dem Programm des Plugins. Auf dem Mac
  /// liegt es als Archiv dort (E11) und wird vor jedem Start frisch in den
  /// Datenordner neben [einstellungen] ausgepackt.
  factory Einstellungsfenster.standard({required File einstellungen}) {
    final pluginOrdner = p.dirname(Platform.resolvedExecutable);
    if (Platform.isMacOS) {
      final ziel = Directory(p.join(einstellungen.parent.path, 'einstellungsfenster'));
      return Einstellungsfenster(
        programm: fensterProgrammIn(ziel),
        einstellungen: einstellungen,
        vorbereiten: () => packeFensterAus(
          archiv: File(p.join(pluginOrdner, fensterArchivName)),
          ziel: ziel,
        ),
      );
    }
    return Einstellungsfenster(
      programm: p.join(
        pluginOrdner,
        'einstellungsfenster',
        Platform.isWindows ? 'kontext_einstellungen.exe' : 'kontext_einstellungen',
      ),
      einstellungen: einstellungen,
    );
  }

  /// Das Programm des Fensters.
  final String programm;

  /// Die Einstellungsdatei, deren Pfad das Fenster bekommt.
  final File einstellungen;

  final Future<Process> Function(String programm, List<String> argumente)
  _starten;

  /// Wie lange ein Fenster nach SIGTERM (und dann nach SIGKILL) Zeit hat zu enden.
  final Duration wartezeit;

  /// Die Kommandozeile eines Prozesses; null, wenn es ihn nicht gibt. Wirft
  /// [BefehlszeilenFehler], wenn sich das nicht feststellen lässt.
  final Future<String?> Function(int pid) _befehlszeile;

  /// Was vor jedem Start geschieht, nachdem ein Rest beendet ist (auf dem Mac:
  /// das Archiv auspacken). Wirft [FensterVorbereitungsFehler].
  final Future<void> Function()? _vorbereiten;

  // Die Pid des offenen Fensters steht im Datenordner neben den Einstellungen.
  // Sie überlebt ein Plugin, das ohne Aufräumen endet (Absturz, SIGKILL): Der
  // nächste Start beendet den Rest, bevor er ein Fenster öffnet, damit nie zwei
  // offen sind. Geschrieben wird sie wie die Einstellungen (Datei daneben, dann
  // umbenennen); eine Verknüpfung an der Stelle der Pid-Datei oder der Datei
  // daneben wird ersetzt, nie gefolgt.
  final File _pidDatei;

  /// Das laufende Fenster, solange es offen ist.
  Process? _prozess;

  /// Ob bei diesem Ausfall schon ein Fenster geöffnet wurde. Erst wenn der Ort
  /// wieder antwortet, gilt der nächste Ausfall als neuer.
  bool _ausfallOffen = false;

  /// Ob gerade ein Start läuft (zwischen Aufruf und Rückkehr des Startens).
  bool _startet = false;

  /// Der laufende Start, auf den [beenden] wartet.
  Future<FensterErgebnis>? _laufenderStart;

  /// Ob das Plugin endet: dann startet kein Fenster mehr, und eines, das gerade
  /// startet, wird gleich wieder beendet.
  bool _endet = false;

  /// Auf Wunsch (`context_settings`): öffnet das Fenster, wenn es nicht offen ist.
  Future<FensterErgebnis> oeffnen() async {
    if (_prozess != null) {
      return const FensterErgebnis(FensterStand.lauft, 'The settings window is already open.');
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
    _endet = true;
    // Ein Start, der gerade läuft, beendet sein Fenster selbst, sobald es da ist.
    try {
      await _laufenderStart;
    } on Object {
      // Ein gescheiterter Start hat kein Fenster hinterlassen.
    }
    final prozess = _prozess;
    _prozess = null;
    if (prozess != null) {
      prozess.kill();
      await prozess.exitCode.timeout(
        wartezeit,
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
      if (FileSystemEntity.isLinkSync(_pidDatei.path) || _pidDatei.existsSync()) {
        await _pidDatei.delete();
      }
    } on FileSystemException {
      // Eine Pid-Datei, die bleibt, wird beim nächsten Start geprüft.
    }
  }

  Future<void> _schreibePid(int pid) async {
    try {
      final tmp = File('${_pidDatei.path}.tmp');
      if (FileSystemEntity.isLinkSync(tmp.path)) await tmp.delete();
      await tmp.writeAsString('$pid', flush: true);
      await tmp.rename(_pidDatei.path);
    } on FileSystemException {
      // Ohne Pid-Datei bleibt nur der Schutz beim geordneten Ende des Plugins.
    }
  }

  /// Ob [zeile] die Kommandozeile unseres Fensters ist: das Programm als
  /// ganzes Wort am Anfang und sein Argument `--einstellungen`. Die Pid kann
  /// inzwischen einem fremden Prozess gehören, der den Pfad nur erwähnt.
  bool _istFenster(String zeile) {
    var z = zeile;
    if (Platform.isWindows) {
      // Windows nennt das Programm mit Anführungszeichen, und Pfade
      // unterscheiden dort nicht zwischen Groß- und Kleinschreibung.
      z = z.toLowerCase().replaceFirst('"', '').replaceFirst('"', '');
    }
    final soll = Platform.isWindows ? programm.toLowerCase() : programm;
    return (z == soll || z.startsWith('$soll ')) && z.contains('--einstellungen');
  }

  Future<bool> _lebt(int pid) async => await _befehlszeile(pid) != null;

  Future<bool> _warteBisEnde(int pid) async {
    final bis = DateTime.now().add(wartezeit);
    while (DateTime.now().isBefore(bis)) {
      if (!await _lebt(pid)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return !await _lebt(pid);
  }

  /// Beendet ein Fenster aus einem früheren Lauf, das noch offen ist: erst
  /// SIGTERM, nach der Wartezeit SIGKILL. Gibt den Grund zurück, wenn danach
  /// nicht sicher ist, dass es fort ist (dann öffnet kein zweites Fenster).
  Future<String?> _raeumeRestAuf() async {
    final int? pid;
    try {
      pid = FileSystemEntity.isLinkSync(_pidDatei.path)
          ? null
          : int.tryParse((await _pidDatei.readAsString()).trim());
    } on FileSystemException {
      return null;
    }
    if (pid != null && pid > 1) {
      try {
        final zeile = await _befehlszeile(pid);
        if (zeile != null && _istFenster(zeile)) {
          Process.killPid(pid);
          if (!await _warteBisEnde(pid)) {
            Process.killPid(pid, ProcessSignal.sigkill);
            if (!await _warteBisEnde(pid)) return _restBleibt;
          }
        }
      } on BefehlszeilenFehler {
        return _restNichtGeprueft;
      }
    }
    await _loeschePid();
    return null;
  }

  Future<FensterErgebnis> _start() {
    if (_endet) return Future.value(_nichtGestartet);
    if (_prozess != null || _startet) {
      return Future.value(
        const FensterErgebnis(FensterStand.lauft, 'The settings window is already open.'),
      );
    }
    // Gesetzt, bevor etwas wartet: Ein zweiter Aufruf, der während des Wartens
    // hier ankommt, startet kein zweites Fenster.
    _startet = true;
    return _laufenderStart = _startInnen().whenComplete(() => _startet = false);
  }

  Future<FensterErgebnis> _startInnen() async {
    final Process prozess;
    try {
      final grund = await _raeumeRestAuf();
      if (grund != null) {
        return FensterErgebnis(FensterStand.nichtGestartet, grund);
      }
      // Erst nach dem Aufräumen: Das Auspacken ersetzt die Dateien, aus denen
      // ein Rest liefe.
      final vorbereiten = _vorbereiten;
      if (vorbereiten != null) {
        try {
          await vorbereiten();
        } on FensterVorbereitungsFehler catch (e) {
          // Der Grund geht nur in die Fehlerausgabe des Plugins, nicht zur KI.
          stderr.writeln('context: settings window: ${e.grund}');
          return _nichtAusgepackt;
        }
      }
      prozess = await _starten(programm, ['--einstellungen', einstellungen.path]);
    } on ProcessException {
      return _nichtGestartet;
    }
    if (_endet) {
      // Das Plugin endete, während das Fenster startete.
      prozess.kill(ProcessSignal.sigkill);
      return _nichtGestartet;
    }
    _prozess = prozess;
    await _schreibePid(prozess.pid);
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

const _nichtGestartet = FensterErgebnis(
  FensterStand.nichtGestartet,
  'The settings window could not be started. Ask the teacher to open it from the plugin folder.',
);
// Ohne den Grund: Er nennt Pfade des Rechners, und die gehören nicht zur KI.
const _nichtAusgepackt = FensterErgebnis(
  FensterStand.nichtGestartet,
  'The settings window could not be unpacked from the plugin folder. Ask the teacher to reinstall the plugin.',
);
const _restBleibt =
    'The settings window could not be started: an earlier settings window of the plugin is still open and did not end. Ask the teacher to close it.';
const _restNichtGeprueft =
    'The settings window could not be started: an earlier settings window may still be open and could not be checked (the system tool ps failed). Ask the teacher to close it.';

/// Das Vorbereiten des Fensters vor dem Start ist gescheitert; [grund] nennt
/// die Ursache für das Protokoll, nie für die KI.
class FensterVorbereitungsFehler implements Exception {
  const FensterVorbereitungsFehler(this.grund);

  final String grund;

  @override
  String toString() => 'FensterVorbereitungsFehler: $grund';
}

/// Die Kommandozeile eines Prozesses ließ sich nicht feststellen (`ps` fehlt oder
/// scheitert), anders als "es gibt den Prozess nicht".
class BefehlszeilenFehler implements Exception {
  const BefehlszeilenFehler();
}

/// Ob das Fenster geöffnet wurde, schon offen war oder nicht startete.
enum FensterStand { geoeffnet, lauft, nichtGestartet }

/// Das Ergebnis mit [meldung] für die KI. Sie enthält nie Werte der Einstellungen.
class FensterErgebnis {
  const FensterErgebnis(this.stand, this.meldung);

  final FensterStand stand;
  final String meldung;
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

/// Die Kommandozeile unter [pid] über `ps` (Linux und macOS) bzw. PowerShell
/// (Windows). `ps -p` endet mit 1 und ohne Ausgabe, wenn es den Prozess nicht
/// gibt; jeder andere Ausfall ist ein [BefehlszeilenFehler].
Future<String?> _echteBefehlszeile(int pid) async {
  if (Platform.isWindows) {
    // Die Pid ist eine Zahl; sie steht allein im Befehl. Ohne den Prozess gibt
    // Get-CimInstance nichts aus und endet mit 0.
    final ProcessResult w;
    try {
      w = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-CimInstance Win32_Process -Filter 'ProcessId=$pid').CommandLine",
      ]);
    } on ProcessException {
      throw const BefehlszeilenFehler();
    }
    if (w.exitCode != 0) throw const BefehlszeilenFehler();
    final text = (w.stdout as String).trim();
    return text.isEmpty ? null : text;
  }
  final ProcessResult r;
  try {
    r = await Process.run('ps', ['-p', '$pid', '-o', 'args=']);
  } on ProcessException {
    throw const BefehlszeilenFehler();
  }
  final zeile = (r.stdout as String).trim();
  if (r.exitCode == 0 && zeile.isNotEmpty) return zeile;
  if (r.exitCode == 1 && zeile.isEmpty) return null;
  throw const BefehlszeilenFehler();
}
