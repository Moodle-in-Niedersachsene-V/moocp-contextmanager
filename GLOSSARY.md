# Glossar

Fachsprache dieses Projekts. Begriffe von moocp (Plugin, Instanzprofil, Freigabe, Arbeitsordner, Zusatzadresse, Steckbrief) gelten wie in dessen Glossar und stehen hier nicht noch einmal.

## Der Kontextbereich

**Kontextbereich**:
Der Ordner der Lehrkraft außerhalb von Moodle, der Planung, Entscheidungen und Standards ihrer Unterrichtsarbeit mit Moodle über Kurse, Schuljahre und Instanzen hinweg bewahrt. CoursePilot und moocp arbeiten auf demselben Kontextbereich.
_Vermeiden_: Kontextspeicher, Wissensbasis, Arbeitsbereich

**Wurzel**:
Der eine Ordner, unter dem der ganze Kontextbereich liegt. Außerhalb liest und schreibt das Plugin nichts, bis auf den Wegweiser im Materialordner (ADR 0005).

**Index**:
Die Datei `index.md` jeder Ebene. Sie verweist nur auf die Ebenen darunter und auf Glossar, Gewohnheiten, Entscheidungen und Plan dieser Ebene, je mit einer Zeile, was dort steht. Sie enthält selbst keine Regeln.
_Vermeiden_: Kontextdatei, Inhaltsverzeichnis, Übersicht

**Fachbereich**:
Eine Ebene unter der Wurzel für ein Fach, mit den Gewohnheiten und Standards, die für alle Klassen dieses Fachs gelten, etwa ein Gestaltungsstandard.

**Inhaltsverzeichnis**:
Die Gliederung einer Datei über 100 Zeilen aus ihren Überschriften `##` und `###` mit Zeilenbereichen. Statt des Textes liefert `context_read` sie, bis die KI einen Abschnitt oder die ganze Datei verlangt.
_Vermeiden_: Index (der verweist auf Dateien, nicht auf Abschnitte)

**Abschnitt**:
Eine Überschrift `##` oder `###` mit allem bis zur nächsten Überschrift gleicher oder höherer Ebene. Ein `##`-Abschnitt enthält seine `###`-Teile.

**Eigene Datei**:
Eine Datei, die die Lehrkraft selbst angelegt und benannt hat, in ihrer Sprache. Feste Dateien des Werkzeugs tragen englische Namen; so ist auf einen Blick klar, was woher kommt.

**Ebene**:
Eine Stufe des Kontextbereichs von der Wurzel bis zur Einheit: Wurzel, Fachbereich, Schuljahr, Klasse, Einheit. Eine tiefere Ebene gilt vor einer höheren nur, wo sie eine Abweichung ausdrücklich nennt.

**Wegweiser**:
Die Datei `CONTEXT-LINK.md` in einem Materialordner der Lehrkraft, je Klasse genau eine. Sie zeigt auf die passende Stelle im Kontextbereich, damit die KI sie ohne Suche findet. Sie ist keine Planungsdatei und kein Index.
_Vermeiden_: Marker, Pointer, Verknüpfung, Link-Datei

**Abweichung**:
Eine ausdrückliche Festlegung einer tieferen Ebene, die von einer höheren abweicht. Ohne sie gilt die höhere Ebene; ein Widerspruch ohne Abweichung ist ein Fehler und wird mit der Lehrkraft geklärt.

**Gewohnheit**:
Eine Festlegung, die die Lehrkraft immer wieder gleich trifft und nicht jedes Mal neu entscheidet, etwa die Anrede oder der Aufbau von Fragen. Sie steht in `habits.md` auf der allgemeinsten Ebene, für die sie gilt, wird nach unten genauer und kann Vorgaben des Werkzeugs überschreiben.
_Vermeiden_: Konvention, Standard, Regel, Entscheidung

**Entscheidung**:
Eine einmalige Festlegung für ein Vorhaben, die ohne ihren Grund später überraschen würde und eine echte Alternative hatte, als eigene kurze Datei in `decisions/`: Lage, Wahl, Grund.
_Vermeiden_: Protokoll, Beschluss, Gewohnheit

**Grundaufbau**:
Die gemeinsame Ordnung des Kontextbereichs (Ebenen mit `index.md`, `habits.md`, `glossary.md`, `decisions/`, `plan.md` oder `plan/`, `journal/`), die alle Lehrkräfte gleich verwenden, damit sich ein Kontextbereich weitergeben lässt. Eigene Kategorien einer Lehrkraft sind erlaubt und stehen im Index. Die Dateien beschreibt `skills/context/references/layout.md`.

**Archiv**:
Der Unterordner `archive/` eines Ordners im Kontextbereich, in den `context_archive` die alten Dateien verschiebt. Nichts darin wird gelöscht oder überschrieben.
_Vermeiden_: Papierkorb, Müll

**Altes Layout**:
Die Dateien aus Coursepilot (`CONTEXT.md` als Index, `status.md`, `journal-*.md`). Sie bleiben lesbar; neue Schreibvorgänge nutzen das neue Layout.

**Konfliktkopie**:
Die Datei, die ein Sync-Client anlegt, wenn zwei Geräte dieselbe Datei gleichzeitig ändern (etwa `plan (Conflicted copy).md`). Das Plugin meldet sie mit dem Namen des Originals und ändert sie nicht.

**Einstellungsfenster**:
Das eigene Fenster (Programm `kontext_einstellungen` aus `fenster/`), in dem die Lehrkraft Ort und Passwort des Kontextbereichs einträgt und die Verbindung prüft. Es öffnet sich beim ersten Start ohne Einstellungen, einmal je Ausfall des Ortes und auf Wunsch der KI (`context_settings`), die dabei keine Werte sieht.
_Vermeiden_: Konfigurationsdialog, Einstellungsmaske

## Wenn der Ort nicht antwortet

**Ausstand**:
Ein gültiger Schreibvorgang für den Kontextbereich, der am Ort gescheitert ist und samt Inhalt aufbewahrt wird, bis er nachgetragen ist. Er liegt im Datenordner des Plugins, nicht im Kontextbereich, und wird auf Anfrage mit `context_start` nachgetragen. Ein Ausstand ist kein zweiter Kontextbereich: gelesen wird daraus nie.
_Vermeiden_: Zwischenspeicher, lokale Kopie, Offline-Modus, Warteschlange, Puffer

**Kontextlücke**:
Der Zustand, in dem der Kontextbereich nicht gelesen werden kann. `context_start` nennt die Ursache. Verloren ist dabei nichts; es fehlt nur, was nicht gelesen werden konnte. Planen im Chat bleibt erlaubt, aber ein gespeicherter Plan wird dann nicht aus dem Gedächtnis umgesetzt.

## Plan und Verlauf

**Plan**:
Der Sollstand eines Vorhabens in `plan.md` oder `plan/`, nach Inhalt (Wochen oder Kursabschnitte) geordnet und nie nach Datum gewachsen. Er ist ein Entwurf, bis die Lehrkraft ihn freigibt; nur ein freigegebener Plan, der im Kontextbereich steht, darf in den Moodle-Kurs.
_Vermeiden_: Statusdatei, Fahrplan

**Stand**:
Zwei Bedeutungen, beide im Code gebraucht. Der Stand einer Datei ist ihre Version beim Lesen: geschrieben wird nur mit dem gelesenen Stand, sonst bricht das Schreiben mit einem Konflikt ab. Der Stand eines Planabschnitts ist `draft`, `approved` oder `implemented`, dazu Abweichungen und Restarbeit; er steht am Abschnitt, nicht in einer zweiten Datei.
_Vermeiden_: Status als eigener Plan, Umsetzungsbericht, Abschlussstand

**Journal**:
Die Tagesdatei `journal/YYYY-MM-DD.md` (alt: `journal-*.md`), in der Einträge nur angehängt, nie ersetzt werden. Der Plan ist der Zustand, das Journal die Geschichte.

**Nacharbeit**:
Eine Korrektur an schon Geplantem, die am Inhalt nichts ändert, etwa Rechtschreibung oder ein kleiner Fehler. Sie geht in Plan und Journal, ohne die Freigabe zurückzusetzen.

**Planänderung**:
Eine inhaltliche Änderung an dem, was der Plan schon enthält. Der betroffene Abschnitt geht auf `draft` zurück und braucht die Freigabe erneut; das Journal vermerkt sie.

**Planergänzung**:
Neuer Inhalt im Plan, der bisher nicht bedacht war, etwa eine neue Aktivität. Er braucht die Freigabe, und das Journal vermerkt ihn.
_Vermeiden_: Erweiterung

**Aufschreibmodus**:
Die Gewohnheit, wann die KI vor dem Festhalten fragt: `ask` (Standard, fragt bei jeder wichtigen Entscheidung), `always` (schreibt ohne Frage in der Sitzung und meldet jede Schreibung) oder `wait` (sammelt die ungespeicherten Punkte in der Liste im Chat). Er steht im Kontextbereich, für alle Kurse oder für einen.
_Vermeiden_: Schreibmodus
