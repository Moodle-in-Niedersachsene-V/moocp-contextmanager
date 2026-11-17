# E4 Schlüsselbund und Verbindung zum WebDAV-Server

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

**Passwort.** Das Passwort eines WebDAV-Speichers liegt im Schlüsselbund des Systems. Das Plugin liest es über dessen Werkzeuge: `secret-tool lookup` (Linux, libsecret) und `security find-generic-password -w` (macOS). Dienstname `moocp-contextmanager`, Konto `Benutzer@Adresse`. Das Plugin schreibt nie in den Schlüsselbund; eingetragen wird es im Einstellungsfenster.

**Kein Ersatz.** Fehlt das Werkzeug, der Eintrag oder ist der Schlüsselbund gesperrt, ist das ein Fehler mit Grund. Das Passwort wird dann nie aus einer Datei, einer Umgebungsvariablen oder einer Eingabe der KI genommen (A6).

**Ausgabe.** Das Passwort kommt auf der Standardausgabe des Werkzeugs, nie in einer Kommandozeile. Es geht nur in den `Authorization`-Kopf der Anfrage und in keine Meldung, kein Protokoll und keinen Ordner.

**Adresse.** Die Adresse der Wurzel braucht `https`. `http` ist nur zu einer Schleife erlaubt (127.0.0.1, ::1, localhost), sonst ginge das Passwort offen über das Netz. Zugangsdaten gehören nicht in die Adresse; eine Adresse mit Benutzer oder Passwort wird abgewiesen.

**Einstellungen.** Die Einstellungsdatei nennt Art, Adresse und Benutzer, nie das Passwort (A6).

## Verworfen

- `flutter_secure_storage`: Das Plugin ist reines Dart und läuft ohne Flutter; der Schlüsselbund wird deshalb über die Werkzeuge des Systems erreicht.
- Passwort in der Einstellungsdatei oder im Datenordner: Verstieße gegen A6.
- Passwort über eine Umgebungsvariable des Plugins: moocp würde es an den Prozess geben, und ein Protokoll kann es zeigen.
- Passwort über ein KI-Werkzeug setzen: A6 verbietet es.
- `http` zu anderen Rechnern erlauben: Das Passwort ginge im Klartext über das Netz.
- Weiterleitungen folgen: Die Zugangsdaten gingen an eine Adresse, die die Lehrkraft nicht eingetragen hat.
