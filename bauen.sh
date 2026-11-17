#!/usr/bin/env bash
# Baut das Plugin zu einem fertigen Plugin-Ordner: übersetzt das Programm mit
# `dart compile exe` unter dem Namen, den `programm` in plugin.json nennt, baut
# das Einstellungsfenster (fenster/, Flutter, E8) und legt beides mit plugin.json
# und skills/ in den Zielordner (Linux; Mac und Windows folgen mit eigenen Schritten).
#
#   bash bauen.sh [Zielordner]
#
# Vorgabe für den Zielordner ist build/context in diesem Projekt. Ein Zielordner,
# der nicht leer ist und keine plugin.json enthält, bricht das Skript ab, ohne
# etwas zu ändern. Sonst ersetzt es dort Programm, plugin.json, skills/ und das
# Einstellungsfenster unter dem Namen einstellungsfenster/.
# Das dart kommt aus dem Suchpfad oder aus der Umgebungsvariablen DART, das
# flutter aus dem Suchpfad oder aus FLUTTER.
set -euo pipefail

ORDNER="$(cd "$(dirname "$0")" && pwd)"
ZIEL="${1:-$ORDNER/build/context}"
DART="${DART:-dart}"
FLUTTER="${FLUTTER:-flutter}"

# Das Einstellungsfenster gibt es bisher nur für Linux (fenster/linux). Auf dem
# Mac fehlt fenster/macos: Dort wird das Plugin ohne Fenster gebaut, und das
# Skript sagt es. BAUEN_SYSTEM überschreibt das System (nur zum Prüfen des Zweigs).
SYSTEM="${BAUEN_SYSTEM:-$(uname -s)}"
FENSTER_BAUEN=1
if [[ "$SYSTEM" != Linux ]]; then
  FENSTER_BAUEN=0
  echo 'WARNUNG: Das Einstellungsfenster gibt es auf diesem System noch nicht (fenster/macos fehlt). Das Plugin wird ohne Fenster gebaut; die Einrichtung ist dann nur von Hand möglich.' >&2
fi

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
# flutter es baut; das Plugin startet das Programm darin (standardFensterProgramm).
if [[ "$FENSTER_BAUEN" == 1 ]]; then
  (cd "$ORDNER/fenster" && "$FLUTTER" build linux --release)
  FENSTER_BUENDEL="$ORDNER/fenster/build/linux/x64/release/bundle"
  if [[ ! -x "$FENSTER_BUENDEL/kontext_einstellungen" ]]; then
    echo "Das Einstellungsfenster fehlt nach dem Bauen: $FENSTER_BUENDEL" >&2
    rm -f "$ZIEL/$PROGRAMM.neu"
    exit 1
  fi
fi
rm -rf "$ZIEL/$PROGRAMM"
mv "$ZIEL/$PROGRAMM.neu" "$ZIEL/$PROGRAMM"
# Ein altes Fenster im Zielordner passt zu keinem neuen Stand: weg damit.
rm -rf "$ZIEL/einstellungsfenster"
if [[ "$FENSTER_BAUEN" == 1 ]]; then
  cp -R "$FENSTER_BUENDEL" "$ZIEL/einstellungsfenster"
fi
cp plugin.json "$ZIEL/plugin.json"
if [[ -d skills ]]; then
  rm -rf "$ZIEL/skills"
  cp -R skills "$ZIEL/skills"
fi
echo "Das Plugin liegt fertig in $ZIEL"
