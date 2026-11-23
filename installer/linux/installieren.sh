#!/usr/bin/env bash
# Installiert das moocp-Plugin @ANZEIGENAME@ @VERSION@ für den angemeldeten
# Benutzer oder entfernt es wieder. Liegt im Installationsarchiv neben dem Ordner
# plugin/ (installer_linux.sh).
#
#   bash installieren.sh              installieren oder aktualisieren
#   bash installieren.sh --entfernen  entfernen
#
# Was moocp vom Installer eines Plugins erwartet (README von moocp, „Plugins“):
# - Das Plugin kommt nach plugins/<kurzname> im Einstellungsordner von moocp,
#   $XDG_CONFIG_HOME/moocp, sonst ~/.config/moocp, und nirgends sonst hin.
# - Ohne moocp bricht das Skript ab, bevor es etwas schreibt.
# - Es läuft ohne Administratorrechte und lehnt root ab.
# - Es beendet nie einen Prozess. Läuft das Plugin (oder sein Einstellungsfenster),
#   bricht es mit der Bitte ab, moocp zu schließen.
# - Es ersetzt den Plugin-Ordner ganz, damit die Prüfsumme der Zustimmung nur
#   enthält, was zur neuen Version gehört. Einstellungen und Ausstand im
#   Datenordner (~/.config/moocp-contextmanager) und das Passwort im
#   Schlüsselbund fasst es nie an.
set -euo pipefail

KURZNAME='@KURZNAME@'
VERSION='@VERSION@'
ANZEIGENAME='@ANZEIGENAME@'

fehler() { echo "Abbruch: $*" >&2; exit 1; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUELLE="$HIER/plugin"

if [[ "$(id -u)" == 0 ]]; then
  fehler 'Bitte als normaler Benutzer ausführen, nicht als root: Das Plugin gehört in den Einstellungsordner des Benutzers, und es braucht keine Administratorrechte.'
fi
if [[ "$(uname -s)" != Linux ]]; then
  fehler 'Dieses Skript ist für Linux.'
fi

# moocp: $XDG_CONFIG_HOME, wenn es ein absoluter Pfad ist, sonst ~/.config.
BASIS="${XDG_CONFIG_HOME:-}"
if [[ -z "$BASIS" || "$BASIS" != /* ]]; then
  [[ -n "${HOME:-}" ]] || fehler 'HOME ist nicht gesetzt.'
  BASIS="$HOME/.config"
fi
MOOCP="$BASIS/moocp"
PLUGINS="$MOOCP/plugins"
ZIEL="$PLUGINS/$KURZNAME"

if [[ ! -d "$MOOCP" ]]; then
  fehler "moocp ist auf diesem Rechner nicht eingerichtet ($MOOCP fehlt). Bitte zuerst moocp installieren und einmal starten, dann dieses Skript noch einmal ausführen."
fi

# Läuft ein Programm aus dem Plugin-Ordner (das Plugin selbst oder sein
# Einstellungsfenster), liefe es aus Dateien, die gleich ersetzt werden. Es wird
# nie beendet: moocp beendet seine Plugins selbst, wenn es regulär geschlossen wird.
laeuft_noch() {
  local p exe
  for p in /proc/[0-9]*; do
    exe="$(readlink "$p/exe" 2>/dev/null || true)"
    case "$exe" in
      "$ZIEL"/*) return 0 ;;
    esac
  done
  return 1
}
if [[ -d "$ZIEL" ]] && laeuft_noch; then
  fehler "Das Plugin $ANZEIGENAME läuft noch. Bitte moocp schließen (das beendet das Plugin) und dieses Skript noch einmal ausführen. Es wurde nichts verändert."
fi

if [[ "${1:-}" == --entfernen ]]; then
  if [[ -L "$ZIEL" ]]; then rm -f "$ZIEL"; else rm -rf "$ZIEL"; fi
  [[ ! -e "$ZIEL" ]] || fehler "Der Plugin-Ordner ließ sich nicht entfernen: $ZIEL"
  echo "Das Plugin $ANZEIGENAME ist entfernt ($ZIEL)."
  echo "Einstellungen ($BASIS/moocp-contextmanager) und das Passwort im Schlüsselbund bleiben stehen; löschen Sie sie bei Bedarf von Hand. Die Skills bietet moocp beim nächsten Start zum Entfernen an."
  exit 0
elif [[ -n "${1:-}" ]]; then
  fehler "Unbekannte Option: $1 (erlaubt ist nur --entfernen)"
fi

# Vollständigkeit des Archivs, bevor etwas angefasst wird.
for datei in plugin.json "$KURZNAME.exe" einstellungsfenster/kontext_einstellungen skills/context/SKILL.md; do
  [[ -f "$QUELLE/$datei" ]] || fehler "Das Archiv ist unvollständig ($datei fehlt). Bitte neu herunterladen."
done
if [[ -n "$(find "$QUELLE" -type l)" ]]; then
  fehler 'Das Archiv enthält eine Verknüpfung; moocp würde das Plugin ablehnen.'
fi

# Erst neben dem Ziel vollständig ablegen, dann den alten Ordner ersetzen: Bricht
# das Kopieren ab, bleibt der alte Stand.
mkdir -p "$PLUGINS"
NEU="$PLUGINS/.$KURZNAME.neu.$$"
trap 'rm -rf "$NEU"' EXIT
rm -rf "$NEU"
cp -R "$QUELLE" "$NEU"
chmod 755 "$NEU/$KURZNAME.exe" "$NEU/einstellungsfenster/kontext_einstellungen"
if [[ -L "$ZIEL" ]]; then rm -f "$ZIEL"; else rm -rf "$ZIEL"; fi
[[ ! -e "$ZIEL" ]] || fehler "Der alte Plugin-Ordner ließ sich nicht entfernen: $ZIEL"
mv "$NEU" "$ZIEL"

echo "Das Plugin $ANZEIGENAME $VERSION ist installiert: $ZIEL"
echo 'moocp fragt beim nächsten Start nach Ihrer Zustimmung zu dieser Version.'
if ! command -v secret-tool >/dev/null 2>&1; then
  echo 'HINWEIS: secret-tool fehlt (Paket libsecret-tools). Ohne es kann das Plugin das Passwort eines WebDAV-Servers weder speichern noch lesen; ein lokaler Ordner geht auch ohne.' >&2
fi
