#!/usr/bin/env bash
# Baut das Plugin zu einem fertigen Plugin-Ordner: übersetzt das Programm mit
# `dart compile exe` unter dem Namen, den `programm` in plugin.json nennt, baut
# das Einstellungsfenster (fenster/, Flutter, E8) und legt beides mit plugin.json
# und skills/ in den Zielordner, unter Linux und macOS (Windows: Issue #17).
#
#   bash bauen.sh [Zielordner]
#
# Vorgabe für den Zielordner ist build/context in diesem Projekt. Ein Zielordner,
# der nicht leer ist und keine plugin.json enthält, bricht das Skript ab, ohne
# etwas zu ändern. Sonst ersetzt es dort Programm, plugin.json, skills/ und das
# Einstellungsfenster: unter Linux als Ordner einstellungsfenster/, auf dem Mac
# als Archiv einstellungsfenster.zip (E11).
# Das dart kommt aus dem Suchpfad oder aus der Umgebungsvariablen DART, das
# flutter aus dem Suchpfad oder aus FLUTTER.
set -euo pipefail

ORDNER="$(cd "$(dirname "$0")" && pwd)"
ZIEL="${1:-$ORDNER/build/context}"
DART="${DART:-dart}"
FLUTTER="${FLUTTER:-flutter}"

# Das Einstellungsfenster gibt es für Linux und macOS. Auf anderen Systemen wird
# das Plugin ohne Fenster gebaut, und das Skript sagt es. BAUEN_SYSTEM
# überschreibt das System (nur zum Prüfen der Zweige).
SYSTEM="${BAUEN_SYSTEM:-$(uname -s)}"
case "$SYSTEM" in
  Linux) FENSTER_BAUEN=linux ;;
  Darwin) FENSTER_BAUEN=macos ;;
  *)
    FENSTER_BAUEN=
    echo 'WARNUNG: Auf diesem System gibt es kein Einstellungsfenster (nur Linux und macOS). Das Plugin wird ohne Fenster gebaut; die Einrichtung ist dann nur von Hand möglich.' >&2
    ;;
esac

# Ohne jq: der Text hinter "programm" in plugin.json.
PROGRAMM="$(sed -n 's/.*"programm"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ORDNER/plugin.json" | head -n 1)"
if [[ -z "$PROGRAMM" ]]; then
  echo 'plugin.json nennt kein programm.' >&2
  exit 2
fi
if [[ -e "$ZIEL" && ! -d "$ZIEL" ]]; then
  echo "Der Zielordner ist eine Datei: $ZIEL" >&2
  exit 2
fi
if [[ -d "$ZIEL" && -n "$(ls -A "$ZIEL")" && ! -f "$ZIEL/plugin.json" ]]; then
  echo "Der Zielordner ist nicht leer und kein Plugin-Ordner: $ZIEL" >&2
  exit 2
fi
mkdir -p "$ZIEL"
ZIEL="$(cd "$ZIEL" && pwd)"

# Erst übersetzen, dann ersetzen: Schlägt das Übersetzen fehl, bleibt der
# Zielordner, wie er war.
cd "$ORDNER"
"$DART" compile exe bin/context.dart -o "$ZIEL/$PROGRAMM.neu"
# Das Einstellungsfenster als Bündel (Programm samt lib/ und data/), wie
# flutter es baut; das Plugin startet das Programm darin (Einstellungsfenster.standard).
if [[ "$FENSTER_BAUEN" == linux ]]; then
  (cd "$ORDNER/fenster" && "$FLUTTER" build linux --release)
  # Der Ordner heißt nach der Architektur (x64, arm64): der erste Treffer zählt.
  FENSTER_BUENDEL="$(ls -d "$ORDNER"/fenster/build/linux/*/release/bundle 2>/dev/null | head -n 1 || true)"
  if [[ -z "$FENSTER_BUENDEL" || ! -x "$FENSTER_BUENDEL/kontext_einstellungen" ]]; then
    echo "Das Einstellungsfenster fehlt nach dem Bauen: $ORDNER/fenster/build/linux/*/release/bundle" >&2
    rm -f "$ZIEL/$PROGRAMM.neu"
    exit 1
  fi
fi
# Auf dem Mac ist das Fenster eine .app mit Verknüpfungen in ihren Frameworks.
# moocp lehnt einen Plugin-Ordner mit Verknüpfungen ab (Prüfsumme der
# Zustimmung); deshalb kommt das Bündel als Archiv in den Plugin-Ordner, und das
# Plugin packt es vor dem Öffnen in seinen Datenordner aus (E11). ditto erhält
# Verknüpfungen, Rechte und die Signatur des Bündels.
if [[ "$FENSTER_BAUEN" == macos ]]; then
  (cd "$ORDNER/fenster" && "$FLUTTER" build macos --release)
  FENSTER_APP="$ORDNER/fenster/build/macos/Build/Products/Release/kontext_einstellungen.app"
  if [[ ! -x "$FENSTER_APP/Contents/MacOS/kontext_einstellungen" ]]; then
    echo "Das Einstellungsfenster fehlt nach dem Bauen: $FENSTER_APP" >&2
    rm -f "$ZIEL/$PROGRAMM.neu"
    exit 1
  fi
  rm -f "$ZIEL/einstellungsfenster.zip.neu"
  ditto -c -k --keepParent "$FENSTER_APP" "$ZIEL/einstellungsfenster.zip.neu"
fi
rm -rf "$ZIEL/$PROGRAMM"
mv "$ZIEL/$PROGRAMM.neu" "$ZIEL/$PROGRAMM"
# Ein altes Fenster im Zielordner passt zu keinem neuen Stand: weg damit.
rm -rf "$ZIEL/einstellungsfenster" "$ZIEL/einstellungsfenster.zip"
if [[ "$FENSTER_BAUEN" == linux ]]; then
  cp -R "$FENSTER_BUENDEL" "$ZIEL/einstellungsfenster"
fi
if [[ "$FENSTER_BAUEN" == macos ]]; then
  mv "$ZIEL/einstellungsfenster.zip.neu" "$ZIEL/einstellungsfenster.zip"
fi
cp plugin.json "$ZIEL/plugin.json"
if [[ -d skills ]]; then
  rm -rf "$ZIEL/skills"
  cp -R skills "$ZIEL/skills"
fi
echo "Das Plugin liegt fertig in $ZIEL"
