# E5 Wegweiser im Materialordner

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md). Ausnahme zu A2 (nur der Kontextordner).

## Entscheidung

**Einzige Schreibstelle außerhalb der Wurzel.** `context_link` schreibt die Datei `CONTEXT-LINK.md` in einen Ordner der Lehrkraft, und nur diese Datei. Das ist die einzige Ausnahme von A2. Der Ordner kommt allein aus dem Ordnerdialog der App (`/v1/dialog/pfad`, E35); die KI nennt keinen Ordner, und die Antwort nennt ihn nie.

**Freigabe auf jeder Stufe.** Der Wegweiser wird mit `ab: keine` angefragt (E20). Die Stufe der Lehrkraft senkt das nicht. Die Freigabe nennt Datei, Einträge und, dass vorhandene Einträge mit gleicher Bezeichnung ersetzt werden.

**Ziele unter der Wurzel.** Jeder Eintrag zeigt auf eine vorhandene Datei oder einen vorhandenen Ordner unter der Wurzel. Der Pfad wird wie jeder Pfad geprüft (A2); die Wurzel selbst ist kein Ziel. Fehlt ein Ziel, wird vor dem Dialog abgewiesen, und nichts wird gefragt.

**Aufbau.** Eine feste Kopfzeile, danach je Eintrag ein Block aus `Bezeichnung:` (nur bei parallelen Klassen), `Pfad:` und `Beschreibung:` (eine Zeile). Die Wurzel steht nie in der Datei. Eine Datei mit anderem Aufbau wird nicht angefasst, sondern abgewiesen.

**Fortschreiben.** Ein Eintrag mit gleicher Bezeichnung ersetzt den alten an seiner Stelle; die übrigen bleiben; neue hängen hinten an. Der Eintrag ohne Bezeichnung ist höchstens einmal da.

**Stand.** Die Datei wird vor dem Dialog gelesen und nach der Freigabe erneut verglichen; hat sie sich geändert, wird nichts geschrieben. Geschrieben wird mit Rücklesen, und nur bei gleichen Bytes meldet das Werkzeug `verified` (E1, A3).

**Kein Ausstand.** Der Wegweiser schreibt nicht in die Wurzel. Antwortet der Kontextbereich nicht, scheitert der Aufruf mit Grund, und nichts wird zurückgestellt (E2 gilt nur für Schreibvorgänge in den Kontextbereich).

## Verworfen

- Den Ordner von der KI nennen lassen: Der Ordner ist eine Entscheidung der Lehrkraft, und der Dialog ist der einzige Weg dazu (A1, E35).
- Die Wurzel im Wegweiser nennen: Die Datei liegt im Materialordner und wandert mit ihm; der Ort der Wurzel gehört auf jeden Rechner anders (A7).
- Den Wegweiser über `context_write` mit einer Art `signpost` schreiben: Dann schriebe `context_write` außerhalb der Wurzel, und die Ausnahme wäre nicht mehr eng.
- Den Wegweiser in den Ausstand legen, wenn der Kontextbereich nicht antwortet: Er ist keine Änderung des Kontextbereichs, und seine Ziele lassen sich ohne ihn nicht prüfen.
- Die Einträge im Wegweiser sammeln, ohne sie zu prüfen: Dann zeigte er auf Stellen, die es nicht gibt, und die KI suchte dort.
