import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import 'app.dart';
import 'einstellungen.dart';
import 'schluessel.dart';
import 'speicher.dart';
import 'werkzeuge.dart';

/// Der MCP-Server des Plugins auf 127.0.0.1 nach den Regeln von moocp (E35):
/// Streamable HTTP unter `/mcp`, jede Anfrage mit dem Schlüssel, in konstanter
/// Zeit geprüft.
StreamableMcpServer kontextServer({
  required int port,
  required String schluessel,
  required File einstellungen,
}) {
  return StreamableMcpServer(
    serverFactory: (_) =>
        _mcpServer(() => oeffneKontextbereich(einstellungen), schluessel),
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
  Future<LokalerSpeicher> Function() oeffnen,
  String schluessel,
) {
  final server = McpServer(
    const Implementation(name: 'context', version: '0.1.0'),
  );
  final app = AppAnschluss(
    adresse: () => _adresseDerApp(server),
    schluessel: schluessel,
  );
  registriereWerkzeuge(server, oeffnen, app);
  return server;
}

/// Die Adresse der App für Plugins, die moocp beim `initialize` dieser Sitzung
/// nennt (E35); null, wenn sie fehlt.
Uri? _adresseDerApp(McpServer server) {
  final moocp = server.server.getClientCapabilities()?.experimental?['moocp'];
  final adresse = moocp is Map ? moocp['adresse'] : null;
  return adresse is String ? Uri.tryParse(adresse) : null;
}
