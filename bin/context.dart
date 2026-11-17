// Das Plugin "context" von moocp: der Kontextbereich der Lehrkraft für die KI.
// Ein eigenes Programm, das moocp startet und über MCP anspricht (E35). Was es
// für moocp tut, steht in der Schnittstelle des Beispiel-Plugins; die
// Werkzeuge stehen in lib/src/werkzeuge.dart.
//
// Aufruf: context --port <Zahl> [--einstellungen <Datei>] [--entwicklung]
// Der Schlüssel kommt aus MOOCP_PLUGIN_SCHLUESSEL, nie von der Kommandozeile.
// --einstellungen ersetzt den Ort der Einstellungsdatei (Vorgabe: im Datenordner
// des Plugins, siehe standardEinstellungenPfad); --entwicklung hält das Plugin am
// Leben, wenn seine Standardeingabe endet (Entwicklung von Hand).
import 'dart:io';

import 'package:contextmanager/src/einstellungen.dart';
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

  final server = kontextServer(
    port: port,
    schluessel: schluessel,
    einstellungen: einstellungen,
  );
  await server.start();

  // Zum Entwickeln von Hand: die Standardeingabe gehört nicht moocp.
  if (argumente.contains('--entwicklung')) return;

  // Endet die Standardeingabe, ist moocp fort: aufräumen und enden.
  stdin.listen(
    (_) {},
    onDone: () async {
      await server.stop();
      exit(0);
    },
  );
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
