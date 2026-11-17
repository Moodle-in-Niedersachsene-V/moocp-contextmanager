# E3 WebDAV: Version als ETag, Schreiben mit Bedingung

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

**Version.** Die Version einer Datei auf einem WebDAV-Server ist ihr starkes ETag, ohne Anführungszeichen. Der lokale Ordner nutzt weiter die sha256-Prüfsumme des Inhalts (E1). Beide Orte liefern dieselbe Form, die Werkzeuge sehen keinen Unterschied. Fehlt ein ETag oder ist es schwach (`W/`), gilt [E9](0009-version-ohne-etag.md): Die Version ist dann die Prüfsumme der Bytes, und der Server erzwingt keine Stand-Prüfung; die Schreibantwort sagt es.

**Schreiben.** Ersetzen per `PUT` mit `If-Match: "<ETag>"`, Neuanlegen per `PUT` mit `If-None-Match: *`. Der Server lehnt mit `412` ab, wenn sich die Datei geändert hat; das wird ein Konflikt. Vor dem Schreiben prüft das Plugin den Stand trotzdem, damit die Antwort den Grund nennt und keine Freigabe für einen Schreibvorgang gefragt wird, der ohnehin scheitert. Nach dem Schreiben liest das Plugin die Datei zurück; `verifiziert` nur bei gleichen Bytes (E1).

**Ordner und Verschieben.** Fehlende Ordner entstehen per `MKCOL`; `405` heißt „ist schon da“. Verschoben wird per `MOVE` mit `Overwrite: F`: Ein vorhandenes Ziel bleibt unangetastet und ist ein Konflikt.

**Ausfall.** Verbindungsfehler, Zeitablauf (Zeitlimit, Vorgabe 20 Sekunden) und Serverfehler (`5xx`) zählen als „der Ort antwortet nicht“ (`KontextNichtErreichbar`). Nur dieser Fehler führt zum Ausstand (E2). Anmeldung (`401`, `403`), Weiterleitungen (`3xx`), eine fehlende Wurzel (`404`), ein Zertifikat, das nicht vertraut wird, und Adressfehler sind Ursachen, die sichtbar bleiben, und kommen nie in den Ausstand.

**Weiterleitungen** werden nicht gefolgt. Die Zugangsdaten gehen nur an die eingetragene Adresse.

## Verworfen

- Die Prüfsumme des Inhalts als Version auch bei Servern mit starkem ETag: Der Server kennt sie nicht; ein zweiter Abruf vor dem Schreiben löst den Wettlauf nicht, den `If-Match` schließt.
- Sperren (`LOCK`): Die Server verhalten sich unterschiedlich, und eine vergessene Sperre blockiert die Datei.
- Den Zeitstempel (`Last-Modified`) als Version: Die Auflösung ist eine Sekunde, zwei Änderungen in derselben Sekunde blieben unbemerkt.
- Bei einem Server mit starkem ETag nur vor dem Schreiben vergleichen: Der Wettlauf bliebe offen, obwohl der Server die Bedingung erzwingen kann. Nur ohne starkes ETag bleibt es dabei (E9).
