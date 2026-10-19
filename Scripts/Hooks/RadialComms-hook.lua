-- RadialComms v0.1 - Hook de arranque
-- Copiar a: Saved Games\DCS\Scripts\Hooks\
-- Este archivo solo carga el modulo principal y registra los callbacks de DCS.
-- Si algo falla, el error queda en dcs.log con el prefijo [RadialComms].

local function loadRadialComms()
    local lfs = require("lfs")
    local path = lfs.writedir() .. "Scripts/RadialComms/RadialComms.lua"

    local chunk, err = loadfile(path)
    if not chunk then
        error("no se pudo leer " .. path .. ": " .. tostring(err))
    end

    local mod = chunk()
    mod.start()

    local handler = {}

    function handler.onSimulationFrame()
        mod.onFrame()
    end

    function handler.onMissionLoadEnd()
        mod.onMissionLoadEnd()
    end

    function handler.onSimulationStop()
        mod.onSimulationStop()
    end

    DCS.setUserCallbacks(handler)
    net.log("[RadialComms] Hook cargado (v0.1)")
end

local ok, err = pcall(loadRadialComms)
if not ok then
    net.log("[RadialComms] Error al cargar: " .. tostring(err))
end
