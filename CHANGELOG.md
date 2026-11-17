# Changelog

## Unreleased

- Neu: Die KI kann Markdown-Dateien im Kontextbereich anlegen, ersetzen (`context_write`) und Text anhängen (`context_append`). Jede Änderung fragt die Lehrkraft in moocp je nach Freigabestufe; eine Datei, die sich seit dem Lesen geändert hat, wird nicht überschrieben, und ein Journal wird nur angehängt.
- Neu: Das Plugin „context“ zeigt der KI den Kontextbereich aus einem lokalen Ordner: Ordner auflisten und Textdateien mit Version lesen. Pfade, die aus dem Ordner hinausführen, werden abgewiesen.
- Geändert: Eine Einstellungsdatei, die nicht gelesen werden kann, nennt das als eigenen Grund; ein relativer Ordnerpfad wird abgewiesen.
