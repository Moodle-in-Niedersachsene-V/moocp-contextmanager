# E2 Ausstand: Schreibvorgänge bei nicht antwortendem Ort

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

**Was in den Ausstand kommt.** Ein gültiger Schreibauftrag (`context_write`, `context_append`), dessen Ort nicht antwortet: Die Wurzel fehlt oder ist nicht lesbar. Konflikte, Abweisungen (Pfad, Art, Zusammenfassung, Journal) und Fehler der Einstellungen kommen nie in den Ausstand; sie werden wie bisher gemeldet.

**Wo.** Im Datenordner des Plugins, im Ordner `ausstand/` neben der Einstellungsdatei. Je Vorgang eine JSON-Datei mit Kennung, Zeitpunkt (UTC), Ziel, Art, Zusammenfassung, Inhalt, erwarteter Version und der Angabe, ob angehängt wird. Geschrieben wird über eine temporäre Datei und ein Umbenennen. Der Ausstand liegt nie in der Wurzel: Kein Werkzeug liest ihn als Kontext. Ordner und Dateien sind nur für die Benutzerin lesbar (POSIX: 0700 und 0600), damit die Vorgänge nicht über das Konto anderer Nutzer sichtbar werden.

**Ort.** Jeder Vorgang trägt die Kennung seines Ortes: der Wurzelordner oder die WebDAV-Adresse, nie ein Passwort. Die Wiederholung schreibt einen Vorgang nur an den Ort, an dem er entstand. Gehört er zu einem anderen Ort oder zu keinem erfassten, bleibt er stehen und wird gemeldet.

**Freigabe.** Ist der Ort nicht erreichbar, wird nichts geschrieben und daher nicht gefragt. Die Freigabe kommt bei der Wiederholung, mit der Stufe der Art wie bei jedem Schreiben. Verschwindet der Ort erst nach der Freigabe, aber vor dem Schreiben, wird der Vorgang zurückgestellt und bei der Wiederholung erneut gefragt.

**Wiederholen.** Nur auf Anfrage: `context_start` mit `wiederholen: true`. Die Vorgänge laufen der Reihe nach: Ort öffnen, Stand gegen die gespeicherte Version prüfen, Freigabe, Schreiben, Zurücklesen. Nur ein bestätigtes Ergebnis entfernt einen Vorgang. Bei einem Konflikt wird nichts geschrieben und nichts überschrieben; der Vorgang bleibt, die übrigen laufen weiter. Eine Ablehnung entfernt den Vorgang. Ein Abbruch oder Zeitablauf der Freigabe, ein nicht bestätigtes Zurücklesen und andere Fehler lassen den Vorgang stehen. Antwortet der Ort wieder nicht, hält die Wiederholung an und der Rest bleibt.

**Antwort.** Ein zurückgestellter Schreibauftrag meldet „not saved yet“ mit seiner Kennung. Die Antwort trägt kein Fehlerkennzeichen, weil der Vorgang gehalten ist; sie sagt aber deutlich, dass er nicht im Kontextbereich steht und nicht noch einmal geschrieben werden soll.

**Start.** `context_start` antwortet auch ohne Ort: mit der Lage oder der Kontextlücke samt Ursache, dem Ausstand, dem Wurzelindex und den Wurzelgewohnheiten. Fehlt eine der beiden Dateien, steht „missing“ da. Ein Eintrag im Ausstand, der sich nicht lesen lässt, stoppt die Wiederholung und wird mit Namen genannt; er wird weder übergangen noch gelöscht.

## Verworfen

- Den Ausstand in die Wurzel oder in einen Ordner des Kontextbereichs legen: Dann läse ihn `context_list` oder `context_read` als Kontext, und ein Ausfall könnte die Wurzel verändern, die gerade nicht antwortet.
- Die Vorgänge nur im Speicher des laufenden Plugins halten: Ein Neustart von moocp verlöre sie.
- Beim Lesen oder Schreiben automatisch wiederholen: Dann liefe eine Freigabe ohne Anlass. Die Wiederholung geschieht nur auf Anfrage.
- Schon beim Zurückstellen fragen: Die Lehrkraft würde für einen Vorgang gefragt, der noch nicht geschrieben werden kann, und ein zweites Mal beim Wiederholen.
- Beim Wiederholen ohne neue Freigabe schreiben: Die Lehrkraft hätte keine Gelegenheit mehr, einen Vorgang abzulehnen, den sie vor Tagen bestätigt hat, dessen Lage sich inzwischen geändert haben kann.
- Einen Vorgang mit Konflikt beim Wiederholen überschreiben oder die übrigen anhalten: Ein Konflikt betrifft nur seine Datei.
