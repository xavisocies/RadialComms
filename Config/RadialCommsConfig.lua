-- RadialComms - configuracion
-- Copiar a: Saved Games\DCS\Config\
-- Tras editarlo, reinicia DCS (o recarga la UI en una mision).

return {
    -- Abrir/cerrar la rueda. Nombres de tecla validos: DCS World\dxgui\bind\KeyNames.txt
    -- Boton de joystick (experimental): Herramientas > "Asignar boton joystick".
    -- Ponlo en false para desactivarlo. (Alternativa: asignar una tecla al boton con el software
    -- del joystick y poner aqui esa tecla, p. ej. hotkey = "f13"; validas f1..f15.)
    joystickButton = true,

    -- Con el boton de joystick: una pulsacion LARGA abre o cierra la rueda y una CORTA hace clic
    -- sobre la cuña resaltada. Segundos que hay que mantenerlo para que cuente como larga
    -- (un numero mayor que 0; si no es valido se usa 1).
    longPressSeconds = 1.0,

    hotkey = "Ctrl+Shift+q",

    -- Cerrar la rueda automaticamente tras ejecutar una accion
    closeAfterAction = true,

    -- Volcar al log (Logs\RadialComms.log) que partes del menu de radio nativo
    -- son accesibles desde un Hook. Util mientras se desarrolla la v0.2.
    runProbe = true,

    -- Sonda de cabeza (VR): mientras la rueda esta abierta, registra en el log la
    -- orientacion de la camara respecto a la que tenia al abrir, y que sector se
    -- seleccionaria con esa mirada. Sirve para comprobar si el movimiento de cabeza
    -- llega al Hook. No cambia el comportamiento de la rueda.
    headProbe = true,
    headProbeInterval = 0.5, -- segundos entre muestras
    headProbeSamples = 60,   -- maximo de muestras por apertura (60 x 0.5 s = 30 s)

    -- Resaltar cuñas con la cabeza (VR/TrackIR): al abrir la rueda se toma tu mirada como centro.
    -- Gira la cabeza hacia una cuña para resaltarla y pulsa el boton (pulsacion corta) para elegirla;
    -- mirar una cuña nunca la ejecuta por si solo. En un submenu, mira al centro y pulsa para volver atras.
    -- Ponlo en false para usar solo el cursor del raton.
    headSelect = true,
    headDeadzone = 7,   -- grados que hay que girar la cabeza antes de resaltar (mayor que 0; si no, 7)

    -- Marca de la mirada: un punto blanco sobre la rueda marca hacia donde apunta tu cabeza y, al
    -- salir de la zona muerta, una linea lo une con el centro. El raton no tiene marca.
    -- Necesita headSelect = true. Ponlo en false para ocultar el punto y la linea.
    headMark = true,
    headMarkScale = 15, -- grados de giro con los que el punto llega al borde (mayor que 0; si no, 15)

    -- Ocultar en las listas de radio las estaciones que la radio no puede alcanzar ("[N/A]").
    hideUnavailable = true,

    -- Quitar "Personal de tierra" de las listas de COM1/COM2 (ya esta en GROUND CREW).
    hideGroundCrewInRadios = true,
}
