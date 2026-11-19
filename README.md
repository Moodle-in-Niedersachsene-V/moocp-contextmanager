# moocp-contextmanager

Das Plugin `context` für moocp gibt der KI den Kontextbereich der Lehrkraft:
einen Ordner mit Konventionen, Stand und Fachsprache, der Kurse und Schuljahre
überdauert. Der Kontextbereich liegt in einem lokalen Ordner oder auf einem
WebDAV-Server.

## Quickstart

```
bash bauen.sh                       # baut das Plugin nach build/context (braucht dart und flutter)
bash entwickeln.sh /pfad/zu/moocp   # startet es zum Entwickeln an moocp
```

Beim ersten Start öffnet sich das Einstellungsfenster. Dort richtet die
Lehrkraft den Kontextbereich ein (siehe Benutzerhandbuch).

## Vorstellung

Eine Lehrkraft plant Kurse mit der KI und hält das Wissen dahinter (Pläne,
Entscheidungen, Gewohnheiten, Fachbegriffe) in einem Kontextbereich außerhalb
von Moodle. `context` stellt diesen Bereich der KI über acht Werkzeuge bereit:

- `context_list` listet einen Ordner, `context_read` liest eine Datei mit ihrer Version.
  Konfliktkopien von Sync-Clients meldet `context_list` unter der Liste, mit beiden Dateinamen.
  Dateien über 100 Zeilen kommen zuerst als Inhaltsverzeichnis; ein Abschnitt wird über seine Überschrift gelesen.
- `context_write` legt eine Markdown-Datei an oder ersetzt sie, `context_append` hängt Text an.
- `context_archive` verschiebt Dateien eines Ordners nach `archive/` in diesem Ordner. Es wird nichts gelöscht und nichts überschrieben.
- `context_link` schreibt den Wegweiser `CONTEXT-LINK.md` in den Projektordner der KI (Parameter `ordner`) oder, ohne Angabe, in einen Ordner, den die Lehrkraft in moocp wählt. Liegt der Projektordner auf einem anderen Rechner als das Plugin, schreibt die KI die Datei selbst.
- `context_settings` öffnet das Einstellungsfenster, in dem die Lehrkraft Ort und Passwort einträgt. Die Antwort nennt keinen Wert.
- `context_start` beginnt die Sitzung: Lage des Kontextbereichs, offene Vorgänge, Konfliktkopien im ganzen Kontextbereich, `index.md` (bei altem Layout `CONTEXT.md`) und `habits.md` der Wurzel. Mit `wiederholen: true` werden die offenen Vorgänge nachgetragen.

Lesen und Schreiben bleiben im Kontextbereich. Jeder Schreibvorgang fragt die
Lehrkraft in moocp je nach Freigabestufe, bricht ab, wenn die Datei sich seit
dem Lesen geändert hat, und gilt erst als geprüft, wenn der Inhalt beim
Zurücklesen stimmt. Das Plugin läuft als eigenes Programm neben moocp; die KI
spricht es über den MCP-Server von moocp an. Der Skill `context` führt die KI
durch diese Werkzeuge: er verlangt, dass ein freigegebener Plan vor jedem
Schreiben in Moodle im Kontextbereich steht und geprüft ist.

## Benutzerhandbuch

### Installation

Das fertige Plugin ist der Ordner aus `bauen.sh`. Er gehört in den
Einstellungsordner von moocp unter `plugins/context`. moocp vorher beenden:
Beim nächsten Start fragt moocp nach der Zustimmung zu dieser Version. Der
Ordner enthält das Einstellungsfenster in `einstellungsfenster/`; das Plugin
startet es von dort.

Der Skill `context` liegt im Ordner `skills/` des Plugins. moocp richtet ihn
bei den KI-Werkzeugen ein (Claude Code, Codex CLI, LM Studio), sobald die
Lehrkraft das Plugin zugestimmt hat. Der Skill sagt der KI, wann sie den
Kontextbereich liest und schreibt: zu Sitzungsbeginn, vor jedem Schreiben in
Moodle, bei Freigaben und beim Wegweiser. Die Lehrkraft muss nichts davon
einstellen; der Aufschreibmodus („fragen“, „immer“, „warten“) steht als
Gewohnheit im Kontextbereich.

### Einstellungen

Die Einrichtung geschieht im Einstellungsfenster. Es öffnet sich von selbst beim
ersten Start ohne Einstellungen und, wenn der Kontextbereich nicht antwortet.
Die KI kann es mit `context_settings` öffnen; sie sieht und setzt dabei keine
Werte. Das Fenster schließt sich, wenn das Plugin endet. Blieb nach einem
Absturz ein altes Fenster stehen, beendet der nächste Start es, bevor er ein
neues öffnet.

Im Fenster wählt die Lehrkraft:

- **Ordner auf diesem Rechner**: den Ordner über den Dateidialog, „Ordner wählen“.
- **WebDAV-Server**: Adresse, Benutzer und Passwort. Das Passwort wird verdeckt
  eingetragen. Die Adresse beginnt mit `https://` (`http://` nur für 127.0.0.1 oder
  localhost) und enthält keine Zugangsdaten.

„Verbindung prüfen“ öffnet den Kontextbereich und listet seinen Ordner, ohne
etwas zu schreiben. Die Antwort sagt, ob es geklappt hat, oder nennt die Ursache.
„Speichern“ trägt das Passwort in den Schlüsselbund des Systems ein und schreibt
danach die Einstellungen. Ist der Schlüsselbund nicht erreichbar, bleibt die
bisherige Einstellung unverändert. Ein leeres Passwortfeld lässt das bisherige
Passwort stehen.

Die Einstellungen liegen im Datenordner des Plugins, in der Datei
`einstellungen.json`:

- Linux: `~/.config/moocp-contextmanager/einstellungen.json`
- Mac: `~/Library/Application Support/moocp-contextmanager/einstellungen.json`

Für einen lokalen Ordner steht darin der absolute Pfad:

```json
{ "art": "lokal", "pfad": "/home/name/Kontext" }
```

Für einen WebDAV-Server stehen Adresse und Benutzer darin, nie das Passwort:

```json
{ "art": "webdav", "adresse": "https://cloud.example.org/remote.php/dav/files/name/Kontext/", "benutzer": "name" }
```

Das Passwort liegt im Schlüsselbund des Systems unter dem Dienst
`moocp-contextmanager` und dem Konto `Benutzer@Adresse`. Unter Linux braucht das
Plugin dafür `secret-tool` (Paket `libsecret-tools`), auf dem Mac `security`.
Fehlt das Werkzeug oder der Eintrag, meldet das Plugin das; es sucht das Passwort
nie in einer Datei.

Fehlt die Datei, ist der Ordner nicht da oder kann er nicht gelesen werden,
meldet das Plugin den Grund; es arbeitet nie auf einer leeren Liste weiter.

### Lange Dateien

Eine Datei mit höchstens 100 Zeilen liest die KI ganz. Eine längere Datei liefert
`context_read` als Inhaltsverzeichnis aus ihren Überschriften `##` und `###` mit
Zeilenbereichen. Die KI fordert dann einen Abschnitt über seine Überschrift an oder
die ganze Datei, wenn sie sie ausdrücklich braucht. Eine lange Datei ohne
Überschriften liefert das Plugin nur mit einem Hinweis; die Datei bekommt dann
Überschriften oder wird ganz gelesen.

### Altes Layout (Coursepilot)

Ein Kontextbereich aus Coursepilot bleibt unverändert nutzbar. Die Dateien
`CONTEXT.md`, `status.md` und `journal-*.md` werden wie neue Dateien aufgelistet
und gelesen. Fehlt in der Wurzel `index.md`, liest `context_start` die
`CONTEXT.md` als Index und sagt das in der Überschrift. Ist `index.md` da, gilt
sie allein. Ein altes Journal `journal-*.md` wird nur angehängt, wie jedes Journal.

Einen Umbau in das neue Layout macht die KI nicht von allein. Die alten Dateien
eines Projekts legt sie mit `context_archive` in `archive/` ab, bevor sie die neue
Struktur schreibt. Journale bleiben beim Umbau an ihrem Platz, weil sie nie verschoben werden.

### Konfliktkopien

Ändert ein Sync-Client dieselbe Datei an zwei Geräten gleichzeitig, legt er eine
Konfliktkopie an. Das Plugin erkennt die Namen von Syncthing
(`name.sync-conflict-…`), Nextcloud (`name_conflict-…`), Dropbox und neuere
Nextcloud-Versionen (`name (conflicted copy …)`) und Seafile (`name (SFConflict …)`).
Jede Meldung nennt beide Dateinamen. Ob das Original fehlt, sagt die Meldung auch.

Das Plugin löscht und verändert nichts. Die Lehrkraft vergleicht die beiden
Fassungen und behält eine. `context_start` sucht im ganzen Kontextbereich, bis
500 Ordner und 10 Ebenen tief und bricht nach 20 Sekunden ab; was danach liegt,
wird nicht geprüft, und die Antwort sagt „not fully checked“ mit der Ursache und der Zahl der geprüften Ordner. Andere Namensmuster, etwa deutsche Dropbox-Bezeichnungen,
erkennt das Plugin nicht.

### Archivieren

`context_archive` verschiebt die genannten Dateien eines Ordners nach
`<Ordner>/archive/`. Die KI nennt den Ordner und die Dateinamen direkt darin; sie
kann nichts außerhalb des Ordners erreichen. Die Lehrkraft gibt die Verschiebung
frei, wie eine neue Datei: auf Stufe „alle“, für Dateien im Wurzelordner schon auf
Stufe „mittel“.

Existiert eine Datei schon im Zielordner, wird nichts verschoben und nicht
gefragt. Ändert sich eine Datei zwischen Frage und Verschieben, bricht die
Verschiebung ab. Journale verschiebt das Plugin nie. Antwortet der Kontextbereich
nicht, wird nichts verschoben, und es wird nichts zurückgestellt; der Aufruf
muss später wiederholt werden.

### Schreiben und Freigaben

Die KI schreibt nur `.md`-Dateien innerhalb des Kontextbereichs. Welche
Änderungen moocp der Lehrkraft zur Freigabe vorlegt, richtet sich nach der
Freigabestufe in moocp:

- Stufe „alle“: jede Änderung, auch Journaleinträge, Nacharbeiten und neue Dateien.
- Stufe „mittel“: zusätzlich Planänderungen, Planergänzungen und Dateien direkt im Wurzelordner des Kontextbereichs.
- Stufe „keine“: keine dieser Änderungen. Der Wegweiser wird auf jeder Stufe gefragt.

Eine abgelehnte oder abgebrochene Freigabe schreibt nichts, und die Antwort sagt
es. Die Datei wird nie überschrieben, wenn sie sich seit dem Lesen geändert hat.
Journaleinträge werden nur angehängt, auch in Journalordnern unterhalb der Wurzel.

### Wegweiser im Materialordner

Der Wegweiser `CONTEXT-LINK.md` sagt der KI, welche Stelle im Kontextbereich zu
einem Materialordner gehört, damit sie nicht suchen muss. Die KI legt ihn mit
`context_link` an. Den Ordner wählt die Lehrkraft im Ordnerdialog von moocp; die
KI nennt keinen Ordner. Die Lehrkraft gibt jede Änderung frei, auf jeder
Freigabestufe, auch auf „keine“.

Jeder Eintrag zeigt auf eine Datei oder einen Ordner im Kontextbereich, relativ
zu dessen Wurzel, und hat eine Zeile dazu. Parallele Klassen bekommen je eine
Bezeichnung (etwa „Gruppe A“); ein neuer Eintrag mit gleicher Bezeichnung ersetzt
nur den alten, die übrigen bleiben. Zeigt ein Eintrag auf eine Stelle, die es
nicht gibt, schreibt das Plugin nichts. Eine vorhandene Datei `CONTEXT-LINK.md`,
die nicht im Aufbau des Plugins ist, bleibt unverändert.

Der Wegweiser ist die einzige Datei, die das Plugin außerhalb des Kontextbereichs
schreibt. Die Wurzel steht nie darin.

### WebDAV-Server ohne ETag

Sendet ein WebDAV-Server keine ETags, liest und schreibt das Plugin trotzdem. Die
Version einer Datei ist dann eine Prüfsumme (`sha256:…`), und das Plugin vergleicht
den Stand selbst unmittelbar vor dem Schreiben. Der Server erzwingt diese Prüfung
nicht: Ändert jemand die Datei in den Sekundenbruchteilen dazwischen, geht die
Änderung unbemerkt verloren. Jede Antwort eines Schreibvorgangs auf einem solchen
Server enthält deshalb die Zeile „check: not enforced by the server“; mehr dazu in
[E9](docs/adr/0009-version-ohne-etag.md).

### Antwortet der Kontextbereich nicht

Fehlt der Ordner der Wurzel oder ist er nicht lesbar, ist das eine Kontextlücke.
Bei einem WebDAV-Server gilt dasselbe, wenn er nicht antwortet: Verbindungsfehler,
Zeitablauf nach 20 Sekunden oder ein Serverfehler. Ein falsches Passwort oder eine
falsche Adresse ist eine Ursache, die die Antwort nennt. Ein Schreibvorgang kommt
dafür nicht in den Ausstand; er wird erst nach der Korrektur der Einstellungen neu gestellt.
`context_start` nennt die Ursache, und die KI arbeitet nicht auf einer Kopie weiter.
Bei einem solchen Ausfall öffnet sich das Einstellungsfenster einmal, damit die
Lehrkraft die Einstellungen gleich korrigieren kann.

Ein Schreibvorgang, der an diesem Zustand scheitert, bleibt im Datenordner des
Plugins erhalten (Ordner `ausstand/` neben der Einstellungsdatei) und wird nicht
in den Kontextbereich geschrieben. Die KI sagt, dass er noch nicht gespeichert
ist. Sobald der Ordner wieder da ist, lässt die KI die offenen Vorgänge mit
`context_start` und `wiederholen: true` nachtragen. Jeder Vorgang wird dabei wie
ein neues Schreiben geprüft und erneut freigegeben:

- Hat sich die Datei geändert oder ist sie inzwischen da, wird nichts überschrieben;
  der Vorgang bleibt stehen und die Antwort nennt die Datei.
- Lehnt die Lehrkraft ab, wird der Vorgang aus dem Ausstand entfernt.
- Bricht die Freigabe ab oder läuft sie ab, bleibt der Vorgang stehen.

Konflikte und ungültige Aufträge (etwa ein Pfad außerhalb des Kontextbereichs)
kommen nie in den Ausstand; sie werden sofort abgewiesen. Jeder Vorgang merkt sich,
an welchem Ort er entstand. Wird der Ort gewechselt, schreibt die Wiederholung
den Vorgang nicht an den neuen Ort, sondern meldet ihn und lässt ihn stehen.

## Entwicklerhandbuch

### Aufbau

Die Zahlen E1 bis E8 verweisen auf die [Entscheidungen in `docs/adr/`](docs/adr/).
E20 und E35 sind Entscheidungen von moocp.

- `bin/context.dart`: Start nach den Regeln von moocp (Port auf der
  Kommandozeile, Schlüssel aus `MOOCP_PLUGIN_SCHLUESSEL`, Ende mit der
  Standardeingabe).
- `skills/context/`: der Skill für die KI (`SKILL.md`, Ablauf und Regeln, auf Englisch; `references/layout.md`: Dateilayout). Er nennt nur Werkzeuge und Arten, die das Plugin kennt; `test/skill_test.dart` prüft das und die Beschreibungsdatei (`skills`) und das Bauen.
- `lib/src/inhaltsverzeichnis.dart`: Lesen von Dateien über 100 Zeilen: Inhaltsverzeichnis, Abschnitt über die Überschrift, ganze Datei nur auf Bitte.
- `lib/src/start.dart`: `context_start`, die Startantwort mit Lage, Ausstand, Konfliktkopien und Wurzeldateien (altes Layout: `CONTEXT.md` als Index).
- `lib/src/konflikt.dart`: Namensmuster der Konfliktkopien von Sync-Clients und die Suche im Kontextbereich ([E7](docs/adr/0007-konfliktkopien-melden.md)).
- `lib/src/archiv.dart`: `context_archive`: Verschieben nach `archive/` mit Prüfung, Freigabe und Rücklesen ([E6](docs/adr/0006-altes-layout-und-archiv.md)).
- `lib/src/wegweiser.dart`: `context_link`: Format von `CONTEXT-LINK.md`, Prüfung der Einträge, Zusammenführen und Schreiben im gewählten Ordner ([E5](docs/adr/0005-wegweiser-im-materialordner.md)). Die einzige Schreibstelle außerhalb der Wurzel.
- `lib/src/ausstand.dart`: Ausstand im Datenordner (eine Datei je Vorgang) und die Wiederholung mit Stand-Prüfung und Freigabe ([E2](docs/adr/0002-ausstand-bei-nicht-antwortendem-ort.md)).
- `lib/src/schreibauftrag.dart`: ein Schreibauftrag, sein Schreiben und seine Freigabe; gemeinsam für neue Schreibvorgänge und die Wiederholung.
- `lib/src/speicher.dart`: der Kontextbereich als Schnittstelle (`Kontextspeicher`) mit
  Lesen, Schreiben, Anhängen, Verschieben und Stand-Prüfung. Der lokale Ordner
  (`LokalerSpeicher`) löst Verknüpfungen auf und prüft jeden Pfad gegen die Wurzel.
- `lib/src/webdav.dart`: der WebDAV-Server als zweiter Ort (`WebDavSpeicher`): ETag
  als Version, bedingtes Schreiben ([E3](docs/adr/0003-webdav-version-und-bedingtes-schreiben.md)),
  ohne starkes ETag die Prüfsumme als Version ([E9](docs/adr/0009-version-ohne-etag.md)), Zeitlimit und Ausfall.
- `lib/src/pfad.dart`: die Pfadregeln für beide Orte.
- `lib/src/ort.dart`: der Zugang zum Ort aus den Einstellungen (jedes Mal neu gelesen).
- `lib/src/schluesselbund.dart`: das Passwort aus dem Schlüsselbund über die Werkzeuge des Systems ([E4](docs/adr/0004-schluesselbund-und-verbindung.md)).
- `lib/src/art.dart`: Arten der Änderung und ihre Freigabestufe (E20 von moocp).
- `lib/src/app.dart`: Freigaben über die Adresse der App für Plugins (E35 von moocp).
- `lib/src/einstellungen.dart`: Einstellungsdatei für beide Orte und Prüfung der Adresse.
- `lib/src/werkzeuge.dart`: die MCP-Werkzeuge.
- `lib/src/server.dart`: MCP-Server auf `127.0.0.1` mit Schlüsselprüfung.
- `lib/src/einrichtung.dart`: die Einrichtung aus dem Fenster: Eingabe prüfen, Verbindung prüfen, speichern (Schlüsselbund vor Datei) und die deutschen Meldungen ([E8](docs/adr/0008-einstellungsfenster.md)).
- `lib/src/einstellungsfenster.dart`: Start des Fensters: beim ersten Start ohne Einstellungen, einmal je Ausfall, auf Wunsch der KI (`context_settings`); Ende des Fensters mit dem Plugin und Aufräumen eines Rests über `fenster.pid` ([E8](docs/adr/0008-einstellungsfenster.md)).
- `fenster/`: das Einstellungsfenster als eigenes Flutter-Programm (Material 3, moocps Grundfarbe, `window_manager`). Es benutzt das Plugin über den Pfad `..`; `bauen.sh` legt es als `einstellungsfenster/` in den Plugin-Ordner.
- `plugin.json`: Beschreibungsdatei für moocp.

### Tests

```
TMPDIR=<Ordner auf der Platte> dart test -j 1 -r expanded
```

Jede Test-Datei läuft zweimal, einmal am lokalen Ordner und einmal am WebDAV-Server
im Testprozess (`fuerJedenOrt` in `test/harness.dart`). Der Server bedient den Ordner
des Tests; das Passwort kommt von einem Ersatz für `secret-tool` im Ordner des Tests,
der nur das Konto der Testanlage kennt. Der echte Schlüsselbund wird nie benutzt.
Der Skill und seine Ablage prüft `test/skill_test.dart`: jeder Werkzeugname und jede Art im Skill muss zum Plugin passen, und `bauen.sh` muss den Skill in den Zielordner kopieren (mit einem Ersatz für `dart`, der nur die Ausgabedatei anlegt).
Die Vertragstests der Speicherschicht (gleiche Fälle für beide Orte) stehen in
`test/speicher_vertrag_test.dart`, die WebDAV-Fälle (Ausfall, Zeitlimit, Anmeldung,
Adressen) in `test/webdav_test.dart`, der Schlüsselbund in `test/schluesselbund_test.dart`.

Die Tests rufen `bin/context.dart` wie moocp es startet über Streamable HTTP
auf und arbeiten in einem temporären Ordner. `test/harness.dart` stellt
`PluginProzess` bereit: Start mit Port und Schlüssel, `werkzeug` für den
Aufruf eines Werkzeugs mit Token, und `app` (`FakeApp`): eine falsche Adresse
der App, die Freigaben nach der Stufe der Lehrkraft beantwortet und jede
Anfrage zählt. Die Tests liegen je Werkzeug oder Thema in `test/`. Das
Einstellungsfenster prüft `fenster/test/` mit `flutter test` im Ordner `fenster/`;
dort ersetzen Fakes die Logik des Plugins. Ein Ausfall des Ortes simulieren die
Tests, indem sie den Wurzelordner entfernen, am WebDAV-Ort stoppen sie den Server
(`ausfallen`). Tests, die nur am lokalen Ordner Sinn haben (Verknüpfungen), sind
dort übersprungen.

### Entwickeln

`entwickeln.sh <moocp>` erzeugt einen Schlüssel, startet das Plugin auf dem
Port `entwicklungsPort` aus `plugin.json` mit `--entwicklung` und startet moocp
mit `--plugin-entwicklung`. Das Plugin läuft dann, bis der Entwickler es beendet.
Das Einstellungsfenster öffnet es aus `build/context/einstellungsfenster`, wenn
`bauen.sh` das schon getan hat.
Das Einstellungsfenster gibt es nur für Linux. Auf dem Mac baut `bauen.sh` das
Plugin ohne Fenster und warnt dabei.
