#!/usr/bin/env bash
# Startet das Plugin zum Entwickeln und hängt es an moocp an (README,
# Entwicklerhandbuch). Mit dieser Fassung für Linux und Mac; das Muster folgt
# dem Beispiel-Plugin von moocp.
#
#   bash entwickeln.sh <Pfad zum Programm von moocp>
#
# 1. Einen zufälligen Schlüssel erzeugen und in MOOCP_PLUGIN_SCHLUESSEL legen,
#    nie auf die Kommandozeile.
# 2. Das Plugin auf dem Port aus entwicklungsPort in plugin.json starten, aus
#    dem Quelltext mit `dart run`, mit --entwicklung.
# 3. moocp mit --plugin-entwicklung <dieser Ordner> starten.
set -euo pipefail

ORDNER="$(cd "$(dirname "$0")" && pwd)"
MOOCP="${1:-}"
if [[ -z "$MOOCP" || ! -x "$MOOCP" ]]; then
  echo 'Bitte den Pfad zum Programm von moocp als ersten Parameter angeben.' >&2
  exit 2
fi
PORT="$(sed -n 's/.*"entwicklungsPort"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ORDNER/plugin.json" | head -n 1)"
if [[ -z "$PORT" ]]; then
  echo 'plugin.json nennt keinen entwicklungsPort.' >&2
  exit 2
fi

MOOCP_PLUGIN_SCHLUESSEL="$(head -c 32 /dev/urandom | base64 | tr -d '\n=' | tr '+/' '-_')"
export MOOCP_PLUGIN_SCHLUESSEL

cd "$ORDNER"
# Ist das Einstellungsfenster gebaut (bauen.sh), öffnet das Plugin es von dort.
# Auf dem Mac direkt aus dem Bau von flutter, ohne das Archiv (E11).
if [[ "$(uname -s)" == Darwin ]]; then
  FENSTER="$ORDNER/fenster/build/macos/Build/Products/Release/kontext_einstellungen.app/Contents/MacOS/kontext_einstellungen"
else
  FENSTER="$ORDNER/build/context/einstellungsfenster/kontext_einstellungen"
fi
FENSTER_ARG=()
if [[ -x "$FENSTER" ]]; then FENSTER_ARG=(--fenster "$FENSTER"); fi
PLUGIN=""
trap '[[ -n "$PLUGIN" ]] && kill "$PLUGIN" 2>/dev/null; exit 130' INT TERM
trap '[[ -n "$PLUGIN" ]] && kill "$PLUGIN" 2>/dev/null || true' EXIT
MOOCP_GESTARTET=""
while true; do
  dart run bin/context.dart --port "$PORT" --entwicklung "${FENSTER_ARG[@]}" &
  PLUGIN=$!
  if [[ -z "$MOOCP_GESTARTET" ]]; then
    echo "Das Plugin läuft auf 127.0.0.1:$PORT. moocp startet und fragt, ob es das Plugin anhängen soll."
    "$MOOCP" --plugin-entwicklung "$ORDNER" >/dev/null 2>&1 &
    MOOCP_GESTARTET=1
  else
    echo "Das Plugin läuft wieder auf 127.0.0.1:$PORT, mit demselben Schlüssel."
  fi
  wait "$PLUGIN" || true
  PLUGIN=""
  read -r -p 'Das Plugin ist beendet. Enter startet es neu, Strg+C beendet: ' || exit 0
done
