-- RadialComms v0.1 - Modulo principal
-- Rueda radial de comunicaciones que funciona sobre cualquier modulo de DCS.
--
-- ESTADO: v0.1 es un esqueleto. La rueda y la sonda de diagnostico estan
-- escritas siguiendo la API de dxgui que usan otros mods (dcs-scratchpad),
-- pero NO se ha podido probar dentro de DCS. Revisa Logs\RadialComms.log
-- tras la primera prueba: ahi queda todo lo que ha pasado.

local M = {}

function M.start()
    package.path = package.path .. ";.\\Scripts\\?.lua;.\\Scripts\\UI\\?.lua;"

    local lfs = require("lfs")
    local Window = require("Window")
    local Panel = require("Panel")
    local Button = require("Button")
    local Static = require("Static")
    local Skin = require("Skin")
    local dxgui = require("dxgui")

    ----------------------------------------------------------------------
    -- Log propio
    ----------------------------------------------------------------------
    local logFile = io.open(lfs.writedir() .. [[Logs\RadialComms.log]], "w")

    local function log(str)
        if logFile and str then
            logFile:write("[" .. os.date("%H:%M:%S") .. "] " .. tostring(str) .. "\r\n")
            logFile:flush()
        end
    end

    ----------------------------------------------------------------------
    -- Configuracion (con valores por defecto si no existe el archivo)
    ----------------------------------------------------------------------
    local defaultConfig = {
        hotkey = "Ctrl+Shift+q", -- abrir/cerrar la rueda (nombres de tecla: dxgui\bind\KeyNames.txt)
        closeAfterAction = true, -- cerrar la rueda tras ejecutar una accion
        runProbe = true,         -- volcar al log que partes del menu nativo son accesibles
        headProbe = true,        -- registrar la orientacion de la camara/cabeza mientras la rueda esta abierta
        headProbeInterval = 0.5, -- segundos entre muestras
        headProbeSamples = 60,   -- maximo de muestras por apertura (60 x 0.5 s = 30 s)
        headSelect = false,      -- (EXPERIMENTAL, sin probar) elegir cuñas con la cabeza (VR / TrackIR): mirar un sector y mantener
        headDwell = 1.0,         -- segundos mirando un sector para elegirlo
        headDeadzone = 7,        -- grados de giro desde la posicion inicial antes de resaltar un sector
    }

    local defaultMenu = {
        title = "Comunicaciones",
        items = {
            {
                label = "Prueba de mensaje",
                action = {
                    type = "mission_lua",
                    code = 'trigger.action.outText("RadialComms: la rueda funciona", 6)',
                },
            },
            {
                label = "ATC",
                items = {
                    { label = "Solicitar arranque", action = { type = "radio_item", path = { "ATC", "Request Startup" } } },
                    { label = "Solicitar rodaje", action = { type = "radio_item", path = { "ATC", "Request Taxi" } } },
                },
            },
            {
                label = "Escanear menu radio",
                action = { type = "radio_scan" },
            },
            {
                label = "Volcar dialogo activo",
                action = { type = "radio_dump", start = "dialog" },
            },
        },
    }

    -- Carga un archivo Lua que devuelve una tabla, en un entorno vacio (sin acceso a funciones).
    local function loadTable(path)
        local chunk, err = loadfile(path)
        if not chunk then
            return nil, err
        end
        setfenv(chunk, {})
        local ok, res = pcall(chunk)
        if ok and type(res) == "table" then
            return res
        end
        return nil, tostring(res)
    end

    local config = {}
    for k, v in pairs(defaultConfig) do
        config[k] = v
    end

    do
        local userCfg, err = loadTable(lfs.writedir() .. "Config/RadialCommsConfig.lua")
        if userCfg then
            for k, v in pairs(userCfg) do
                config[k] = v
            end
            log("Config cargada de Config/RadialCommsConfig.lua")
        else
            log("Config por defecto (" .. tostring(err) .. ")")
        end
    end

    local menuRoot
    do
        local userMenu, err = loadTable(lfs.writedir() .. "Config/RadialCommsMenu.lua")
        if userMenu then
            menuRoot = userMenu
            log("Menu cargado de Config/RadialCommsMenu.lua")
        else
            menuRoot = defaultMenu
            log("Menu por defecto (" .. tostring(err) .. ")")
        end
    end

    ----------------------------------------------------------------------
    -- Estado
    ----------------------------------------------------------------------
    local window = nil
    local windowDefaultSkin = nil
    local windowSkinHidden = Skin.windowSkinChatMin()
    local panel = nil

    local isHidden = true
    local inMission = false
    local stack = { menuRoot } -- pila de menus (el ultimo es el actual)
    local probeDone = false
    local statusMsg = nil   -- aviso corto que se muestra en la barra de titulo de la rueda
    local joy = nil         -- boton de joystick (JoyButton.lua)
    local toggleWheel       -- abre/cierra la rueda (definida mas abajo)
    local render, setStatus -- se definen mas abajo (declaradas aqui para que las vea runAction)
    local wedge = nil       -- widgets del estilo de cuñas (nil si no se pudieron crear)
    local radioState = nil  -- estado de Lua donde vive el menu de radio nativo ("local", "gui", ...)
    local detectRadioState  -- se define mas abajo (la usa tambien la sonda de diagnostico)

    local TITLE_H = 20 -- alto de la barra de titulo de la ventana
    local winW, winH = 440, 440 + 22
    local WEDGE_S, WEDGE_STRIP = 440, 22     -- lado de la imagen de la rueda y franja de titulo
    local WEDGE_R_IN, WEDGE_R_LABEL = 64, 134 -- radio del circulo central / radio de las etiquetas
    -- Colores de cuña disponibles (cada uno tiene sus imagenes en img\\); "color" en el menu elige uno
    local THEMES = { "blue", "green", "amber", "teal", "purple", "red", "grey" }
    local THEME_OK = {}
    for _, t in ipairs(THEMES) do THEME_OK[t] = true end

    ----------------------------------------------------------------------
    -- Sonda de diagnostico: que del menu de radio nativo es accesible
    -- desde un Hook. No importa (require) nada de la UI nativa para no
    -- provocar efectos secundarios; solo inspecciona y lista.
    ----------------------------------------------------------------------
    local function matchesRadio(name)
        local n = string.lower(tostring(name))
        return string.find(n, "radio", 1, true)
            or string.find(n, "command", 1, true)
            or string.find(n, "dialog", 1, true)
            or string.find(n, "menu", 1, true)
    end

    local function runProbe()
        log("===== SONDA DE DIAGNOSTICO =====")

        local okUnit, unit = pcall(function() return DCS.getPlayerUnitType() end)
        log("Unidad del jugador: " .. tostring(okUnit and unit or "n/d"))

        local count = 0
        for name, _ in pairs(package.loaded) do
            if matchesRadio(name) then
                log("package.loaded: " .. tostring(name))
                count = count + 1
            end
        end
        log("Modulos cargados con nombre relacionado: " .. count)

        count = 0
        for k, v in pairs(_G) do
            if type(k) == "string" and matchesRadio(k) then
                log("_G." .. k .. " (" .. type(v) .. ")")
                count = count + 1
            end
        end
        log("Globales con nombre relacionado: " .. count)

        local dir = lfs.currentdir() .. "/Scripts/UI/RadioCommandDialogPanel"
        local mode = lfs.attributes(dir, "mode")
        log("Carpeta del menu nativo: " .. dir .. " -> " .. tostring(mode))
        if mode == "directory" then
            for name in lfs.dir(dir) do
                if name ~= "." and name ~= ".." then
                    log("  " .. name)
                end
            end
        end

        log("net.dostring_in disponible: " .. tostring(type(net.dostring_in) == "function"))
        if inMission then
            local ok, res = pcall(net.dostring_in, "mission", 'return "ok-mission"')
            log("Prueba entorno 'mission': ok=" .. tostring(ok) .. " res=" .. tostring(res))
        else
            log("Prueba entorno 'mission' omitida (no hay mision cargada)")
        end

        if inMission then
            log("Estado donde vive el menu de radio nativo: " .. tostring(detectRadioState()))
        end

        log("===== FIN SONDA =====")
    end

    ----------------------------------------------------------------------
    -- Sonda de cabeza (VR): registra la orientacion de la camara mientras
    -- la rueda esta abierta, para comprobar si el movimiento de cabeza
    -- llega al Hook y con que signo. Es el prototipo de la seleccion por
    -- mirada: la referencia se toma en la primera muestra tras abrir la
    -- rueda, y la desviacion respecto a ella decide el sector.
    ----------------------------------------------------------------------
    local headRef = nil
    local headLastT = nil
    local headSamples = 0
    local headStructLogged = false
    -- Seleccion con la cabeza: ref = orientacion al abrir la rueda (relativa al avion)
    local headSel = { ref = nil, dy = 0, dp = 0, sec = nil, since = 0, armed = true, lastT = 0 }

    local function nowSeconds()
        local ok, t = pcall(function() return DCS.getRealTime() end)
        if ok and type(t) == "number" then
            return t
        end
        return os.clock()
    end

    local function wrap180(a)
        while a > 180 do a = a - 360 end
        while a < -180 do a = a + 360 end
        return a
    end

    -- Sector 1-8 (1 arriba, sentido horario) segun la desviacion en grados.
    -- Devuelve nil dentro de la zona muerta.
    local function sectorFromDelta(dYaw, dPitch, deadzone)
        if math.sqrt(dYaw * dYaw + dPitch * dPitch) < deadzone then
            return nil
        end
        local deg = math.deg(math.atan2(dYaw, dPitch)) -- 0 = arriba, positivo = derecha
        if deg < 0 then
            deg = deg + 360
        end
        return math.floor((deg + 22.5) / 45) % 8 + 1
    end

    local function sampleHead()
        if headSamples >= config.headProbeSamples then
            return
        end

        local t = nowSeconds()
        if headLastT and (t - headLastT) < config.headProbeInterval then
            return
        end
        headLastT = t

        if type(Export) ~= "table" or type(Export.LoGetCameraPosition) ~= "function" then
            log("HEAD: Export.LoGetCameraPosition no disponible en este entorno")
            headSamples = config.headProbeSamples -- no insistir
            return
        end

        local ok, cam = pcall(Export.LoGetCameraPosition)
        if not ok or type(cam) ~= "table" or type(cam.x) ~= "table" or type(cam.p) ~= "table" then
            log("HEAD: LoGetCameraPosition sin datos validos: ok=" .. tostring(ok) .. " res=" .. tostring(cam))
            headSamples = headSamples + 1
            return
        end

        if not headStructLogged then
            headStructLogged = true
            local okA, allowed = pcall(Export.LoIsOwnshipExportAllowed)
            log("HEAD: LoIsOwnshipExportAllowed=" .. tostring(okA and allowed or "n/d"))
            local keys = {}
            for k, _ in pairs(cam) do
                keys[#keys + 1] = tostring(k)
            end
            table.sort(keys)
            log("HEAD: campos de la camara: " .. table.concat(keys, ","))
        end

        -- cam.x = vector "hacia delante" de la camara en coordenadas del mundo
        local fx, fy, fz = cam.x.x, cam.x.y, cam.x.z
        local yaw = math.deg(math.atan2(fz, fx))
        local pitch = math.deg(math.asin(math.max(-1, math.min(1, fy))))

        if not headRef then
            headRef = { yaw = yaw, pitch = pitch }
            log(string.format("HEAD: referencia yaw=%.1f pitch=%.1f", yaw, pitch))
        end

        local dYaw = wrap180(yaw - headRef.yaw)
        local dPitch = pitch - headRef.pitch
        local sector = sectorFromDelta(dYaw, dPitch, 8)

        -- Actitud del avion (si la exportacion esta permitida): sirve para ver si las
        -- maniobras mueven la camara respecto a la referencia (la v0.2 deberia compensarlo).
        local acInfo = ""
        if type(Export.LoGetSelfData) == "function" then
            local okS, sd = pcall(Export.LoGetSelfData)
            if okS and type(sd) == "table" and sd.Heading then
                acInfo = string.format(" ac=(hdg %.0f, pit %.0f, bank %.0f)",
                    math.deg(sd.Heading), math.deg(sd.Pitch or 0), math.deg(sd.Bank or 0))
            end
        end

        headSamples = headSamples + 1
        log(string.format("HEAD #%d yaw=%.1f pitch=%.1f dYaw=%.1f dPitch=%.1f sector=%s pos=(%.1f,%.1f,%.1f)%s",
            headSamples, yaw, pitch, dYaw, dPitch, sector and tostring(sector) or "-",
            cam.p.x, cam.p.y, cam.p.z, acInfo))
    end

    ----------------------------------------------------------------------
    -- Acciones
    ----------------------------------------------------------------------
    local function stateFailed(ok, res, success)
        return (not ok)
            or success == false
            or (type(res) == "string" and string.find(res, "attempt to", 1, true) ~= nil)
    end

    -- Ejecuta Lua en el entorno REAL de scripting de mision (donde existen trigger, world, env...).
    -- Desde un Hook, el estado "mission" NO tiene esas APIs: el log de la v0.1.1 mostro
    --   dostring_in("mission", 'trigger.action...')  ->  attempt to index global 'trigger' (a nil value)
    -- La via documentada por la comunidad es llamar a a_do_script() desde el estado "mission".
    -- Si falla, se prueba el estado "server" como alternativa. Devuelve true, o false + motivo.
    local function runMission(code)
        if not inMission then
            return false, "no hay mision cargada"
        end

        local wrapped = "return a_do_script(" .. string.format("%q", code) .. ")"
        local ok, res, success = pcall(net.dostring_in, "mission", wrapped)
        log("runMission[mission/a_do_script] ok=" .. tostring(ok) .. " success=" .. tostring(success)
            .. " res=" .. tostring(res))
        if not stateFailed(ok, res, success) then
            return true
        end

        local ok2, res2, success2 = pcall(net.dostring_in, "server", code)
        log("runMission[server] ok=" .. tostring(ok2) .. " success=" .. tostring(success2)
            .. " res=" .. tostring(res2))
        if not stateFailed(ok2, res2, success2) then
            return true
        end

        return false, tostring(res2 or res)
    end

    ----------------------------------------------------------------------
    -- Menu de radio nativo de DCS
    --
    -- Lo que se sabe leyendo Scripts/UI/RadioCommandDialogPanel (solo lectura):
    --  * El panel es el modulo RadioCommandDialogsPanel, con setShowMenu(on), isVisible(),
    --    selectMenuItem(n) (1-10 = F1..F10, 11 = menu anterior, 12 = salir) y toPrevMenu().
    --  * El menu mostrado se lee de curDialogIt.element_.commandMenu:getItem(k):getText(),
    --    con textos tipo "F5. ATC..." (los submenus acaban en "...").
    --  * setShowMenu(true) bloquea el raton (DCS.lockAllMouseInput); setShowMenu(false) lo libera.
    --    Por eso el codigo inyectado SIEMPRE termina con setShowMenu(false).
    --  * El modulo se borra de los globales del Hook, asi que se busca en los estados de Lua
    --    de DCS con net.dostring_in. NO se ha podido comprobar en cual vive: se detecta al
    --    primer uso y queda escrito en el log (lineas "radio-state-probe").
    ----------------------------------------------------------------------
    local RADIO_RUNNER = [==[
local path, mode, start, devSpec = __PATH__, "__MODE__", "__START__", __DEV__
local p = RadioCommandDialogsPanel
if type(p) ~= 'table' then return 'ERR|sin panel de radio en este estado' end

local function slots()
  local res = {}
  local ok, cm = pcall(function() return p.curDialogIt.element_.commandMenu end)
  if not ok or not cm then return res, 'sin commandMenu: ' .. tostring(cm) end
  for k = 1, 12 do
    local ok2, txt = pcall(function() local it = cm:getItem(k); return it and it:getText() or '' end)
    if ok2 and txt and txt ~= '' then res[k] = txt end
  end
  return res
end

local function dumpSlots(s)
  local t = {}
  for k = 1, 12 do if s[k] then t[#t + 1] = k .. '=' .. s[k] end end
  return table.concat(t, ' ; ')
end

-- "F5. ATC...>>" -> "ATC"
local function label(txt)
  txt = (string.gsub(txt, '^F%d+%.%s*', ''))
  txt = (string.gsub(txt, '>+$', ''))
  txt = (string.gsub(txt, '%.%.%.$', ''))
  txt = (string.gsub(txt, '^%s+', ''))
  txt = (string.gsub(txt, '%s+$', ''))
  return txt
end

local function norm(txt) return string.lower(label(txt)) end

-- DCS anade "..." a las entradas que abren un submenu (y ">>" si ademas tienen un dialogo abierto)
local function isSub(txt) return string.find(txt, '%.%.%.>*$') ~= nil end

-- Entradas en las que se puede entrar (submenu "..." o conversacion abierta ">>")
local function isEnter(txt) return isSub(txt) or string.find(txt, '>>$') ~= nil end

-- Siempre cerrar el menu nativo al salir: libera el bloqueo de raton que pone setShowMenu(true)
local function finish(msg)
  pcall(p.setShowMenu, false)
  return msg
end

-- Seleccion de la radio fisica (comunicacion facil desactivada): devSpec = numero de dispositivo
-- o "autoN" (la N-esima radio del avion que acepta frecuencias VHF/UHF).
local devInfo = ''
if devSpec ~= nil then
  local id = devSpec
  if type(devSpec) == 'string' then
    local n = tonumber(string.match(devSpec, '^auto(%d+)$')) or 1
    local found = {}
    for i = 0, 100 do
      local okd, d = pcall(GetDevice, i)
      if okd and d then
        local okf, f = pcall(function() return d:get_frequency() end)
        if okf and type(f) == 'number' then
          local okr, inr = pcall(function() return d:is_frequency_in_range(130000000) or d:is_frequency_in_range(250000000) end)
          if okr and inr then found[#found + 1] = i end
        end
      end
    end
    devInfo = 'candidatos=' .. table.concat(found, ',')
    id = found[n]
    if not id then return 'ERR|no encuentro la radio ' .. devSpec .. ' (' .. devInfo .. ')' end
  end
  local oks, err = pcall(p.setCommunicatorId, id)
  devInfo = devInfo .. ' dev=' .. tostring(id) .. ' sel=' .. tostring(oks) .. (oks and '' or (':' .. tostring(err)))
  -- La radio que TRANSMITE se elige en el intercom de la cabina (igual que hace DCS al sintonizar
  -- con comunicacion facil): radios independientes -> set_as_current_radio; resto -> intercom.
  local txInfo = ''
  local okc, commDev = pcall(GetDevice, id)
  if okc and commDev then
    local oka, standalone = pcall(function()
      return commDev.get_is_standalone ~= nil and commDev:get_is_standalone() == true
    end)
    if oka and standalone then
      local ok3, e3 = pcall(function() commDev:set_as_current_radio() end)
      txInfo = 'standalone set_as_current_radio=' .. tostring(ok3) .. (ok3 and '' or (':' .. tostring(e3)))
    else
      local iid, idev = nil, nil
      for i = 0, 100 do
        local okd, d = pcall(GetDevice, i)
        if okd and d then
          local okm, fn = pcall(function() return d.set_communicator end)
          if okm and fn ~= nil then iid, idev = i, d; break end
        end
      end
      if idev then
        pcall(function() idev:make_setup_for_communicator(id) end)
        local ok2, e2 = pcall(function() idev:set_communicator(id) end)
        txInfo = 'intercom=' .. iid .. ' set_communicator=' .. tostring(ok2) .. (ok2 and '' or (':' .. tostring(e2)))
      else
        txInfo = 'sin intercom'
      end
    end
  end
  devInfo = devInfo .. ' tx[' .. txInfo .. ']'
  local okq, fq = pcall(function() return GetDevice(id):get_frequency() end)
  if okq and type(fq) == 'number' then devInfo = devInfo .. ' freqHz=' .. string.format('%d', fq) end
end

pcall(p.setShowMenu, true)
if start ~= 'dialog' then
  -- Si hay una conversacion en curso (p. ej. con ATC), DCS muestra su menu en vez del principal:
  -- volver al menu principal y a su raiz. Con start = "dialog" se respeta el menu activo.
  pcall(p.switchToMainMenu)
  pcall(function() p.curDialogIt.element_:setMainMenu() end)
end
local s, serr = slots()
if serr then return finish('ERR|' .. serr) end

local last = #path
local trail = {}
for i, step in ipairs(path) do
  local idx = nil
  if type(step) == 'number' then
    idx = step
  else
    -- un paso puede ser un nombre o una lista de nombres alternativos (idiomas)
    local names = type(step) == 'table' and step or { step }
    for _, nm in ipairs(names) do
      local want = string.lower(nm)
      for k = 1, 12 do
        if not idx and s[k] and norm(s[k]) == want then idx = k end
      end
      if not idx then
        -- coincidencia parcial (p. ej. "gudauta" dentro de "[N/A] Gudauta (4.2 / 130 ... Mhz)")
        for k = 1, 10 do
          if not idx and s[k] and string.find(norm(s[k]), want, 1, true) then idx = k end
        end
      end
      if idx then break end
    end
    if not idx then
      return finish('ERR|no encuentro "' .. (type(step) == 'table' and table.concat(step, '/') or step) .. '" en: ' .. dumpSlots(s))
    end
  end
  -- En modo volcado/escaneo/lista solo se entra en submenus: nunca se ejecuta un comando
  local canEnter = s[idx] and ((mode == 'list' and isEnter(s[idx])) or isSub(s[idx]))
  if mode ~= 'run' and not canEnter then
    return finish('ERR|"' .. tostring(step) .. '" no es un submenu (en modo ' .. mode .. ' no se ejecutan comandos)')
  end
  trail[#trail + 1] = s[idx] and label(s[idx]) or tostring(idx)
  local ok, err = pcall(p.selectMenuItem, idx)
  if not ok then return finish('ERR|selectMenuItem(' .. idx .. '): ' .. tostring(err)) end
  if i < last or mode ~= 'run' then
    s, serr = slots()
    if serr then return finish('ERR|' .. serr) end
  end
end

if mode == 'dump' then return finish('OK|' .. dumpSlots(s)) end

if mode == 'list' then
  local out = {}
  for k = 1, 10 do if s[k] then out[#out + 1] = k .. '\t' .. s[k] end end
  return finish('OK|' .. devInfo .. '|' .. table.concat(out, '\n'))
end

if mode == 'scan' then
  -- Recorre en profundidad todos los submenus (entradas que acaban en "...") y vuelve atras con
  -- F11 tras cada uno. No pulsa comandos. Limites: profundidad 4 y 80 submenus.
  local lines, count, aborted = {}, 0, nil
  local function scan(prefix, depth)
    local cur, e = slots()
    if e then lines[#lines + 1] = prefix .. ' !! ' .. e; return end
    lines[#lines + 1] = prefix .. ' => ' .. dumpSlots(cur)
    if depth >= 4 then return end
    for k = 1, 10 do
      if aborted then return end
      if cur[k] and isSub(cur[k]) then
        count = count + 1
        if count > 80 then aborted = 'limite de 80 submenus'; return end
        local ok, err = pcall(p.selectMenuItem, k)
        if not ok then aborted = 'selectMenuItem(' .. k .. '): ' .. tostring(err); return end
        scan(prefix .. '/' .. label(cur[k]), depth + 1)
        if aborted then return end
        pcall(p.selectMenuItem, 11)
        local back = slots()
        if dumpSlots(back) ~= dumpSlots(cur) then
          aborted = 'no pude volver atras desde ' .. label(cur[k])
          return
        end
      end
    end
  end
  scan(#trail > 0 and table.concat(trail, '/') or '(raiz)', 0)
  if aborted then lines[#lines + 1] = 'ABORTADO: ' .. aborted end
  return finish('OK|' .. table.concat(lines, ' || '))
end

return finish('OK')
]==]

    local function luaLiteral(v)
        if type(v) == "number" then
            return tostring(v)
        elseif type(v) == "table" then
            local t = {}
            for _, x in ipairs(v) do t[#t + 1] = luaLiteral(x) end
            return "{" .. table.concat(t, ",") .. "}"
        end
        return string.format("%q", tostring(v))
    end

    local function pathText(path)
        local t = {}
        for _, v in ipairs(path or {}) do
            t[#t + 1] = type(v) == "table" and table.concat(v, "/") or tostring(v)
        end
        return table.concat(t, " > ")
    end

    local function pathLiteral(path)
        local t = {}
        for _, v in ipairs(path or {}) do
            t[#t + 1] = luaLiteral(v)
        end
        return "{" .. table.concat(t, ",") .. "}"
    end

    -- Busca el estado de Lua donde existe RadioCommandDialogsPanel. Solo cachea los aciertos
    -- (el panel no existe hasta que hay una mision con unidad del jugador).
    detectRadioState = function()
        if radioState then
            return radioState
        end

        if type(RadioCommandDialogsPanel) == "table" then
            radioState = "local"
            log("radio-state-probe: el panel esta en el entorno del Hook")
            return radioState
        end

        local probe = "return type(RadioCommandDialogsPanel)"
        for _, st in ipairs({ "gui", "mission", "export", "config", "server" }) do
            local ok, res, success = pcall(net.dostring_in, st, probe)
            log("radio-state-probe[" .. st .. "] ok=" .. tostring(ok) .. " success=" .. tostring(success)
                .. " res=" .. tostring(res))
            if ok and res == "table" and not radioState then
                radioState = st
            end
        end

        if radioState then
            log("radio-state-probe: elegido '" .. radioState .. "'")
        end
        return radioState
    end

    -- mode: "run" (seguir la ruta y pulsar el comando), "dump" (leer los textos del menu al que
    -- lleva la ruta) o "scan" (leer todo el arbol de submenus desde ahi). start: "main" (por
    -- defecto, menu principal) o "dialog" (el menu activo, p. ej. una conversacion con ATC).
    -- Devuelve true + detalle, o false + motivo.
    local function runRadio(mode, path, start, device)
        if not inMission then
            return false, "no hay mision cargada"
        end

        local st = detectRadioState()
        if not st then
            return false, "menu de radio no accesible (ver log)"
        end

        local body = RADIO_RUNNER
        -- La ruta (texto del usuario) se sustituye la ultima, para que no pueda alterar los demas marcadores
        body = (string.gsub(body, "__MODE__", function() return mode end))
        body = (string.gsub(body, "__START__", function() return start == "dialog" and "dialog" or "main" end))
        body = (string.gsub(body, "__DEV__", function() return device ~= nil and luaLiteral(device) or "nil" end))
        body = (string.gsub(body, "__PATH__", function() return pathLiteral(path) end))

        local res, success
        if st == "local" then
            local f, err = loadstring(body)
            if not f then
                return false, "error interno: " .. tostring(err)
            end
            local ok, r = pcall(f)
            res, success = r, ok
        else
            local ok, r, s2 = pcall(net.dostring_in, st, body)
            res, success = r, (ok and s2 ~= false)
        end
        log("runRadio[" .. st .. "/" .. mode .. "] success=" .. tostring(success) .. " res=" .. tostring(res))

        res = tostring(res or "")
        if success and string.sub(res, 1, 3) == "OK|" then
            return true, string.sub(res, 4)
        elseif success and res == "OK" then
            return true, ""
        end
        if string.sub(res, 1, 4) == "ERR|" then
            return false, string.sub(res, 5)
        end
        return false, res
    end

    -- Radios fisicas del avion (para trabajar con comunicacion facil DESACTIVADA).
    -- info: lista los dispositivos con frecuencia. tune: sintoniza un dispositivo y lo selecciona.
    local RADIO_DEV = [==[
local mode, devId, freqHz = "__MODE__", __DEV__, __FREQ__
local p = RadioCommandDialogsPanel
if mode == 'info' then
  local out = {}
  for i = 0, 100 do
    local okd, d = pcall(GetDevice, i)
    if okd and d then
      local okf, f = pcall(function() return d:get_frequency() end)
      if okf and type(f) == 'number' then
        local lo, hi = '', ''
        pcall(function() lo = tostring(d:is_frequency_in_range(30000000)) .. '/' .. tostring(d:is_frequency_in_range(130000000)) .. '/' .. tostring(d:is_frequency_in_range(250000000)) end)
        out[#out + 1] = 'dev ' .. i .. ' freq=' .. f .. ' en_rango(30/130/250MHz)=' .. lo
      end
    end
  end
  local okc, cur = pcall(p.getCommunicatorId)
  return 'OK|comunicador_actual=' .. tostring(okc and cur or 'n/d') .. ' || ' .. table.concat(out, ' || ')
end
local okd, d = pcall(GetDevice, devId)
if not okd or not d then return 'ERR|no existe el dispositivo ' .. tostring(devId) end
if not d:is_frequency_in_range(freqHz) then return 'ERR|frecuencia fuera de rango para el dispositivo ' .. devId end
d:set_frequency(freqHz)
local oks, err = pcall(p.setCommunicatorId, devId)
return 'OK|sintonizado ' .. devId .. ' a ' .. freqHz .. ' (seleccion=' .. tostring(oks) .. ')'
]==]

    local function runRadioDev(mode, dev, freqHz)
        if not inMission then return false, "no hay mision cargada" end
        local st = detectRadioState()
        if not st then return false, "menu de radio no accesible (ver log)" end
        local body = RADIO_DEV
        body = (string.gsub(body, "__MODE__", function() return mode end))
        body = (string.gsub(body, "__DEV__", function() return tostring(tonumber(dev) or -1) end))
        body = (string.gsub(body, "__FREQ__", function() return string.format("%d", tonumber(freqHz) or 0) end))
        local res, success
        if st == "local" then
            local f, err = loadstring(body)
            if not f then return false, "error interno: " .. tostring(err) end
            local ok, r = pcall(f)
            res, success = r, ok
        else
            local ok, r, s2 = pcall(net.dostring_in, st, body)
            res, success = r, (ok and s2 ~= false)
        end
        log("runRadioDev[" .. st .. "/" .. mode .. "] success=" .. tostring(success) .. " res=" .. tostring(res))
        res = tostring(res or "")
        if success and string.sub(res, 1, 3) == "OK|" then return true, string.sub(res, 4) end
        if string.sub(res, 1, 4) == "ERR|" then return false, string.sub(res, 5) end
        return false, res
    end

    -- Devuelve true si la accion se completo (y la rueda puede cerrarse). Si no se completa,
    -- la rueda sigue abierta y la barra de titulo explica por que.
    local function runAction(a, item)
        if a.type == "joy_learn" then
            if not joy then setStatus("Boton de joystick no disponible (ver log)"); return false end
            local ok, err = joy.startLearn(DCS.getRealTime(), 12)
            if ok then
                setStatus("Pulsa ahora un boton del joystick (12 s)")
            else
                setStatus("Joystick: " .. tostring(err))
            end
            return false
        end
        if a.type == "joy_clear" then
            if joy then joy.clear() end
            setStatus("Boton de joystick borrado")
            return false
        end
        if a.type == "radio_info" or a.type == "radio_tune" then
            local ok, detail
            if a.type == "radio_info" then
                ok, detail = runRadioDev("info", -1, 0)
                log("RADIO-INFO: ok=" .. tostring(ok) .. "\r\n" .. (string.gsub(tostring(detail), " || ", "\r\n")))
            else
                ok, detail = runRadioDev("tune", a.device, (tonumber(a.freq) or 0) * 1000000)
                log("radio_tune [" .. tostring(a.device) .. " @ " .. tostring(a.freq) .. "] ok=" .. tostring(ok) .. " detalle=" .. tostring(detail))
            end
            if ok then
                setStatus(a.type == "radio_info" and "Info radios en el log" or nil)
                return a.type == "radio_tune"
            end
            setStatus("Radio: " .. string.sub(string.gsub(tostring(detail), "%s+", " "), 1, 70))
            return false
        end
        if a.type == "mission_lua" then
            local ok, detail = runMission(a.code)
            if ok then
                setStatus(nil)
                return true
            end
            log("mission_lua FALLO: " .. tostring(detail))
            local short = string.sub(string.gsub(tostring(detail), "%s+", " "), 1, 70)
            setStatus("Error: " .. short)
            return false
        elseif a.type == "radio_item" or a.type == "radio_dump" or a.type == "radio_scan" then
            local mode = (a.type == "radio_dump" and "dump") or (a.type == "radio_scan" and "scan") or "run"
            local ok, detail = runRadio(mode, a.path, a.start, a.device)
            if mode == "scan" then
                log("RADIO-SCAN: ok=" .. tostring(ok) .. "\r\n" .. (string.gsub(tostring(detail), " || ", "\r\n")))
            elseif mode == "dump" then
                log("RADIO-DUMP: " .. tostring(detail))
            else
                log("radio_item [" .. pathText(a.path) .. "] ok=" .. tostring(ok)
                    .. " detalle=" .. tostring(detail))
            end

            if ok then
                if mode ~= "run" then
                    setStatus(mode == "scan" and "Escaneo en el log" or "Volcado en el log")
                    return false -- la rueda sigue abierta para ver el aviso
                end
                setStatus(nil)
                return true
            end

            local short = string.sub(string.gsub(tostring(detail), "%s+", " "), 1, 70)
            setStatus("Radio: " .. short)
            return false
        end

        log("Tipo de accion desconocido: " .. tostring(a.type))
        setStatus("Accion desconocida")
        return false
    end

    ----------------------------------------------------------------------
    -- Navegacion y dibujo
    ----------------------------------------------------------------------
    local function currentNode()
        return stack[#stack]
    end

    local hide

    local hoverSector = nil -- sector bajo el raton en el estilo de cuñas (0 = centro)

    local function updateHover(sec)
        hoverSector = sec
        if not wedge then return end
        local node = currentNode()
        for i = 1, 8 do
            local on = (sec == i) and node.items and node.items[i] ~= nil
            wedge.hover[i]:setVisible(on and true or false)
        end
        wedge.centerHover:setVisible(sec == 0)
    end

    render = function()
        local node = currentNode()
        local title = "Radial Comms - " .. tostring(node.title or node.label or "")
        if statusMsg then
            title = title .. "  |  " .. statusMsg
        end
        window:setText(title)

        if wedge then
            wedge.title:setText(title)
            -- color: el del propio sector, o el del ultimo nodo con color de la pila
            local base = "blue"
            for _, n in ipairs(stack) do
                if n.color and THEME_OK[n.color] then base = n.color end
            end
            for i = 1, 8 do
                local item = node.items and node.items[i]
                local theme = (item and item.color and THEME_OK[item.color]) and item.color or base
                if wedge.cur[i] ~= theme then
                    wedge.normal[i]:setSkin(wedge.skin[theme][i])
                    wedge.cur[i] = theme
                end
                local text = ""
                if item then
                    text = tostring(item.label)
                    if item.items or item.radio then text = text .. " \194\187" end -- indica submenu
                end
                wedge.label[i]:setText(text)
                wedge.normal[i]:setOpacity(item and 1 or 0.3)
            end
            if wedge.curCenter ~= base then
                wedge.centerNormal:setSkin(wedge.skin[base].center)
                wedge.curCenter = base
            end
            -- centro: radio activa + frecuencia sintonizada; si no, atras / cerrar
            local cx0, cy0 = math.floor(WEDGE_S / 2 - 46), WEDGE_STRIP + WEDGE_S / 2
            local badge = node.badge
            if badge then
                wedge.centerLabel:setText("< " .. tostring(badge.name))
                wedge.centerLabel:setBounds(cx0, math.floor(cy0 - 21), 92, 22)
                local freq = badge.hz and string.format("%.3f", badge.hz / 1000000) or ""
                wedge.centerSub:setText(freq)
                local want = badge.warn and "warn" or "ok"
                if wedge.subCur ~= want then
                    wedge.centerSub:setSkin(want == "warn" and wedge.subWarn or wedge.subOk)
                    wedge.subCur = want
                end
            else
                wedge.centerLabel:setText(#stack > 1 and "< Atras" or "Cerrar")
                wedge.centerLabel:setBounds(cx0, math.floor(cy0 - 14), 92, 28)
                wedge.centerSub:setText("")
            end
            updateHover(nil)
            return
        end
    end

    setStatus = function(msg)
        statusMsg = msg
        if window then
            render()
        end
    end

    ----------------------------------------------------------------------
    -- Nodos dinamicos: reflejan en la rueda el menu nativo de una radio
    ----------------------------------------------------------------------
    local function cleanLabel(txt)
        txt = string.gsub(txt, "^F%d+%.%s*", "")
        txt = string.gsub(txt, ">+$", "")
        txt = string.gsub(txt, "%.%.%.$", "")
        txt = string.gsub(txt, "^%s+", "")
        txt = string.gsub(txt, "%s+$", "")
        return txt
    end

    local function shortLabel(txt, max)
        if string.len(txt) > max then
            return string.sub(txt, 1, max - 1) .. "~"
        end
        return txt
    end

    -- "[N/A] Gudauta (130 Mhz AM)>>" -> "Gudauta 130"  (nombre corto + frecuencia)
    local function displayLabel(text)
        local clean = cleanLabel(text)
        clean = string.gsub(clean, "^%[N/A%]%s*", "")
        local name, paren = string.match(clean, "^(.-)%s*%((.-)%)$")
        if name and name ~= "" then
            local f = string.match(paren, "([%d%.]+)%s*[Mm][Hh][Zz]")
            if f then
                return shortLabel(name, 24 - string.len(f) - 1) .. " " .. f
            end
        end
        return shortLabel(clean, 24)
    end

    local function copyPath(path, extra)
        local t = {}
        for _, v in ipairs(path or {}) do t[#t + 1] = v end
        if extra ~= nil then t[#t + 1] = extra end
        return t
    end

    -- entries = { {idx=, text=}, ... } -> items de la rueda (maximo 8 por pagina; "Mas..." enlaza la siguiente)
    local function buildPage(entries, from, device, basePath, badgeName)
        local items = {}
        local remaining = #entries - from + 1
        local perPage = remaining > 8 and 7 or 8
        for n = from, math.min(#entries, from + perPage - 1) do
            local e = entries[n]
            local text = e.text
            local enter = string.find(text, "%.%.%.>*$") ~= nil or string.find(text, ">>$") ~= nil
            local label = displayLabel(text)
            if enter then
                local mhz = tonumber(string.match(text, "([%d%.]+)%s*[Mm][Hh][Zz]"))
                items[#items + 1] = { label = label, radio = { device = device, path = copyPath(basePath, e.idx), freq = mhz, badgeName = badgeName } }
            else
                items[#items + 1] = { label = label, action = { type = "radio_item", device = device, path = copyPath(basePath, e.idx) } }
            end
        end
        if remaining > 8 then
            items[#items + 1] = { label = "Mas...", items = buildPage(entries, from + 7, device, basePath, badgeName) }
        end
        return items
    end

    local function openDynamic(item)
        local r = item.radio
        local ok, detail = runRadio("list", r.path or {}, "main", r.device)
        if not ok then
            log("lista radio [" .. tostring(item.label) .. "] FALLO: " .. tostring(detail))
            setStatus("Radio: " .. string.sub(string.gsub(tostring(detail), "%s+", " "), 1, 70))
            return
        end
        local info, body = string.match(tostring(detail), "^([^|]*)|(.*)$")
        info = info or ""
        body = body or tostring(detail)
        local entries = {}
        for line in string.gmatch(body, "[^\n]+") do
            local k, text = string.match(line, "^(%d+)\t(.*)$")
            if k then entries[#entries + 1] = { idx = tonumber(k), text = text } end
        end
        log("LISTA radio [" .. tostring(item.label) .. "] " .. info .. " entradas=" .. #entries)
        -- Estaciones que esta radio no puede alcanzar ("[N/A]"): se ocultan salvo hideUnavailable = false
        local hidden = 0
        if config.hideUnavailable ~= false then
            local kept = {}
            for _, e in ipairs(entries) do
                if string.find(e.text, "%[N/A%]") then
                    hidden = hidden + 1
                else
                    kept[#kept + 1] = e
                end
            end
            entries = kept
        end
        if hidden > 0 then
            log("LISTA radio [" .. tostring(item.label) .. "] ocultas " .. hidden .. " estaciones [N/A]")
        end
        -- COM1/COM2: "Personal de tierra" vive en GROUND CREW, no se repite aqui
        if r.device ~= nil and #(r.path or {}) == 0 and config.hideGroundCrewInRadios ~= false then
            local kept, gc = {}, 0
            for _, e in ipairs(entries) do
                local t = string.lower(e.text)
                if string.find(t, "personal de tierra", 1, true) or string.find(t, "ground crew", 1, true) then
                    gc = gc + 1
                else
                    kept[#kept + 1] = e
                end
            end
            entries = kept
            if gc > 0 then log("LISTA radio [" .. tostring(item.label) .. "] ocultado ground crew: " .. gc) end
        end
        if #entries == 0 then
            setStatus(hidden > 0 and "Ninguna estacion alcanzable con esta radio"
                or "Sin opciones disponibles")
            return
        end
        local badgeName = r.badgeName or (r.device ~= nil and cleanLabel(item.label) or nil)
        local node = { label = item.label, color = item.color, items = buildPage(entries, 1, r.device, r.path or {}, badgeName) }
        local tunedHz0 = tonumber(string.match(info, "freqHz=(%d+)"))
        if badgeName then
            node.badge = { name = badgeName, hz = tunedHz0 }
        end
        table.insert(stack, node)
        statusMsg = nil
        -- Aviso: con la comunicacion facil desactivada el mensaje sale por la frecuencia SINTONIZADA
        local tunedHz = tonumber(string.match(info, "freqHz=(%d+)"))
        if r.freq and tunedHz then
            local tunedMhz = tunedHz / 1000000
            log(string.format("FRECUENCIA radio dev=%s sintonizada=%.3f estacion=%.3f", tostring(r.device), tunedMhz, r.freq))
            if math.abs(tunedMhz - r.freq) > 0.006 then
                statusMsg = string.format("OJO: radio en %.3f, estacion en %.3f", tunedMhz, r.freq)
                if node.badge then node.badge.warn = true end
            end
        end
        render()
    end

    local function onSelect(i)
        local item = currentNode().items and currentNode().items[i]
        if not item then
            return
        end
        log("CLICK sector " .. i .. ": " .. tostring(item.label))

        if item.items then
            table.insert(stack, item)
            statusMsg = nil
            render()
        elseif item.radio then
            openDynamic(item)
        elseif item.action then
            local done = runAction(item.action, item)
            if done and config.closeAfterAction then
                hide()
            end
        end
    end

    local function onCenter()
        log("CLICK centro (" .. (#stack > 1 and "atras" or "cerrar") .. ")")
        if #stack > 1 then
            table.remove(stack)
            statusMsg = nil
            render()
        else
            hide()
        end
    end

    ----------------------------------------------------------------------
    -- Estilo de cuñas: imagenes (img\\*.png) + deteccion de sector por angulo
    ----------------------------------------------------------------------
    local function deepCopy(t)
        if type(t) ~= "table" then return t end
        local c = {}
        for k, v in pairs(t) do c[k] = deepCopy(v) end
        return c
    end

    -- Skin de Static: parte de la skin por defecto de DCS y le pone imagen y/o estilo de texto
    local function staticSkin(file, textColor, fontSize, wrap)
        local base
        local okb, sk = pcall(function() return Skin.getSkin("staticSkin") end)
        if okb and type(sk) == "table" and sk.skinData then
            base = deepCopy(sk)
        else
            base = { skinData = { params = {}, states = { released = { [1] = {} }, disabled = { [1] = {} } }, type = "Static" }, version = 1 }
        end
        local sd = base.skinData
        sd.params = sd.params or {}
        sd.params.textWrapping = wrap and true or false
        sd.states = sd.states or {}
        for _, st in ipairs({ "released", "disabled" }) do
            sd.states[st] = sd.states[st] or {}
            local e = sd.states[st][1] or {}
            sd.states[st][1] = e
            e.text = {
                blur = 0, color = textColor or "0xffffffff",
                font = "DejaVuLGCSansCondensed-Bold.ttf", fontSize = fontSize or 13,
                horzAlign = { type = "middle" }, vertAlign = { offset = 0, type = "middle" },
                shadowOffset = { horz = 1, vert = 1 },
            }
            if file then
                e.picture = { color = "0xffffffff", file = file,
                              horzAlign = { type = "middle" }, vertAlign = { offset = 0, type = "middle" } }
            end
        end
        return base
    end

    -- Sector (1-8, 0 = centro, nil = fuera) bajo el punto (x, y) en coordenadas de la ventana
    local winX, winY = 0, 0 -- posicion de la ventana en pantalla (la fija centerWindow)

    local function sectorAt(x, y)
        -- DCS entrega el raton en coordenadas de PANTALLA; si ya vienen locales (x,y dentro de la
        -- ventana) se usan tal cual.
        if x > winW or y > winH then
            x, y = x - winX, y - winY
        end
        local cx, cy = WEDGE_S / 2, WEDGE_STRIP + WEDGE_S / 2
        local dx, dy = x - cx, y - cy
        local r = math.sqrt(dx * dx + dy * dy)
        if r <= WEDGE_R_IN - 4 then return 0 end
        if r > WEDGE_S / 2 then return nil end
        local deg = math.deg(math.atan2(dx, -dy)) -- 0 = arriba, sentido horario
        deg = (deg + 22.5) % 360
        return math.floor(deg / 45) + 1
    end

    local function buildWedges(parent)
        local dir = lfs.writedir() .. "Scripts\\RadialComms\\img\\"
        local w = { normal = {}, hover = {}, label = {}, cur = {}, curCenter = "blue" }
        w.skin = {}
        for _, t in ipairs(THEMES) do
            w.skin[t] = {}
            for i = 1, 8 do w.skin[t][i] = staticSkin(dir .. "wedge_" .. t .. "_" .. i .. ".png") end
            w.skin[t].center = staticSkin(dir .. "center_" .. t .. ".png")
        end
        local function mk(skin, x, y, ww, hh)
            local st = Static.new("")
            st:setSkin(skin)
            st:setBounds(x, y, ww, hh)
            parent:insertWidget(st)
            return st
        end
        for i = 1, 8 do
            w.normal[i] = mk(w.skin.blue[i], 0, WEDGE_STRIP, WEDGE_S, WEDGE_S)
            w.cur[i] = "blue"
        end
        for i = 1, 8 do
            w.hover[i] = mk(staticSkin(dir .. "wedge_h_" .. i .. ".png"), 0, WEDGE_STRIP, WEDGE_S, WEDGE_S)
            w.hover[i]:setVisible(false)
        end
        w.centerNormal = mk(w.skin.blue.center, 0, WEDGE_STRIP, WEDGE_S, WEDGE_S)
        w.centerHover = mk(staticSkin(dir .. "center_h.png"), 0, WEDGE_STRIP, WEDGE_S, WEDGE_S)
        w.centerHover:setVisible(false)
        local lw, lh = 110, 44
        for i = 1, 8 do
            local a = math.rad(-90 + (i - 1) * 45)
            local x = WEDGE_S / 2 + WEDGE_R_LABEL * math.cos(a)
            local y = WEDGE_STRIP + WEDGE_S / 2 + WEDGE_R_LABEL * math.sin(a)
            w.label[i] = mk(staticSkin(nil, "0xffffffff", 13, true), math.floor(x - lw / 2), math.floor(y - lh / 2), lw, lh)
        end
        w.centerLabel = mk(staticSkin(nil, "0xffffffff", 14, false),
            math.floor(WEDGE_S / 2 - 46), math.floor(WEDGE_STRIP + WEDGE_S / 2 - 14), 92, 28)
        w.subOk = staticSkin(nil, "0xaecbe8ff", 12, false)
        w.subWarn = staticSkin(nil, "0xffb347ff", 12, false)
        w.centerSub = mk(w.subOk, math.floor(WEDGE_S / 2 - 46), math.floor(WEDGE_STRIP + WEDGE_S / 2 + 2), 92, 18)
        w.subCur = "ok"
        w.title = mk(staticSkin(nil, "0xe8eef7ff", 12, false), 0, 0, WEDGE_S, WEDGE_STRIP)

        -- capa transparente encima de todo: recibe el raton y calcula el sector
        local hit = mk(staticSkin(nil), 0, 0, WEDGE_S, WEDGE_S + WEDGE_STRIP)
        local logged = 0
        hit:addMouseMoveCallback(function(self, x, y)
            if logged < 4 then
                logged = logged + 1
                log(string.format("WEDGE raton move x=%s y=%s -> sector %s", tostring(x), tostring(y), tostring(sectorAt(x, y))))
            end
            local sec = sectorAt(x, y)
            if sec ~= hoverSector then updateHover(sec) end
        end)
        hit:addMouseLeaveCallback(function() updateHover(nil) end)
        hit:addMouseUpCallback(function(self, x, y)
            local sec = sectorAt(x, y)
            log(string.format("WEDGE raton up x=%s y=%s -> sector %s", tostring(x), tostring(y), tostring(sec)))
            if sec == 0 then
                onCenter()
            elseif sec then
                onSelect(sec)
            end
        end)
        w.hit = hit
        return w
    end

    local function currentSize()
        return WEDGE_S, WEDGE_S + WEDGE_STRIP
    end

    local function centerWindow()
        local sw, sh = dxgui.GetScreenSize()
        winW, winH = currentSize()
        winX, winY = math.floor((sw - winW) / 2), math.floor((sh - winH) / 2)
        window:setBounds(
            math.floor((sw - winW) / 2),
            math.floor((sh - winH) / 2),
            winW,
            winH
        )
    end

    -- Ajusta tamaño, skin de la ventana y widgets de la rueda
    local function applyStyle()
        if not window or not wedge then return end
        for i = 1, 8 do
            wedge.normal[i]:setVisible(true)
            wedge.label[i]:setVisible(true)
            wedge.hover[i]:setVisible(false)
        end
        wedge.centerNormal:setVisible(true)
        wedge.centerHover:setVisible(false)
        wedge.centerLabel:setVisible(true)
        wedge.centerSub:setVisible(true)
        wedge.title:setVisible(true)
        wedge.hit:setVisible(true)
        winW, winH = currentSize()
        centerWindow()
        pcall(function() window:setTitleHeight(0) end)
        window:setSkin(windowSkinHidden) -- ventana sin marco ni fondo: solo se ven las cuñas
        panel:setBounds(0, 0, winW, winH)
        render()
    end

    local function show()
        stack = { menuRoot }
        headRef = nil
        headLastT = nil
        headSamples = 0
        headSel = { ref = nil, dy = 0, dp = 0, sec = nil, since = 0, armed = true, lastT = 0 }
        statusMsg = nil
        if not wedge then
            log("No se puede abrir: la rueda no se creo (ver ERROR arriba)")
            return
        end
        window:setVisible(true)
        panel:setVisible(true)
        window:setHasCursor(true)
        applyStyle()
        isHidden = false

        if config.runProbe and not probeDone then
            probeDone = true
            local ok, err = pcall(runProbe)
            if not ok then
                log("Error en la sonda: " .. tostring(err))
            end
        end
    end

    hide = function()
        -- No se puede ocultar la ventana sin destruirla (igual que en dcs-scratchpad),
        -- asi que se cambia a una skin invisible y se quita el cursor.
        window:setSkin(windowSkinHidden)
        panel:setVisible(false)
        window:setHasCursor(false)
        isHidden = true
    end

    -- Seleccion con la cabeza: la orientacion de la camara (relativa al avion, para que las
    -- maniobras no cuenten) se compara con la que tenia al abrir la rueda. Pasar de la zona muerta
    -- resalta el sector; mantener la mirada headDwell segundos lo elige. Despues hay que volver
    -- a la zona muerta antes de poder elegir otro (evita elegir el opuesto al volver al centro).
    local function headAngles()
        if type(Export) ~= "table" or type(Export.LoGetCameraPosition) ~= "function" then return nil end
        local ok, cam = pcall(Export.LoGetCameraPosition)
        if not ok or type(cam) ~= "table" or type(cam.x) ~= "table" then return nil end
        local yaw = math.deg(math.atan2(cam.x.z, cam.x.x))
        local pitch = math.deg(math.asin(math.max(-1, math.min(1, cam.x.y))))
        if type(Export.LoGetSelfData) == "function" then
            local okS, sd = pcall(Export.LoGetSelfData)
            if okS and type(sd) == "table" and sd.Heading then
                yaw = yaw - math.deg(sd.Heading)
                pitch = pitch - math.deg(sd.Pitch or 0)
            end
        end
        return wrap180(yaw), pitch
    end

    local function headTick()
        local t = nowSeconds()
        if t - headSel.lastT < 0.05 then return end
        headSel.lastT = t

        local yaw, pitch = headAngles()
        if not yaw then return end
        if not headSel.ref then
            headSel.ref = { yaw = yaw, pitch = pitch }
            log(string.format("HEADSEL: referencia yaw=%.1f pitch=%.1f", yaw, pitch))
            return
        end

        -- suavizado: la cabeza tiembla unos grados
        local k = 0.35
        headSel.dy = headSel.dy + k * (wrap180(yaw - headSel.ref.yaw) - headSel.dy)
        headSel.dp = headSel.dp + k * ((pitch - headSel.ref.pitch) - headSel.dp)

        local sec = sectorFromDelta(headSel.dy, headSel.dp, config.headDeadzone)
        if sec ~= headSel.sec then
            headSel.sec = sec
            headSel.since = t
            updateHover(sec)
        end
        if sec == nil then
            headSel.armed = true
        elseif headSel.armed and (t - headSel.since) >= config.headDwell then
            local node = currentNode()
            if node.items and node.items[sec] then
                headSel.armed = false
                log(string.format("HEADSEL: sector %d elegido (dYaw=%.1f dPitch=%.1f)", sec, headSel.dy, headSel.dp))
                onSelect(sec)
            end
        end
    end

    local function createWindow()
        if window ~= nil then
            return
        end

        window = Window.new(0, 0, winW, winH, "RadialComms.Window")
        windowDefaultSkin = window:getSkin()

        panel = Panel.new()
        panel:setBounds(0, 0, winW, winH)
        window:insertWidget(panel)

        local okw, wres = pcall(buildWedges, panel)
        if okw then
            wedge = wres
            log("Rueda de cuñas lista")
        else
            log("ERROR creando la rueda de cuñas: " .. tostring(wres))
            wedge = nil
        end

        toggleWheel = function()
            if isHidden then show() else hide() end
        end
        window:addHotKeyCallback(config.hotkey, toggleWheel)

        if config.joystickButton ~= false then
            local okj, J = pcall(function()
                return dofile(lfs.writedir() .. "Scripts/RadialComms/JoyButton.lua")
            end)
            if okj and J then
                joy = J.new({ log = log, savePath = lfs.writedir() .. "Config/RadialCommsJoystick.lua" })
                joy.load()
            else
                log("JOY: no se pudo cargar JoyButton.lua: " .. tostring(J))
            end
        end

        centerWindow()
        window:setVisible(true)
        hide()
        log("Ventana creada. Hotkey: " .. tostring(config.hotkey))
    end

    ----------------------------------------------------------------------
    -- Callbacks expuestos al Hook
    ----------------------------------------------------------------------
    function M.onFrame()
        if window == nil then
            local ok, err = pcall(createWindow)
            if not ok then
                log("ERROR creando la ventana: " .. tostring(err))
                net.log("[RadialComms] Error creando la ventana: " .. tostring(err))
                -- evita reintentar cada frame
                window = false
            end
        end

        if joy then
            local okp, errp = pcall(joy.poll, DCS.getRealTime(),
                function() if toggleWheel then toggleWheel() end end,
                function(dev, btn)
                    log("JOY: asignado " .. dev .. " / " .. btn)
                    setStatus("Boton asignado: " .. btn)
                end,
                function() setStatus("Sin pulsacion: no se asigno ningun boton") end)
            if not okp then
                log("JOY: error en poll (desactivado): " .. tostring(errp))
                joy = nil
            end
        end

        if window and not isHidden and config.headSelect then
            local ok, err = pcall(headTick)
            if not ok then
                log("Error en la seleccion con la cabeza (desactivada): " .. tostring(err))
                config.headSelect = false
            end
        end

        if window and not isHidden and config.headProbe then
            local ok, err = pcall(sampleHead)
            if not ok then
                log("Error en la sonda de cabeza (desactivada): " .. tostring(err))
                config.headProbe = false
            end
        end
    end

    function M.onMissionLoadEnd()
        inMission = true
        radioState = nil -- el panel de radio se recrea con cada mision: volver a detectarlo
        if joy then pcall(joy.reassert) end
        log("Mision cargada")
    end

    function M.onSimulationStop()
        inMission = false
        radioState = nil
        if window then
            hide()
        end
        log("Simulacion detenida")
    end

    log("RadialComms v0.9.0 iniciado")
end

-- Si DCS llama antes de start(), los callbacks no hacen nada.
function M.onFrame() end
function M.onMissionLoadEnd() end
function M.onSimulationStop() end

return M
