# RadialComms

Rueda radial de comunicaciones para DCS World (todos los módulos, con comunicación fácil desactivada).
Menús: COM1, COM2, GROUND CREW y Herramientas.

## Instalación con OvGME

1. Descarga `RadialComms-v0.9.0-OvGME.zip` desde Releases y descomprímelo en la biblioteca de mods de OvGME
   (destino del mod: `C:\Users\<tu usuario>\Saved Games\DCS`).
2. Activa el mod en OvGME.
3. Arranca DCS (si estaba abierto, ciérralo y vuelve a abrirlo).

Instalación manual: copia las carpetas `Scripts` y `Config` dentro de `Saved Games\DCS\` (reemplaza archivos).

## Abrir la rueda con el teclado

Estando en una misión, pulsa **Ctrl + Shift + Q**. La rueda aparece en el centro de la pantalla.
Pulsa la misma combinación para cerrarla.

- Elige una cuña con el ratón (clic). Cada cuña es una opción del menú o un submenú.
- El círculo del centro vuelve atrás; en el menú principal, cierra la rueda.
- COM1, COM2 y GROUND CREW muestran en vivo el menú de radio de DCS (F1-F12) y, al pulsar una opción,
  la ejecutan.

### Cambiar la tecla

Edita `Saved Games\DCS\Config\RadialCommsConfig.lua` y cambia la línea:

```lua
hotkey = "Ctrl+Shift+q",
```

Los nombres de tecla válidos están en `G:\DCS World\dxgui\bind\KeyNames.txt`
(por ejemplo `"Ctrl+Alt+r"` o `"f13"`). Reinicia DCS para aplicar el cambio.

## Abrir la rueda con un botón del joystick

El mod puede usar cualquier botón de cualquier mando, sin software externo.

**Asignar el botón**
1. Abre la rueda con el teclado (Ctrl+Shift+Q).
2. Pulsa **Herramientas** y luego **Asignar boton joystick**.
3. Dentro de los 12 segundos siguientes, pulsa el botón del joystick que quieras usar.
4. Aparece el aviso "Boton asignado". Desde ese momento ese botón abre y cierra la rueda.

La asignación se guarda en `Saved Games\DCS\Config\RadialCommsJoystick.lua` y se recuerda entre sesiones.
Si el botón es el mismo número en dos mandos, solo cuenta el mando en el que lo asignaste.

**Quitar o cambiar el botón**
- Herramientas > **Quitar boton joystick** borra la asignación.
- Para cambiarlo, vuelve a usar **Asignar boton joystick** y pulsa otro botón.

**Consejo:** elige un botón que no tengas asignado a otra función en DCS. Si lo tienes asignado,
puede que al pulsarlo se abra la rueda y además se ejecute la otra función.

## Desinstalar

Con OvGME, desactiva el mod. Si lo copiaste a mano, borra `Scripts\Hooks\RadialComms-hook.lua`,
`Scripts\RadialComms\` y los `Config\RadialComms*.lua`. Si asignaste un botón de joystick,
borra también `Config\RadialCommsJoystick.lua` (OvGME no lo gestiona).

## Licencia y autoría

RadialComms © 2026 **xavisocies**.
Licencia [Creative Commons Atribución-NoComercial 4.0 (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/deed.es) — texto completo en `LICENSE`.

- Puedes usar, copiar, compartir y modificar el mod libremente.
- Si lo compartes o lo modificas, debes citar al autor original (xavisocies), enlazar este repositorio e indicar si hiciste cambios.
- No se puede vender ni usar con fines comerciales.

## Aviso

RadialComms es un mod de aficionado, independiente y gratuito. **No está afiliado, patrocinado ni respaldado por Eagle Dynamics SA.**
DCS World y los nombres relacionados son marcas de sus respectivos propietarios, y se mencionan solo para indicar con qué es compatible el mod.
