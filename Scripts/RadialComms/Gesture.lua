-- RadialComms - gesto de un solo boton (spec 001-Botones)
--
-- Distingue pulsacion LARGA (abre/cierra la rueda) y CORTA (clic sobre lo resaltado) de un boton.
-- Modulo PURO: no usa DCS ni reloj propio; el tiempo (en segundos) entra siempre como parametro,
-- para poder probarlo fuera del juego.
--
--   local g = Gesture.new({ longSec = 1.0 })
--   g.down(t)                 -- el boton se pulsa
--   g.tick(t)                 -- cada frame; devuelve "toggle" al cumplirse el umbral (sin soltar)
--   g.up(t, ruedaAbierta)     -- el boton se suelta; devuelve "click", "toggle" o nil
--   g.reset()                 -- descarta la pulsacion en curso (cambio de mision/avion)

local G = {}

local DEFAULT_LONG = 1.0 -- umbral de pulsacion larga por defecto (s)
local DEFAULT_MIN = 0.05 -- por debajo de esto se descarta como ruido del boton (s)

-- numero positivo y finito, o el valor por defecto
local function positive(v, default)
    if type(v) == "number" and v > 0 and v == v and v < math.huge then
        return v
    end
    return default
end

function G.new(opts)
    opts = type(opts) == "table" and opts or {}
    local longSec = positive(opts.longSec, DEFAULT_LONG)
    local minSec = positive(opts.minSec, DEFAULT_MIN)

    local self = {}
    local downT = nil   -- instante en que se pulso, o nil si no hay pulsacion en curso
    local fired = false -- la pulsacion larga ya se disparo

    function self.down(t)
        -- una pulsacion nueva sustituye a otra perdida (p. ej. si no llego el 'soltar')
        downT = t
        fired = false
    end

    function self.tick(t)
        if downT and not fired and t - downT >= longSec then
            fired = true
            return "toggle"
        end
        return nil
    end

    function self.up(t, wheelOpen)
        if not downT then
            return nil
        end
        local dur = t - downT
        local wasFired = fired
        downT, fired = nil, false

        if wasFired then
            return nil          -- la larga ya actuo: soltar no hace clic
        end
        if dur >= longSec then
            return "toggle"     -- suelta justo en el umbral, sin tick previo: cuenta como larga
        end
        if dur < minSec then
            return nil          -- ruido del boton
        end
        if wheelOpen then
            return "click"
        end
        return nil
    end

    function self.reset()
        downT, fired = nil, false
    end

    return self
end

return G
