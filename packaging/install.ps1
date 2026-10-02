# Installs or removes the Gravity Circuit Archipelago client in the game's save folder, which Steam never touches.
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$saveDir = Join-Path $env:APPDATA "Gravity Circuit"
$apDir = Join-Path $saveDir "archipelago"

# Release zips ship the client as .\mod; in the repository it lives in ..\client.
$src = Join-Path $PSScriptRoot "mod"
if (-not (Test-Path $src)) {
    $src = Join-Path $PSScriptRoot "..\client"
}

if ($Uninstall) {
    Remove-Item -LiteralPath (Join-Path $saveDir "main.lua") -ErrorAction SilentlyContinue
    if (Test-Path $apDir) {
        Get-ChildItem $apDir -Filter *.lua | Remove-Item
    }
    Write-Host "Removed the Archipelago client. Saves, connection settings and logs were kept."
    exit 0
}

New-Item -ItemType Directory -Force -Path $apDir | Out-Null
Copy-Item -LiteralPath (Join-Path $src "main.lua") -Destination $saveDir -Force
Copy-Item -Path (Join-Path $src "archipelago\*.lua") -Destination $apDir -Force
Write-Host "Installed to $saveDir"
Write-Host "Start Gravity Circuit, press F9, enter server/slot/password, then start a NEW GAME in an empty slot."
