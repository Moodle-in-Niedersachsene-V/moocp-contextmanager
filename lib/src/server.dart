import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'ausstand.dart';
import 'einstellungsfenster.dart';
import 'ort.dart';
import 'schluessel.dart';
import 'schluesselbund.dart';
import 'werkzeuge.dart';

/// Der MCP-Server des Plugins auf 127.0.0.1 nach den Regeln von moocp (E35):
/// Streamable HTTP unter `/mcp`, jede Anfrage mit dem Schlüssel, in konstanter
/// Zeit geprüft.
StreamableMcpServer kontextServer({
  required int port,
  required String schluessel,
  required File einstellungen,
  Schluesselbund? schluesselbund,
  Einstellungsfenster? fenster,
}) {
  // Der Ausstand liegt neben der Einstellungsdatei, im Datenordner des Plugins.
  final ausstand = Ausstand(
    Directory(p.join(einstellungen.parent.path, 'ausstand')),
  );
  final einstellungsfenster =
      fenster ??
      Einstellungsfenster(
        programm: standardFensterProgramm(),
        einstellungen: einstellungen,
      );
  final zugang = Ortszugang(
    einstellungen: einstellungen,
    schluesselbund: schluesselbund ?? SystemSchluesselbund(),
    fenster: einstellungsfenster,
  );
  return StreamableMcpServer(
    serverFactory: (_) =>
        _mcpServer(zugang, schluessel, ausstand, einstellungsfenster),
    host: '127.0.0.1',
    port: port,
    path: '/mcp',
    enableJsonResponse: true,
    allowedHosts: const {'127.0.0.1', 'localhost'},
    authenticator: (anfrage) => gleichInKonstanterZeit(
      anfrage.headers.value(HttpHeaders.authorizationHeader),
      'Bearer $schluessel',
    ),
  );
}

McpServer _mcpServer(
  Ortszugang zugang,
  String schluessel,
  Ausstand ausstand,
  Einstellungsfenster fenster,
) {
  final server = McpServer(
    const Implementation(name: 'context', version: '0.1.1'),
  );
  final app = AppAnschluss(
    adresse: () => _adresseDerApp(server),
    schluessel: schluessel,
  );
  registriereWerkzeuge(server, zugang, app, ausstand, fenster);
  return server;
}

/// Die Adresse der App für Plugins, die moocp beim `initialize` dieser Sitzung
/// nennt (E35); null, wenn sie fehlt.
Uri? _adresseDerApp(McpServer server) {
  final moocp = server.server.getClientCapabilities()?.experimental?['moocp'];
  final adresse = moocp is Map ? moocp['adresse'] : null;
  final uri = adresse is String ? Uri.tryParse(adresse) : null;
  // moocp läuft auf diesem Rechner (A1). Eine andere Adresse bekäme den
  // Schlüssel des Plugins und das Token des Aufrufs nicht.
  const schleife = {'127.0.0.1', 'localhost', '::1'};
  if (uri == null || !schleife.contains(uri.host)) return null;
  return uri;
}
