# RadialComms

Rueda radial de comunicaciones para DCS World (todos los módulos, con comunicación fácil desactivada).
Menús: COM1, COM2, GROUND CREW y Herramientas.

## Instalación con OvGME

1. Descarga el zip `RadialComms-vX.Y.Z-OvGME.zip` de la última versión en Releases y descomprímelo en la biblioteca de mods de OvGME
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

## Usar la rueda con un solo botón del joystick

Pensado para VR: **un único botón** del joystick sirve para todo.

| Pulsación | Con la rueda cerrada | Con la rueda abierta |
|---|---|---|
| **Larga** (mantener 1 s) | Abre la rueda | Cierra la rueda |
| **Corta** | No hace nada | Clic sobre la cuña resaltada |

Si sueltas el botón después de una pulsación larga no se hace ningún clic. Las pulsaciones muy breves
(menos de 50 ms) se ignoran como ruido del botón.

### Asignar el botón
1. Abre la rueda con el teclado (Ctrl+Shift+Q).
2. Pulsa **Herramientas** y luego **Asignar boton joystick**.
3. Dentro de los 12 segundos siguientes, pulsa el botón del joystick que quieras usar.
4. Aparece el aviso "Boton asignado". Desde ese momento ese botón funciona como se explica arriba.

La asignación se guarda en `Saved Games\DCS\Config\RadialCommsJoystick.lua` y se recuerda entre sesiones.
Si el botón es el mismo número en dos mandos, solo cuenta el mando en el que lo asignaste.

**Quitar o cambiar el botón**
- Herramientas > **Quitar boton joystick** borra la asignación.
- Para cambiarlo, vuelve a usar **Asignar boton joystick** y pulsa otro botón.

**Consejo:** elige un botón que no tengas asignado a otra función en DCS. Si lo tienes asignado,
puede que al pulsarlo se abra la rueda y además se ejecute la otra función.

### Qué cuña se resalta: cursor o cabeza
Con la rueda abierta se resalta la cuña que señala **el cursor del ratón** o la que **miras con la cabeza**,
la que se haya movido en último lugar. La pulsación corta clica la que esté resaltada.

- **Cabeza (VR o TrackIR):** al abrir la rueda, tu mirada de ese momento es el centro. Gira la cabeza
  unos 7° hacia una cuña para resaltarla. **Mirar una cuña nunca la ejecuta por sí solo**: hay que pulsar el botón.
- **Volver atrás con la cabeza:** mira una cuña (con opción) y vuelve a mirar al centro: el centro se resalta
  y una pulsación corta retrocede (o cierra la rueda si estás en el menú principal). Justo al abrir la rueda
  o al entrar en un submenú el centro no se resalta, para que una pulsación corta no cierre la rueda por error.
- Los giros del propio avión no cuentan como movimiento de cabeza.

### El punto y la línea de la mirada
Para saber hacia dónde apunta tu cabeza, la rueda dibuja una marca blanca:

- **Un punto** que se mueve con tu cabeza. Al abrir la rueda está en el centro y llega al borde cuando giras 15°.
- **Una línea** del centro al punto, que aparece cuando sales de la zona muerta (7°), es decir, cuando la
  mirada empieza a señalar una cuña. Al volver al centro la línea desaparece y el punto se queda.

La marca siempre muestra la cabeza. El ratón no tiene marca y funciona como siempre.

### Opciones (`Saved Games\DCS\Config\RadialCommsConfig.lua`)
```lua
longPressSeconds = 1.0,  -- segundos manteniendo el botón para que cuente como larga
headSelect = true,       -- resaltar cuñas con la cabeza (false = solo cursor)
headDeadzone = 7,        -- grados que hay que girar la cabeza antes de resaltar
headMark = true,         -- punto y línea de la mirada (false = ocultarlos)
headMarkScale = 15,      -- grados de giro con los que el punto llega al borde
```
Reinicia DCS tras cambiarlas. Si el valor no es un número mayor que 0 se usa el de por defecto.

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
