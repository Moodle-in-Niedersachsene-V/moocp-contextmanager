@echo off
rem Baut den Installer des Plugins: erst den Plugin-Ordner mit
rem bauen.ps1, dann NSIS. Ergebnis: installer\<kurzname>_setup_<Version>.exe,
rem hier installer\context_setup_<Version>.exe. Kurzname, Version und Programm
rem kommen aus plugin.json; die Version steht nur dort.
rem
rem Voraussetzungen: Flutter (flutter und dart im Suchpfad; für das Plugin und das
rem Einstellungsfenster, Visual Studio mit C++-Desktopentwicklung) und NSIS 3
rem (makensis im Suchpfad oder unter %ProgramFiles(x86)%\NSIS).
rem
rem Die Datei ist UTF-8 mit CRLF; chcp 65001 lässt cmd die Umlaute der
rem Meldungen richtig lesen. CRLF, weil cmd Sprungmarken in Dateien mit LF
rem nicht zuverlässig findet.
setlocal
cd /d "%~dp0"
for /f "tokens=2 delims=:." %%c in ('chcp') do set "ALTE_CODEPAGE=%%c"
chcp 65001 >nul

where dart >nul 2>&1
if errorlevel 1 (
  echo Dart nicht gefunden: https://dart.dev/get-dart
  goto fehler
)
where flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter nicht gefunden: https://flutter.dev
  goto fehler
)

rem Außerhalb von Klammern: Die Klammern in "(x86)" beendeten sonst den Block.
set "MAKENSIS=%ProgramFiles(x86)%\NSIS\makensis.exe"
where makensis >nul 2>&1 && set "MAKENSIS=makensis"
if not "%MAKENSIS%"=="makensis" if not exist "%MAKENSIS%" (
  echo NSIS 3 nicht gefunden: https://nsis.sourceforge.io
  goto fehler
)

rem Kurzname, Version und Programm aus plugin.json, in einer Zeile. Gibt
rem PowerShell nichts aus, verstößt ein Wert gegen die Regeln, die der
rem Installer braucht: Kurzname wie in moocp (Kleinbuchstaben und Ziffern,
rem höchstens 12 Zeichen), Version aus drei Zahlen (die Versionsangabe der
rem exe verlangt Zahlen), Programm eine exe ohne Pfad.
set "KURZNAME="
set "VERSION="
set "PROGRAMM="
for /f "tokens=1-3" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$b = ConvertFrom-Json (Get-Content -LiteralPath 'plugin.json' -Raw -Encoding UTF8); if ($b.kurzname -cmatch '\A[a-z][a-z0-9]{0,11}\z' -and $b.version -match '\A[0-9]+\.[0-9]+\.[0-9]+\z' -and $b.programm -match '\A[A-Za-z0-9_.-]+\.exe\z') { $b.kurzname + ' ' + $b.version + ' ' + $b.programm }"') do (
  set "KURZNAME=%%a"
  set "VERSION=%%b"
  set "PROGRAMM=%%c"
)
if "%PROGRAMM%"=="" (
  echo plugin.json: kurzname, version oder programm fehlt oder passt nicht.
  goto fehler
)

echo.
echo [1/2] Plugin %KURZNAME% %VERSION% bauen
rem Der Bauordner wird ganz neu angelegt: bauen.ps1 lässt in einem
rem bestehenden Ordner stehen, was es nicht selbst hinlegt, und der Installer
rem packt alles, was darin liegt.
if exist "build\%KURZNAME%" rmdir /s /q "build\%KURZNAME%"
if exist "build\%KURZNAME%" (
  echo Der Bauordner build\%KURZNAME% ließ sich nicht leeren.
  goto fehler
)
powershell -NoProfile -ExecutionPolicy Bypass -File bauen.ps1 -Ziel "build\%KURZNAME%"
if errorlevel 1 goto fehler

echo.
echo [2/2] Installer bauen
"%MAKENSIS%" /V2 /DKURZNAME=%KURZNAME% /DVERSION=%VERSION% /DPROGRAMM=%PROGRAMM% installer\windows\plugin.nsi
if errorlevel 1 goto fehler

if not exist "installer\%KURZNAME%_setup_%VERSION%.exe" (
  echo Der Installer fehlt: installer\%KURZNAME%_setup_%VERSION%.exe
  goto fehler
)
echo.
echo Fertig: installer\%KURZNAME%_setup_%VERSION%.exe
chcp %ALTE_CODEPAGE% >nul
exit /b 0

:fehler
echo.
echo Abgebrochen.
chcp %ALTE_CODEPAGE% >nul
exit /b 1
