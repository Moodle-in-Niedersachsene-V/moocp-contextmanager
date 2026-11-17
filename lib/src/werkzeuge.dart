import 'package:mcp_dart/mcp_dart.dart';

import 'fehler.dart';
import 'speicher.dart';

/// Die Werkzeuge des Plugins am MCP-Server. Jeder Aufruf öffnet den
/// Kontextbereich neu über [oeffnen] (siehe `oeffneKontextbereich`), damit
/// eine Änderung der Einstellungen sofort wirkt und ein Fehler sofort sichtbar
/// wird. Fehler kommen als Ergebnis mit `isError`, nie als leere Antwort.
void registriereWerkzeuge(
  McpServer server,
  Future<LokalerSpeicher> Function() oeffnen,
) {
  server.registerTool(
    'context_list',
    description:
        'Lists the files and folders directly inside a folder of the teacher\'s '
        'context area. Folders end with a slash. Use an empty path for the root. '
        'Paths are relative to the context area; paths that leave it are refused.',
    inputSchema: JsonSchema.object(
      properties: {
        'pfad': JsonSchema.string(
          description: 'Folder relative to the context area; empty for the root.',
        ),
      },
    ),
    annotations: const ToolAnnotations(
      title: 'List context folder',
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final pfad = (args['pfad'] as String?) ?? '';
      return _ausfuehren(() async {
        final speicher = await oeffnen();
        final eintraege = await speicher.liste(pfad);
        if (eintraege.isEmpty) return 'The folder is empty.';
        return eintraege.map((e) => e.istOrdner ? '${e.name}/' : e.name).join('\n');
      });
    },
  );

  server.registerTool(
    'context_read',
    description:
        'Reads one text file of the teacher\'s context area and returns its content '
        'and its version (a hash of the content). Paths are relative to the context '
        'area; paths that leave it are refused.',
    inputSchema: JsonSchema.object(
      properties: {
        'pfad': JsonSchema.string(
          description: 'File relative to the context area, for example "index.md".',
        ),
      },
      required: ['pfad'],
    ),
    annotations: const ToolAnnotations(
      title: 'Read context file',
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final pfad = args['pfad'] as String;
      return _ausfuehren(() async {
        final speicher = await oeffnen();
        final gelesen = await speicher.lese(pfad);
        return 'path: $pfad\n'
            'version: ${gelesen.version}\n'
            '\n'
            '${gelesen.text}';
      });
    },
  );
}

/// Führt die Arbeit aus und macht aus jedem bekannten Fehler ein Ergebnis mit
/// `isError`: Die KI bekommt den Grund, kein Weiterarbeiten.
Future<CallToolResult> _ausfuehren(Future<String> Function() arbeit) async {
  try {
    return CallToolResult(content: [TextContent(text: await arbeit())]);
  } on KontextFehler catch (f) {
    return CallToolResult(content: [TextContent(text: f.meldung)], isError: true);
  }
}
