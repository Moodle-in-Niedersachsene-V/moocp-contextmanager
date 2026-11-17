# E1 Schreiben mit Prüfung des Stands und Freigabe nach Stufe

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Schreiben (`context_write`, `context_append`) prüft den Stand vor dem Ändern: Die KI gibt die Version an, die sie gelesen hat. Stimmt sie nicht mehr, bricht der Vorgang mit einem Konflikt ab und fragt niemanden. Eine Datei ohne Version wird nur angelegt, wenn es sie noch nicht gibt; eine vorhandene wird nur mit ihrer Version ersetzt.

Vor dem Schreiben fragt das Plugin die Lehrkraft über die Adresse der App (E35) mit einer Freigabe. Die Stufe, ab der gefragt wird, hängt von der Art der Änderung ab: Journaleintrag, Nacharbeit und neue Datei ab Stufe „alle“; Planänderung, Planergänzung und jede Datei direkt am Wurzelordner ab Stufe „mittel“. Die Prüfung des Stands läuft vor der Frage und noch einmal nach ihr, weil die Lehrkraft sich Zeit lassen kann. Nach dem Schreiben liest das Plugin die Datei zurück; nur bei Gleichheit meldet es `verified`.

Ein Journal wird nur angehängt, nie ersetzt. Geschrieben werden nur `.md`-Dateien innerhalb der Wurzel.

## Verworfen

- Die Art der Änderung der KI überlassen, ohne Stufe im Plugin: Eine Freigabe, die die KI einstuft, ist keine Grenze (K2 der Vereinsstandards).
- Anlegen und Ersetzen über zwei Werkzeuge mit einer Schalterkombination: Die Version als einziger Schlüssel reicht, und eine Datei ohne Version kann nicht versehentlich ersetzt werden.
- Die Datei atomar über eine temporäre Datei ersetzen: Die Prüfung und das Schreiben laufen nacheinander, nicht gleichzeitig; eine Sperre des Dateisystems ist plattformabhängig und wird nicht erzwungen.
