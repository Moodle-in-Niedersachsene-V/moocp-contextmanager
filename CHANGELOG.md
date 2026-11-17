# Changelog

## Unreleased

- Neu: Der Kontextbereich kann auf einem WebDAV-Server liegen. Adresse und Benutzer stehen in den Einstellungen, das Passwort im Schlüsselbund des Systems. Antwortet der Server nicht, gilt dasselbe wie bei einem fehlenden Ordner: Der Schreibvorgang wartet im Ausstand.
- Geändert: Der Ausstand ist nur für die Benutzerin lesbar. Eine Wiederholung schreibt einen Vorgang nur an den Ort, an dem er entstand; für einen anderen Ort meldet sie ihn und lässt ihn stehen.
- Neu: Die KI kann Markdown-Dateien im Kontextbereich anlegen, ersetzen (`context_write`) und Text anhängen (`context_append`). Jede Änderung fragt die Lehrkraft in moocp je nach Freigabestufe; eine Datei, die sich seit dem Lesen geändert hat, wird nicht überschrieben, und ein Journal wird nur angehängt.
- Neu: `context_start` beginnt jede Sitzung: Lage des Kontextbereichs, offene Vorgänge, Wurzelindex und Wurzelgewohnheiten. Mit `wiederholen` werden offene Vorgänge nachgetragen.
- Neu: Antwortet der Kontextbereich nicht (Ordner fehlt oder ist nicht lesbar), bleibt der Schreibvorgang mit seinem Inhalt erhalten, wird nicht geschrieben und später nach neuer Freigabe nachgetragen; die KI sagt, dass er noch nicht gespeichert ist.
- Neu: Das Plugin „context“ zeigt der KI den Kontextbereich aus einem lokalen Ordner: Ordner auflisten und Textdateien mit Version lesen. Pfade, die aus dem Ordner hinausführen, werden abgewiesen.
- Neu: Dateien über 100 Zeilen liest die KI zuerst über ihr Inhaltsverzeichnis aus den Überschriften; einen Abschnitt fordert sie über seine Überschrift an, die ganze Datei nur auf ausdrückliche Bitte.
- Geändert: Journaleinträge werden auch bei anderer Groß- und Kleinschreibung (etwa `Journal/`) nur angehängt, nie ersetzt.
- Geändert: Ein Abschnitt lässt sich auch mit seiner Markierung anfordern (etwa „## Woche 2“). Ein Codeblock schließt sich nur mit demselben Zaun (``` oder ~~~ in gleicher Länge); eine Überschrift darin zählt nicht.
- Geändert: Eine Einstellungsdatei, die nicht gelesen werden kann, nennt das als eigenen Grund; ein relativer Ordnerpfad wird abgewiesen.
