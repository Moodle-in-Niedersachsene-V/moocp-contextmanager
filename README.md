# moocp-contextmanager

Das Plugin `context` für moocp gibt der KI den Kontextbereich der Lehrkraft:
einen Ordner mit Konventionen, Stand und Fachsprache, der Kurse und Schuljahre
überdauert. Der Kontextbereich liegt in einem lokalen Ordner oder auf einem
WebDAV-Server (WebDAV folgt).

## Quickstart

```
bash bauen.sh                       # baut das Plugin nach build/context
bash entwickeln.sh /pfad/zu/moocp   # startet es zum Entwickeln an moocp
```

Danach einen Kontextbereich in `einstellungen.json` eintragen (siehe Benutzerhandbuch).

## Vorstellung

Eine Lehrkraft plant Kurse mit der KI und hält das Wissen dahinter (Pläne,
Entscheidungen, Gewohnheiten, Fachbegriffe) in einem Kontextbereich außerhalb
von Moodle. `context` stellt diesen Bereich der KI über vier Werkzeuge bereit:

- `context_list` listet einen Ordner, `context_read` liest eine Datei mit ihrer Version.
  Dateien über 100 Zeilen kommen zuerst als Inhaltsverzeichnis; ein Abschnitt wird über seine Überschrift gelesen.
- `context_write` legt eine Markdown-Datei an oder ersetzt sie, `context_append` hängt Text an.

Lesen und Schreiben bleiben im Kontextbereich. Jeder Schreibvorgang fragt die
Lehrkraft in moocp je nach Freigabestufe, bricht ab, wenn die Datei sich seit
dem Lesen geändert hat, und gilt erst als geprüft, wenn der Inhalt beim
Zurücklesen stimmt. Das Plugin läuft als eigenes Programm neben moocp; die KI
spricht es über den MCP-Server von moocp an.

## Benutzerhandbuch

### Installation

Das fertige Plugin ist der Ordner aus `bauen.sh`. Er gehört in den
Einstellungsordner von moocp unter `plugins/context`. moocp vorher beenden:
Beim nächsten Start fragt moocp nach der Zustimmung zu dieser Version. Die
Einrichtung über ein Einstellungsfenster folgt; bis dahin ist die
Einstellungsdatei von Hand anzulegen.

### Einstellungen

Die Datei `einstellungen.json` liegt im Datenordner des Plugins:

- Linux: `~/.config/moocp-contextmanager/einstellungen.json`
- Mac: `~/Library/Application Support/moocp-contextmanager/einstellungen.json`

Inhalt für einen lokalen Ordner, der Pfad muss absolut sein:

```json
{ "art": "lokal", "pfad": "/home/name/Kontext" }
```

Fehlt die Datei, ist der Ordner nicht da oder kann er nicht gelesen werden,
meldet das Plugin den Grund; es arbeitet nie auf einer leeren Liste weiter.

### Lange Dateien

Eine Datei mit höchstens 100 Zeilen liest die KI ganz. Eine längere Datei liefert
`context_read` als Inhaltsverzeichnis aus ihren Überschriften `##` und `###` mit
Zeilenbereichen. Die KI fordert dann einen Abschnitt über seine Überschrift an oder
die ganze Datei, wenn sie sie ausdrücklich braucht. Eine lange Datei ohne
Überschriften liefert das Plugin nur mit einem Hinweis; die Datei bekommt dann
Überschriften oder wird ganz gelesen.

### Schreiben und Freigaben

Die KI schreibt nur `.md`-Dateien innerhalb des Kontextbereichs. Welche
Änderungen moocp der Lehrkraft zur Freigabe vorlegt, richtet sich nach der
Freigabestufe in moocp:

- Stufe „alle“: jede Änderung, auch Journaleinträge und Nacharbeiten.
- Stufe „mittel“: Planänderungen, Planergänzungen, neue Dateien direkt im Wurzelordner des Kontextbereichs.
- Stufe „keine“: keine dieser Änderungen.

Eine abgelehnte oder abgebrochene Freigabe schreibt nichts, und die Antwort sagt
es. Die Datei wird nie überschrieben, wenn sie sich seit dem Lesen geändert hat.
Journaleinträge werden nur angehängt.

## Entwicklerhandbuch

### Aufbau

- `bin/context.dart`: Start nach den Regeln von moocp (Port auf der
  Kommandozeile, Schlüssel aus `MOOCP_PLUGIN_SCHLUESSEL`, Ende mit der
  Standardeingabe).
- `lib/src/inhaltsverzeichnis.dart`: Lesen von Dateien über 100 Zeilen: Inhaltsverzeichnis, Abschnitt über die Überschrift, ganze Datei nur auf Bitte.
- `lib/src/speicher.dart`: Kontextbereich im lokalen Ordner. Lesen, Schreiben
  und Anhängen mit Prüfung des Stands und Rücklesen. Jeder Pfad wird gegen die
  Wurzel geprüft; Verknüpfungen werden aufgelöst.
- `lib/src/art.dart`: Arten der Änderung und ihre Freigabestufe (E20).
- `lib/src/app.dart`: Freigaben über die Adresse der App für Plugins (E35).
- `lib/src/einstellungen.dart`: Einstellungsdatei und Öffnen des Bereichs.
- `lib/src/werkzeuge.dart`: die MCP-Werkzeuge.
- `lib/src/server.dart`: MCP-Server auf `127.0.0.1` mit Schlüsselprüfung.
- `plugin.json`: Beschreibungsdatei für moocp.

### Tests

```
TMPDIR=<Ordner auf der Platte> dart test -j 1 -r expanded
```

Die Tests rufen `bin/context.dart` wie moocp es startet über Streamable HTTP
auf und arbeiten in einem temporären Ordner. `test/harness.dart` stellt
`PluginProzess` bereit: Start mit Port und Schlüssel, `werkzeug` für den
Aufruf eines Werkzeugs mit Token, und `app` (`FakeApp`): eine falsche Adresse
der App, die Freigaben nach der Stufe der Lehrkraft beantwortet und jede
Anfrage zählt. Die Tests für Lesen und Einstellungen stehen in
`test/context_plugin_test.dart`, die für lange Dateien in
`test/inhaltsverzeichnis_test.dart`, die für Schreiben in `test/schreiben_test.dart`.

### Entwickeln

`entwickeln.sh <moocp>` erzeugt einen Schlüssel, startet das Plugin auf dem
Port `entwicklungsPort` aus `plugin.json` mit `--entwicklung` und startet moocp
mit `--plugin-entwicklung`. Das Plugin läuft dann, bis der Entwickler es beendet.
