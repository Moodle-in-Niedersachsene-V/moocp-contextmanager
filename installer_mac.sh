#!/usr/bin/env bash
# Baut den Installer des Plugins für macOS: erst den Plugin-Ordner mit bauen.sh,
# dann ein Paket mit pkgbuild und productbuild. Ergebnis:
# installer/<kurzname>_setup_<Version>.pkg, hier installer/context_setup_<Version>.pkg.
# Kurzname, Version und Name kommen aus plugin.json; die Version steht nur dort.
# Das Gegenstück für Windows ist create_installer.bat im Beispiel-Plugin von
# moocp; was der Installer tun muss, steht in installer/macos/distribution.xml.
#
#   bash installer_mac.sh
#
# Voraussetzungen: macOS mit Apple Silicon, dart und flutter (wie bauen.sh) und
# die Kommandozeilenwerkzeuge von Xcode (pkgbuild, productbuild).
#
# Das Paket ist nicht signiert: Ohne Developer ID von Apple warnt macOS beim
# ersten Öffnen (README, Installation auf dem Mac).
set -euo pipefail

ORDNER="$(cd "$(dirname "$0")" && pwd)"
cd "$ORDNER"

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Der Installer für macOS wird auf einem Mac gebaut.' >&2
  exit 2
fi
# dart compile exe übersetzt nur für den eigenen Prozessor; das Paket nennt
# arm64 als einzige Architektur (distribution.xml).
if [[ "$(uname -m)" != arm64 ]]; then
  echo 'Der Installer wird auf einem Mac mit Apple Silicon gebaut (arm64).' >&2
  exit 2
fi
for werkzeug in pkgbuild productbuild plutil ditto; do
  if ! command -v "$werkzeug" >/dev/null 2>&1; then
    echo "$werkzeug nicht gefunden: xcode-select --install" >&2
    exit 2
  fi
done

# Die Werte aus plugin.json, geprüft wie in create_installer.bat: Kurzname wie in
# moocp (Kleinbuchstaben und Ziffern, höchstens 12 Zeichen), Version aus drei
# Zahlen, Name ohne Zeichen, die im XML oder sed stören.
wert() { plutil -extract "$1" raw -o - plugin.json 2>/dev/null || true; }
KURZNAME="$(wert kurzname)"
VERSION="$(wert version)"
ANZEIGENAME="$(wert name)"
if [[ ! "$KURZNAME" =~ ^[a-z][a-z0-9]{0,11}$ || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'plugin.json: kurzname oder version fehlt oder passt nicht.' >&2
  exit 2
fi
if [[ -z "$ANZEIGENAME" || "$ANZEIGENAME" =~ [\<\>\&\"\|\\] ]]; then
  echo 'plugin.json: name fehlt oder enthält eines der Zeichen < > & " | \' >&2
  exit 2
fi
KENNUNG="de.moodle-in-niedersachsen.moocp-plugin.$KURZNAME"
PAKET="installer/${KURZNAME}_setup_${VERSION}.pkg"

echo "[1/3] Plugin $KURZNAME $VERSION bauen"
# Der Bauordner wird ganz neu angelegt: bauen.sh lässt in einem bestehenden
# Ordner stehen, was es nicht selbst hinlegt, und das Paket nimmt alles mit.
BAU="$ORDNER/build/$KURZNAME"
rm -rf "$BAU"
bash bauen.sh "$BAU"
# moocp lädt kein Plugin mit einer Verknüpfung im Ordner (Prüfsumme der
# Zustimmung); das Fenster liegt deshalb als Archiv darin (E11).
if [[ -n "$(find "$BAU" -type l)" ]]; then
  echo "Der Plugin-Ordner enthält eine Verknüpfung; moocp würde ihn ablehnen: $BAU" >&2
  exit 1
fi
if [[ ! -f "$BAU/einstellungsfenster.zip" ]]; then
  echo "Das Einstellungsfenster fehlt im Plugin-Ordner: $BAU" >&2
  exit 1
fi

echo "[2/3] Paket des Plugins bauen"
ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT
# Das Ziel ist relativ zum Benutzerordner, denn das Paket installiert nur dort
# (distribution.xml, domains).
pkgbuild \
  --root "$BAU" \
  --install-location "/Library/Application Support/moocp/plugins/$KURZNAME" \
  --identifier "$KENNUNG" \
  --version "$VERSION" \
  --scripts installer/macos/scripts \
  --ownership recommended \
  "$ARBEIT/plugin.pkg"

echo "[3/3] Installer bauen"
ersetze() {
  sed -e "s|@KURZNAME@|$KURZNAME|g" -e "s|@VERSION@|$VERSION|g" \
    -e "s|@ANZEIGENAME@|$ANZEIGENAME|g" -e "s|@KENNUNG@|$KENNUNG|g" "$1" > "$2"
}
mkdir -p "$ARBEIT/resources"
ersetze installer/macos/distribution.xml "$ARBEIT/distribution.xml"
for seite in installer/macos/resources/*.html; do
  ersetze "$seite" "$ARBEIT/resources/$(basename "$seite")"
done
rm -f "$PAKET"
productbuild \
  --distribution "$ARBEIT/distribution.xml" \
  --resources "$ARBEIT/resources" \
  --package-path "$ARBEIT" \
  "$PAKET"

echo "Fertig: $PAKET"
