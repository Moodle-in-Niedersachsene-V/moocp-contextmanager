# Änderungsprotokoll

## Unveröffentlicht

- Ein Wegweiser `CONTEXT-LINK.md` im Materialordner zeigt auf die passende Stelle im Kontextbereich. Den Ordner wählt die Lehrkraft im Ordnerdialog von moocp, und jede Änderung wird vorher freigegeben.
- Bei parallelen Klassen hat der Wegweiser je Klasse einen Eintrag mit eigener Bezeichnung; ein neuer Eintrag mit gleicher Bezeichnung ersetzt nur den alten.
- Antwortet ein WebDAV-Server erst bei der Prüfung des Stands nicht, kommt der Schreibvorgang in den Ausstand wie bei jedem anderen Ausfall.
- Ein WebDAV-Server, der Benutzer oder Passwort ablehnt, meldet das (401); einer, der die Berechtigung für die Datei verweigert, meldet das getrennt (403).
- Eine Auflistung mit Namen, die einen Schrägstrich oder Steuerzeichen enthalten, wird abgewiesen, statt sie stillschweigend zu übergehen.
- Eine Antwort des WebDAV-Servers über 8 MiB wird abgebrochen, statt sie ganz zu laden.
- Ein Ausstand, dessen Ort sich nicht öffnen lässt, bleibt stehen und wird als Fehler genannt; die übrigen Einträge der Wiederholung bleiben vollständig gemeldet.
