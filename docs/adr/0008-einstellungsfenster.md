# E8 Einstellungsfenster

Status: gilt. Die Regeln dazu stehen im Index der [CLAUDE.md](../../CLAUDE.md). Ergänzt E4 (Schlüsselbund) und E5 (Ordnerwahl); die Schnittstelle der App steht in E35 von moocp.

## Entscheidung

**Eigenes Fenster.** Die Einrichtung läuft in einem eigenen Flutter-Programm (`fenster/`), das `bauen.sh` in den Plugin-Ordner unter `einstellungsfenster/` legt. Die Dialoge der App reichen dafür nicht: Sie kennen kein verdecktes Feld, keine Gruppe aus Art, Adresse, Benutzer und Passwort und kein Ergebnis einer Prüfung, das neben den Feldern stehen bleibt (A1, „ein eigenes Fenster nur, wo ein Dialog der App nicht reicht“).

**Wann es sich öffnet.** Das Plugin öffnet das Fenster
- beim Start, wenn keine Einstellungsdatei da ist;
- bei einem Ausfall des Kontextbereichs (jede Ursache beim Öffnen des Ortes: fehlender Ordner, Anmeldung, Adresse, Zeitablauf), und zwar einmal je Ausfall. Erst wenn der Ort wieder antwortet, gilt der nächste Ausfall als neuer;
- auf Wunsch der KI mit `context_settings`, und nie zwei Fenster gleichzeitig.

**Was die KI sieht.** `context_settings` öffnet nur das Fenster. Die Antwort nennt keinen Wert der Einstellungen, auch nicht den Pfad der Datei oder des Ordners. Das Fenster bekommt den Pfad der Einstellungsdatei als Argument und sonst nichts (A6).

**Speichern.** Zuerst wird die Eingabe geprüft, dann das Passwort in den Schlüsselbund geschrieben, erst danach die Einstellungsdatei, und die Datei wird über eine Datei daneben umbenannt. Scheitert der Schlüsselbund, bleibt die Datei unberührt, und die Datei zeigt nie auf ein Passwort, das fehlt. Ein leeres Passwort im Fenster lässt den bisherigen Eintrag im Schlüsselbund stehen; das Fenster zeigt das Passwort nie an.

**Verbindungsprüfung.** Sie öffnet den Ort aus der Eingabe und listet den Wurzelordner, ohne etwas zu schreiben. Ein eingetragenes Passwort gilt nur für diese Prüfung; sonst liest sie den Schlüsselbund.

**Meldungen.** Das Fenster zeigt deutsche Meldungen. Die Übersetzung hängt an den englischen Meldungen des Plugins, und ein Test prüft jede Zuordnung gegen den echten Fehler, damit eine geänderte Meldung nicht still auf Englisch fällt. Eine unbekannte Meldung bekommt einen allgemeinen deutschen Satz ohne Rohtext.

**Schlüsselbund schreiben.** Linux über `secret-tool store` mit dem Passwort auf der Standardeingabe; macOS über `security -i`, damit das Passwort nie in einer Kommandozeile steht.

**Plattformen.** Das Fenster gibt es nur für Linux. Auf dem Mac baut `bauen.sh` das Plugin ohne Fenster.

## Verworfen

Die Dialoge der App für das Fenster: Sie können ein Feld nicht verdecken, und das Ergebnis einer Prüfung stünde nicht neben den Feldern. Ein Eintrag „Plugins“ in den Einstellungen von moocp als einziger Weg: Die App kennt ihn nicht, und das Fenster soll auch dann öffnen, wenn moocp nicht läuft. Das Passwort in der Einstellungsdatei oder über ein KI-Werkzeug (A6). `flutter_secure_storage` im Plugin: Das Plugin ist reines Dart (E4). Ein Fenster im Plugin selbst, das es ohne Flutter baut: Die Oberfläche braucht Flutter, das Plugin nicht.
