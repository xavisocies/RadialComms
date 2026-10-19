import shutil, tempfile
from lupa.lua51 import LuaRuntime

import os
src_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
wd = tempfile.mkdtemp(prefix="dcs_writedir_") + "/"
shutil.copytree(f"{src_root}/Config", wd + "Config")
shutil.copytree(f"{src_root}/Scripts", wd + "Scripts")

test = r'''
local WD = ...
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
Input = {
  createLayer = function(n) layers[n] = {} end,
  deleteLayer = function(n) layers[n] = nil; for i=#stack,1,-1 do if stack[i]==n then table.remove(stack,i) end end end,
  addKeyCombo = function(l, ev, dev, ref, down) layers[l][ev] = down end,
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
DCS = { getPlayerUnitType = function() return "F-16C_50" end,
        setUserCallbacks = function(h) handler = h end, getRealTime = function() return os.clock() end }
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
local function lab(i) return statics[18 + i].text end
local function sel(i)
  local a = math.rad(-90 + (i - 1) * 45)
  hit().cbs.up(hit(), 960 + 150 * math.cos(a), 551 + 150 * math.sin(a), 1)
end
local function center() hit().cbs.up(hit(), 965, 556, 1) end
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
-- pulsar el boton abre y cierra la rueda
if window.cursor then open() end
assert(window.cursor == false)
press(101); handler.onSimulationFrame(); assert(window.cursor == true, "boton abre la rueda")
press(101); handler.onSimulationFrame(); assert(window.cursor == false, "boton cierra la rueda")
press(100); handler.onSimulationFrame(); assert(window.cursor == false, "otros botones no hacen nada")
-- DCS rehace la pila: se repone
stack = {}; layers = {}
local t0 = os.clock(); while os.clock() - t0 < 0.01 do end
DCS.getRealTime = function() return 1e6 end
handler.onSimulationFrame()
assert(layers["RadialComms"] and layers["RadialComms"][101], "capa repuesta")
-- borrar
fresh(); sel(4); sel(labidx("Quitar boton"))
assert(layers["RadialComms"] == nil, "capa borrada")
print("JOY OK")
print("WEDGE ONLY DYNAMIC TEST OK")
'''
lua = LuaRuntime()
lua.eval("function(src, wd) return assert(loadstring(src))(wd) end")(test, wd)
print(open(wd+"Logs\\RadialComms.log",encoding="utf-8").read()[-1500:]) if False else None
shutil.rmtree(wd.rstrip("/"), ignore_errors=True)
