# E9 Version auf WebDAV-Servern ohne starkes ETag

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md). Ergänzt [E3](0003-webdav-version-und-bedingtes-schreiben.md) für Server, die kein starkes ETag senden; keine Ausnahme zu A1 bis A7.

## Entscheidung

**Version.** Sendet der Server für eine Datei ein starkes ETag, bleibt es die Version und das Schreiben läuft wie in E3 mit `If-Match`. Sendet er keines oder nur ein schwaches (`W/`), ist die Version die Prüfsumme der gelesenen Bytes mit Präfix: `sha256:<hex>`. Das Präfix trennt sie vom ETag und von der Prüfsumme des lokalen Ortes, und die Schreibwege erkennen daran, dass der Server nichts erzwingen kann. Die Version wird bei jedem Lesen aus den Bytes des `GET` gebildet; der Server muss dafür nichts können.

**Schreiben ohne ETag.** Das Plugin liest die Datei unmittelbar vor dem `PUT` noch einmal und vergleicht die Prüfsumme mit der Version, die die KI gelesen hat. Weicht sie ab oder fehlt die Datei, ist das ein Konflikt, und es wird nichts geschrieben. Dann folgt das `PUT` ohne `If-Match`. Ebenso das Verschieben (`MOVE` mit `Overwrite: F`, ohne `If-Match`). Die Prüfsumme deckt die Größe ab; `Last-Modified` kommt nicht dazu, weil ein bloßes Berühren der Datei sonst einen Konflikt ohne Änderung erzeugte.

**Das Wettlauffenster bleibt offen.** Zwischen dem Vergleich und dem `PUT` kann ein anderer Schreiber (Sync-Client, andere Sitzung) die Datei ändern; das Plugin sieht es nicht, der Server lehnt es nicht ab, und die Änderung des anderen geht verloren. Das Rücklesen findet dann die Bytes des Plugins und meldet `verified`; es zeigt nur, dass die geschriebenen Bytes da sind, nicht dass niemand dazwischen war. Deshalb steht in jeder Antwort eines Schreibvorgangs (`context_write`, `context_append`, `context_archive`, wiederholter Vorgang aus dem Ausstand), bei dem der Server nichts erzwungen hat, eine Zeile `check: not enforced by the server …`. Die Antwort behauptet nie, der Server habe die Bedingung durchgesetzt (A3). Bei einem Server mit starkem ETag fehlt die Zeile.

**Neue Dateien.** Das Anlegen sendet weiter `If-None-Match: *`. Ob der Server es durchsetzt, zeigt sich nach dem Schreiben: Kennt er für die neue Datei kein starkes ETag, gilt die Prüfung als nicht erzwungen, und die Zeile steht in der Antwort.

**Kein stiller Ersatzweg.** Das Lesen auf einem Server ohne ETag ist keine Ausweichlösung, sondern der geregelte Weg dieser Entscheidung; er ist in der Version (`sha256:`) und in jeder Schreibantwort sichtbar. Ein Server, der gar nicht antwortet, bleibt ein Ausfall (E2, E3). Die Zugangsdaten sind davon nicht berührt (A6).

**Grenze.** Ein starkes ETag, das selbst mit `sha256:` beginnt, wird wie eine Prüfsumme behandelt: Das Plugin vergleicht dann selbst und sagt es in der Antwort. Das ist sicher, nur weniger streng.

## Verworfen

- Nur Lesen auf solchen Servern, Schreiben immer abgewiesen: Der Umbau eines Projekts (Ticket #13) braucht Schreiben, und der Vergleich unmittelbar vor dem `PUT` fängt die üblichen Änderungen (Sync-Client, zweite Sitzung während der Freigabe) ab; nur das Fenster dazwischen bleibt, und es ist benannt.
- `If-Unmodified-Since` mit `Last-Modified`: Die Auflösung ist eine Sekunde, und viele Server ohne ETag ignorieren den Kopf; das Plugin könnte nie wissen, ob er galt.
- Sperren (`LOCK`) für das Fenster: wie in E3, die Server verhalten sich unterschiedlich, und eine vergessene Sperre blockiert die Datei.
- `verified` bei nicht erzwungener Prüfung weglassen oder verneinen: `verified` heißt nach E1 „Bytes zurückgelesen“; die fehlende Erzwingung steht in der eigenen Zeile, damit die beiden Aussagen nicht vermischt werden.
- Die Prüfsumme auch bei Servern mit starkem ETag: Der Server schließt dort das Fenster, das wäre ein Rückschritt (E3).
