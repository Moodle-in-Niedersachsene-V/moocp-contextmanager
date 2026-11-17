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
von Moodle. `context` stellt diesen Bereich der KI über vier Werkzeuge bereit,
die nur innerhalb des Kontextbereichs lesen. Das Plugin läuft als eigenes
Programm neben moocp; die KI spricht es über den MCP-Server von moocp an.

Werkzeuge in dieser Fassung: `context_list` (Ordner auflisten) und
`context_read` (Textdatei mit Version lesen).

## Benutzerhandbuch

### Installation

Das fertige Plugin ist der Ordner aus `bauen.sh`. Er wird
im Einstellungsordner von moocp unter `plugins/context` abgelegt; danach fragt moocp beim nächsten Start nach
der Zustimmung zu dieser Version. Die Einrichtung über ein Einstellungsfenster
folgt; bis dahin ist die Einstellungsdatei von Hand anzulegen.

### Einstellungen

Die Datei `einstellungen.json` liegt im Datenordner des Plugins:

- Linux: `~/.config/moocp-contextmanager/einstellungen.json`
- Mac: `~/Library/Application Support/moocp-contextmanager/einstellungen.json`

Inhalt für einen lokalen Ordner:

```json
{ "art": "lokal", "pfad": "/home/name/Kontext" }
```

Fehlt die Datei, ist der Ordner nicht da oder kann er nicht gelesen werden,
meldet das Plugin den Grund; es arbeitet nie auf einer leeren Liste weiter.

## Entwicklerhandbuch

### Aufbau

- `bin/context.dart`: Start nach den Regeln von moocp (Port auf der
  Kommandozeile, Schlüssel aus `MOOCP_PLUGIN_SCHLUESSEL`, Ende mit der
  Standardeingabe).
- `lib/src/speicher.dart`: Kontextbereich im lokalen Ordner. Jeder Pfad wird
  gegen die Wurzel geprüft; Verknüpfungen werden aufgelöst.
- `lib/src/einstellungen.dart`: Einstellungsdatei und Öffnen des Bereichs.
- `lib/src/werkzeuge.dart`: die MCP-Werkzeuge.
- `lib/src/server.dart`: MCP-Server auf `127.0.0.1` mit Schlüsselprüfung.
- `plugin.json`: Beschreibungsdatei für moocp.

### Tests

```
TMPDIR=<Ordner auf der Platte> dart test -j 1 -r expanded
```

Die Tests laufen am MCP-Seam (`test/context_plugin_test.dart`): Sie starten
`bin/context.dart` wie moocp es tut, rufen die Werkzeuge über Streamable HTTP
auf und arbeiten in einem temporären Ordner. `test/harness.dart` stellt
`PluginProzess` bereit: Start mit Port und Schlüssel, eine Test-Adresse der App
(`appServer`, zählt nur Anfragen) und die Hilfsfunktionen `initialisieren`,
`werkzeug` und `anfragen`.

### Entwickeln

`entwickeln.sh <moocp>` erzeugt einen Schlüssel, startet das Plugin auf dem
Port `entwicklungsPort` aus `plugin.json` mit `--entwicklung` und startet moocp
mit `--plugin-entwicklung`. Das Plugin läuft dann, bis der Entwickler es beendet.
