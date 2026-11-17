import 'package:mcp_dart/mcp_dart.dart';

import 'app.dart';
import 'art.dart';
import 'fehler.dart';
import 'speicher.dart';

/// Die Werkzeuge des Plugins am MCP-Server. Jeder Aufruf öffnet den
/// Kontextbereich neu über [oeffnen] (siehe `oeffneKontextbereich`), damit
/// eine Änderung der Einstellungen sofort wirkt und ein Fehler sofort sichtbar
/// wird. Fehler kommen als Ergebnis mit `isError`, nie als Ausnahme.
void registriereWerkzeuge(
  McpServer server,
  Future<LokalerSpeicher> Function() oeffnen,
  AppAnschluss app,
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
          description:
              'Folder relative to the context area; empty for the root.',
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
      return _ausfuehren(() async {
        final pfad = _optionalerText(args, 'pfad') ?? '';
        final speicher = await oeffnen();
        final eintraege = await speicher.liste(pfad);
        if (eintraege.isEmpty) return 'The folder is empty.';
        return eintraege
            .map((e) => e.istOrdner ? '${e.name}/' : e.name)
            .join('\n');
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
          description:
              'File relative to the context area, for example "index.md".',
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
      return _ausfuehren(() async {
        final pfad = _text(args, 'pfad');
        final speicher = await oeffnen();
        final gelesen = await speicher.lese(pfad);
        return 'path: $pfad\n'
            'version: ${gelesen.version}\n'
            '\n'
            '${gelesen.text}';
      });
    },
  );

  server.registerTool(
    'context_write',
    description:
        'Creates a Markdown file in the teacher\'s context area, or replaces one. '
        'Omit version only to create a new file. To replace a file, pass the version '
        'from context_read; the write stops with a conflict if the file changed since. '
        'Every write asks the teacher for approval in moocp and is read back before it '
        'counts as verified. art names the kind of change: journal (use context_append '
        'instead), correction, plan_change, plan_addition, new_file or root_file. '
        'Only .md files; paths that leave the context area are refused.',
    inputSchema: _schreibSchema(
      mitInhalt: 'The whole new content of the file.',
    ),
    annotations: const ToolAnnotations(
      title: 'Write context file',
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async => _schreibVorgang(
      args: args,
      aufruf: _aufruf(extra),
      oeffnen: oeffnen,
      app: app,
      anhaengen: false,
    ),
  );

  server.registerTool(
    'context_append',
    description:
        'Appends text to a Markdown file of the teacher\'s context area, for example a '
        'journal entry. Pass the version from context_read to append to an existing file; '
        'omit it only when the file does not exist yet, and it is created. The write stops '
        'with a conflict if the file changed since it was read. Every append asks the '
        'teacher for approval in moocp (for journal entries on the highest approval level) '
        'and is read back before it counts as verified. art names the kind of change; see '
        'context_write. Only .md files; paths that leave the context area are refused.',
    inputSchema: _schreibSchema(mitInhalt: 'The text to append.'),
    annotations: const ToolAnnotations(
      title: 'Append to context file',
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async => _schreibVorgang(
      args: args,
      aufruf: _aufruf(extra),
      oeffnen: oeffnen,
      app: app,
      anhaengen: true,
    ),
  );
}

/// Die Eingabe eines Schreibwerkzeugs. Der Text ist Inhalt für die Datei; die
/// Zusammenfassung erscheint in der Freigabe der Lehrkraft.
JsonObject _schreibSchema({required String mitInhalt}) => JsonSchema.object(
  properties: {
    'pfad': JsonSchema.string(
      description: 'File relative to the context area, ending in .md, for example "journal/2026-11-17.md".',
    ),
    'inhalt': JsonSchema.string(description: mitInhalt),
    'art': JsonSchema.string(
      description: 'The kind of change; decides on which approval level the teacher is asked.',
      enumValues: [for (final a in Art.values) a.wert],
    ),
    'zusammenfassung': JsonSchema.string(
      description: 'A short summary in German (at most 500 characters) for the approval dialog of the teacher.',
    ),
    'version': JsonSchema.string(
      description: 'The version from context_read of the file that is changed. Omit only to create a new file.',
    ),
  },
  required: ['pfad', 'inhalt', 'art', 'zusammenfassung'],
);

/// Der Ablauf eines Schreibens: Stand prüfen, Freigabe, Stand erneut prüfen,
/// schreiben, zurücklesen. Scheitert ein Schritt, ist nichts geschrieben, außer
/// wenn das Zurücklesen abweicht; dann sagt die Antwort, dass es nicht geprüft ist.
Future<CallToolResult> _schreibVorgang({
  required Map<String, dynamic> args,
  required String? aufruf,
  required Future<LokalerSpeicher> Function() oeffnen,
  required AppAnschluss app,
  required bool anhaengen,
}) {
  return _ausfuehren(() async {
    final pfad = _text(args, 'pfad');
    final inhalt = _text(args, 'inhalt');
    final zusammenfassung = _text(args, 'zusammenfassung');
    final art = _art(args);
    final version = _optionalerText(args, 'version');
    if (zusammenfassung.length > 500) {
      throw const KontextFehler(
        'The summary is longer than 500 characters; shorten it and try again.',
      );
    }
    final imWurzelordner = _imWurzelordner(pfad);
    if (art == Art.rootFile && !imWurzelordner) {
      throw const KontextFehler(
        'root_file is only for a file directly in the context root; use new_file or another kind for a file in a folder.',
      );
    }
    if (!anhaengen && art == Art.journal) {
      throw KontextFehler(
        "A journal is only appended, never replaced: use context_append for '$pfad'.",
      );
    }

    final speicher = await oeffnen();
    // Vor der Frage prüfen: Ein Vorgang, der ohnehin scheitert, fragt nicht.
    await speicher.pruefeStand(pfad, erwartet: version);

    final ausgang = await app.freigabe(
      aufruf: aufruf,
      titel: anhaengen
          ? 'Im Kontextbereich ergänzen?'
          : 'Im Kontextbereich speichern?',
      zusammenfassung:
          'Datei: $pfad\nArt: ${art.bezeichnung}\n\n$zusammenfassung',
      ab: freigabestufeFuer(art, imWurzelordner: imWurzelordner),
    );
    switch (ausgang) {
      case Freigabeausgang.freigegeben:
        break;
      case Freigabeausgang.abgelehnt:
        throw const KontextFehler(
          'Not written: the teacher declined the approval.',
        );
      case Freigabeausgang.abgebrochen:
        throw const KontextFehler(
          'Not written: the approval was cancelled or timed out.',
        );
    }

    final geschrieben = anhaengen
        ? await speicher.haengeAn(pfad, inhalt, erwartet: version)
        : await speicher.schreibe(pfad, inhalt, erwartet: version);
    if (!geschrieben.verifiziert) {
      throw KontextFehler(
        "not verified: '$pfad' does not read back with the written content. Read it before going on.",
      );
    }
    return 'verified\n'
        'path: $pfad\n'
        'version: ${geschrieben.version}';
  });
}

Art _art(Map<String, dynamic> args) {
  final wert = _text(args, 'art');
  final art = Art.aus(wert);
  if (art == null) {
    throw KontextFehler(
      "The kind '$wert' is unknown; use one of: ${[for (final a in Art.values) a.wert].join(', ')}.",
    );
  }
  return art;
}

/// Ob der Pfad direkt am Wurzelordner liegt (ohne Ordner davor).
bool _imWurzelordner(String pfad) =>
    pfad.split('/').where((t) => t.isNotEmpty && t != '.').length == 1;

/// Das Token des laufenden Aufrufs, das moocp in `_meta` mitgibt.
String? _aufruf(RequestHandlerExtra extra) {
  final t = extra.meta?['moocp/aufruf'];
  return t is String ? t : null;
}

/// Ein Text-Argument; fehlt es oder hat es den falschen Typ, ist das ein
/// Fehler, der den Namen des Arguments nennt.
String _text(Map<String, dynamic> args, String name) {
  final wert = args[name];
  if (wert == null) throw KontextFehler("The argument '$name' is missing.");
  if (wert is! String)
    throw KontextFehler("The argument '$name' must be text.");
  return wert;
}

String? _optionalerText(Map<String, dynamic> args, String name) {
  final wert = args[name];
  if (wert == null) return null;
  if (wert is! String)
    throw KontextFehler("The argument '$name' must be text.");
  return wert;
}

/// Führt die Arbeit aus und macht aus jedem bekannten Fehler ein Ergebnis mit
/// `isError`: Die KI bekommt den Grund und den nächsten Schritt, kein Weiterarbeiten.
Future<CallToolResult> _ausfuehren(Future<String> Function() arbeit) async {
  try {
    return CallToolResult(content: [TextContent(text: await arbeit())]);
  } on KontextFehler catch (f) {
    return CallToolResult(
      content: [TextContent(text: f.meldung)],
      isError: true,
    );
  }
}
