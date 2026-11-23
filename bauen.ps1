# Baut das Plugin zu einem fertigen Plugin-Ordner unter Windows: übersetzt das
# Programm mit `dart compile exe` unter dem Namen, den `programm` in plugin.json
# nennt, baut das Einstellungsfenster (fenster\, Flutter, E8) und legt beides mit
# plugin.json und skills\ in den Zielordner. Auf Linux und dem Mac tut bauen.sh
# dasselbe.
#
#   powershell -ExecutionPolicy Bypass -File bauen.ps1 [-Ziel <Zielordner>]
#
# Vorgabe für den Zielordner ist build\context in diesem Projekt. Ein
# Zielordner, der nicht leer ist und keine plugin.json enthält, bricht das
# Skript ab, ohne etwas zu ändern. Sonst ersetzt es dort Programm, plugin.json,
# skills\ und das Einstellungsfenster (einstellungsfenster\).
# Das dart kommt aus dem Suchpfad oder aus -Dart, das flutter aus dem Suchpfad
# oder aus -Flutter.
#
# Gespeichert als UTF-8 mit BOM: Windows PowerShell 5.1 liest eine Datei ohne
# BOM in der Codepage des Systems und zeigte die Umlaute falsch an.

param(
    # Der fertige Plugin-Ordner.
    [string]$Ziel = (Join-Path $PSScriptRoot 'build\context'),
    [string]$Dart = 'dart',
    [string]$Flutter = 'flutter'
)

$ErrorActionPreference = 'Stop'

$ordner = $PSScriptRoot
$beschreibung = Get-Content -LiteralPath (Join-Path $ordner 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$programm = [string]$beschreibung.programm
if (-not $programm) {
    Write-Error 'plugin.json nennt kein programm.'
}
if (Test-Path -LiteralPath $Ziel -PathType Leaf) {
    Write-Error "Der Zielordner ist eine Datei: $Ziel"
}
if ((Test-Path -LiteralPath $Ziel -PathType Container) -and
    (Get-ChildItem -LiteralPath $Ziel -Force | Select-Object -First 1) -and
    -not (Test-Path -LiteralPath (Join-Path $Ziel 'plugin.json') -PathType Leaf)) {
    Write-Error "Der Zielordner ist nicht leer und kein Plugin-Ordner: $Ziel"
}
$Ziel = (New-Item -ItemType Directory -Force -Path $Ziel).FullName

# Erst übersetzen, dann ersetzen: Schlägt das Übersetzen fehl, bleibt der
# Zielordner, wie er war.
$neu = Join-Path $Ziel "$programm.neu"
Push-Location $ordner
try {
    & $Dart compile exe 'bin\context.dart' -o $neu
    if ($LASTEXITCODE -ne 0) {
        Write-Error "dart compile exe ist mit Exit-Code $LASTEXITCODE gescheitert."
    }
    # Das Einstellungsfenster als Bündel (kontext_einstellungen.exe samt DLLs
    # und data\), wie flutter es baut; das Plugin startet das Programm darin.
    Push-Location (Join-Path $ordner 'fenster')
    try {
        & $Flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            Write-Error "flutter build windows ist mit Exit-Code $LASTEXITCODE gescheitert."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}
$buendel = Join-Path $ordner 'fenster\build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $buendel 'kontext_einstellungen.exe') -PathType Leaf)) {
    Remove-Item -LiteralPath $neu -Force -ErrorAction SilentlyContinue
    Write-Error "Das Einstellungsfenster fehlt nach dem Bauen: $buendel"
}
foreach ($alt in @('skills', 'plugin.json', $programm, 'einstellungsfenster')) {
    $pfad = Join-Path $Ziel $alt
    if (Test-Path -LiteralPath $pfad) {
        Remove-Item -LiteralPath $pfad -Recurse -Force
    }
}
Move-Item -LiteralPath $neu -Destination (Join-Path $Ziel $programm)
Copy-Item -LiteralPath $buendel -Destination (Join-Path $Ziel 'einstellungsfenster') -Recurse
Copy-Item -LiteralPath (Join-Path $ordner 'plugin.json') -Destination (Join-Path $Ziel 'plugin.json')
Copy-Item -LiteralPath (Join-Path $ordner 'skills') -Destination (Join-Path $Ziel 'skills') -Recurse
Write-Host "Das Plugin liegt fertig in $Ziel"
