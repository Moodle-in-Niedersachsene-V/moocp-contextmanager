# Glossar

Fachsprache dieses Projekts. Begriffe von moocp (Plugin, Instanzprofil, Freigabe, Arbeitsordner, Zusatzadresse) gelten wie in dessen Glossar und stehen hier nicht noch einmal.

**Kontextbereich**: Der Ordner mit den Dateien, die der KI Konventionen, Stand und Fachsprache der Lehrkraft mitgeben. _Vermeiden_: Kontextspeicher, Wissensbasis.

**Inhaltsverzeichnis**: Die Gliederung einer Datei über 100 Zeilen aus ihren Überschriften `##` und `###` mit Zeilenbereichen. Statt des Textes liefert `context_read` sie, bis die KI einen Abschnitt oder die ganze Datei verlangt.

**Abschnitt**: Eine Überschrift `##` oder `###` mit allem bis zur nächsten Überschrift gleicher oder höherer Ebene. Ein `##`-Abschnitt enthält seine `###`-Teile.

**Wurzel**: Der eine Ordner, unter dem der ganze Kontextbereich liegt. Außerhalb liest und schreibt das Plugin nichts, bis auf den Wegweiser im Materialordner (ADR 0005).

**Ausstand**: Die Schreibvorgänge, die der Kontextbereich nicht annehmen konnte, weil der Ort nicht antwortete. Sie liegen im Datenordner des Plugins, nicht im Kontextbereich, und werden auf Anfrage mit `context_start` nachgetragen. _Vermeiden_: Warteschlange, Puffer.

**Kontextlücke**: Der Zustand, in dem der Kontextbereich nicht gelesen werden kann. `context_start` nennt die Ursache. Planen im Chat bleibt erlaubt, aber ein gespeicherter Plan wird dann nicht aus dem Gedächtnis umgesetzt.

**Archiv**: Der Unterordner `archive/` eines Ordners im Kontextbereich, in den `context_archive` die alten Dateien verschiebt. Nichts darin wird gelöscht oder überschrieben. _Vermeiden_: Papierkorb, Müll.

**Konfliktkopie**: Die Datei, die ein Sync-Client anlegt, wenn zwei Geräte dieselbe Datei gleichzeitig ändern (etwa `plan (Conflicted copy).md`). Das Plugin meldet sie mit dem Namen des Originals und ändert sie nicht.

**Altes Layout**: Die Dateien aus Coursepilot (`CONTEXT.md` als Index, `status.md`, `journal-*.md`). Sie bleiben lesbar; neue Schreibvorgänge nutzen das neue Layout.

**Einstellungsfenster**: Das eigene Fenster (Programm `kontext_einstellungen` aus `fenster/`), in dem die Lehrkraft Ort und Passwort des Kontextbereichs einträgt und die Verbindung prüft. Es öffnet sich beim ersten Start ohne Einstellungen, einmal je Ausfall des Ortes und auf Wunsch der KI (`context_settings`), die dabei keine Werte sieht. _Vermeiden_: Konfigurationsdialog, Einstellungsmaske.

**Wegweiser**: Die Datei `CONTEXT-LINK.md` in einem Materialordner der Lehrkraft. Sie zeigt je Klasse auf die passende Stelle im Kontextbereich, damit die KI sie ohne Suche findet. _Vermeiden_: Verknüpfung, Link-Datei.

**Index**: Die Datei `index.md` jeder Ebene. Sie verweist nur auf die Ebenen darunter und auf die Dateien der eigenen Ebene, je mit einer Zeile dazu. _Vermeiden_: Inhaltsverzeichnis (das meint nur die Gliederung einer langen Datei).

**Ebene**: Eine Stufe des Kontextbereichs von der Wurzel bis zur Einheit: Wurzel, Fachbereich, Schuljahr, Klasse, Einheit. Eine tiefere Ebene gilt vor einer höheren nur, wo sie eine Abweichung ausdrücklich nennt.

**Fachbereich**: Eine Ebene unter der Wurzel für ein Fach, mit den Gewohnheiten und Standards, die für alle Klassen dieses Fachs gelten.

**Abweichung**: Eine ausdrückliche Festlegung einer tieferen Ebene, die von einer höheren abweicht. Ohne sie gilt die höhere Ebene; ein Widerspruch ohne Abweichung wird mit der Lehrkraft geklärt.

**Gewohnheit**: Eine Arbeitsweise der Lehrkraft, etwa wie sie Lernende anspricht oder Fragen baut. Sie steht in `habits.md` auf der allgemeinsten Ebene, auf die sie zutrifft. Dazu gehört der Aufschreibmodus.

**Entscheidung**: Eine überraschende Festlegung mit echter Alternative, als eigene kurze Datei in `decisions/`: die Lage, die Wahl, der Grund. _Vermeiden_: Protokoll, Beschluss.

**Grundaufbau**: Die gemeinsame Ordnung des Kontextbereichs (Ebenen mit `index.md`, `habits.md`, `glossary.md`, `decisions/`, `plan.md` oder `plan/`, `journal/`), die alle Lehrkräfte nutzen, damit ein Kontextbereich weitergegeben werden kann. Die Dateien beschreibt `skills/context/references/layout.md`.

**Eigene Datei**: Eine Datei für genau einen Gegenstand, etwa eine Entscheidung oder der Abschnitt einer Woche im Plan, statt alles in eine große Datei zu schreiben.

**Plan**: Der Zielzustand einer Einheit in `plan.md` oder `plan/`, geordnet nach Wochen oder Kursabschnitten. Jeder Abschnitt trägt seinen Zustand (`draft`, `approved`, `implemented`), seine Abweichungen und seine Restarbeit. _Vermeiden_: Statusdatei, Fahrplan.

**Stand**: Die Version einer Datei beim Lesen. Geschrieben wird nur mit dem Stand, den die KI gelesen hat; hat sich die Datei seither geändert, bricht das Schreiben mit einem Konflikt ab.

**Journal**: Die Tagesdatei `journal/YYYY-MM-DD.md` (alt: `journal-*.md`), in der Einträge nur angehängt, nie ersetzt werden. Die Geschichte steht im Journal, nicht im Plan.

**Nacharbeit**: Eine Korrektur, die den Inhalt nicht ändert, etwa ein Rechtschreibfehler. Sie geht in Plan und Journal, ohne die Freigabe zurückzusetzen.

**Planänderung**: Eine Änderung vorhandenen Plan-Inhalts. Der betroffene Abschnitt geht auf `draft` zurück und braucht die Freigabe erneut. Das Journal vermerkt sie.

**Planergänzung**: Neuer Inhalt, der nicht geplant war. Er braucht die Freigabe, und das Journal vermerkt ihn.

**Aufschreibmodus**: Die Gewohnheit, wann die KI vor dem Festhalten fragt: `ask` (Standard, fragt bei jeder wichtigen Entscheidung), `always` (schreibt ohne Frage in der Sitzung und meldet jede Schreibung) oder `wait` (sammelt die ungespeicherten Punkte in der Liste im Chat). _Vermeiden_: Schreibmodus.
