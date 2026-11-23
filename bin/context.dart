// Das Plugin "context" von moocp: der Kontextbereich der Lehrkraft für die KI.
// Ein eigenes Programm, das moocp startet und über MCP anspricht (E35). Was es
// für moocp tut, steht in der Schnittstelle des Beispiel-Plugins; die
// Werkzeuge stehen in lib/src/werkzeuge.dart.
//
// Aufruf: context --port <Zahl> [--einstellungen <Datei>] [--fenster <Programm>] [--entwicklung]
// Der Schlüssel kommt aus MOOCP_PLUGIN_SCHLUESSEL, nie von der Kommandozeile.
// --einstellungen ersetzt den Ort der Einstellungsdatei (Vorgabe: im Datenordner
// des Plugins, siehe standardEinstellungenPfad); --entwicklung hält das Plugin am
// Leben, wenn seine Standardeingabe endet (Entwicklung von Hand).
import 'dart:io';

import 'package:contextmanager/src/einstellungen.dart';
import 'package:contextmanager/src/einstellungsfenster.dart';
import 'package:contextmanager/src/server.dart';

const schluesselVariable = 'MOOCP_PLUGIN_SCHLUESSEL';

Future<void> main(List<String> argumente) async {
  final port = _port(argumente);
  final schluessel = Platform.environment[schluesselVariable] ?? '';
  // Ohne Port oder Schlüssel gibt es nichts anzubieten: Ein Plugin ohne
  // Schlüssel stünde jedem Programm auf dem Rechner offen.
  if (port == null || schluessel.isEmpty) {
    stderr.writeln('context: needs --port <number> and $schluesselVariable.');
    exit(2);
  }
  final einstellungen = File(
    _wert(argumente, '--einstellungen') ?? standardEinstellungenPfad(),
  );

  // --fenster nennt ein Programm des Fensters, das ohne Auspacken startet
  // (Entwicklung, entwickeln.sh); sonst gilt das ausgelieferte (E8, E11).
  final fensterProgramm = _wert(argumente, '--fenster');
  final fenster = fensterProgramm == null
      ? Einstellungsfenster.standard(einstellungen: einstellungen)
      : Einstellungsfenster(programm: fensterProgramm, einstellungen: einstellungen);
  final server = kontextServer(
    port: port,
    schluessel: schluessel,
    einstellungen: einstellungen,
    fenster: fenster,
  );
  await server.start();
  // Das Fenster endet mit dem Plugin, auf jedem Weg des Endes (E8). exit(0)
  // läuft immer, auch wenn das Aufräumen scheitert.
  var endet = false;
  Future<void> enden() async {
    if (endet) return;
    endet = true;
    try {
      await fenster.beenden();
      await server.stop();
    } finally {
      exit(0);
    }
  }

  // Vor dem Öffnen des Fensters: Ein Signal, das gleich danach kommt, darf das
  // Fenster nicht zurücklassen.
  // SIGTERM gibt es nur unter Linux und macOS; unter Windows wirft watch().
  // Dort endet das Plugin über die Standardeingabe (unten) oder Strg+C.
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => enden());
  }
  ProcessSignal.sigint.watch().listen((_) => enden());

  // Gibt es noch keine Einstellungen, öffnet die Lehrkraft das Fenster gleich (E8).
  if (!await einstellungen.exists()) await fenster.beiAusfall();

  // Zum Entwickeln von Hand: die Standardeingabe gehört nicht moocp.
  if (argumente.contains('--entwicklung')) return;

  // Endet die Standardeingabe, ist moocp fort: aufräumen und enden.
  stdin.listen((_) {}, onDone: enden);
}

String? _wert(List<String> argumente, String name) {
  final i = argumente.indexOf(name);
  if (i < 0 || i + 1 >= argumente.length) return null;
  return argumente[i + 1];
}

int? _port(List<String> argumente) {
  final wert = _wert(argumente, '--port');
  final port = wert == null ? null : int.tryParse(wert);
  return port != null && port > 0 && port < 65536 ? port : null;
}
