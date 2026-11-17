import 'package:mcp_dart/mcp_dart.dart';

import 'app.dart';
import 'archiv.dart';
import 'art.dart';
import 'ausstand.dart';
import 'einstellungsfenster.dart';
import 'fehler.dart';
import 'inhaltsverzeichnis.dart';
import 'konflikt.dart';
import 'ort.dart';
import 'pfad.dart';
import 'schreibauftrag.dart';
import 'speicher.dart';
import 'start.dart';
import 'wegweiser.dart';

/// Die Werkzeuge des Plugins am MCP-Server. Jeder Aufruf öffnet den
/// Kontextbereich neu über [zugang], damit eine Änderung der Einstellungen
/// sofort wirkt und ein Fehler sofort sichtbar wird. Fehler kommen als Ergebnis
/// mit `isError`, nie als Ausnahme.
void registriereWerkzeuge(
  McpServer server,
  Ortszugang zugang,
  AppAnschluss app,
  Ausstand ausstand,
  Einstellungsfenster fenster,
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
        final speicher = await zugang.oeffnen();
        final eintraege = await speicher.liste(pfad);
        final liste = eintraege.isEmpty
            ? 'The folder is empty.'
            : eintraege
                  .map((e) => e.istOrdner ? '${e.name}/' : e.name)
                  .join('\n');
        // Konfliktkopien des Ordners stehen unter der Liste; nur
        // dieser Ordner, Unterordner meldet context_start.
        final kopien = konfliktkopienIn(pfadTeile(pfad).join('/'), eintraege);
        if (kopien.isEmpty) return liste;
        return '$liste\n\n'
            'conflict copies: a sync client made these; compare each pair and keep one. '
            'The plugin deletes nothing.\n'
            '${konfliktZeilen(kopien, vollerPfad: false).join('\n')}';
      });
    },
  );

  server.registerTool(
    'context_read',
    description:
        'Reads one text file of the teacher\'s context area and returns its version '
        '(a hash of the whole file, needed for context_write) and its content. Files of '
        '$grenzeZeilen lines or fewer come back whole. Longer files come back as a table '
        'of contents of their ## and ### headings with line ranges. Then call again with '
        '"abschnitt" set to one heading text to read that section, or with "ganz": true '
        'to read the whole file. Paths are relative to the context area; paths that leave '
        'it are refused.',
    inputSchema: JsonSchema.object(
      properties: {
        'pfad': JsonSchema.string(
          description:
              'File relative to the context area, for example "index.md".',
        ),
        'abschnitt': JsonSchema.string(
          description:
              'Heading text of one section to read, as listed in the table of contents, '
              'for example "Woche 2". Not together with ganz.',
        ),
        'ganz': JsonSchema.boolean(
          description:
              'true returns the whole file, also when it is longer than $grenzeZeilen lines. '
              'Not together with abschnitt.',
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
        final abschnitt = _optionalerText(args, 'abschnitt');
        final ganz = _optionalerBool(args, 'ganz') ?? false;
        final speicher = await zugang.oeffnen();
        final gelesen = await speicher.lese(pfad);
        return leseAusschnitt(pfad, gelesen, abschnitt: abschnitt, ganz: ganz);
      });
    },
  );

  server.registerTool(
    'context_write',
    description:
        'Creates a Markdown file in the teacher\'s context area, or replaces one. '
        'Omit version only to create a new file. To replace a file, pass the version '
        'from context_read; the write stops with a conflict if the file changed since. '
        'Whether moocp asks the teacher for approval depends on the teacher\'s approval level and on '
        'art, the kind of change: journal, correction, plan_change, plan_addition, new_file '
        'or root_file. Files under journal/ cannot be replaced; use context_append. The write '
        'is read back before it counts as verified. If the context area does not answer, the write '
        'is kept as a pending write and is not saved yet; do not write it again (see context_start). '
        'Only .md files; paths that leave the '
        'context area are refused.',
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
      zugang: zugang,
      app: app,
      ausstand: ausstand,
      anhaengen: false,
    ),
  );

  server.registerTool(
    'context_append',
    description:
        'Appends text to a Markdown file of the teacher\'s context area, for example a '
        'journal entry. Pass the version from context_read to append to an existing file; '
        'omit it only when the file does not exist yet, and it is created. The write stops '
        'with a conflict if the file changed since it was read. Whether moocp asks the '
        'teacher for approval depends on the teacher\'s approval level and on art (see context_write). '
        'The append is read back before it counts as verified. If the context area does not answer, '
        'the append is kept as a pending write and is not saved yet (see context_start). Only .md files; paths that '
        'leave the context area are refused.',
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
      zugang: zugang,
      app: app,
      ausstand: ausstand,
      anhaengen: true,
    ),
  );

  server.registerTool(
    'context_link',
    description:
        'Writes the signpost file CONTEXT-LINK.md into a folder of the teacher\'s material. The '
        'teacher picks the folder in moocp\'s folder dialog; you never name it. Each entry names '
        'a place inside the context area (relative path, must exist; a trailing slash for a folder) '
        'and one descriptive line. Give a "bezeichnung" for parallel classes; an entry with the same '
        'label replaces the old one, the others stay. The teacher is asked for approval on every '
        'approval level. Nothing else is written outside the context area.',
    inputSchema: JsonSchema.object(
      properties: {
        'eintraege': JsonSchema.array(
          minItems: 1,
          description: 'One entry per class or place.',
          items: JsonSchema.object(
            properties: {
              'pfad': JsonSchema.string(
                description: 'Place relative to the context area, for example "klassen/7b/index.md" or "klassen/7b/".',
              ),
              'beschreibung': JsonSchema.string(
                description: 'One line in German on what is there, for example "Mathematik, Klasse 7b, 2026/27".',
              ),
              'bezeichnung': JsonSchema.string(
                description: 'Optional label for parallel classes, for example "Gruppe A".',
              ),
            },
            required: ['pfad', 'beschreibung'],
          ),
        ),
      },
      required: ['eintraege'],
    ),
    annotations: const ToolAnnotations(
      title: 'Write signpost',
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      return _ausfuehren(() async {
        final eintraege = _wegweiserEintraege(args);
        return verknuepfeWegweiser(
          zugang: zugang,
          app: app,
          aufruf: _aufruf(extra),
          eintraege: eintraege,
        );
      });
    },
  );

  server.registerTool(
    'context_archive',
    description:
        'Moves Markdown files of one folder of the teacher\'s context area into the folder '
        'archive/ inside it, for example the files of the old layout before a unit is restructured. '
        'Pass the folder ("ordner", empty for the root) and the file names directly inside it ("dateien"). '
        'Nothing is deleted or overwritten: if a target already exists, nothing is moved. Journals are never '
        'moved. The teacher is asked for approval like for a new file. If the context area does not answer, '
        'nothing is moved and nothing is kept as a pending write; repeat the call later. Paths that leave the '
        'context area are refused.',
    inputSchema: JsonSchema.object(
      properties: {
        'ordner': JsonSchema.string(
          description: 'Folder relative to the context area, for example "klassen/7b/mathe"; empty for the root.',
        ),
        'dateien': JsonSchema.array(
          minItems: 1,
          description: 'File names directly inside the folder, for example ["plan.md", "status.md"].',
          items: JsonSchema.string(),
        ),
        'zusammenfassung': JsonSchema.string(
          description: 'A short summary in German for the approval dialog of the teacher.',
          maxLength: 500,
        ),
      },
      required: ['ordner', 'dateien', 'zusammenfassung'],
    ),
    annotations: const ToolAnnotations(
      title: 'Archive context files',
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      return _ausfuehren(() async {
        return archiviere(
          zugang: zugang,
          app: app,
          aufruf: _aufruf(extra),
          ordner: _text(args, 'ordner'),
          dateien: _textListe(args, 'dateien'),
          zusammenfassung: _text(args, 'zusammenfassung'),
        );
      });
    },
  );

  server.registerTool(
    'context_settings',
    description:
        'Opens the settings window of the context plugin, where the teacher enters the '
        'location (a local folder or a WebDAV server) and its password. Use it when the '
        'context area does not answer or when the teacher asks for the settings. The window '
        'also opens by itself on the first start and when the location does not answer. '
        'This tool only opens the window and returns no values: the assistant never sees, '
        'sets or repeats the location or the password.',
    inputSchema: JsonSchema.object(properties: {}),
    annotations: const ToolAnnotations(
      title: 'Open settings window',
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final ergebnis = await fenster.oeffnen();
      return CallToolResult(
        content: [TextContent(text: ergebnis.meldung)],
        isError: ergebnis.stand == FensterStand.nichtGestartet,
      );
    },
  );

  server.registerTool(
    'context_start',
    description:
        'Call this first in every session. In one answer it returns whether the context '
        'area answers (or the context gap and its cause), the pending writes that are not '
        'yet saved, the conflict copies of sync clients with both file names, the root index.md '
        '(CONTEXT.md of the old layout when index.md is missing) and the root habits.md. Pass "wiederholen": true to '
        'replay the pending writes now: each one is checked for changes like a new write '
        'and approved by the teacher again before it is written. A changed target is reported '
        'and never overwritten. Pending writes are not context: read the context area for '
        'what is saved.',
    inputSchema: JsonSchema.object(
      properties: {
        'wiederholen': JsonSchema.boolean(
          description: 'true replays the pending writes now; default false.',
        ),
      },
    ),
    annotations: const ToolAnnotations(
      title: 'Start context session',
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      return _ausfuehren(() async {
        final wiederholen = _optionalerBool(args, 'wiederholen') ?? false;
        return leseStart(
          zugang: zugang,
          ausstand: ausstand,
          app: app,
          aufruf: _aufruf(extra),
          wiederholen: wiederholen,
        );
      });
    },
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
      description:
          'A short summary in German for the approval dialog of the teacher.',
      maxLength: 500,
    ),
    'version': JsonSchema.string(
      description: 'The version from context_read of the file that is changed. Omit only to create a new file.',
    ),
  },
  required: ['pfad', 'inhalt', 'art', 'zusammenfassung'],
);

/// Der Ablauf eines Schreibens: Ort öffnen, Stand prüfen, Freigabe, Ort erneut
/// öffnen, schreiben, zurücklesen. Antwortet der Ort nicht, kommt der Auftrag in den
/// Ausstand und die Antwort sagt, dass er noch nicht gespeichert ist (E2).
/// Konflikte und ungültige Aufträge werden nie zurückgestellt.
Future<CallToolResult> _schreibVorgang({
  required Map<String, dynamic> args,
  required String? aufruf,
  required Ortszugang zugang,
  required AppAnschluss app,
  required Ausstand ausstand,
  required bool anhaengen,
}) {
  return _ausfuehren(() async {
    final auftrag = _auftragAus(args, anhaengen: anhaengen);

    final Kontextspeicher speicher;
    try {
      speicher = await zugang.oeffnen();
    } on KontextNichtErreichbar catch (f) {
      return _zurueckgestellt(auftrag, zugang, ausstand, f.meldung);
    }
    // Vor der Frage prüfen: Ein Vorgang, der ohnehin scheitert, fragt nicht.
    // Antwortet der Ort schon hier nicht, gilt dasselbe wie beim Öffnen: Ausstand.
    try {
      await speicher.pruefeStand(auftrag.pfad, erwartet: auftrag.version);
    } on KontextNichtErreichbar catch (f) {
      return _zurueckgestellt(auftrag, zugang, ausstand, f.meldung);
    }

    final ausgang = await frageFreigabe(
      app,
      aufruf,
      auftrag,
      titel: anhaengen
          ? 'Im Kontextbereich ergänzen?'
          : 'Im Kontextbereich speichern?',
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

    // Nach der Freigabe noch einmal öffnen: Der Ort kann in der Wartezeit verschwunden sein.
    // Antwortet er auch beim Schreiben nicht, kommt der Vorgang in den Ausstand. Die Wiederholung
    // prüft den Stand: Hat der Server doch geschrieben, meldet sie einen Konflikt statt zu überschreiben.
    final Geschrieben geschrieben;
    try {
      final offen = await zugang.oeffnen();
      geschrieben = await schreibeAuftrag(offen, auftrag);
    } on KontextNichtErreichbar catch (f) {
      return _zurueckgestellt(auftrag, zugang, ausstand, f.meldung);
    }
    if (!geschrieben.verifiziert) {
      throw KontextFehler(
        "not verified: '${auftrag.pfad}' does not read back with the written content. Read it before going on.",
      );
    }
    return 'verified\n'
        'path: ${auftrag.pfad}\n'
        'version: ${geschrieben.version}';
  });
}

/// Hält einen Auftrag im Ausstand, weil der Ort nicht antwortet. Die Antwort sagt
/// deutlich, dass nichts im Kontextbereich steht, und dass er nicht noch einmal
/// geschrieben werden soll.
Future<String> _zurueckgestellt(
  Schreibauftrag auftrag,
  Ortszugang zugang,
  Ausstand ausstand,
  String grund,
) async {
  final eintrag = await ausstand.merke(auftrag, ort: await zugang.kennung());
  return 'not saved yet: the context area does not answer ($grund)\n'
      'The write is kept as pending write ${eintrag.id}; nothing was written to the '
      'context area. Do not write it again: context_start with "wiederholen": true '
      'replays it once the location answers.\n'
      'path: ${auftrag.pfad}';
}

/// Prüft die Argumente eines Schreibwerkzeugs und baut den Auftrag. Ungültiges
/// wird hier abgewiesen, bevor etwas gespeichert oder gefragt wird.
Schreibauftrag _auftragAus(
  Map<String, dynamic> args, {
  required bool anhaengen,
}) {
  final pfad = _text(args, 'pfad');
  final inhalt = _text(args, 'inhalt');
  final zusammenfassung = _text(args, 'zusammenfassung');
  final art = _art(args);
  final version = _optionalerText(args, 'version');
  schreibTeile(pfad);
  if (zusammenfassung.trim().isEmpty) {
    throw const KontextFehler(
      "The summary is empty: pass a short German summary of the change in 'zusammenfassung'.",
    );
  }
  if (zusammenfassung.length > 500) {
    throw const KontextFehler(
      'The summary is longer than 500 characters; shorten it and try again.',
    );
  }
  final auftrag = Schreibauftrag(
    pfad: pfad,
    inhalt: inhalt,
    art: art,
    zusammenfassung: zusammenfassung,
    version: version,
    anhaengen: anhaengen,
  );
  if (art == Art.rootFile && !auftrag.imWurzelordner) {
    throw const KontextFehler(
      'root_file is only for a file directly in the context root; use new_file or another kind for a file in a folder.',
    );
  }
  // Die Bindung hängt am Pfad, nicht an der Art, die die KI nennt: Ein Journal
  // wird nur angehängt, und `art: journal` gilt nur für eine Journaldatei. Sonst
  // würde eine Planänderung als Journaleintrag auf Stufe alle nie gefragt.
  if (art == Art.journal && !istJournalPfad(pfad)) {
    throw KontextFehler(
      "The kind 'journal' is only for a journal file (journal/YYYY-MM-DD.md or journal-*.md), not for '$pfad'; use another kind.",
    );
  }
  if (!anhaengen && istJournalPfad(pfad)) {
    throw KontextFehler(
      "A journal is only appended, never replaced: use context_append for '$pfad'.",
    );
  }
  return auftrag;
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

/// Die Einträge von `context_link`. Die Argumente werden hier auf Typ und Pflichtfelder
/// geprüft; Inhalt und Pfade prüft [pruefeEintraege].
List<WegweiserEintrag> _wegweiserEintraege(Map<String, dynamic> args) {
  final liste = args['eintraege'];
  if (liste is! List) {
    throw const KontextFehler("The argument 'eintraege' must be a list.");
  }
  return [
    for (final eintrag in liste)
      () {
        if (eintrag is! Map) {
          throw const KontextFehler(
            "Each entry of 'eintraege' must be an object with 'pfad' and 'beschreibung'.",
          );
        }
        final map = eintrag.cast<String, dynamic>();
        return WegweiserEintrag(
          bezeichnung: _optionalerText(map, 'bezeichnung'),
          pfad: _text(map, 'pfad'),
          beschreibung: _text(map, 'beschreibung'),
        );
      }(),
  ];
}

/// Eine Liste von Texten als Argument; fehlt sie oder ist sie anders, ist das ein Fehler.
List<String> _textListe(Map<String, dynamic> args, String name) {
  final wert = args[name];
  if (wert is! List || wert.any((e) => e is! String)) {
    throw KontextFehler("The argument '$name' must be a list of text.");
  }
  return wert.cast<String>();
}

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

bool? _optionalerBool(Map<String, dynamic> args, String name) {
  final wert = args[name];
  if (wert == null) return null;
  if (wert is! bool)
    throw KontextFehler("The argument '$name' must be true or false.");
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
