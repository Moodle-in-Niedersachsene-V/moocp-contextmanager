; Installer des Plugins „context“ für moocp (NSIS 3), nach dem Muster des
; Beispiel-Plugins von moocp. create_installer.bat baut erst den
; Plugin-Ordner (bauen.ps1, nach build\<kurzname>) und ruft dann dieses
; Skript auf, mit den Werten aus plugin.json:
;
;   makensis /DKURZNAME=context /DVERSION=<x.y.z> /DPROGRAMM=context.exe installer\windows\plugin.nsi
;
; Was moocp vom Installer eines Plugins erwartet (README von moocp, Teil 4,
; „Plugins“), und wo es hier steht:
;
; - Er legt das Plugin nach plugins\<kurzname> im Einstellungsordner von
;   moocp, %APPDATA%\moocp\plugins\<kurzname>, und nirgends sonst hin:
;   moocp lädt Plugins nur von dort (PLUGINORDNER, .onInit).
; - Er bricht ab, wenn moocp fehlt (MoocpVorhanden).
; - Er heißt <kurzname>_setup_<Version>.exe: Unter diesem Namen sucht die
;   Update-Prüfung von moocp ihn im Release (OutFile).
; - Er läuft sichtbar und ohne Parameter durch, denn so startet moocp ihn
;   beim Update, und er kommt mit laufender moocp zurecht: moocp wartet
;   dann auf sein Ende, und das Plugin läuft zu diesem Zeitpunkt nicht
;   (PluginBeendet).
; - Er beendet nie einen Prozess, weder moocp noch das Plugin.
; - Er ersetzt den Plugin-Ordner ganz, damit die Prüfsumme der Zustimmung
;   nur enthält, was zur neuen Version gehört (Section).
; - Er liest und schreibt sonst nichts im Einstellungsordner von moocp, auch
;   nicht die Einstellungen; Zustimmung und Skills erledigt moocp selbst.
;
; Für einen Benutzer, ohne Administratorrechte, wie moocp selbst: Der
; Einstellungsordner von moocp gehört dem Benutzer.
;
; Die Datei ist UTF-8 mit BOM; ohne BOM liest makensis sie in der
; ANSI-Codepage, und die Umlaute gingen verloren.

Unicode true
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

; Kurzname, Version und Programm kommen von der Kommandozeile, damit sie nur
; in plugin.json stehen; create_installer.bat liest sie dort und prüft sie.
!macro Pflicht WERT
  !ifndef ${WERT}
    !error "${WERT} fehlt. Aufruf: makensis /DKURZNAME=<kurzname> /DVERSION=<x.y.z> /DPROGRAMM=<programm.exe> installer\windows\plugin.nsi"
  !endif
!macroend
!insertmacro Pflicht KURZNAME
!insertmacro Pflicht VERSION
!insertmacro Pflicht PROGRAMM

; Anzeigename wie `name` in plugin.json. Er steht hier, nicht auf der
; Kommandozeile, weil ein Name mit Umlauten dort nicht sicher ankommt.
!define ANZEIGENAME "Kontextbereich"
!define HERAUSGEBER "Moodle in Niedersachsen e. V."

; Der fertige Plugin-Ordner aus bauen.ps1, relativ zu diesem Skript (installer\windows):
; makensis wechselt in den Ordner des Skripts. Alles, was darin liegt, kommt
; in den Installer, deshalb legt create_installer.bat ihn jedes Mal neu an.
!define QUELLE "..\..\build\${KURZNAME}"

; Der einzige Ort, von dem moocp das Plugin lädt.
!define PLUGINORDNER "$APPDATA\moocp\plugins\${KURZNAME}"

; Der Uninstaller liegt im Plugin-Ordner. Er geht damit in die Prüfsumme der
; Zustimmung ein, und das ist gewollt: Er ist bei jeder Installation
; derselben Version dieselbe Datei, die Zustimmung bleibt also gültig, und
; wer ihn austauscht, ändert die Prüfsumme, sodass moocp neu fragt. Der
; Einstellungsordner wandert unter Windows mit dem Benutzerprofil; so kommt
; der Uninstaller auf jedem Rechner mit dem Plugin an. Und entfernt die
; Deinstallation von moocp den Einstellungsordner, ist er mit entfernt.
!define UNINST_EXE "${PLUGINORDNER}\uninstall.exe"

; Der Eintrag unter „Installierte Apps“. Der Name bleibt über alle Versionen
; gleich, damit eine neue Version die alte ersetzt.
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\moocp-plugin-${KURZNAME}"

Name "moocp-Plugin ${ANZEIGENAME}"
; Eine Ebene höher, in installer\: dort erwartet create_installer.bat ihn.
OutFile "..\${KURZNAME}_setup_${VERSION}.exe"
InstallDir "${PLUGINORDNER}"
RequestExecutionLevel user

;--------------------------------
; Seiten
;
; Wenige Seiten: Willkommen mit dem Hinweis auf die Zustimmung, Installieren,
; Fertig. Keine Seite zur Wahl des Ordners, denn moocp lädt nur von
; PLUGINORDNER, und am Ende kein „moocp starten“: Beim Update läuft moocp
; schon und wartet auf diesen Installer.

!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "moocp-Plugin ${ANZEIGENAME} ${VERSION}"
!define MUI_WELCOMEPAGE_TEXT "Dieser Assistent installiert das moocp-Plugin ${ANZEIGENAME} in der Version ${VERSION} für den angemeldeten Benutzer. Eine ältere Version wird dabei ersetzt.$\r$\n$\r$\nmoocp nutzt das Plugin erst, nachdem Sie ihm zugestimmt haben: Beim nächsten Start fragt moocp danach, nach einem Update aus moocp heraus gleich im Anschluss.$\r$\n$\r$\nmoocp muss dafür nicht geschlossen werden."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TEXT "Das moocp-Plugin ${ANZEIGENAME} ${VERSION} ist installiert. Beim nächsten Start fragt moocp nach Ihrer Zustimmung."
!insertmacro MUI_PAGE_FINISH

!define MUI_UNCONFIRMPAGE_TEXT_TOP "Das moocp-Plugin ${ANZEIGENAME} wird entfernt. Seine Skills in den KI-Werkzeugen bietet moocp beim nächsten Start im Dialog „KI-Werkzeuge einrichten“ zum Entfernen an."
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "German"

; Die Versionsangabe der exe verlangt vier Zahlen; daher die drei aus
; plugin.json und eine 0.
VIProductVersion "${VERSION}.0"
VIFileVersion "${VERSION}.0"
VIAddVersionKey /LANG=${LANG_GERMAN} "ProductName" "moocp-Plugin ${ANZEIGENAME}"
VIAddVersionKey /LANG=${LANG_GERMAN} "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=${LANG_GERMAN} "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=${LANG_GERMAN} "FileDescription" "Installer für das moocp-Plugin ${ANZEIGENAME}"
VIAddVersionKey /LANG=${LANG_GERMAN} "CompanyName" "${HERAUSGEBER}"
VIAddVersionKey /LANG=${LANG_GERMAN} "LegalCopyright" "© ${HERAUSGEBER}"

;--------------------------------
; Vor dem ersten Schritt

Function .onInit
  ; Fest, auch wenn jemand /D=<Ordner> übergibt: Den Ordner leert die
  ; Installation ganz, und moocp lädt ohnehin nur von hier.
  StrCpy $INSTDIR "${PLUGINORDNER}"
  Call MoocpVorhanden
FunctionEnd

; Ohne moocp ist ein Plugin nutzlos, und der Installer legte einen
; Einstellungsordner an, den niemand braucht. Er bricht deshalb ab, bevor er
; etwas schreibt. moocp gilt als vorhanden, wenn es seinen Einstellungsordner
; gibt (moocp lief schon einmal, installiert oder als Entwicklerversion) oder
; die installierte App. Gelesen wird dabei keine Datei, nur nachgesehen, ob
; es den Ordner oder die exe gibt.
Function MoocpVorhanden
  ${If} ${FileExists} "$APPDATA\moocp\*.*"
    Return
  ${EndIf}
  ${If} ${FileExists} "$LOCALAPPDATA\Programs\moocp\moocp.exe"
    Return
  ${EndIf}
  MessageBox MB_OK|MB_ICONSTOP "moocp ist auf diesem Rechner nicht installiert. Bitte zuerst moocp installieren und einmal starten, dann das Plugin installieren." /SD IDOK
  Abort ; in .onInit: beendet den Installer, bevor er etwas schreibt
FunctionEnd

;--------------------------------
; Gemeinsam für Installieren und Deinstallieren

; Läuft das Plugin, ist sein Programm gesperrt: Öffnen zum Schreiben
; scheitert. Das sollte nicht vorkommen, denn moocp startet den Installer
; beim Update, bevor es das Plugin startet, und von Hand installiert man
; meist ohne laufende moocp. Läuft es doch (moocp ist offen, oder ein
; Entwickler hat es gestartet), nicht beenden, sondern darum bitten, moocp
; zu schließen: moocp beendet seine Plugins selbst, und nur beim regulären
; Schließen räumt es auf.
;
; Ohne Programm (noch nicht installiert, oder der Ordner fehlt schon) gibt
; es nichts zu prüfen. Nachsehen, bevor geöffnet wird: FileOpen mit „a“
; legte eine fehlende Datei an.
!macro PluginBeendet UN
Function ${UN}PluginBeendet
  ${Do}
    ${IfNot} ${FileExists} "${PLUGINORDNER}\${PROGRAMM}"
      ${Break}
    ${EndIf}
    ClearErrors
    FileOpen $0 "${PLUGINORDNER}\${PROGRAMM}" a
    ${IfNot} ${Errors}
      FileClose $0
      ${Break}
    ${EndIf}
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Das moocp-Plugin ${ANZEIGENAME} läuft noch. Bitte moocp schließen und dann „Wiederholen“ wählen." /SD IDCANCEL IDRETRY nochmal
    Abort
    nochmal:
  ${Loop}
FunctionEnd
!macroend
!insertmacro PluginBeendet ""
!insertmacro PluginBeendet "un."

;--------------------------------
; Installieren
;
; Erst alles Alte im Plugin-Ordner entfernen, dann die neuen Dateien
; ablegen: moocp bildet die Prüfsumme der Zustimmung über jede Datei des
; Ordners, und eine Datei, die eine ältere Version hinterlassen hat, gehörte
; sonst zur Zustimmung, ohne zur neuen Version zu gehören. Weil sich Version
; und Prüfsumme ändern, fragt moocp danach neu nach der Zustimmung.

Section
  Call PluginBeendet

  ClearErrors
  RMDir /r "${PLUGINORDNER}"
  ${If} ${Errors}
  ${OrIf} ${FileExists} "${PLUGINORDNER}\*.*"
    ; Eine Datei ist gesperrt, etwa weil ein anderes Programm sie offen hat.
    ; Was schon entfernt ist, fehlt jetzt; moocp nutzt das Plugin in diesem
    ; Zustand nicht, denn die Prüfsumme weicht ab und fragt neu, oder das
    ; Programm fehlt und das Plugin lädt nicht. Ein neuer Lauf des
    ; Installers stellt es wieder her.
    MessageBox MB_OK|MB_ICONSTOP "Der alte Ordner des Plugins ließ sich nicht ganz entfernen:$\r$\n${PLUGINORDNER}$\r$\n$\r$\nBitte Programme schließen, die darin eine Datei geöffnet haben, und den Installer noch einmal starten." /SD IDOK
    Abort
  ${EndIf}

  ; Programm, plugin.json, skills\ und einstellungsfenster\, genau wie bauen.ps1
  ; sie hinlegt. Die Einstellungen des Plugins liegen in %APPDATA%\moocp-contextmanager,
  ; das Passwort in der Anmeldeinformationsverwaltung; beides fasst der
  ; Installer nie an.
  SetOutPath "${PLUGINORDNER}"
  File /r "${QUELLE}\*"

  WriteUninstaller "${UNINST_EXE}"

  ; InstallLocation und UninstallString zeigen in den Plugin-Ordner: Daran
  ; erkennt der Uninstaller von moocp den Eintrag eines Plugins und entfernt
  ; ihn mit, wenn moocp vor dem Plugin deinstalliert wird.
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "moocp-Plugin ${ANZEIGENAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${HERAUSGEBER}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "${PLUGINORDNER}"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"${UNINST_EXE}"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"${UNINST_EXE}" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "${PLUGINORDNER}" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" $0
SectionEnd

;--------------------------------
; Deinstallieren
;
; Entfernt den Plugin-Ordner samt dem Uninstaller darin und den Eintrag
; unter „Installierte Apps“. Der Pfad steht fest wie beim Installieren.
;
; Die Skills des Plugins in den KI-Werkzeugen fasst er nicht an: Wo sie
; liegen, weiß nur moocp. Beim nächsten Start bemerkt moocp, dass das
; Plugin fehlt, und bietet sie im Dialog „KI-Werkzeuge einrichten“ zum
; Entfernen an. Auch die Zustimmung in den Einstellungen von moocp bleibt;
; sie gilt nur für genau den entfernten Stand.
;
; Die Deinstallation von moocp entfernt den Plugin-Ordner schon mit dem
; ganzen Einstellungsordner, auch den Uninstaller. Stehen bleibt dann nur
; der Eintrag des Plugins unter „Installierte Apps“; Windows bietet an, ihn
; zu entfernen, wenn man ihn dort aufruft.

Section "Uninstall"
  Call un.PluginBeendet

  ; Der Uninstaller läuft aus einer Kopie im Temp-Ordner und kann deshalb
  ; den Ordner entfernen, in dem er selbst liegt.
  RMDir /r "${PLUGINORDNER}"

  DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
