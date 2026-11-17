import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

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
    serverFactory: (_) => _mcpServer(() => oeffneKontextbereich(einstellungen)),
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

McpServer _mcpServer(Future<LokalerSpeicher> Function() oeffnen) {
  final server = McpServer(
    const Implementation(name: 'context', version: '0.1.0'),
  );
  registriereWerkzeuge(server, oeffnen);
  return server;
}
