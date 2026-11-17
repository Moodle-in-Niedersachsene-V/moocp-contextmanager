# Glossar

Fachsprache dieses Projekts. Begriffe von moocp (Plugin, Instanzprofil, Freigabe, Arbeitsordner, Zusatzadresse) gelten wie in dessen Glossar und stehen hier nicht noch einmal.

**Kontextbereich**: Der Ordner mit den Dateien, die der KI Konventionen, Stand und Fachsprache der Lehrkraft mitgeben. _Vermeiden_: Kontextspeicher, Wissensbasis.

**Inhaltsverzeichnis**: Die Gliederung einer Datei über 100 Zeilen aus ihren Überschriften `##` und `###` mit Zeilenbereichen. Statt des Textes liefert `context_read` sie, bis die KI einen Abschnitt oder die ganze Datei verlangt.

**Abschnitt**: Eine Überschrift `##` oder `###` mit allem bis zur nächsten Überschrift gleicher oder höherer Ebene. Ein `##`-Abschnitt enthält seine `###`-Teile.

**Wurzel**: Der eine Ordner, unter dem der ganze Kontextbereich liegt. Außerhalb liest und schreibt das Plugin nichts.
