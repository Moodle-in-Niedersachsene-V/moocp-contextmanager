#!/usr/bin/env bash
# Baut das Installationsarchiv des Plugins für Linux (x64): erst den Plugin-Ordner
# mit bauen.sh, dann ein tar.gz mit dem Ordner plugin/ und installieren.sh.
# Ergebnis: installer/<kurzname>_linux_x64_<Version>.tar.gz, hier
# installer/context_linux_x64_<Version>.tar.gz. Kurzname, Version und Name kommen
# aus plugin.json; die Version steht nur dort.
#
#   bash installer_linux.sh
#
# Voraussetzungen: Linux auf x86_64 (dart compile exe übersetzt nur für den
# eigenen Prozessor), dart und flutter (wie bauen.sh) und die Pakete für den
# Flutter-Bau unter Linux (README, Entwicklerhandbuch).
set -euo pipefail

ORDNER="$(cd "$(dirname "$0")" && pwd)"
cd "$ORDNER"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'Das Installationsarchiv für Linux wird auf Linux mit x86_64 gebaut.' >&2
  exit 2
fi

wert() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" plugin.json | head -n 1; }
KURZNAME="$(wert kurzname)"
VERSION="$(wert version)"
ANZEIGENAME="$(wert name)"
if [[ ! "$KURZNAME" =~ ^[a-z][a-z0-9]{0,11}$ || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'plugin.json: kurzname oder version fehlt oder passt nicht.' >&2
  exit 2
fi
if [[ -z "$ANZEIGENAME" || "$ANZEIGENAME" =~ [\<\>\&\"\|\\\'] ]]; then
  echo 'plugin.json: name fehlt oder enthält eines der Zeichen < > & " | \ '"'" >&2
  exit 2
fi
ARCHIV="installer/${KURZNAME}_linux_x64_${VERSION}.tar.gz"

echo "[1/2] Plugin $KURZNAME $VERSION bauen"
# Der Bauordner wird ganz neu angelegt: bauen.sh lässt in einem bestehenden
# Ordner stehen, was es nicht selbst hinlegt, und das Archiv nimmt alles mit.
BAU="$ORDNER/build/$KURZNAME"
rm -rf "$BAU"
bash bauen.sh "$BAU"
if [[ -n "$(find "$BAU" -type l)" ]]; then
  echo "Der Plugin-Ordner enthält eine Verknüpfung; moocp würde ihn ablehnen: $BAU" >&2
  exit 1
fi
if [[ ! -x "$BAU/einstellungsfenster/kontext_einstellungen" ]]; then
  echo "Das Einstellungsfenster fehlt im Plugin-Ordner: $BAU" >&2
  exit 1
fi

echo '[2/2] Archiv packen'
ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT
WURZEL="$ARBEIT/${KURZNAME}_linux_x64_${VERSION}"
mkdir -p "$WURZEL"
cp -R "$BAU" "$WURZEL/plugin"
sed -e "s|@KURZNAME@|$KURZNAME|g" -e "s|@VERSION@|$VERSION|g" \
  -e "s|@ANZEIGENAME@|$ANZEIGENAME|g" installer/linux/installieren.sh > "$WURZEL/installieren.sh"
chmod 755 "$WURZEL/installieren.sh"
mkdir -p installer
rm -f "$ARCHIV"
# Rechte bleiben erhalten (das Programm und das Fenster sind ausführbar); Besitzer
# und Zeit sind fest, damit dasselbe nur zu denselben Bytes führt.
tar -C "$ARBEIT" --owner=0 --group=0 --numeric-owner --sort=name \
  --mtime='2026-01-01 00:00:00 UTC' -czf "$ARCHIV" "$(basename "$WURZEL")"
echo "Fertig: $ARCHIV"
