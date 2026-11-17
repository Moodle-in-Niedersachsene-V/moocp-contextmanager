# E1 Schreiben mit Prüfung des Stands und Freigabe nach Stufe

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

**Stand.** Schreiben (`context_write`, `context_append`) verlangt die Version, die die KI gelesen hat. Stimmt sie nicht mehr, bricht der Vorgang mit einem Konflikt ab und fragt niemanden. Eine bestehende Datei wird nur mit `version` ersetzt; ohne `version` entsteht eine Datei nur, wenn es sie noch nicht gibt. Anhängen mit `version` verlangt dieselbe Prüfung.

**Freigabe.** Vor dem Schreiben fragt das Plugin über die Adresse der App (E35). Die Stufe, ab der gefragt wird, folgt aus der Art der Änderung: Journaleintrag, Nacharbeit und neue Datei ab Stufe „alle“; Planänderung und Planergänzung ab Stufe „mittel“. Eine Datei direkt am Wurzelordner wird immer mindestens auf Stufe „mittel“ gefragt, unabhängig von der Art. Die Stand-Prüfung läuft vor der Frage und nochmals nach ihr, weil die Lehrkraft sich Zeit lassen kann.

**Rücklesen.** Nach jedem Schreiben liest das Plugin die Datei zurück. Nur bei Gleichheit meldet es `verified`; das Urteil fällt das Werkzeug.

**Journal.** Dateien unter `journal/` und das alte Journal `journal-*.md` im Wurzelordner werden nur angehängt, nie ersetzt. Die Bindung hängt am Pfad und gilt für jede Art.

**Geltungsbereich.** Geschrieben werden nur `.md`-Dateien innerhalb der Wurzel. Steuerzeichen im Pfad sind ungültig. Eine leere oder zu lange Zusammenfassung wird vor der Freigabe abgewiesen.

**Namen.** Argumente der Werkzeuge heißen auf Deutsch (`pfad`, `inhalt`, `zusammenfassung`, `version`), wie die Argumente in moocp. Die Werte von `art` sind englische Kennungen, weil sie Teil der englischen Beschreibung sind.

**Bekannte Grenze.** `art` gibt die KI an. Ordnet sie eine Änderung falsch ein, fragt moocp auf der falschen Stufe; E20 schützt nur so weit, wie die Art stimmt. Die Bindung des Journals an den Pfad und die Freigabe für Dateien am Wurzelordner sind davon unabhängig.

## Verworfen

- Die Art allein der KI überlassen, ohne Prüfung am Pfad: Eine Einstufung, die die KI selbst vornimmt, ist keine Grenze (K2 der Vereinsstandards). Das Journal ist deshalb an den Pfad gebunden.
- Anlegen und Ersetzen über zwei Werkzeuge: Die Version als einziger Schlüssel reicht; eine Datei ohne Version kann nicht versehentlich ersetzt werden.
- Atomares Ersetzen über eine temporäre Datei: Prüfung und Schreiben laufen nacheinander. Eine Sperre des Dateisystems ist plattformabhängig und wird nicht erzwungen.
