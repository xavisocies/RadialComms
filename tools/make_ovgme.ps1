# Genera la carpeta del mod para OvGME en dist\RadialComms vX.Y.Z (solo Scripts y Config).
# Copia esa carpeta a la biblioteca de mods de OvGME (destino: Saved Games\DCS).
$root = Split-Path -Parent $PSScriptRoot
$ver = "0.0.0"
$m = Select-String -Path "$root\Scripts\RadialComms\RadialComms.lua" -Pattern 'RadialComms v([0-9.]+) iniciado' | Select-Object -First 1
if ($m) { $ver = $m.Matches[0].Groups[1].Value }
$out = Join-Path $root "dist\RadialComms v$ver"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item "$root\Scripts" $out -Recurse
Copy-Item "$root\Config" $out -Recurse
Write-Host "Mod OvGME creado en: $out"
