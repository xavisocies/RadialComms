import sys
from lupa.lua51 import LuaRuntime

import os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = [
    "Scripts/Hooks/RadialComms-hook.lua",
    "Scripts/RadialComms/RadialComms.lua",
    "Scripts/RadialComms/JoyButton.lua",
    "Config/RadialCommsConfig.lua",
    "Config/RadialCommsMenu.lua",
]

lua = LuaRuntime()
check = lua.eval("function(s) local f, e = loadstring(s); return {ok = (f ~= nil), err = e} end")
ok_all = True
for f in files:
    src = open(f"{root}/{f}", encoding="utf-8").read()
    res = check(src)
    if res["ok"]:
        print("syntax ok  ", f)
    else:
        ok_all = False
        print("SYNTAX ERROR", f, res["err"])
sys.exit(0 if ok_all else 1)
