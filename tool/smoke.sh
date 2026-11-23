#!/usr/bin/env bash
# Installiert das gebaute Installationspaket so, wie die Lehrkraft es tut, und
# prüft das Ergebnis mit tool/smoke.dart: Linux (tar.gz mit installieren.sh),
# Windows (setup.exe, still) und macOS (pkg). Läuft im Workflow auf dem Runner des
# jeweiligen Systems, nie auf dem Rechner eines Benutzers: Es legt moocp-Ordner
# an und entfernt das Plugin am Ende wieder.
#
#   SMOKE=<kompiliertes tool/smoke.dart> bash tool/smoke.sh <Installer-Datei>
#
# Das Plugin läuft dabei ohne Dart und ohne Flutter im Suchpfad der Prüfung: Es
# ist ein übersetztes Programm. SMOKE ist das übersetzte smoke.dart.
set -euo pipefail

INSTALLER="${1:?Aufruf: bash tool/smoke.sh <Installer-Datei>}"
SMOKE="${SMOKE:?SMOKE zeigt auf das übersetzte tool/smoke.dart}"
INSTALLER="$(cd "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")"

fehl() { echo "SMOKE FEHLGESCHLAGEN: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }
# Startet ein Plugin, das nicht endet (die Standardeingabe bleibt offen), damit
# die Installer „Plugin läuft“ erkennen können.
STARTE_PID=""
starte_plugin() {
  local programm="$1" daten
  daten="$(mktemp -d)"
  echo '{"art":"lokal","pfad":"."}' > "$daten/einstellungen.json"
  tail -f /dev/null | MOOCP_PLUGIN_SCHLUESSEL=laufprobe "$programm" --port 47998 \
    --einstellungen "$daten/einstellungen.json" --entwicklung >/dev/null 2>&1 &
  STARTE_PID=$!
  sleep 3
}

case "$(uname -s)" in
  Linux)
    export HOME="${HOME:?}"
    BASIS="${XDG_CONFIG_HOME:-$HOME/.config}"
    ZIEL="$BASIS/moocp/plugins/context"
    ARBEIT="$(mktemp -d)"
    tar -xzf "$INSTALLER" -C "$ARBEIT"
    PAKET="$(ls -d "$ARBEIT"/context_linux_x64_*)"

    # Ohne moocp bricht die Installation ab, ohne etwas zu schreiben.
    LEER="$(mktemp -d)"
    if HOME="$LEER" XDG_CONFIG_HOME="" bash "$PAKET/installieren.sh" >/dev/null 2>&1; then
      fehl 'Die Installation ohne moocp hätte abbrechen müssen'
    fi
    [[ ! -e "$LEER/.config/moocp/plugins" ]] || fehl 'Die Installation ohne moocp hat Dateien angelegt'
    ok 'ohne moocp bricht die Installation ab'

    mkdir -p "$BASIS/moocp" "$BASIS/moocp-contextmanager"
    echo '{"art":"lokal","pfad":"/nicht/anfassen"}' > "$BASIS/moocp-contextmanager/einstellungen.json"
    bash "$PAKET/installieren.sh"
    [[ -x "$ZIEL/context.exe" ]] || fehl 'context.exe fehlt oder ist nicht ausführbar'
    [[ -x "$ZIEL/einstellungsfenster/kontext_einstellungen" ]] || fehl 'Einstellungsfenster fehlt oder ist nicht ausführbar'
    ok 'installiert, Rechte erhalten'

    starte_plugin "$ZIEL/context.exe"
    if bash "$PAKET/installieren.sh" >/dev/null 2>&1; then
      kill "$STARTE_PID" 2>/dev/null || true
      fehl 'Die Installation bei laufendem Plugin hätte abbrechen müssen'
    fi
    kill -0 "$STARTE_PID" 2>/dev/null || fehl 'Der Installer hat das laufende Plugin beendet'
    kill "$STARTE_PID" 2>/dev/null || true
    pkill -f "$ZIEL/context.exe" 2>/dev/null || true
    pkill -f "tail -f /dev/null" 2>/dev/null || true
    sleep 1
    ok 'bei laufendem Plugin bricht die Installation ab, ohne einen Prozess zu beenden'

    touch "$ZIEL/alte-datei.txt"
    bash "$PAKET/installieren.sh"
    [[ ! -e "$ZIEL/alte-datei.txt" ]] || fehl 'Das Update hat den Plugin-Ordner nicht ganz ersetzt'
    grep -q nicht/anfassen "$BASIS/moocp-contextmanager/einstellungen.json" || fehl 'Die Einstellungen wurden angefasst'
    ok 'Update ersetzt den Plugin-Ordner ganz, Einstellungen bleiben'

    # Mit Anzeige: Das Einstellungsfenster braucht eine (xvfb auf dem Runner).
    if [[ -n "${DISPLAY:-}" ]]; then "$SMOKE" "$ZIEL"; else xvfb-run -a "$SMOKE" "$ZIEL"; fi

    bash "$PAKET/installieren.sh" --entfernen
    [[ ! -e "$ZIEL" ]] || fehl 'Entfernen hat den Plugin-Ordner nicht gelöscht'
    [[ -f "$BASIS/moocp-contextmanager/einstellungen.json" ]] || fehl 'Entfernen hat die Einstellungen gelöscht'
    ok 'entfernt, Einstellungen bleiben'
    ;;

  Darwin)
    SUPPORT="$HOME/Library/Application Support"
    ZIEL="$SUPPORT/moocp/plugins/context"
    mkdir -p "$SUPPORT/moocp"
    # Nur für den Benutzer, ohne Administratorrechte (distribution.xml).
    installer -pkg "$INSTALLER" -target CurrentUserHomeDirectory
    [[ -x "$ZIEL/context.exe" ]] || fehl 'context.exe fehlt oder ist nicht ausführbar'
    [[ -f "$ZIEL/einstellungsfenster.zip" ]] || fehl 'einstellungsfenster.zip fehlt'
    ok 'installiert'
    touch "$ZIEL/alte-datei.txt"
    installer -pkg "$INSTALLER" -target CurrentUserHomeDirectory
    [[ ! -e "$ZIEL/alte-datei.txt" ]] || fehl 'Das Update hat den Plugin-Ordner nicht ganz ersetzt'
    ok 'Update ersetzt den Plugin-Ordner ganz'
    # Das Programm braucht nichts vom Bau: nur Systembibliotheken.
    if otool -L "$ZIEL/context.exe" | tail -n +2 | grep -i -E 'flutter|hostedtoolcache|/Users/runner'; then
      fehl 'context.exe verweist auf Dateien des Baurechners'
    fi
    "$SMOKE" "$ZIEL"
    rm -rf "$ZIEL"
    ;;

  MINGW*|MSYS*|CYGWIN*)
    APPDATA_U="$(cygpath -u "$APPDATA")"
    ZIEL="$APPDATA_U/moocp/plugins/context"
    ZIEL_W="$(cygpath -w "$ZIEL")"
    mkdir -p "$APPDATA_U/moocp"
    # Der Installer ist ein Fensterprogramm: Start-Process -Wait wartet auf sein Ende.
    still() {
      powershell -NoProfile -Command "\$p = Start-Process -Wait -PassThru -FilePath '$(cygpath -w "$1")' -ArgumentList '/S'; exit \$p.ExitCode"
    }
    still "$INSTALLER" || fehl 'Die stille Installation scheiterte'
    [[ -f "$ZIEL/context.exe" && -f "$ZIEL/einstellungsfenster/kontext_einstellungen.exe" ]] || fehl 'Programm oder Einstellungsfenster fehlt'
    [[ -f "$ZIEL/uninstall.exe" ]] || fehl 'uninstall.exe fehlt'
    reg query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\moocp-plugin-context' >/dev/null \
      || fehl 'Der Eintrag unter „Installierte Apps“ fehlt'
    ok 'installiert'

    starte_plugin "$ZIEL/context.exe"
    if still "$INSTALLER"; then
      taskkill //F //IM context.exe >/dev/null 2>&1 || true
      fehl 'Die Installation bei laufendem Plugin hätte abbrechen müssen'
    fi
    tasklist | grep -qi context.exe || fehl 'Der Installer hat das laufende Plugin beendet'
    taskkill //F //IM context.exe >/dev/null 2>&1 || true
    sleep 2
    ok 'bei laufendem Plugin bricht die Installation ab, ohne einen Prozess zu beenden'

    touch "$ZIEL/alte-datei.txt"
    still "$INSTALLER" || fehl 'Das Update scheiterte'
    [[ ! -e "$ZIEL/alte-datei.txt" ]] || fehl 'Das Update hat den Plugin-Ordner nicht ganz ersetzt'
    ok 'Update ersetzt den Plugin-Ordner ganz'

    "$SMOKE" "$ZIEL_W"

    # Die Prüfung ist zu Ende: Reste von ihr (Plugin, Fenster) sperren sonst die Dateien.
    taskkill //F //IM context.exe >/dev/null 2>&1 || true
    taskkill //F //IM kontext_einstellungen.exe >/dev/null 2>&1 || true
    sleep 3
    # Der Uninstaller kopiert sich in den Temp-Ordner und kehrt sofort zurück.
    # Git Bash machte aus /S sonst einen Pfad (S:\) und der Uninstaller liefe mit Fenster.
    MSYS2_ARG_CONV_EXCL="*" "$ZIEL/uninstall.exe" /S &
    for _ in $(seq 1 60); do
      [[ ! -e "$ZIEL" ]] && break
      sleep 1
    done
    if [[ -e "$ZIEL" ]]; then
      ls -la "$ZIEL" >&2 || true
      tasklist >&2 || true
      fehl 'Die Deinstallation hat den Plugin-Ordner nicht entfernt'
    fi
    if reg query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\moocp-plugin-context' >/dev/null 2>&1; then
      fehl 'Die Deinstallation hat den Eintrag unter „Installierte Apps“ nicht entfernt'
    fi
    ok 'deinstalliert'
    ;;

  *) fehl "Unbekanntes System: $(uname -s)" ;;
esac
echo 'INSTALLATION GEPRÜFT'
