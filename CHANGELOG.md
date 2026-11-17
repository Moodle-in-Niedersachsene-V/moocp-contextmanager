# Changelog

## Unreleased

- Neu: Ein Einstellungsfenster richtet den Kontextbereich ein: Ordner auf dem Rechner oder WebDAV-Server mit Adresse, Benutzer und verdecktem Passwort. „Verbindung prüfen“ zeigt, ob der Ort antwortet, oder nennt die Ursache; „Speichern“ trägt das Passwort in den Schlüsselbund des Systems ein.
- Neu: Das Einstellungsfenster öffnet sich beim ersten Start ohne Einstellungen und, einmal je Ausfall, wenn der Kontextbereich nicht antwortet. Die KI kann es mit `context_settings` öffnen; sie sieht und setzt dabei keine Werte.
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
- Neu: Ein Wegweiser `CONTEXT-LINK.md` im Materialordner zeigt auf die passende Stelle im Kontextbereich. Den Ordner wählt die Lehrkraft im Ordnerdialog von moocp, und jede Änderung wird vorher freigegeben.
- Neu: Bei parallelen Klassen hat der Wegweiser je Klasse einen Eintrag mit eigener Bezeichnung; ein neuer Eintrag mit gleicher Bezeichnung ersetzt nur den alten.
- Geändert: Antwortet ein WebDAV-Server erst bei der Prüfung des Stands nicht, kommt der Schreibvorgang in den Ausstand wie bei jedem anderen Ausfall.
- Geändert: Ein WebDAV-Server, der Benutzer oder Passwort ablehnt, meldet das (401); einer, der die Berechtigung für die Datei verweigert, meldet das getrennt (403).
- Geändert: Eine Auflistung mit Namen, die einen Schrägstrich oder Steuerzeichen enthalten, wird abgewiesen, statt sie stillschweigend zu übergehen.
- Geändert: Eine Antwort des WebDAV-Servers über 8 MiB wird abgebrochen, statt sie ganz zu laden.
- Geändert: Ein Ausstand, dessen Ort sich nicht öffnen lässt, bleibt stehen und wird als Fehler genannt; die übrigen Einträge der Wiederholung bleiben vollständig gemeldet.
- Neu: `context_archive` verschiebt Dateien eines Ordners nach `archive/` in diesem Ordner, etwa das alte Layout vor einem Umbau. Nichts wird gelöscht oder überschrieben; die Lehrkraft gibt die Verschiebung frei wie eine neue Datei.
- Neu: Hat die Wurzel eines Kontextbereichs keine `index.md`, aber eine `CONTEXT.md` aus Coursepilot, liest `context_start` diese als Index. Die alten Dateien (`CONTEXT.md`, `status.md`, `journal-*.md`) lassen sich wie neue auflisten, lesen und anhängen.
- Neu: Konfliktkopien von Sync-Clients (Syncthing, Nextcloud, Dropbox, Seafile) werden mit beiden Dateinamen gemeldet, unter der Liste von `context_list` und in der Antwort von `context_start`. Das Plugin ändert oder löscht sie nicht.
- Geändert: Journale in jedem Projektordner (`journal/`) und alte `journal-*.md` auf jeder Ebene werden nur angehängt, nie ersetzt. Bisher galt das nur in der Wurzel.
