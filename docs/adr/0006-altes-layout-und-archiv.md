# E6 Altes Layout lesen und archivieren

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md). Keine Ausnahme zu A1 bis A7.

## Entscheidung

**Altes Layout ohne Umbau lesbar.** Auflisten, Lesen und Anhängen funktionieren für `CONTEXT.md`, `status.md` und `journal-*.md` wie für neue Dateien. Ein Journal `journal-*.md` bleibt nur anhängbar (E1).

**Index aus `CONTEXT.md`.** `context_start` liest `index.md` der Wurzel. Fehlt sie und gibt es `CONTEXT.md`, liest es diese als Index; die Überschrift sagt es (`--- CONTEXT.md (old layout: …) ---`). Gibt es beide, gewinnt `index.md`, und `CONTEXT.md` wird nicht gelesen. Die Regel gilt nur für die Wurzel, die `context_start` liest; Indexdateien tieferer Ebenen findet die KI über `context_list`.

**Archivieren ist Verschieben, nie Löschen.** `context_archive` nimmt einen Ordner und Dateinamen direkt darin. Jede Datei wandert nach `<Ordner>/archive/<Name>`; das Ziel liegt also immer im selben Projekt. Nur `.md`-Dateien, nur direkte Kinder (kein Schrägstrich im Namen), keine Pfade, die hinausführen (A2).

**Nie überschreiben.** Existiert ein Ziel, wird vor der Frage abgebrochen, und nichts wird verschoben. Der Ablauf ist: lesen und Ziele prüfen, Freigabe, Stand jeder Datei erneut prüfen, verschieben, zurücklesen. Das Verschieben selbst ist am Ort ohne Überschreiben gesichert: Lokal entsteht das Ziel als zweiter Name derselben Datei, den das Betriebssystem nur anlegt, wenn der Name frei ist; WebDAV verlangt im MOVE `Overwrite: F` und den gelesenen Stand als `If-Match`. Ein Ziel, das erst während der Freigabe erscheint, wird so abgewiesen. Scheitert eine Datei nach anderen, meldet die Antwort, was verschoben wurde und was nicht; gelöscht oder überschrieben wird nichts.

**Freigabe wie bei einer neuen Datei.** Die Verschiebung fragt auf Stufe „alle“ (`Art.newFile`), nicht auf „mittel“ wie Planänderungen. Die Freigabe nennt nur Pfade im Kontextbereich, nie die Wurzel (A7).

**Journale wandern nie.** Journal ist, was E1 als Journal fasst: `journal-*.md` und alles in einem Ordner `journal/`, auf jeder Ebene. Ein altes Journal bleibt daher beim Umbau an seinem Platz.

**Kein Ausstand.** Eine Verschiebung hat keinen Inhalt, den ein Ausstand nachtragen könnte. Antwortet der Ort nicht, wird nichts verschoben, die Antwort nennt den Grund und sagt, dass nichts verschoben wurde. Die Wiederholung geschieht durch einen neuen Aufruf.

## Verworfen

- Den Umbau selbst (Index, Gewohnheiten, Plan) durch das Plugin erzeugen lassen: Das ist die Aufgabe der Skill-Anweisung und der Lehrkraft, nicht des Werkzeugs.
- Journale archivieren: Ein Journal ist nur anhängbar, und eine Verschiebung wäre eine Änderung seiner Lage in der Historie. Die Ausnahme ließe sich später begründen, wenn ein Umbau sie braucht; dann ist es eine neue Entscheidung.
- Die Verschiebung in den Ausstand legen: Der Ausstand ist für Inhalte gedacht (E2); eine nachgetragene Verschiebung könnte nach einer Änderung an der Quelle falsch sein.
- Ein Löschen der Originale nach dem Archivieren: Gelöscht wird nur von Hand, wenn die Lehrkraft den neuen Stand annimmt (Spec #10).
