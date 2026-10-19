-- RadialComms - boton de joystick SIN software externo (experimental)
--
-- Usa la misma API de entrada que el panel de controles de DCS (Scripts\Input\*.lua):
--   Input.createLayer / Input.addKeyCombo / Input.setTopLayer / Input.getInputActions
-- Se crea una capa de entrada propia con UN solo boton (el asignado). Los demas botones y ejes
-- no estan en la capa, asi que siguen llegando al avion.
-- Las acciones se numeran fuera del rango de comandos del simulador (>= 10000 + evento).

local J = {}

local LAYER = "RadialComms"
local BASE = 10000 -- igual que maxCommandValue de AddComboDialog.lua

function J.new(opts)
    local log = opts.log
    local savePath = opts.savePath
    local self = {
        assigned = nil,   -- { device = "nombre", button = "JOY_BTN5", event = n }
        learning = nil,   -- { untilT = t, events = { [accion] = {device,name} } }
        layerOn = false,
        lastCheck = 0,
        seen = 0,
        InputUtils = nil,
    }

    local function utils()
        if not self.InputUtils then
            local ok, m = pcall(require, "Input.Utils")
            if ok then self.InputUtils = m else log("JOY: no puedo cargar Input.Utils: " .. tostring(m)) end
        end
        return self.InputUtils
    end

    local I = nil
    local diagDone = false
    local function available()
        if I then return true end
        local cand = nil
        if type(_G.Input) == "table" then cand = _G.Input end
        if not cand then
            local ok, m = pcall(require, "Input")
            if ok and type(m) == "table" then cand = m end
            if not diagDone then log("JOY: require('Input') -> " .. tostring(ok) .. " " .. tostring(m)) end
        end
        if not diagDone then
            diagDone = true
            local names = {}
            if cand then for k in pairs(cand) do names[#names + 1] = tostring(k) end end
            table.sort(names)
            log("JOY: global Input=" .. type(_G.Input) .. "; funciones de la API: " .. table.concat(names, ","))
        end
        if cand and cand.createLayer and cand.addKeyCombo and cand.getInputActions then
            I = cand
            return true
        end
        return false
    end

    ------------------------------------------------------------------
    -- Guardado / carga de la asignacion
    ------------------------------------------------------------------
    function self.load()
        local f = loadfile(savePath)
        if not f then return end
        local ok, t = pcall(f)
        if ok and type(t) == "table" and t.device and t.button then
            self.assigned = { device = t.device, button = t.button }
            log("JOY: boton guardado = " .. t.device .. " / " .. t.button)
        end
    end

    local function save()
        local fh = io.open(savePath, "w")
        if not fh then log("JOY: no puedo escribir " .. savePath); return end
        if self.assigned then
            fh:write(string.format("return { device = %q, button = %q }\n", self.assigned.device, self.assigned.button))
        else
            fh:write("return {}\n")
        end
        fh:close()
    end

    ------------------------------------------------------------------
    -- Capa de entrada
    ------------------------------------------------------------------
    local function dropLayer()
        if available() and I.deleteLayer then pcall(I.deleteLayer, LAYER) end
        self.layerOn = false
    end

    local function inStack()
        if not I.getLayerStack then return nil end
        local ok, st = pcall(I.getLayerStack)
        if not ok or type(st) ~= "table" then return nil end
        for _, v in pairs(st) do
            if v == LAYER or (type(v) == "table" and (v.name == LAYER)) then return true end
        end
        return false
    end

    -- capa con solo el boton asignado
    local function buildAssigned()
        local U = utils()
        if not (available() and U and self.assigned) then return false, "API no disponible" end
        dropLayer()
        local ok, err = pcall(function()
            I.createLayer(LAYER)
            local ev = U.getInputEvent(self.assigned.button)
            if not ev then error("evento desconocido " .. tostring(self.assigned.button)) end
            local id = I.getDeviceId(self.assigned.device)
            self.assigned.event = ev
            self.assigned.deviceId = id
            I.addKeyCombo(LAYER, ev, id, nil, ev + BASE, nil, nil)
            I.setTopLayer(LAYER)
        end)
        if not ok then log("JOY: error creando la capa: " .. tostring(err)); return false, err end
        self.layerOn = true
        log("JOY: capa lista para " .. self.assigned.device .. " / " .. self.assigned.button)
        return true
    end

    -- capa con TODOS los botones de joystick (modo aprender)
    local function buildLearn()
        local U = utils()
        if not (available() and U) then return false, "API de entrada no disponible" end
        dropLayer()
        local map, count = {}, 0
        local ok, err = pcall(function()
            I.createLayer(LAYER)
            local jt = I.getJoystickDeviceTypeName()
            for _, dev in ipairs(I.getDevices()) do
                if U.getDeviceTypeName(dev) == jt then
                    local id = I.getDeviceId(dev)
                    local skip = U.getDeviceEventsToSkip(dev)
                    for _, k in ipairs(U.getDeviceKeys(dev)) do
                        if not skip[k.event] then
                            I.addKeyCombo(LAYER, k.event, id, nil, k.event + BASE, nil, nil)
                            -- clave accion+dispositivo: el mismo boton en dos mandos tiene la misma accion
                            map[(k.event + BASE) .. ":" .. tostring(id)] = { device = dev, button = k.name }
                            count = count + 1
                        end
                    end
                end
            end
            I.setTopLayer(LAYER)
        end)
        if not ok then log("JOY: error en modo aprender: " .. tostring(err)); dropLayer(); return false, err end
        self.layerOn = true
        log("JOY: modo aprender, " .. count .. " botones vigilados")
        return true, map, count
    end

    ------------------------------------------------------------------
    -- API publica
    ------------------------------------------------------------------
    function self.startLearn(now, seconds)
        local ok, map, count = buildLearn()
        if not ok then return false, tostring(map) end
        if count == 0 then dropLayer(); return false, "no hay joysticks" end
        self.learning = { untilT = now + (seconds or 10), map = map }
        return true
    end

    function self.clear()
        self.assigned = nil
        self.learning = nil
        dropLayer()
        save()
        log("JOY: boton borrado")
    end

    function self.status()
        if self.learning then return "esperando boton" end
        if self.assigned then return self.assigned.device .. " " .. self.assigned.button end
        return nil
    end

    -- Se llama en cada frame. onPress() se invoca al pulsar el boton asignado.
    -- onLearned(device, button) / onTimeout() durante el modo aprender.
    function self.poll(now, onPress, onLearned, onTimeout)
        if not available() then return end
        if not (self.learning or self.assigned) then return end

        local ok, actions = pcall(I.getInputActions)
        if not ok then
            log("JOY: getInputActions fallo: " .. tostring(actions))
            self.assigned, self.learning = nil, nil
            return
        end
        if type(actions) == "table" then
            for _, a in ipairs(actions) do
                if self.seen < 12 then
                    self.seen = self.seen + 1
                    log(string.format("JOY: accion=%s dev=%s", tostring(a.action), tostring(a.deviceId)))
                end
                if self.learning then
                    local hit = self.learning.map[tostring(a.action) .. ":" .. tostring(a.deviceId)]
                    if hit then
                        self.learning = nil
                        self.assigned = { device = hit.device, button = hit.button }
                        save()
                        buildAssigned()
                        onLearned(hit.device, hit.button)
                    end
                elseif self.assigned and self.assigned.event and a.action == self.assigned.event + BASE
                    and tostring(a.deviceId) == tostring(self.assigned.deviceId) then
                    onPress()
                end
            end
        end

        if self.learning and now > self.learning.untilT then
            self.learning = nil
            if self.assigned then buildAssigned() else dropLayer() end
            onTimeout()
        end

        -- DCS rehace la pila de capas al cambiar de avion/mision: reponer la nuestra
        if self.assigned and not self.learning and now - self.lastCheck > 2 then
            self.lastCheck = now
            if inStack() == false then
                log("JOY: la capa ya no esta en la pila, la repongo")
                buildAssigned()
            end
        end
    end

    -- tras cargar una mision
    function self.reassert()
        if self.assigned and not self.learning then buildAssigned() end
    end

    return self
end

return J
