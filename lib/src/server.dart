import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'ausstand.dart';
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
}) {
  // Der Ausstand liegt neben der Einstellungsdatei, im Datenordner des Plugins.
  final ausstand = Ausstand(
    Directory(p.join(einstellungen.parent.path, 'ausstand')),
  );
  final zugang = Ortszugang(
    einstellungen: einstellungen,
    schluesselbund: schluesselbund ?? SystemSchluesselbund(),
  );
  return StreamableMcpServer(
    serverFactory: (_) => _mcpServer(zugang, schluessel, ausstand),
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

McpServer _mcpServer(Ortszugang zugang, String schluessel, Ausstand ausstand) {
  final server = McpServer(
    const Implementation(name: 'context', version: '0.1.0'),
  );
  final app = AppAnschluss(
    adresse: () => _adresseDerApp(server),
    schluessel: schluessel,
  );
  registriereWerkzeuge(server, zugang, app, ausstand);
  return server;
}

/// Die Adresse der App für Plugins, die moocp beim `initialize` dieser Sitzung
/// nennt (E35); null, wenn sie fehlt.
Uri? _adresseDerApp(McpServer server) {
  final moocp = server.server.getClientCapabilities()?.experimental?['moocp'];
  final adresse = moocp is Map ? moocp['adresse'] : null;
  return adresse is String ? Uri.tryParse(adresse) : null;
}
