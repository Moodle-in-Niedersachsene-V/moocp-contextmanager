#!/usr/bin/env bash
# Baut das Plugin zu einem fertigen Plugin-Ordner: übersetzt das Programm mit
# `dart compile exe` unter dem Namen, den `programm` in plugin.json nennt, und
# legt es mit plugin.json und skills/ in den Zielordner (Linux und Mac; Windows
# folgt mit eigenem Skript).
#
#   bash bauen.sh [Zielordner]
#
# Vorgabe für den Zielordner ist build/context in diesem Projekt. Ein Zielordner,
# der nicht leer ist und keine plugin.json enthält, bricht das Skript ab, ohne
# etwas zu ändern. Sonst ersetzt es dort Programm, plugin.json und skills/.
# Das dart kommt aus dem Suchpfad oder aus der Umgebungsvariablen DART.
set -euo pipefail

ORDNER="$(cd "$(dirname "$0")" && pwd)"
ZIEL="${1:-$ORDNER/build/context}"
DART="${DART:-dart}"

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
rm -rf "$ZIEL/$PROGRAMM"
mv "$ZIEL/$PROGRAMM.neu" "$ZIEL/$PROGRAMM"
cp plugin.json "$ZIEL/plugin.json"
if [[ -d skills ]]; then
  rm -rf "$ZIEL/skills"
  cp -R skills "$ZIEL/skills"
fi
echo "Das Plugin liegt fertig in $ZIEL"
