import shutil, tempfile
from lupa.lua51 import LuaRuntime

import os
src_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

test = r'''
local WD, HEAD_ON, MARK_ON, MARK_SCALE = ...
local statics = {}
local hotkeys, buttons, window = {}, {}, nil
local calls = {}
local mouse = { lock = 0, unlock = 0 }
local executed = {}

package.preload["lfs"] = function()
  return { writedir = function() return WD end, currentdir = function() return "/nonexistent" end,
           attributes = function() return nil end, dir = function() return function() return nil end end }
end
local function widget(kind)
  local w = { kind = kind, visible = true, text = "", bounds = {}, cbs = {} }
  function w:setText(t) self.text = t end
  function w:setVisible(v) self.visible = v end
  function w:setBounds(x,y,ww,hh) self.bounds = {x,y,ww,hh} end
  function w:insertWidget() end
  function w:addMouseUpCallback(f) self.cbs.up = f end
  function w:addMouseMoveCallback(f) self.cbs.move = f end
  function w:addMouseLeaveCallback(f) self.cbs.leave = f end
  function w:setOpacity(o) self.opacity = o end
  function w:setTitleHeight(h) self.titleH = h end
  function w:getSkin() return "default-skin" end
  function w:setSkin(s) self.skin = s end
  function w:setHasCursor(v) self.cursor = v end
  function w:addHotKeyCallback(k, f) hotkeys[k] = f end
  return w
end
package.preload["Window"] = function() return { new = function() window = widget("window"); return window end } end
package.preload["Panel"]  = function() return { new = function() return widget("panel") end } end
package.preload["Static"] = function() return { new = function(t) local b = widget("static"); b.text = t or ""; table.insert(statics, b); return b end } end
package.preload["Button"] = function() return { new = function(t) local b = widget("button"); b.text = t; table.insert(buttons, b); return b end } end
package.preload["Skin"]   = function() return { windowSkinChatMin = function() return "hidden-skin" end, getSkin = function(n) return { skinData = { params = {}, states = { released = { [1] = {} }, disabled = { [1] = {} } } } } end } end
package.preload["dxgui"]  = function() return { GetScreenSize = function() return 1920, 1080 end } end


-- ===== API Input simulada (como la del panel de controles) =====
local layers, stack, pending = {}, {}, {}
local layerUp = {}
Input = {
  createLayer = function(n) layers[n] = {} end,
  deleteLayer = function(n) layers[n] = nil; for i=#stack,1,-1 do if stack[i]==n then table.remove(stack,i) end end end,
  addKeyCombo = function(l, ev, dev, ref, down, pressed, up)
    layers[l][ev] = down
    layerUp[l] = layerUp[l] or {}; layerUp[l][ev] = up
  end,
  setTopLayer = function(n) table.insert(stack, n) end,
  getLayerStack = function() return stack end,
  getInputActions = function() local r = pending; pending = {}; return r end,
  getDevices = function() return { "Mi Stick {123}", "Keyboard" } end,
  getDeviceId = function(n) return n == "Keyboard" and 1 or 7 end,
  getJoystickDeviceTypeName = function() return "joystick" end,
}
package.preload["Input.Utils"] = function() return {
  getDeviceTypeName = function(d) return d == "Keyboard" and "keyboard" or "joystick" end,
  getDeviceEventsToSkip = function() return {} end,
  getDeviceKeys = function(d) return { {event=100,name="JOY_BTN1"}, {event=101,name="JOY_BTN2"} } end,
  getInputEvent = function(n) return ({JOY_BTN1=100, JOY_BTN2=101})[n] end,
} end
local function press(ev) table.insert(pending, { action = ev + 10000, deviceId = 7 }) end
local handler
local simT = 0   -- reloj simulado (segundos)
DCS = { getPlayerUnitType = function() return "F-16C_50" end,
        setUserCallbacks = function(h) handler = h end, getRealTime = function() return simT end }
net = { log = function() end }

-- ===== Panel de radio simulado (misma semantica que Scripts/UI/RadioCommandDialogPanel) =====
local bases = { items = {} }
for i = 1, 10 do
  bases.items[i] = { name = (i == 3 and "[N/A] " or "") .. "Base" .. i .. " (4." .. i .. " Mhz)", submenu = { items = {
    [3] = { name = "Solicito puesta en marcha de motores", command = "startup" .. i } } } }
end
local tree = { items = {
  [5] = { name = "ATC", submenu = bases },
  [8] = { name = "Personal de tierra", submenu = { items = {
    [1] = { name = "Rearmar y repostar", command = "rearm" },
    [4] = { name = "Calzos", submenu = { items = { [1] = { name = "Poner", command = "chocks" } } } } } } },
} }
local dialogDef = { items = {
  [1] = { name = "Solicito rodaje",     command = "dlg_taxi" },
  [3] = { name = "Aborto el despegue", command = "dlg_abort" },
} }

local P = { shown = false }
local function makeElement(def, isDialog)
  local E = { stack = {}, isDialog = isDialog }
  local function current() return E.stack[#E.stack] or def end
  local function texts()
    local t = {}
    for k, it in pairs(current().items) do t[k] = "F" .. k .. ". " .. it.name .. (it.submenu and "..." or "") end
    if isDialog then t[11] = "F11. Menú principal" elseif #E.stack > 0 then t[11] = "F11. Previous Menu" end
    t[12] = "F12. Salir"
    return t
  end
  E.commandMenu = { getItem = function(self, k)
    local tx = texts()[k] or ""
    return { getText = function() return tx end }
  end }
  function E:setMainMenu() E.stack = {} end
  function E.select(n)
    if n == 12 then P.setShowMenu(false); return end
    if n == 11 then
      if isDialog then P.curDialogIt = { element_ = P.common } else table.remove(E.stack) end
      return
    end
    local it = current().items[n]
    if not it then return end
    if it.submenu then table.insert(E.stack, it.submenu)
    elseif it.command then table.insert(executed, it.command .. "@" .. tostring(P.comm)); E.stack = {} end
  end
  return E
end
P.common = makeElement(tree, false)
P.dialog = makeElement(dialogDef, true)
function P.useDialog() P.curDialogIt = { element_ = P.dialog }; P.common.stack = {} end
P.useDialog()
function P.setCommunicatorId(id) P.comm = id end
function P.getCommunicatorId() return P.comm end
function P.switchToMainMenu() P.curDialogIt = { element_ = P.common } end
function P.isVisible() return P.shown end
function P.setShowMenu(on)
  if on and not P.shown then mouse.lock = mouse.lock + 1; P.curDialogIt.element_:setMainMenu() end
  if (not on) and P.shown then mouse.unlock = mouse.unlock + 1 end
  P.shown = on
end
local function realSelect(n) P.curDialogIt.element_.select(n) end
P.selectMenuItem = realSelect

-- ===== Estados de Lua de DCS simulados =====
local function mkenv()
  return { type = type, pcall = pcall, ipairs = ipairs, pairs = pairs, tostring = tostring,
           string = string, table = table, error = error, tonumber = tonumber,
           GetDevice = function(i) if i == 5 then return { set_communicator = function(self, id) P.tx = id end, make_setup_for_communicator = function() return true end } end if i == 38 or i == 39 then return { get_frequency = function() return 251000000 end, is_frequency_in_range = function(self, f) return true end } end end }
end
local envs = { gui = mkenv(), mission = mkenv(), export = mkenv(), config = mkenv(), server = mkenv() }
local function installPanel(state)
  for _, e in pairs(envs) do e.RadioCommandDialogsPanel = nil end
  _G.RadioCommandDialogsPanel = nil
  if state == "local" then _G.RadioCommandDialogsPanel = P
  elseif state then envs[state].RadioCommandDialogsPanel = P end
end
net.dostring_in = function(state, code)
  table.insert(calls, state)
  local env = envs[state]
  if not env then return "estado desconocido", false end
  local f, err = loadstring(code)
  if not f then return "[syntax] " .. tostring(err), false end
  setfenv(f, env)
  local ok, res = pcall(f)
  if not ok then return tostring(res), false end
  return res == nil and "" or tostring(res), true
end

local function readLog()
  local f = assert(io.open(WD .. "Logs\\RadialComms.log", "r")); local s = f:read("*a"); f:close(); return s
end
local function open() hotkeys["Ctrl+Shift+q"]() end
local function fresh() if window.cursor then open() end; open() end   -- rueda cerrada y reabierta en la raiz

local function balanced(msg)
  assert(mouse.lock == mouse.unlock, (msg or "") .. " raton bloqueado: lock=" .. mouse.lock .. " unlock=" .. mouse.unlock)
  assert(P.shown == false, (msg or "") .. " el menu nativo se quedo abierto")
end
local function fresh() if window.cursor then open() end; open() end
local hit = function() return statics[#statics] end
local function markKind(st)   -- "dot", "seg" o nil
  local ok, f = pcall(function() return st.skin.skinData.states.released[1].picture.file end)
  if not ok or type(f) ~= "string" then return nil end
  if f:find("gaze_dot", 1, true) then return "dot" end
  if f:find("gaze_seg", 1, true) then return "seg" end
  return nil
end
local function nmark() local n = 0; for _, st in ipairs(statics) do if markKind(st) then n = n + 1 end end; return n end
local function lab(i) return statics[18 + nmark() + i].text end
local function sel(i)
  local a = math.rad(-90 + (i - 1) * 45)
  hit().cbs.up(hit(), 960 + 150 * math.cos(a), 551 + 150 * math.sin(a), 1)
end
local function center() hit().cbs.up(hit(), 965, 556, 1) end
local function hover(i)   -- cursor sobre la cuña i (0 = centro)
  if i == 0 then hit().cbs.move(hit(), 965, 556); return end
  local a = math.rad(-90 + (i - 1) * 45)
  hit().cbs.move(hit(), 960 + 150 * math.cos(a), 551 + 150 * math.sin(a))
end
local function unhover() hit().cbs.leave(hit()) end
local function findtxt(prefix) for _, st in ipairs(statics) do if st.text:sub(1, #prefix) == prefix then return st end end end

installPanel("gui")
assert(loadfile(WD .. "Scripts/Hooks/RadialComms-hook.lua"))()
handler.onSimulationFrame()
handler.onMissionLoadEnd()
assert(#buttons == 0, "no debe haber botones clasicos")
open()
assert(window.skin == "hidden-skin" or window.skin == "hidden-skin", "ventana sin marco")
assert(lab(1):find("COM1") and lab(2):find("COM2") and lab(3):find("GROUND CREW") and lab(4):find("Herramientas"), "raiz")
assert(lab(5) == "", "sector vacio")

-- COM1: no debe mostrar "Personal de tierra"
sel(1)
assert(lab(1):find("ATC", 1, true), "COM1: " .. lab(1))
for i = 1, 8 do assert(not lab(i):find("Personal de tierra", 1, true), "ground crew colado en COM1: " .. lab(i)) end
assert(P.comm == 38 and P.tx == 38)
assert(findtxt("< COM1"), "centro con la radio")
balanced("c1")
sel(1)   -- ATC
assert(lab(1):find("Base1 4.1",1,true) and lab(3):find("Base4 4.4",1,true), "etiquetas: " .. lab(1) .. "|" .. lab(3))
assert(lab(7):find("Base8 4.8",1,true) and lab(8):find("Mas", 1, true), "paginacion: " .. lab(7))
sel(8)
assert(lab(1):find("Base9 4.9",1,true) and lab(2):find("Base10 4.10",1,true) and lab(3) == "", "pagina 2")
sel(2)
assert(window.text:find("OJO: radio en 251.000, estacion en 4.100", 1, true), "aviso: " .. window.text)
assert(lab(1):find("puesta en marc", 1, true))
sel(1)
assert(executed[#executed] == "startup10@38", "ejecuto: " .. tostring(executed[#executed]))
assert(window.cursor == false)
balanced("c1b")

fresh(); sel(2)
assert(P.comm == 39 and P.tx == 39, "COM2")
for i = 1, 8 do assert(not lab(i):find("Personal de tierra", 1, true), "ground crew en COM2") end
balanced("c2")

-- GROUND CREW sigue viendolo todo
fresh(); P.comm = nil; sel(3)
assert(lab(1):find("Rearmar", 1, true) and lab(2):find("Calzos", 1, true), "ground: " .. lab(1))
assert(P.comm == nil)
sel(2); sel(1)
assert(executed[#executed] == "chocks@nil", "calzos")
balanced("g")

-- centro = atras
fresh(); sel(1); sel(1); center()
assert(lab(1):find("ATC", 1, true), "atras: " .. lab(1))
center(); assert(lab(1):find("COM1"), "atras a la raiz")
fresh()
balanced("back")

-- radio inexistente
fresh()
local oldGD = envs.gui.GetDevice
envs.gui.GetDevice = function() return nil end
sel(1)
assert(window.text:find("no encuentro la radio", 1, true), "sin radio: " .. window.text)
envs.gui.GetDevice = oldGD
balanced("noradio")

-- Herramientas no tiene "Estilo"
fresh(); sel(4)
for i = 1, 8 do assert(not lab(i):find("Estilo"), "Estilo no debe existir") end
-- colores y centro
fresh()
sel(2)
assert(findtxt("< COM2"))
assert(statics[1].skin.skinData.states.released[1].picture.file:find("wedge_green_1.png", 1, true), "COM2 verde")
local sub; for _, st in ipairs(statics) do if st.text == "251.000" then sub = st end end
assert(sub, "frecuencia en el centro")
center()
assert(findtxt("Cerrar"))
assert(statics[1].skin.skinData.states.released[1].picture.file:find("wedge_blue_1.png", 1, true))

-- === Boton de joystick ===
fresh(); sel(4)
local function labidx(prefix) for i=1,8 do if lab(i):find(prefix,1,true) then return i end end end
local li = labidx("Asignar boton")
assert(li, "falta Asignar boton joystick")
sel(li)
assert(window.text:find("Pulsa ahora un boton", 1, true), "aviso aprender: " .. window.text)
assert(layers["RadialComms"] and layers["RadialComms"][100] == 10100 and layers["RadialComms"][101] == 10101)
press(101); handler.onSimulationFrame()
assert(window.text:find("Boton asignado: JOY_BTN2", 1, true), "asignado: " .. window.text)
local lay = layers["RadialComms"]; assert(lay[101] == 10101 and lay[100] == nil, "capa con un solo boton")
local fh = io.open(WD .. "Config/RadialCommsJoystick.lua"); local saved = fh:read("*a"); fh:close()
assert(saved:find("JOY_BTN2") and saved:find("Mi Stick"), saved)
-- === Gesto de un solo boton (spec 001, T5) ===
local function up(ev) table.insert(pending, { action = ev + 20000, deviceId = 7 }) end
local function frame(dt) simT = simT + (dt or 0); handler.onSimulationFrame() end
local function shortClick() press(101); frame(0); up(101); frame(0.3) end   -- pulsacion corta (0,3 s)
if window.cursor then open() end
assert(window.cursor == false)
-- RF-1: larga con la rueda cerrada abre al cumplirse el umbral, sin soltar
frame(1); press(101); frame(0)
assert(window.cursor == false, "solo pulsar no abre")
frame(0.5); assert(window.cursor == false, "a medio umbral no abre")
frame(0.6); assert(window.cursor == true, "la larga abre la rueda sin soltar")
frame(2);   assert(window.cursor == true, "seguir pulsando no la cierra (una sola vez)")
-- RF-6: soltar tras la larga no hace clic (aunque el cursor este sobre COM1)
hover(1); up(101); frame(0.1)
assert(window.cursor == true and lab(1):find("COM1", 1, true) and not findtxt("< COM1"), "soltar tras la larga no hace clic")
-- RF-3: corta con la rueda abierta = clic en la cuña resaltada (4 = Herramientas)
hover(4); shortClick()
assert(labidx("Asignar boton"), "la corta entro en Herramientas")
-- RF-3: corta sobre el centro = atras
hover(0); shortClick()
assert(lab(1):find("COM1", 1, true), "la corta sobre el centro vuelve atras")
-- RF-5: corta sobre una cuña sin opcion, o sin nada resaltado = no hace nada
hover(5); shortClick()
assert(window.cursor == true and lab(1):find("COM1", 1, true), "cuña vacia: nada")
unhover(); shortClick()
assert(window.cursor == true and lab(1):find("COM1", 1, true), "nada resaltado: nada")
-- RF-18: una pulsacion de 30 ms se descarta
hover(4); press(101); frame(0); up(101); frame(0.03)
assert(lab(1):find("COM1", 1, true), "30 ms no hace clic")
-- el centro en el menu principal cierra la rueda
hover(0); shortClick()
assert(window.cursor == false, "la corta sobre el centro del menu principal cierra")
-- RF-4: corta con la rueda cerrada = nada
shortClick()
assert(window.cursor == false, "corta con la rueda cerrada no hace nada")
-- RF-2 / RF-17: abierta con el atajo de teclado, la larga la cierra
open(); assert(window.cursor == true)
press(101); frame(0); frame(1); assert(window.cursor == false, "la larga cierra la rueda abierta con el teclado")
up(101); frame(0.1)
-- no queda resaltado de la apertura anterior: la corta justo tras abrir no hace nada
open(); hover(4); open(); open()
assert(window.cursor == true); shortClick()
assert(window.cursor == true and lab(1):find("COM1", 1, true), "al reabrir no queda nada resaltado")
open()
-- otros botones y otros mandos no hacen nada
press(100); frame(0); frame(2); assert(window.cursor == false, "otros botones no hacen nada")
table.insert(pending, { action = 10101, deviceId = 8 }); frame(0); frame(2)
assert(window.cursor == false, "el mismo boton en otro mando no hace nada")
-- cambio de mision: la pulsacion en curso se descarta (no abre despues)
press(101); frame(0); frame(0.5); handler.onMissionLoadEnd(); frame(2)
assert(window.cursor == false, "mision cargada: la pulsacion en curso se descarta")
up(101); frame(0.1)
-- parar la simulacion tambien
press(101); frame(0); frame(0.5); handler.onSimulationStop(); frame(2)
assert(window.cursor == false, "simulacion detenida: la pulsacion en curso se descarta")
up(101); frame(0.1); handler.onMissionLoadEnd()
print("BOTON GESTO OK")

-- === Cursor -> Pointer -> resaltado (spec 001, T6) ===
local function hv(i) return statics[8 + i].visible end        -- resaltado de la cuña i
local function hvc() return statics[18].visible end            -- resaltado del centro
local function onlyHover(n)   -- solo la cuña n (o ninguna) esta resaltada; el centro no
  for i = 1, 8 do assert((hv(i) == true) == (i == n), "resaltado de la cuña " .. i .. " con el cursor en " .. tostring(n)) end
  assert(hvc() == false, "el centro no debe estar resaltado")
end
fresh(); onlyHover(nil)
hover(2); onlyHover(2)
hover(3); onlyHover(3)
hover(5); onlyHover(nil)           -- cuña sin opcion: no se resalta
hover(4); onlyHover(4)
unhover(); onlyHover(nil)          -- el cursor sale de la rueda
hover(0); assert(hvc() == true, "centro resaltado con el cursor en el centro")
for i = 1, 8 do assert(hv(i) == false) end
-- cambio de nivel: el resaltado sigue lo que senala el cursor en el menu nuevo
hover(4); shortClick()
assert(labidx("Asignar boton"), "entro en Herramientas")
onlyHover(nil)                     -- el cursor sigue en 4, que en Herramientas esta vacia
hover(1); onlyHover(1)
hover(0); assert(hvc() == true); shortClick()
assert(lab(1):find("COM1", 1, true), "volvio al menu principal")
assert(hvc() == true, "tras volver atras el cursor sigue en el centro y el centro sigue resaltado")
-- al reabrir la rueda no queda nada resaltado
open(); open()
onlyHover(nil)
hover(2); open(); open()
onlyHover(nil)
-- el clic de raton sigue ejecutando la misma cuña (RF-16)
fresh(); sel(4); assert(labidx("Asignar boton"), "clic de raton en Herramientas")
center(); assert(lab(1):find("COM1", 1, true), "clic de raton en el centro vuelve atras")
fresh()
print("CURSOR PUNTERO OK")

-- === Mirada -> Pointer (spec 001, T7) ===
local cam = { yaw = 90, pitch = 0, hdg = 90, apitch = 0 }   -- camara y avion simulados (grados)
Export = {
  LoGetCameraPosition = function()
    local y, p = math.rad(cam.yaw), math.rad(cam.pitch)   -- x = norte, z = este, y = arriba
    return { x = { x = math.cos(p) * math.cos(y), y = math.sin(p), z = math.cos(p) * math.sin(y) }, p = { x = 0, y = 0, z = 0 } }
  end,
  LoGetSelfData = function() return { Heading = math.rad(cam.hdg), Pitch = math.rad(cam.apitch) } end,
  LoIsOwnshipExportAllowed = function() return true end,
}
local function look(yaw, pitch) cam.yaw, cam.pitch = 90 + yaw, pitch end        -- giro de la cabeza respecto al avion
local function frames(n) for _ = 1, n do frame(0.1) end end
local function openAt0() look(0, 0); cam.hdg, cam.apitch = 90, 0; fresh(); frames(3) end   -- abre y toma la referencia

local mod = assert(io.open(WD .. "Scripts/RadialComms/RadialComms.lua", "r")); local modsrc = mod:read("*a"); mod:close()
assert(not modsrc:find("headDwell", 1, true), "ya no existe la eleccion por tiempo de la mirada")

if HEAD_ON then
  -- sin mover la cabeza no se resalta nada (la referencia es donde se miraba al abrir)
  openAt0(); onlyHover(nil)
  -- RF-8: girar a la derecha 15 grados resalta la cuña 3
  look(15, 0); frames(15); onlyHover(3)
  -- RF-9: mantener la mirada no ejecuta nada (ni tras mucho tiempo)
  frames(60)
  assert(window.cursor == true and lab(1):find("COM1", 1, true) and not findtxt("< "), "mantener la mirada no ejecuta ninguna cuña")
  -- arriba 15 grados: cuña 1
  look(0, 15); frames(15); onlyHover(1)
  -- RF-21: volver a la zona muerta tras mirar una cuña con opcion resalta el centro
  look(0, 0); frames(15); assert(hvc() == true, "centro resaltado al volver tras mirar una cuña")
  for i = 1, 8 do assert(hv(i) == false) end
  -- RF-22: al abrir, la zona muerta no resalta el centro
  openAt0(); frames(10); onlyHover(nil)
  -- dentro de la zona muerta (5 grados) no se resalta nada
  look(5, 0); frames(15); onlyHover(nil)
  -- RNF-2: maniobrar con el avion no mueve la mirada (rumbo +30 y cabeceo +20 con la cabeza quieta)
  look(0, 0); cam.hdg, cam.apitch = 120, 20; cam.yaw, cam.pitch = 120, 20; frames(15)
  onlyHover(nil)
  -- RF-7: manda el que cambio en ultimo lugar (cursor/mirada)
  openAt0(); look(15, 0); frames(15); onlyHover(3)
  hover(2); onlyHover(2)
  look(0, 15); frames(15); onlyHover(1)
  -- RF-3 con la mirada: una pulsacion corta clica la cuña resaltada por la cabeza (4 = Herramientas)
  openAt0(); unhover(); look(15, -15); frames(15); onlyHover(4)
  shortClick()
  assert(labidx("Asignar boton"), "la corta clica la cuña mirada")
  -- cambio de nivel: seguir mirando la cuña elegida no arma el centro
  frames(15); assert(hvc() == false, "al entrar en el submenu, mirar la misma cuña no resalta el centro")
  -- mirar otra cuña (1 = Asignar...) y volver al centro lo arma; la corta vuelve atras
  look(0, 15); frames(15); onlyHover(1)
  look(0, 0); frames(15); assert(hvc() == true, "centro armado en el submenu")
  shortClick()
  assert(lab(1):find("COM1", 1, true), "volver atras mirando al centro")
else
  -- RF-15: con la mirada desactivada solo cuenta el cursor
  openAt0(); look(15, 0); frames(15); onlyHover(nil)
  hover(2); onlyHover(2)
  unhover(); onlyHover(nil)
end
-- === Integracion completa (spec 001, T9) ===
local function longPress() press(101); frame(0); frame(1.0) end          -- mantiene el boton 1 s (la larga actua al llegar)
local function release() up(101); frame(0.1) end
if window.cursor then open() end
look(0, 0); cam.hdg, cam.apitch = 90, 0; unhover()
assert(window.cursor == false)
if HEAD_ON then
  -- Escenario A: solo cabeza y un boton. Abrir (larga) -> entrar en un submenu mirando y pulsando (corta)
  -- -> volver atras mirando al centro y pulsando (corta) -> cerrar (larga).
  longPress(); assert(window.cursor == true, "A: la larga abre la rueda")
  release();   assert(window.cursor == true and lab(1):find("COM1", 1, true), "A: soltar tras la larga no hace clic")
  frames(3)                                            -- la referencia de la mirada se toma al abrir
  look(15, -15); frames(15); onlyHover(4)              -- mira Herramientas (abajo a la derecha)
  shortClick(); assert(labidx("Asignar boton"), "A: la corta entra en Herramientas")
  look(0, 15); frames(15); onlyHover(1)                -- mira otra cuña del submenu...
  look(0, 0);  frames(15); assert(hvc() == true, "A: ...y al volver al centro este se resalta")
  shortClick(); assert(lab(1):find("COM1", 1, true), "A: la corta vuelve atras")
  look(0, 0); frames(5); assert(hvc() == false, "A: en la raiz, recien vuelto, el centro no queda resaltado (se desarma al cambiar de nivel)")
  longPress(); assert(window.cursor == false, "A: la larga cierra la rueda")
  release();   assert(window.cursor == false, "A: soltar tras cerrar no la reabre")

  -- Escenario B: cursor y mirada discrepan; manda el ultimo que cambio y la corta clica ese
  look(0, 0); longPress(); release(); frames(3)
  assert(window.cursor == true)
  look(15, 0); frames(15); onlyHover(3)                -- la mirada senala GROUND CREW
  hover(4);    onlyHover(4)                            -- el cursor cambia despues: manda el cursor
  shortClick(); assert(labidx("Asignar boton"), "B: la corta clica lo que senala el cursor (Herramientas), no la mirada")
  look(15, 15); frames(15); onlyHover(2)               -- ahora cambia la mirada (cuña 2 del submenu): manda la mirada
  hover(1);    onlyHover(1)                            -- y luego el cursor
  hover(0); shortClick(); assert(lab(1):find("COM1", 1, true), "B: vuelve atras con el cursor")
  longPress(); assert(window.cursor == false, "B: la larga cierra la rueda"); release()
else
  -- Escenario A con solo cursor (mirada desactivada): mismo recorrido
  longPress(); assert(window.cursor == true, "A: la larga abre la rueda")
  release();   assert(window.cursor == true and lab(1):find("COM1", 1, true), "A: soltar tras la larga no hace clic")
  hover(4); shortClick(); assert(labidx("Asignar boton"), "A: la corta entra en Herramientas")
  hover(0); shortClick(); assert(lab(1):find("COM1", 1, true), "A: la corta vuelve atras")
  longPress(); assert(window.cursor == false, "A: la larga cierra la rueda")
  release();   assert(window.cursor == false)
end
print("INTEGRACION OK")

-- === Marca de la mirada: punto + linea (spec 002, T4-T8) ===
local R_OUT = 204                                   -- borde de la rueda (px)
local dotW, segW = nil, {}
for idx, st in ipairs(statics) do
  local k = markKind(st)
  if k == "dot" then assert(not dotW, "un solo punto"); dotW = st; dotW.idx = idx
  elseif k == "seg" then segW[#segW + 1] = st; st.idx = idx end
end
assert(dotW, "existe el widget del punto")
assert(#segW >= 40, "existen los puntitos de la linea: " .. #segW)
-- RF-9: por encima de cuñas, resaltados y centro (1-18) y por debajo de los textos
for _, st in ipairs(segW) do assert(st.idx > 18 and st.idx <= 18 + nmark(), "puntito entre el centro y los textos") end
assert(dotW.idx > 18 and dotW.idx <= 18 + nmark(), "punto entre el centro y los textos")
for _, st in ipairs(segW) do assert(dotW.idx > st.idx, "el punto va encima de la linea") end
assert(lab(1) ~= nil, "los textos siguen localizables")
local function pos(st) return st.bounds[1] + st.bounds[3] / 2 - 220, st.bounds[2] + st.bounds[4] / 2 - 242 end
local function segsOn() local t = {}; for _, st in ipairs(segW) do if st.visible then t[#t + 1] = st end end; return t end
local function noMark(msg) assert(dotW.visible == false and #segsOn() == 0, msg) end
local function dotAt(x, y, tol, msg)
  assert(dotW.visible == true, msg .. ": punto visible")
  local px, py = pos(dotW)
  assert(math.abs(px - x) <= tol and math.abs(py - y) <= tol, msg .. string.format(": punto en (%.1f, %.1f), esperado (%.1f, %.1f)", px, py, x, y))
end
local full = math.min(15, MARK_SCALE) / MARK_SCALE * R_OUT       -- distancia del punto mirando 15 grados
-- con la rueda cerrada, todo oculto (RF-12)
if window.cursor then open() end
noMark("rueda cerrada")

if HEAD_ON and MARK_ON then
  -- RF-7: al abrir, punto en el centro y sin linea
  openAt0(); dotAt(0, 0, 1, "al abrir"); assert(#segsOn() == 0, "al abrir no hay linea")
  -- RF-1..RF-5: mirar 15 grados a la derecha
  look(15, 0); frames(15); dotAt(full, 0, 1, "15 grados a la derecha")
  local on = segsOn(); assert(#on > 0, "fuera de la zona muerta hay linea")
  for _, st in ipairs(on) do
    local x, y = pos(st)
    assert(x > 0 and x <= full + 1 and math.abs(y) <= 1, "puntito entre el centro y el punto")
  end
  -- arriba y diagonal: direccion correcta (arriba = y negativa)
  look(0, 15); frames(15); dotAt(0, -full, 1, "15 grados arriba")
  look(-15, -15); frames(15); local dx, dy = pos(dotW); assert(dx < -10 and dy > 10, "diagonal abajo-izquierda")
  -- RF-6: dentro de la zona muerta, punto si y linea no
  look(5, 0); frames(15); dotAt(5 / MARK_SCALE * R_OUT, 0, 1, "5 grados"); assert(#segsOn() == 0, "en la zona muerta no hay linea")
  look(0, 0); frames(15); dotAt(0, 0, 1, "de vuelta al centro"); assert(#segsOn() == 0)
  -- RF-14: el cursor no mueve ni oculta la marca
  hover(2); dotAt(0, 0, 1, "el cursor no mueve el punto"); assert(#segsOn() == 0, "el cursor no dibuja linea")
  -- RF-10: con el cursor mandando la cuña resaltada, la marca sigue a la cabeza
  look(0, 15); frames(15); onlyHover(1)
  hover(3); onlyHover(3); dotAt(0, -full, 1, "manda el cursor, la marca sigue a la cabeza"); assert(#segsOn() > 0)
  unhover()
  -- RF-13: al cambiar de nivel la marca sigue segun la cabeza
  openAt0(); look(15, -15); frames(15); onlyHover(4); shortClick()
  assert(labidx("Asignar boton"), "entro en Herramientas")
  frames(2); dx, dy = pos(dotW); assert(dotW.visible and dx > 10 and dy > 10 and #segsOn() > 0, "en el submenu la marca sigue donde mira la cabeza")
  look(0, 15); frames(15); look(0, 0); frames(15); shortClick()
  assert(lab(1):find("COM1", 1, true), "volvio atras"); frames(2); dotAt(0, 0, 1, "tras volver atras")
  -- RF-11 (T6): sin limite de muestreo y suavizado segun el tiempo, no segun los frames
  openAt0(); look(10, 0); frame(0.01)
  dx = pos(dotW); assert(dx > 0, "el punto ya se mueve en el primer frame (sin esperar 0,05 s)")
  openAt0(); look(10, 0); for _ = 1, 30 do frame(0.01) end; local x1 = pos(dotW)
  openAt0(); look(10, 0); for _ = 1, 3 do frame(0.1) end;   local x2 = pos(dotW)
  local target = 10 / MARK_SCALE * R_OUT
  assert(math.abs(x1 - x2) <= 1.5, string.format("mismo avance en 0,3 s con frames de 0,01 y de 0,1 s: %.1f / %.1f", x1, x2))
  assert(x1 > target * 0.5 and x1 < target - 2, "a los 0,3 s el suavizado aun no ha terminado: " .. x1)
  -- RF-12 (T7): cerrar oculta todo (teclado, pulsacion larga y centro)
  openAt0(); look(15, 0); frames(15); assert(dotW.visible and #segsOn() > 0)
  open(); noMark("cerrar con el teclado")
  openAt0(); look(15, 0); frames(15); press(101); frame(0); frame(1.0); up(101); frame(0.1)
  assert(window.cursor == false); noMark("cerrar con la pulsacion larga")
  openAt0(); look(15, 0); frames(15); center(); assert(window.cursor == false); noMark("cerrar con el centro")
  -- al reabrir no queda la linea de antes
  look(0, 0); fresh(); assert(#segsOn() == 0, "al reabrir no queda linea"); frames(3); dotAt(0, 0, 1, "al reabrir")
else
  -- RF-19 / mirada desactivada: nunca hay marca; lo demas igual
  openAt0(); noMark("al abrir, sin marca")
  look(15, 0); frames(15); noMark("mirando, sin marca")
  hover(2); onlyHover(2); noMark("con el cursor, sin marca")
  unhover()
  if HEAD_ON then look(0, 0); frames(15); look(15, 0); frames(15); onlyHover(3) end   -- la mirada sigue resaltando
  open(); noMark("cerrada, sin marca")
end
-- RF-15: el clic de raton y la pulsacion corta ejecutan lo mismo que antes
look(0, 0); fresh(); sel(4); assert(labidx("Asignar boton"), "clic de raton igual que antes")
hover(0); shortClick(); assert(lab(1):find("COM1", 1, true), "pulsacion corta igual que antes")
print("MARCA MIRADA OK")

-- === Centro = atras en los submenus (spec 001, T11 / RF-23) ===
if HEAD_ON then
  -- con la cabeza: entrar en Herramientas y volver mirando directamente al centro
  openAt0(); unhover(); look(15, -15); frames(15); onlyHover(4); shortClick()
  assert(labidx("Asignar boton"), "entro en Herramientas")
  look(0, 0); frames(15); assert(hvc() == true, "submenu: mirar al centro lo resalta sin mirar antes otra cuña")
  shortClick(); assert(lab(1):find("COM1", 1, true), "la corta sobre el centro vuelve atras")
  -- en el principal, recien vuelto, el centro no queda resaltado y otra corta no cierra la rueda
  frames(5); assert(hvc() == false, "principal: el centro no queda resaltado")
  shortClick(); assert(window.cursor == true and lab(1):find("COM1", 1, true), "una segunda corta seguida no cierra la rueda")
  -- entrar con el raton mientras se mira al centro: el centro queda resaltado y la corta vuelve atras
  openAt0(); frames(5); sel(4); assert(labidx("Asignar boton")); frames(2)
  assert(hvc() == true, "submenu abierto con el raton: el centro queda resaltado por la mirada")
  shortClick(); assert(lab(1):find("COM1", 1, true), "y la corta vuelve atras")
  -- dos niveles (COM1 > ATC): mirar al centro y pulsar vuelve de uno en uno
  openAt0(); look(0, 15); frames(15); onlyHover(1); shortClick(); assert(findtxt("< COM1"), "entro en COM1")
  frames(15); shortClick(); assert(lab(1):find("Base", 1, true), "entro en ATC (sigue mirando la cuña 1)")
  look(0, 0); frames(15); assert(hvc() == true); shortClick(); assert(lab(1):find("ATC", 1, true), "vuelve a COM1")
  frames(5); assert(hvc() == true, "sigue en un submenu: el centro sigue resaltado"); shortClick()
  assert(lab(1):find("COM1", 1, true) and not findtxt("< COM1"), "vuelve al principal")
  frames(5); assert(hvc() == false and window.cursor == true)
  balanced("centro-atras")
end
fresh()
print("CENTRO ATRAS OK")
fresh(); Export = nil
print("MIRADA PUNTERO OK")
-- DCS rehace la pila: se repone
stack = {}; layers = {}
simT = simT + 10
handler.onSimulationFrame()
assert(layers["RadialComms"] and layers["RadialComms"][101], "capa repuesta")
-- borrar
fresh(); sel(4); sel(labidx("Quitar boton"))
assert(layers["RadialComms"] == nil, "capa borrada")
print("JOY OK")

-- ===== JoyButton (spec 001, T4): avisa de pulsar Y de soltar =====
do
  local J = dofile(WD .. "Scripts/RadialComms/JoyButton.lua")
  local savePath = WD .. "Config/RadialCommsJoystick_t4.lua"
  local fh = io.open(savePath, "w"); fh:write('return { device = "Mi Stick {123}", button = "JOY_BTN2" }\n'); fh:close()
  local logs = {}
  local j = J.new({ log = function(m) logs[#logs + 1] = m end, savePath = savePath })
  j.load(); j.reassert()
  -- la capa registra pulsar (down) Y soltar (up), con codigos distintos
  assert(layers["RadialComms"] and layers["RadialComms"][101] == 10101, "accion de pulsar")
  assert(layerUp["RadialComms"][101] == 20101, "accion de soltar registrada")
  assert(layerUp["RadialComms"][101] ~= layers["RadialComms"][101], "pulsar y soltar son acciones distintas")

  local downs, ups = {}, {}
  local function onPress(t) downs[#downs + 1] = t end
  local function onUp(t) ups[#ups + 1] = t end
  local function poll(t) j.poll(t, onPress, function() end, function() end, onUp) end
  local function act(code, dev) table.insert(pending, { action = code, deviceId = dev or 7 }) end

  act(10101); poll(5.0)
  assert(#downs == 1 and downs[1] == 5.0 and #ups == 0, "pulsar avisa con la hora")
  act(20101); poll(5.4)
  assert(#downs == 1 and #ups == 1 and ups[1] == 5.4, "soltar avisa con la hora")
  -- pulsar y soltar en el mismo frame: se respeta el orden
  act(10101); act(20101); poll(6.0)
  assert(#downs == 2 and #ups == 2, "pulsar y soltar en el mismo frame")
  -- RNF-1: el mismo boton en OTRO mando no hace nada (ni pulsar ni soltar)
  act(10101, 8); act(20101, 8); poll(7.0)
  assert(#downs == 2 and #ups == 2, "otro mando con el mismo numero de boton: nada")
  -- otro boton del mismo mando: nada
  act(10100); act(20100); poll(7.5)
  assert(#downs == 2 and #ups == 2, "otro boton: nada")
  -- sin onUp (uso antiguo) no falla
  act(20101); j.poll(8.0, onPress, function() end, function() end)
  -- primera accion de soltar: queda en el log (riesgo R1: comprobar que DCS la entrega)
  local sawUp = false; for _, m in ipairs(logs) do if m:find("soltar", 1, true) then sawUp = true end end
  assert(sawUp, "se escribe en el log al recibir el primer 'soltar'")

  -- el modo aprender sigue funcionando y la capa nueva tambien lleva 'soltar'
  local learned
  j.startLearn(9.0, 12)
  assert(layers["RadialComms"][100] == 10100 and layers["RadialComms"][101] == 10101, "aprender: vigila los botones")
  act(10100); j.poll(9.5, onPress, function(d, b) learned = b end, function() end, onUp)
  assert(learned == "JOY_BTN1", "aprender: asigna el boton pulsado")
  assert(layerUp["RadialComms"][100] == 20100, "tras aprender, la capa nueva registra 'soltar'")
  j.clear()
  os.remove(savePath)
end
print("JOY SOLTAR OK")

-- ===== Gesture (spec 001, T1): pulsacion larga / corta / rebote =====
local Gesture = dofile(WD .. "Scripts/RadialComms/Gesture.lua")
do
  local g = Gesture.new({ longSec = 1.0 })
  -- RF-1: larga con la rueda cerrada -> "toggle" al cumplirse el umbral, sin esperar a soltar
  g.down(10.0)
  assert(g.tick(10.5) == nil, "antes del umbral no pasa nada")
  assert(g.tick(11.0) == "toggle", "al llegar al umbral abre/cierra")
  assert(g.tick(11.5) == nil, "la larga dispara una sola vez aunque se siga pulsando")
  assert(g.tick(30.0) == nil, "mantenida mucho tiempo: sigue siendo una sola vez")
  -- RF-6: soltar tras la larga no da clic (con rueda abierta o cerrada)
  assert(g.up(31.0, true) == nil, "soltar tras la larga: sin clic")
  g.down(40.0); assert(g.tick(41.0) == "toggle"); assert(g.up(41.2, false) == nil)

  -- RF-3: corta con la rueda abierta -> clic
  g.down(50.0); assert(g.up(50.3, true) == "click", "corta con rueda abierta = clic")
  -- RF-4: corta con la rueda cerrada -> nada
  g.down(60.0); assert(g.up(60.3, false) == nil, "corta con rueda cerrada = nada")

  -- RF-18: rebote (menos de 50 ms se descarta, 60 ms vale)
  g.down(70.0); assert(g.up(70.03, true) == nil, "30 ms se descarta")
  g.down(80.0); assert(g.up(80.06, true) == "click", "60 ms es una pulsacion valida")

  -- suelta justo en el umbral (sin tick previo) cuenta como larga
  g.down(90.0); assert(g.up(91.0, true) == "toggle", "suelta en el umbral = larga")
  assert(g.tick(92.0) == nil, "tras soltar no queda nada pendiente")

  -- soltar sin haber pulsado
  assert(g.up(100.0, true) == nil, "up sin down no hace nada")

  -- una pulsacion nueva sustituye a otra perdida (se perdio el 'soltar')
  g.down(110.0); g.down(115.0)
  assert(g.tick(115.5) == nil, "la pulsacion nueva reinicia el tiempo")
  assert(g.tick(116.0) == "toggle")

  -- reset descarta la pulsacion en curso (cambio de mision/avion)
  g.down(120.0); g.reset()
  assert(g.tick(125.0) == nil and g.up(125.1, true) == nil, "reset descarta la pulsacion")

  -- RF-12: umbral configurable
  local g2 = Gesture.new({ longSec = 0.5 })
  g2.down(0); assert(g2.tick(0.4) == nil and g2.tick(0.5) == "toggle", "umbral 0,5 s")

  -- RF-13: umbral invalido -> 1 s
  for _, bad in ipairs({ 0, -1, "x", false }) do
    local gb = Gesture.new({ longSec = bad })
    gb.down(0); assert(gb.tick(0.9) == nil and gb.tick(1.0) == "toggle", "umbral invalido (" .. tostring(bad) .. ") usa 1 s")
  end
  local gn = Gesture.new({}); gn.down(0); assert(gn.tick(0.9) == nil and gn.tick(1.0) == "toggle", "sin umbral usa 1 s")
  local gz = Gesture.new(); gz.down(0); assert(gz.tick(1.0) == "toggle", "sin opciones usa 1 s")
end
print("GESTURE OK")

-- ===== Pointer (spec 001, T2): sectores de la mirada y arbitro cursor/mirada =====
local Pointer = dofile(WD .. "Scripts/RadialComms/Pointer.lua")
do
  local S = Pointer.sectorFromDelta
  -- RF-8 / RF-10 / RF-19: zona muerta de 7 grados
  assert(S(0, 0, 7) == nil and S(0, 6.99, 7) == nil and S(4, 4, 7) == nil, "dentro de la zona muerta: nil")
  assert(S(0, 7, 7) == 1, "justo en el borde de la zona muerta ya cuenta")
  -- 1 = arriba, sentido horario (yaw positivo = derecha, pitch positivo = arriba)
  assert(S(0, 10, 7) == 1,  "arriba")
  assert(S(10, 10, 7) == 2, "arriba-derecha")
  assert(S(10, 0, 7) == 3,  "derecha")
  assert(S(10, -10, 7) == 4, "abajo-derecha")
  assert(S(0, -10, 7) == 5, "abajo")
  assert(S(-10, -10, 7) == 6, "abajo-izquierda")
  assert(S(-10, 0, 7) == 7, "izquierda")
  assert(S(-10, 10, 7) == 8, "arriba-izquierda")
  -- limites entre sectores (22,5 grados)
  local function pol(deg, r) local a = math.rad(deg); return r * math.sin(a), r * math.cos(a) end
  local x, y = pol(22, 10);  assert(S(x, y, 7) == 1, "22 grados sigue en el sector 1")
  x, y = pol(23, 10);        assert(S(x, y, 7) == 2, "23 grados ya es el sector 2")
  x, y = pol(-22, 10);       assert(S(x, y, 7) == 1, "-22 grados sigue en el sector 1")
  x, y = pol(-23, 10);       assert(S(x, y, 7) == 8, "-23 grados es el sector 8")

  -- el puntero usa 7 grados por defecto (RF-19) y los configurados si son validos
  local p = Pointer.new({})
  p.gaze(0, 6); assert(p.current() == nil, "6 grados: dentro de la zona muerta por defecto")
  p.gaze(0, 8); assert(p.current() == 1, "8 grados: sector 1 con la zona muerta por defecto")
  local p10 = Pointer.new({ deadzone = 10 })
  p10.gaze(0, 8); assert(p10.current() == nil, "zona muerta de 10 grados configurada")
  p10.gaze(0, 11); assert(p10.current() == 1)
  -- RF-20: zona muerta invalida -> 7
  for _, bad in ipairs({ 0, -3, "x", false }) do
    local pb = Pointer.new({ deadzone = bad })
    pb.gaze(0, 6); assert(pb.current() == nil, "zona muerta invalida (" .. tostring(bad) .. ") usa 7: 6 grados dentro")
    pb.gaze(0, 8); assert(pb.current() == 1, "zona muerta invalida (" .. tostring(bad) .. ") usa 7: 8 grados fuera")
  end
  assert(Pointer.new().current() == nil, "sin opciones ni fuentes: nada resaltado")

  -- RF-7: manda la fuente que cambio en ultimo lugar
  local a = Pointer.new({})
  a.mouse(3); assert(a.current() == 3, "solo cursor")
  a.gaze(0, 10); assert(a.current() == 1, "la mirada cambio despues: manda la mirada")
  a.mouse(5); assert(a.current() == 5, "el cursor cambio despues: manda el cursor")
  a.gaze(0, 0); a.gaze(0, 10)
  assert(a.current() == 1, "la mirada cambio en ultimo lugar")
  a.mouse(5)  -- el cursor ya estaba en 5: repetir el valor no cuenta como cambio
  assert(a.current() == 1, "repetir el mismo valor no cuenta como cambio: sigue mandando la mirada")
  a.mouse(0); assert(a.current() == 0, "el cursor en el centro resalta el centro")
  -- si la fuente mas reciente no senala nada, se usa la otra
  -- (puntero sin cuñas con opcion: el centro no se arma, la zona muerta no senala nada; ver T3)
  local f = Pointer.new({ hasItem = function() return false end })
  f.mouse(2); f.gaze(0, 10)
  f.gaze(0, 0); assert(f.current() == 2, "la mirada vuelve a la zona muerta: vale el cursor")
  f.mouse(nil); assert(f.current() == nil, "ninguna fuente senala nada")
  f.mouse(4); f.mouse(nil); f.gaze(10, 0); assert(f.current() == 3)
  f.mouse(nil); f.gaze(0, 0); assert(f.current() == nil)

  -- RF-15: sin llamar a gaze (mirada desactivada) solo cuenta el cursor
  local c = Pointer.new({})
  c.mouse(6); assert(c.current() == 6); c.mouse(nil); assert(c.current() == nil, "sin mirada: solo cursor")
end
print("POINTER OK")

-- ===== Pointer (spec 001, T3): centro "armado" y reinicio por nivel de menu =====
do
  local items = { [1] = true, [2] = true, [3] = true, [4] = true }          -- cuñas con opcion
  local function has(s) return items[s] == true end
  local function new() return Pointer.new({ hasItem = has }) end

  -- RF-22: al abrir, la mirada en la zona muerta no resalta el centro
  local p = new()
  p.gaze(0, 0); assert(p.current() == nil, "al abrir, el centro no se resalta con la mirada")
  p.gaze(1, 2);  assert(p.current() == nil, "dentro de la zona muerta sigue sin resaltar")

  -- RF-21: tras mirar una cuña con opcion y volver a la zona muerta, se resalta el centro
  p.gaze(0, 10); assert(p.current() == 1)
  p.gaze(0, 0);  assert(p.current() == 0, "tras mirar una cuña, la zona muerta resalta el centro")
  p.gaze(10, 0); assert(p.current() == 3, "mirar otra cuña la resalta")
  p.gaze(0, 0);  assert(p.current() == 0, "y volver al centro lo resalta de nuevo")

  -- el centro de la mirada tambien se rige por "el ultimo que cambio"
  p.mouse(2); assert(p.current() == 2, "el cursor cambio despues")
  p.gaze(0, 0); assert(p.current() == 2, "la mirada sigue en el centro sin cambiar: manda el cursor")
  p.mouse(nil); assert(p.current() == 0, "sin cursor vale el centro de la mirada")

  -- sin hasItem, toda cuña tiene opcion
  local q = Pointer.new({}); q.gaze(0, 10); q.gaze(0, 0)
  assert(q.current() == 0, "sin hasItem se asume que toda cuña tiene opcion")

  -- mirar una cuña SIN opcion no arma el centro
  local r = new()
  r.gaze(-10, -10); assert(r.current() == 6, "el puntero senala la cuña 6 aunque no tenga opcion")
  r.gaze(0, 0);     assert(r.current() == nil, "una cuña sin opcion no arma el centro")

  -- reset: desarma
  local s = new()
  s.gaze(0, 10); s.gaze(0, 0); assert(s.current() == 0)
  s.reset(); assert(s.current() == nil, "tras reset el centro deja de resaltarse")
  s.gaze(0, 0); assert(s.current() == nil, "y no se vuelve a resaltar hasta mirar una cuña")
  s.gaze(0, 10); s.gaze(0, 0); assert(s.current() == 0, "mirando una cuña se arma otra vez")

  -- caso limite: entrar en un submenu con la mirada aun sobre la cuña elegida
  local t = new()
  t.gaze(0, 10); assert(t.current() == 1)
  t.reset()                                   -- se entra en el submenu; la mirada sigue en la cuña 1
  assert(t.current() == 1, "la mirada sigue señalando la cuña 1 del submenu nuevo")
  t.gaze(0, 10); t.gaze(0, 10)
  t.gaze(0, 0); assert(t.current() == nil, "la misma cuña de antes no arma el centro")
  t.gaze(0, 10); t.gaze(0, 0); assert(t.current() == nil, "volver a la misma cuña tampoco")
  t.gaze(10, 0); assert(t.current() == 3)
  t.gaze(0, 0);  assert(t.current() == 0, "mirar OTRA cuña si arma el centro")

  -- reset no toca el cursor
  local u = new(); u.mouse(4); u.reset()
  assert(u.current() == 4, "reset no cambia el cursor")

  -- RF-9: el puntero no tiene ninguna operacion que elija una cuña por tiempo
  local api = {}
  for k in pairs(p) do api[#api + 1] = k end
  table.sort(api)
  assert(table.concat(api, ",") == "current,gaze,mouse,reset", "API del puntero: " .. table.concat(api, ","))
end

-- ===== Pointer (spec 001, T11 / RF-23): en un submenu el centro se resalta siempre =====
do
  local inSub = false
  local function new() return Pointer.new({ hasItem = function(s) return s <= 4 end, centerAlways = function() return inSub end }) end
  -- menu principal: como antes (hay que mirar una cuña primero)
  local p = new()
  p.gaze(0, 0); assert(p.current() == nil, "principal: el centro no se resalta al abrir")
  -- submenu: la zona muerta resalta el centro sin armar
  inSub = true
  local q = new()
  q.gaze(0, 0); assert(q.current() == 0, "submenu: la zona muerta resalta el centro")
  q.gaze(0, 10); assert(q.current() == 1); q.gaze(0, 0); assert(q.current() == 0)
  -- entrar en un submenu mirando la cuña elegida y volver al centro: se resalta
  inSub = false
  local r = new()
  r.gaze(0, 10); assert(r.current() == 1)
  inSub = true; r.reset()
  assert(r.current() == 1, "sigue mirando la cuña")
  r.gaze(0, 0); assert(r.current() == 0, "submenu: al volver a la zona muerta se resalta el centro sin mirar otra cuña")
  -- cambiar a un submenu con la mirada ya en la zona muerta: el centro queda resaltado tras el reset
  inSub = false
  local t = new()
  t.gaze(0, 0); assert(t.current() == nil)
  inSub = true; t.reset(); assert(t.current() == 0, "submenu: tras cambiar de nivel mirando al centro, queda resaltado")
  -- volver al principal mirando al centro: se desarma
  inSub = false; t.reset(); assert(t.current() == nil, "principal: recien vuelto, el centro no queda resaltado")
  t.gaze(0, 0); assert(t.current() == nil)
  -- sin datos de mirada, el reset en un submenu no inventa el centro
  inSub = true
  local u = new(); u.mouse(2); u.reset(); assert(u.current() == 2)
  u.mouse(nil); assert(u.current() == nil, "sin mirada no hay centro aunque sea un submenu")
  -- el cursor sigue mandando si cambio el ultimo
  local v = new(); v.gaze(0, 0); v.mouse(3); assert(v.current() == 3); v.mouse(nil); assert(v.current() == 0)
end
print("POINTER SUBMENU OK")
print("POINTER CENTRO OK")

-- ===== GazeMark (spec 002, T1): posicion del punto y si hay linea =====
local GazeMark = dofile(WD .. "Scripts/RadialComms/GazeMark.lua")
do
  local function near(a, b) return math.abs(a - b) < 1e-6 end
  local m = GazeMark.new({ scale = 15, deadzone = 7, radius = 220 })
  -- giro 0: punto en el centro, sin linea
  local x, y, line = m.compute(0, 0)
  assert(x == 0 and y == 0 and line == false, "giro 0: centro y sin linea")
  -- direcciones (en pantalla, arriba = y negativa)
  x, y = m.compute(0, 7.5);   assert(near(x, 0) and near(y, -110), "arriba, mitad del radio")
  x, y = m.compute(7.5, 0);   assert(near(x, 110) and near(y, 0), "derecha, mitad del radio")
  x, y = m.compute(0, -7.5);  assert(near(x, 0) and near(y, 110), "abajo")
  x, y = m.compute(-7.5, 0);  assert(near(x, -110) and near(y, 0), "izquierda")
  x, y = m.compute(3, 4);     assert(near(x, 3 / 15 * 220) and near(y, -4 / 15 * 220), "diagonal proporcional (giro 5)")
  x, y = m.compute(-3, -4);   assert(x < 0 and y > 0, "diagonal abajo-izquierda")
  -- RF-3: al llegar a la escala, en el borde
  x, y = m.compute(15, 0);    assert(near(x, 220) and near(y, 0), "15 grados: en el borde")
  -- RF-4: mas alla de la escala no pasa del borde
  x, y = m.compute(40, 0);    assert(near(x, 220) and near(y, 0), "40 grados: sigue en el borde")
  x, y = m.compute(30, 40);   assert(near(math.sqrt(x * x + y * y), 220), "diagonal grande: en el borde")
  assert(near(x, 220 * 0.6) and near(y, -220 * 0.8), "diagonal grande: conserva la direccion")
  -- RF-5 / RF-6: linea solo con giro >= zona muerta
  local _, _, l1 = m.compute(0, 6.9); assert(l1 == false, "6,9 grados: sin linea")
  local _, _, l2 = m.compute(0, 7);   assert(l2 == true, "7 grados: con linea")
  local _, _, l3 = m.compute(5, 5);   assert(l3 == true, "diagonal de 7,07 grados: con linea")
  local _, _, l4 = m.compute(4, 4);   assert(l4 == false, "diagonal de 5,66 grados: sin linea")
  -- RF-18: escala invalida -> 15; zona muerta invalida -> 7
  for _, bad in ipairs({ 0, -5, "x", false }) do
    local mb = GazeMark.new({ scale = bad, deadzone = bad, radius = 220 })
    local bx = mb.compute(7.5, 0); assert(near(bx, 110), "escala invalida (" .. tostring(bad) .. ") usa 15")
    local _, _, a = mb.compute(0, 6.9); local _, _, b = mb.compute(0, 7)
    assert(a == false and b == true, "zona muerta invalida (" .. tostring(bad) .. ") usa 7")
  end
  local md = GazeMark.new({ radius = 100 })
  x = md.compute(15, 0); assert(near(x, 100), "sin escala usa 15; radio configurable")
  -- escala configurable
  local m30 = GazeMark.new({ scale = 30, radius = 220 })
  x = m30.compute(15, 0); assert(near(x, 110), "escala 30: 15 grados es la mitad del radio")
end
print("GAZEMARK OK")

-- ===== GazeMark (spec 002, T2): puntitos de la linea =====
do
  local function near(a, b) return math.abs(a - b) < 1e-6 end
  -- punto en el centro: sin puntitos
  assert(#GazeMark.segments(0, 0, 50, 4) == 0, "punto en el centro: lista vacia")
  -- hacia la derecha, punto a 100 px: puntitos cada 4 px en linea recta, sin pasarse del punto
  local seg = GazeMark.segments(100, 0, 50, 4)
  assert(#seg > 0 and #seg <= 50, "hay puntitos y no mas de n")
  for i, q in ipairs(seg) do
    assert(near(q.y, 0) and near(q.x, 4 * i), "puntito " .. i .. " a " .. (4 * i) .. " px en la recta")
    assert(q.x <= 100, "ningun puntito mas lejos que el punto")
  end
  assert(seg[#seg].x > 100 - 8, "la linea llega hasta cerca del punto")
  -- en diagonal: todos sobre la recta y dentro
  seg = GazeMark.segments(-60, 80, 50, 4)          -- distancia 100
  for i, q in ipairs(seg) do
    local d = math.sqrt(q.x * q.x + q.y * q.y)
    assert(near(d, 4 * i) and d <= 100, "diagonal: distancia del puntito " .. i)
    assert(near(q.x / d, -0.6) and near(q.y / d, 0.8), "diagonal: misma direccion que el punto")
  end
  -- nunca mas de n
  seg = GazeMark.segments(204, 0, 10, 4)
  assert(#seg == 10, "tope de n puntitos")
  -- punto muy cerca del centro: ninguno
  assert(#GazeMark.segments(3, 0, 50, 4) == 0, "punto a 3 px: no cabe ningun puntito")
end
print("GAZEMARK LINEA OK")
print("WEDGE ONLY DYNAMIC TEST OK")
'''
import re


# --- el archivo de configuracion real lleva las opciones nuevas (spec 001, T8)
real_cfg = open(f"{src_root}/Config/RadialCommsConfig.lua", encoding="utf-8").read()
for key, val in (("longPressSeconds", "1.0"), ("headDeadzone", "7"), ("headSelect", "true"), ("headMark", "true"), ("headMarkScale", "15")):
    assert re.search(key + r"\s*=\s*" + re.escape(val) + r"\b", real_cfg), "falta " + key + " = " + val + " en Config/RadialCommsConfig.lua"
assert "headDwell" not in real_cfg, "Config/RadialCommsConfig.lua no debe llevar headDwell"
CLAVES_NUEVAS = ("longPressSeconds", "headDeadzone", "headSelect", "headMark", "headMarkScale")


def setkey(cfg, key, val):
    # cambia el valor de una clave de la config, o la añade si no esta
    pat = r"(?m)^([ \t]*)" + key + r"[ \t]*=[ \t]*[^,\n]*"
    if re.search(pat, cfg):
        return re.sub(pat, lambda m: m.group(1) + key + " = " + val, cfg)
    return cfg.replace("return {", "return {\n    " + key + " = " + val + ",", 1)


def run(head_on, antigua=False, mark=True, scale=15):
    # carpeta de escritura temporal con la config de la prueba (mirada y marca activadas o no).
    # antigua=True: config de una version anterior (sin las claves nuevas y con headDwell): deben valer los
    # valores por defecto del modulo.
    wd = tempfile.mkdtemp(prefix="dcs_writedir_") + "/"
    shutil.copytree(f"{src_root}/Config", wd + "Config")
    shutil.copytree(f"{src_root}/Scripts", wd + "Scripts")
    cfgp = wd + "Config/RadialCommsConfig.lua"
    cfg = open(cfgp, encoding="utf-8").read()
    if antigua:
        for key in CLAVES_NUEVAS:
            cfg = re.sub(r"(?m)^[ \t]*" + key + r"[ \t]*=.*$", "", cfg)
        cfg = cfg.replace("return {", "return {\n    headDwell = 1.0,", 1)
    else:
        cfg = setkey(cfg, "headSelect", "true" if head_on else "false")
        cfg = setkey(cfg, "headMark", "true" if mark else "false")
        cfg = setkey(cfg, "headMarkScale", str(scale))
    open(cfgp, "w", encoding="utf-8").write(cfg)
    lua = LuaRuntime()
    lua.eval("function(src, wd, headOn, markOn, scale) return assert(loadstring(src))(wd, headOn, markOn, scale) end")(test, wd, head_on, mark, scale)
    shutil.rmtree(wd.rstrip("/"), ignore_errors=True)


for mode in (True, False):
    print("--- mirada " + ("activada" if mode else "desactivada") + " ---")
    run(mode)
print("--- config antigua (valores por defecto: mirada y marca activadas) ---")
run(True, antigua=True)
print("--- marca de la mirada desactivada (headMark = false) ---")
run(True, mark=False)
print("--- escala de la marca 30 grados ---")
run(True, scale=30)
