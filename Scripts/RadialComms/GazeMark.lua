-- RadialComms - marca de la mirada: punto + linea (spec 002-Linea-puntero)
--
-- Calcula DONDE se dibuja el punto que marca hacia donde apunta la cabeza y si hay linea
-- desde el centro hasta el. Solo geometria: no decide que cuña se elige (eso es Pointer.lua).
-- Modulo PURO: no usa DCS ni dxgui; se prueba fuera del juego.
--
--   local m = GazeMark.new({ scale = 15, deadzone = 7, radius = 220 })
--   local x, y, line = m.compute(dYaw, dPitch)
--       x, y : posicion del punto en pixeles respecto al centro de la rueda
--              (x positivo = derecha; y positivo = ABAJO, como en pantalla)
--       line : true si hay que dibujar la linea (giro fuera de la zona muerta)

local M = {}

local DEFAULT_SCALE = 15   -- grados de giro con los que el punto llega al borde
local DEFAULT_DEADZONE = 7 -- grados; la misma zona muerta que usa Pointer.lua

-- numero positivo y finito, o el valor por defecto
local function positive(v, default)
    if type(v) == "number" and v > 0 and v == v and v < math.huge then
        return v
    end
    return default
end

-- Posiciones {x, y} de los puntitos que forman la linea: uno cada `step` pixeles desde el centro
-- hacia el punto (x, y), como mucho `n`, y ninguno mas lejos del centro que el punto.
function M.segments(x, y, n, step)
    local out = {}
    local dist = math.sqrt(x * x + y * y)
    if dist == 0 then
        return out
    end
    local ux, uy = x / dist, y / dist
    for i = 1, n do
        local d = step * i
        if d > dist then
            break
        end
        out[i] = { x = ux * d, y = uy * d }
    end
    return out
end

function M.new(opts)
    opts = type(opts) == "table" and opts or {}
    local scale = positive(opts.scale, DEFAULT_SCALE)
    local deadzone = positive(opts.deadzone, DEFAULT_DEADZONE)
    local radius = positive(opts.radius, 1)

    local self = {}

    function self.compute(dYaw, dPitch)
        local turn = math.sqrt(dYaw * dYaw + dPitch * dPitch)
        if turn == 0 then
            return 0, 0, false
        end
        -- proporcional al giro, con tope en el borde de la rueda
        local k = math.min(turn, scale) / scale * radius / turn
        return dYaw * k, -dPitch * k, turn >= deadzone
    end

    return self
end

return M
