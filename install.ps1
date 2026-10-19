# Copia el mod a Saved Games\DCS (cambia $dst si usas DCS.openbeta)
$dst = Join-Path $env:USERPROFILE "Saved Games\DCS"
$src = $PSScriptRoot
Copy-Item "$src\Scripts" $dst -Recurse -Force
# no machacar tu configuracion/menu si ya existen
foreach ($f in "RadialCommsConfig.lua","RadialCommsMenu.lua") {
  if (-not (Test-Path "$dst\Config\$f")) { Copy-Item "$src\Config\$f" "$dst\Config\$f" }
  else { Write-Host "Se conserva $f (copialo a mano si quieres la version nueva)" }
}
Write-Host "Instalado en $dst. Reinicia DCS."
