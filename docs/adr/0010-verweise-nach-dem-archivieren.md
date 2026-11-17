# E10 Verweise nach dem Archivieren

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md). Keine Ausnahme zu A1 bis A7. Ergänzt [E6](0006-altes-layout-und-archiv.md).

## Entscheidung

**Melden statt umschreiben.** Nach dem Verschieben sucht `context_archive` in den Indexdateien nach Verweisen auf die verschobenen Dateien und nennt jede Stelle in der Antwort (Abschnitt `references:`). Die KI korrigiert sie im selben Schritt mit `context_read` und `context_write`; jede Korrektur ist ein Schreibvorgang mit Stand und Freigabe (E1), der Wurzelindex als `plan_change`. Das Plugin schreibt nie selbst einen Index um.

**Wo gesucht wird.** In `index.md` und `CONTEXT.md` (Groß- und Kleinschreibung gleich) der Ebene des Ordners, aller Ebenen darüber bis zur Wurzel und aller Ebenen darunter. Ordner `archive` darunter werden übergangen, dort liegt, was schon archiviert ist. Andere Dateien (Pläne, Notizen) durchsucht das Werkzeug nicht; der Skill sagt der KI, dass sie solche Verweise selbst prüft.

**Was ein Verweis ist.** Jedes pfadartige Stück einer Zeile: Ziel eines Markdown-Links (auch `<…>`), Inhalt eines Backtick-Paars und jedes Wort ohne Leerzeichen und Klammern. Der Pfad zählt, wenn er relativ zum Ordner der Indexdatei oder relativ zur Wurzel (auch mit `/` davor) auf die verschobene Datei zeigt; `#Anker`, `?…`, `./`, `..` und `%20` werden aufgelöst, Adressen mit Schema nie. Groß- und Kleinschreibung zählt nicht. Es wird lieber zu viel gemeldet als zu wenig, denn ein Treffer ist ein Hinweis, den die KI prüft.

**Nur lesen, nur Pfade melden.** Die Suche liest nur. Die Antwort nennt Datei, Zeile und den Pfad, wie er in der Datei steht, nie die Zeile selbst: Inhalte des Kontextbereichs sind Daten (A4) und gelangen so nicht als Text in die Antwort.

**Begrenzt, und die Grenze steht in der Antwort.** Die Suche läuft nach dem Verschieben und hat Obergrenzen: 10 Ebenen, 300 Ordner, 100 Indexdateien, 1 MiB je Datei und 8 Sekunden insgesamt (unter den 20 Sekunden, die ein Aufruf bei moocp hat). Ein Ort, der nicht antwortet, eine unlesbare Datei, eine erreichte Grenze oder der Zeitablauf lassen die Verschiebung unberührt (sie ist dann geschehen und wird gemeldet), machen die Suche aber `INCOMPLETE`: Die Antwort nennt den Grund und, was nicht geprüft wurde, und verlangt von der KI, es selbst zu prüfen, bevor sie sagt, dass nichts mehr auf eine verschobene Datei zeigt. Eine unvollständige Suche wird nie als „nichts gefunden“ gemeldet. Bricht die Verschiebung nach einigen Dateien ab, sucht das Werkzeug für die schon verschobenen und hängt den Abschnitt an die Fehlermeldung.

## Verworfen

- Die Verweise selbst umschreiben: Der Index ist Inhalt der Lehrkraft. Ein Umschreiben erzeugte im Text, in Tabellen oder Codeblöcken unbeabsichtigte Änderungen, und es wäre ein Schreiben außerhalb der Freigabe der Art `plan_change`. Der Weg über die KI braucht dieselbe Freigabe wie jede Indexänderung.
- Die Suche vor der Freigabe der Verschiebung: Sie verzögerte die Frage an die Lehrkraft und sähe einen Stand, der sich noch ändert; nach dem Verschieben sieht sie den Endstand.
- Alle Dateien des Kontextbereichs durchsuchen: Bei einem großen Kontextbereich hinge die Antwort am Zeitlimit des Ortes; der Index ist, worauf die KI sich verlässt.
