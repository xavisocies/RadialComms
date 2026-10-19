-- RadialComms - arbol de menu
-- Copiar a: Saved Games\DCS\Config\
--
-- Cada menu tiene hasta 8 elementos (se colocan en sentido horario empezando arriba).
-- Un elemento puede ser:
--   * un submenu:   { label = "...", items = { ... } }
--   * una accion:   { label = "...", action = { type = "...", ... } }
--
-- Tipos de accion:
--   mission_lua : ejecuta codigo Lua en el entorno de mision
--                 { type = "mission_lua", code = 'trigger.action.outText("hola", 5)' }
--
--   radio_item  : recorre el menu de radio NATIVO de DCS (F1-F12) siguiendo una ruta y pulsa el
--                 ultimo paso. Cada paso es un NOMBRE (tal como lo muestra DCS, sin "F5." ni "...";
--                 sin distinguir mayusculas; vale una parte del texto, p. ej. "Gudauta") o un
--                 NUMERO de tecla (1-10).
--                 { type = "radio_item", path = { "ATC", "Gudauta", "puesta en marcha" } }
--
--   radio_scan  : escribe en Logs\RadialComms.log todo el arbol de submenus (bloque RADIO-SCAN).
--   radio_info  : lista en el log (RADIO-INFO) las radios del avion y su frecuencia actual.
--   radio_tune  : sintoniza una radio y la selecciona (para comunicacion facil DESACTIVADA).
--                 { type = "radio_tune", device = 38, freq = 129.0 }   -- device sale de radio_info
--   color       : (en cualquier elemento) color de la cuña: blue, green, amber, teal, purple, red o grey.
--                 Los hijos heredan el color del padre. Sin color = blue.
--   joy_learn   : espera la pulsacion de un boton de joystick y lo asigna para abrir la rueda.
--   joy_clear   : borra el boton asignado.
--   radio_dump  : escribe los textos de un solo menu (RADIO-DUMP).
--
-- Opcional: start = "main" (por defecto, raiz) o "dialog" (menu activo, p. ej. conversacion con ATC):
--   { type = "radio_item", start = "dialog", path = { "Solicito rodaje" } }
--
--   radio       : (en vez de items/action) nodo DINAMICO: la rueda lee en vivo el menu nativo de DCS
--                 y lo dibuja (con paginacion si hay mas de 8 opciones). Sirve con la comunicacion
--                 facil DESACTIVADA: lo que aparece depende de la frecuencia que tengas sintonizada.
--                 { label = "COM1", radio = { device = "auto1" } }   -- 1.a radio del avion
--                 { label = "COM2", radio = { device = "auto2" } }   -- 2.a radio
--                 device tambien puede ser el numero de dispositivo (ver "Info radios avion").
--                 { label = "GROUND CREW", color = "amber", radio = { path = { { "Personal de tierra", "Ground crew" } } } }
--                 (un paso puede ser una lista de nombres alternativos segun el idioma)
--
-- Nombres tomados del escaneo real (F/A-18C, Caucaso, DCS en espanol). Los aerodromos dependen de
-- la mision: cambia "Gudauta" por el tuyo.

return {
    title = "Comunicaciones",
    items = {
        { label = "COM1",        color = "blue",  radio = { device = "auto1" } },
        { label = "COM2",        color = "green", radio = { device = "auto2" } },
        { label = "GROUND CREW", color = "amber", radio = { path = { { "Personal de tierra", "Ground crew" } } } },
        {
            label = "Herramientas",
            color = "grey",
            items = {
                { label = "Asignar boton joystick", action = { type = "joy_learn" } },
                { label = "Quitar boton joystick",  action = { type = "joy_clear" } },
            },
        },
    },
}
