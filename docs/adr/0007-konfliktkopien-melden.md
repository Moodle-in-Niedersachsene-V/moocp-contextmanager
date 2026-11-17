# E7 Konfliktkopien von Sync-Clients melden

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md). Keine Ausnahme zu A1 bis A7.

## Entscheidung

**Melden, nie ändern.** Das Plugin erkennt Konfliktkopien an ihrem Namen und meldet sie mit beiden Namen. Es löscht, verschiebt und überschreibt nichts. Die Lehrkraft vergleicht und behält eine Fassung.

**Erkannte Muster.** Namen, die die Sync-Clients für Konfliktkopien vergeben (`lib/src/konflikt.dart`):

- Syncthing: `name.sync-conflict-JJJJMMTT-HHMMSS[-GERÄT].endung` (die Gerätekennung fehlt manchmal)
- Nextcloud-Desktop, ältere Form: `name_conflict-[BENUTZER-]JJJJMMTT-HHMMSS.endung`
- Dropbox und neuere Nextcloud-Versionen: `name (conflicted copy [BENUTZER] JJJJ-MM-TT HHMMSS).endung` (ohne Beachtung der Groß- und Kleinschreibung)
- Seafile: `name (SFConflict Benutzer Zeit).endung`

Das Original ist der Name mit gleicher Endung ohne den Zusatz. Ob es im selben Ordner liegt, wird mitgemeldet.

**Nicht erkannt.** Ein Muster, das hier fehlt, etwa eine deutsche Dropbox-Bezeichnung oder die Namen von OneDrive (Windows, außerhalb des Geltungsbereichs) oder iCloud (`name 2.md`, zu mehrdeutig), wird nicht gemeldet. Das ist eine Lücke, kein Fehler; ein neues Muster kommt mit einem Test.

**Wo gemeldet.** `context_list` meldet die Konfliktkopien des Ordners, den es auflistet, unter der Liste, nur auf dieser Ebene. `context_start` sucht im ganzen Kontextbereich, breit zuerst, und nennt Pfade relativ zur Wurzel. Ein Ordner, der sich nicht lesen lässt, wird genannt und übergangen.

**Obergrenzen.** Die Suche prüft höchstens 500 Ordner und 10 Ebenen tief und bricht nach 20 Sekunden ab. Was darüber liegt, wird nicht geprüft, und die Antwort sagt „not fully checked“. So wächst die Startantwort nicht mit einem unerwartet großen Kontextbereich, und eine Verknüpfung, die im Kreis führt, hält die Suche nicht an. Die Zeitgrenze lässt sich am MCP-Seam nicht verkürzen und wird deshalb am Modul geprüft.

**Ausfall.** Antwortet der Ort während der Suche nicht, steht in der Antwort „not checked“ mit dem Grund; `context_start` wirft nicht.

## Verworfen

- Konfliktkopien automatisch zusammenführen oder löschen: Die Zusammenführung ist eine inhaltliche Entscheidung der Lehrkraft, und das Plugin darf nichts löschen (A3).
- Konfliktkopien im Verzeichnis verstecken: Die Lehrkraft soll sie sehen, bevor zwei Fassungen unbemerkt bleiben.
- Nach Dateiinhalten vergleichen: Ein Vergleich liest jede Datei; die Namen genügen für die Meldung.
