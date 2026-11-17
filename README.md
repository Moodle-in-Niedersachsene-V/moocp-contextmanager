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
von Moodle. `context` stellt diesen Bereich der KI über fünf Werkzeuge bereit:

- `context_list` listet einen Ordner, `context_read` liest eine Datei mit ihrer Version.
  Dateien über 100 Zeilen kommen zuerst als Inhaltsverzeichnis; ein Abschnitt wird über seine Überschrift gelesen.
- `context_write` legt eine Markdown-Datei an oder ersetzt sie, `context_append` hängt Text an.
- `context_start` beginnt die Sitzung: Lage des Kontextbereichs, offene Vorgänge, `index.md` und `habits.md` der Wurzel. Mit `wiederholen: true` werden die offenen Vorgänge nachgetragen.

Lesen und Schreiben bleiben im Kontextbereich. Jeder Schreibvorgang fragt die
Lehrkraft in moocp je nach Freigabestufe, bricht ab, wenn die Datei sich seit
dem Lesen geändert hat, und gilt erst als geprüft, wenn der Inhalt beim
Zurücklesen stimmt. Das Plugin läuft als eigenes Programm neben moocp; die KI
spricht es über den MCP-Server von moocp an.

Jede Sitzung beginnt mit `context_start`: Es sagt in einer Antwort, ob der
Kontextbereich antwortet, welche Schreibvorgänge noch nicht gespeichert sind,
und gibt den Wurzelindex und die Wurzelgewohnheiten. Antwortet der Ort nicht,
bleibt ein Schreibvorgang mit seinem Inhalt erhalten und wird später nachgetragen.

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

Liegt der Kontextbereich auf einem WebDAV-Server, nennt die Datei Adresse und
Benutzer. Die Adresse beginnt mit `https://` (`http://` nur für 127.0.0.1 oder
localhost) und enthält keine Zugangsdaten:

```json
{ "art": "webdav", "adresse": "https://cloud.example.org/remote.php/dav/files/name/Kontext/", "benutzer": "name" }
```

Das Passwort gehört nicht in diese Datei. Es liegt im Schlüsselbund des Systems
unter dem Dienst `moocp-contextmanager` und dem Konto `Benutzer@Adresse`.
Unter Linux braucht das Plugin dafür `secret-tool` (Paket `libsecret-tools`),
auf dem Mac `security`. Fehlt das Werkzeug oder der Eintrag, meldet das Plugin
das; es sucht das Passwort nie in einer Datei.

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

### Antwortet der Kontextbereich nicht

Fehlt der Ordner der Wurzel oder ist er nicht lesbar, ist das eine Kontextlücke.
Bei einem WebDAV-Server gilt dasselbe, wenn er nicht antwortet: Verbindungsfehler,
Zeitablauf nach 20 Sekunden oder ein Serverfehler. Ein falsches Passwort oder eine
falsche Adresse ist eine Ursache, die die Antwort nennt. Ein Schreibvorgang kommt
dafür nicht in den Ausstand; er wird erst nach der Korrektur der Einstellungen neu gestellt.
`context_start` nennt die Ursache, und die KI arbeitet nicht auf einer Kopie weiter.

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

- `bin/context.dart`: Start nach den Regeln von moocp (Port auf der
  Kommandozeile, Schlüssel aus `MOOCP_PLUGIN_SCHLUESSEL`, Ende mit der
  Standardeingabe).
- `lib/src/inhaltsverzeichnis.dart`: Lesen von Dateien über 100 Zeilen: Inhaltsverzeichnis, Abschnitt über die Überschrift, ganze Datei nur auf Bitte.
- `lib/src/start.dart`: `context_start`, die Startantwort mit Lage, Ausstand und Wurzeldateien.
- `lib/src/ausstand.dart`: Ausstand im Datenordner (eine Datei je Vorgang) und die Wiederholung mit Stand-Prüfung und Freigabe (E2).
- `lib/src/schreibauftrag.dart`: ein Schreibauftrag, sein Schreiben und seine Freigabe; gemeinsam für neue Schreibvorgänge und die Wiederholung.
- `lib/src/speicher.dart`: der Kontextbereich als Schnittstelle (`Kontextspeicher`) mit
  Lesen, Schreiben, Anhängen, Verschieben und Stand-Prüfung. Der lokale Ordner
  (`LokalerSpeicher`) löst Verknüpfungen auf und prüft jeden Pfad gegen die Wurzel.
- `lib/src/webdav.dart`: der WebDAV-Server als zweiter Ort (`WebDavSpeicher`): ETag
  als Version, bedingtes Schreiben (E3), Zeitlimit und Ausfall.
- `lib/src/pfad.dart`: die Pfadregeln für beide Orte.
- `lib/src/ort.dart`: der Zugang zum Ort aus den Einstellungen (jedes Mal neu gelesen).
- `lib/src/schluesselbund.dart`: das Passwort aus dem Schlüsselbund über die Werkzeuge des Systems (E4).
- `lib/src/art.dart`: Arten der Änderung und ihre Freigabestufe (E20).
- `lib/src/app.dart`: Freigaben über die Adresse der App für Plugins (E35).
- `lib/src/einstellungen.dart`: Einstellungsdatei für beide Orte und Prüfung der Adresse.
- `lib/src/werkzeuge.dart`: die MCP-Werkzeuge.
- `lib/src/server.dart`: MCP-Server auf `127.0.0.1` mit Schlüsselprüfung.
- `plugin.json`: Beschreibungsdatei für moocp.

### Tests

```
TMPDIR=<Ordner auf der Platte> dart test -j 1 -r expanded
```

Jede Test-Datei läuft zweimal, einmal am lokalen Ordner und einmal am WebDAV-Server
im Testprozess (`fuerJedenOrt` in `test/harness.dart`). Der Server bedient den Ordner
des Tests; das Passwort kommt von einem Ersatz für `secret-tool` im Ordner des Tests,
der nur das Konto der Testanlage kennt. Der echte Schlüsselbund wird nie benutzt.
Die Vertragstests der Speicherschicht (gleiche Fälle für beide Orte) stehen in
`test/speicher_vertrag_test.dart`, die WebDAV-Fälle (Ausfall, Zeitlimit, Anmeldung,
Adressen) in `test/webdav_test.dart`, der Schlüsselbund in `test/schluesselbund_test.dart`.

Die Tests rufen `bin/context.dart` wie moocp es startet über Streamable HTTP
auf und arbeiten in einem temporären Ordner. `test/harness.dart` stellt
`PluginProzess` bereit: Start mit Port und Schlüssel, `werkzeug` für den
Aufruf eines Werkzeugs mit Token, und `app` (`FakeApp`): eine falsche Adresse
der App, die Freigaben nach der Stufe der Lehrkraft beantwortet und jede
Anfrage zählt. Die Tests für Lesen und Einstellungen stehen in
`test/context_plugin_test.dart`, die für lange Dateien in
`test/inhaltsverzeichnis_test.dart`, die für Schreiben in `test/schreiben_test.dart`,
die für den Start in `test/start_test.dart` und für den Ausstand in
`test/ausstand_test.dart`. Ein Ausfall des Ortes simulieren die Tests, indem sie
den Wurzelordner entfernen, am WebDAV-Ort stoppen sie den Server (`ausfallen`).
Tests, die nur am lokalen Ordner Sinn haben (Verknüpfungen), sind dort übersprungen.

### Entwickeln

`entwickeln.sh <moocp>` erzeugt einen Schlüssel, startet das Plugin auf dem
Port `entwicklungsPort` aus `plugin.json` mit `--entwicklung` und startet moocp
mit `--plugin-entwicklung`. Das Plugin läuft dann, bis der Entwickler es beendet.
