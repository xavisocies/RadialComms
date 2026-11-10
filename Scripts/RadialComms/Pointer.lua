-- RadialComms - puntero de la rueda: cursor + mirada (spec 001-Botones)
--
-- Decide QUE cuña esta resaltada a partir de dos fuentes: el cursor del raton y la mirada
-- (orientacion de la cabeza). Manda la fuente que cambio en ultimo lugar; si esa fuente no
-- senala nada, se usa la otra.
-- Modulo PURO: no usa DCS ni reloj; se prueba fuera del juego.
--
--   local p = Pointer.new({ deadzone = 7 })
--   p.mouse(sector)           -- sector bajo el cursor: nil (fuera), 0 (centro) o 1-8
--   p.gaze(dYaw, dPitch)      -- desviacion de la cabeza en grados respecto a la referencia
--   p.current()               -- nil, 0 (centro) o 1-8: lo que hay que resaltar
--
-- Sectores: 1 = arriba, numerados en sentido horario (yaw positivo = derecha, pitch positivo = arriba).

local P = {}

local DEFAULT_DEADZONE = 7 -- grados

-- numero positivo y finito, o el valor por defecto
local function positive(v, default)
    if type(v) == "number" and v > 0 and v == v and v < math.huge then
        return v
    end
    return default
end

-- Sector 1-8 segun la desviacion en grados; nil dentro de la zona muerta.
function P.sectorFromDelta(dYaw, dPitch, deadzone)
    if math.sqrt(dYaw * dYaw + dPitch * dPitch) < deadzone then
        return nil
    end
    local deg = math.deg(math.atan2(dYaw, dPitch)) -- 0 = arriba, positivo = derecha
    if deg < 0 then
        deg = deg + 360
    end
    return math.floor((deg + 22.5) / 45) % 8 + 1
end

function P.new(opts)
    opts = type(opts) == "table" and opts or {}
    local deadzone = positive(opts.deadzone, DEFAULT_DEADZONE)

    -- hasItem(sec): la cuña tiene opcion en el menu actual (por defecto, todas la tienen)
    local hasItem = type(opts.hasItem) == "function" and opts.hasItem or function() return true end

    local self = {}
    local mouseSec, gazeSec = nil, nil
    local last = nil -- "mouse" o "gaze": la fuente que cambio en ultimo lugar

    -- Centro "armado": la mirada solo resalta el centro (0) al volver a la zona muerta DESPUES de
    -- haber mirado una cuña con opcion. Asi, justo al abrir la rueda o al entrar en un submenu, una
    -- pulsacion corta no cierra ni retrocede por accidente.
    local armed = false
    local gazeRaw = nil -- sector que senala la cabeza ahora (1-8) o nil en la zona muerta
    local skipSec = nil -- cuña que ya se miraba al cambiar de nivel: no arma el centro

    function self.mouse(sec)
        if sec ~= mouseSec then
            mouseSec = sec
            last = "mouse"
        end
    end

    function self.gaze(dYaw, dPitch)
        local raw = P.sectorFromDelta(dYaw, dPitch, deadzone)
        if raw and raw ~= skipSec and hasItem(raw) then
            armed = true
        end
        gazeRaw = raw
        local sec = raw
        if sec == nil and armed then
            sec = 0
        end
        if sec ~= gazeSec then
            gazeSec = sec
            last = "gaze"
        end
    end

    -- Al abrir la rueda se crea un puntero nuevo; reset() es para cada cambio de nivel de menu.
    -- No toca el cursor.
    function self.reset()
        armed = false
        skipSec = gazeRaw
        gazeSec = gazeRaw
    end

    function self.current()
        local first, second
        if last == "gaze" then
            first, second = gazeSec, mouseSec
        else
            first, second = mouseSec, gazeSec
        end
        if first ~= nil then
            return first
        end
        return second
    end

    return self
end

return P
