# Grid Fibonacci Pro - copies this project into every MetaTrader 5 data folder
# found for the current Windows user.
#
# Right-click this file and choose "Run with PowerShell", or from this folder:
#     powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# It only copies files. You still compile (F7 in MetaEditor) and attach the EA
# to a chart yourself - see INSTALL.md steps 4 and 5.

$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
$files  = Get-ChildItem -Path $source -File | Where-Object { $_.Extension -in '.mq5', '.mqh' }

if ($files.Count -eq 0) {
    Write-Host "No .mq5/.mqh files next to this script. Run it from inside the GridFibonacciEA folder." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

$terminalRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
if (-not (Test-Path $terminalRoot)) {
    Write-Host "No MetaTrader 5 data folder found at $terminalRoot" -ForegroundColor Red
    Write-Host "Open MT5 -> File -> Open Data Folder and copy the folder there by hand (INSTALL.md steps 2-3)."
    Read-Host "Press Enter to close"
    exit 1
}

# A terminal instance is any folder under Terminal\ that has an MQL5\Experts
# directory. Common\ and the crash-report folders do not, so they drop out.
$targets = Get-ChildItem -Path $terminalRoot -Directory |
           Where-Object { Test-Path (Join-Path $_.FullName 'MQL5\Experts') }

if ($targets.Count -eq 0) {
    Write-Host "Found $terminalRoot but no MQL5\Experts inside it." -ForegroundColor Red
    Write-Host "Start MetaTrader 5 once, then run this again."
    Read-Host "Press Enter to close"
    exit 1
}

foreach ($t in $targets) {
    $dest = Join-Path $t.FullName 'MQL5\Experts\GridFibonacciEA'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path $files.FullName -Destination $dest -Force
    Write-Host "Installed $($files.Count) files to:" -ForegroundColor Green
    Write-Host "  $dest"
}

Write-Host ""
Write-Host "Next: open MetaEditor (F4 in MT5), open Experts\GridFibonacciEA\GridFibonacciEA.mq5, press F7 to compile."
Read-Host "Press Enter to close"
