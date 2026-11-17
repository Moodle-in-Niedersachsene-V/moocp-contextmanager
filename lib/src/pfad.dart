import 'package:path/path.dart' as p;

import 'fehler.dart';

/// Die Regeln für Pfade im Kontextbereich, für jeden Ort gleich: Der Pfad ist
/// relativ zur Wurzel, Schrägstriche trennen, und nichts darf hinausführen.
/// Ein Pfad, der hinausführt (`..`, absolut, `~`), wird abgewiesen, bevor etwas
/// gelesen oder geschrieben wird. Verknüpfungen prüft der lokale Ort selbst.
const meldungAusserhalb =
    'The path is outside the context area and is refused.';

/// Die Bestandteile eines relativen Pfads (leere und `.`-Teile fallen weg).
List<String> pfadTeile(String relativ) {
  // Steuerzeichen (auch Zeilenende und Tab) haben in einem Dateinamen nichts zu suchen.
  if (relativ.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
    throw const KontextFehler(
      'The path contains a control character and is not valid.',
    );
  }
  if (p.posix.isAbsolute(relativ) ||
      p.windows.isAbsolute(relativ) ||
      relativ.startsWith('~')) {
    throw const KontextFehler(meldungAusserhalb);
  }
  final teile = relativ
      .split('/')
      .where((t) => t.isNotEmpty && t != '.')
      .toList();
  if (teile.contains('..')) {
    throw const KontextFehler(meldungAusserhalb);
  }
  return teile;
}

/// Der Pfad für einen Schreibvorgang: wie beim Lesen, dazu nur `.md`-Dateien.
List<String> schreibTeile(String relativ) {
  final teile = pfadTeile(relativ);
  if (teile.isEmpty || teile.last == '.md' || !teile.last.endsWith('.md')) {
    throw const KontextFehler(
      'Only .md files can be written; the path must end in .md.',
    );
  }
  return teile;
}

/// Ob ein Pfad zum Journal gehört: Einträge unter `journal/` und das alte
/// Journal im Wurzelordner (`journal-*.md`, Coursepilot). Das Journal wird nur
/// angehängt, unabhängig davon, welche Art die KI angibt. Der Pfad allein
/// entscheidet, nicht die Art.
///
/// Der Vergleich ignoriert Groß- und Kleinschreibung: Auf macOS und Windows
/// ist `Journal/x.md` dieselbe Datei wie `journal/x.md`, und die Sperre
/// darf nicht über die Schreibweise umgangen werden.
bool istJournalPfad(String relativ) {
  final teile = relativ
      .split('/')
      .where((t) => t.isNotEmpty && t != '.')
      .map((t) => t.toLowerCase())
      .toList();
  if (teile.isEmpty) return false;
  if (teile.length > 1) return teile.first == 'journal';
  return teile.first.startsWith('journal-') && teile.first.endsWith('.md');
}
