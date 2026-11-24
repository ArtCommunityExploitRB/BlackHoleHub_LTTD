--[[
    ╔══════════════════════════════════════════════╗
    ║   BlackHoleHub_LTTD  by  ART1XL1S            ║
    ║   UI: Rayfield                               ║
    ║   Игра: Legacy (Наследие)                    ║
    ║   Игра PlaceId : 131703399727686             ║
    ║   Лобби PlaceId: 93712201161812              ║
    ╚══════════════════════════════════════════════╝

    Папки (создаются автоматически в workspace executor'а):
        MacrosBHL_LTTD/
            Player/Settings.json   -- вкладка Settings + параметры макросов
            Player/Player.json     -- вкладка Player (позиции кликов, волны, тумблеры)
            Macros/<имя>.json      -- макросы
            Macros/<имя>.bak       -- резервная копия макроса (если включено)

    ДЛЯ AUTO EXECUTE:
        Либо впиши raw-ссылку на этот скрипт в SELF_URL ниже,
        либо сохрани этот файл как  MacrosBHL_LTTD/BlackHoleHub_LTTD.lua
]]

local SELF_URL = "https://raw.githubusercontent.com/ArtCommunityExploitRB/BlackHoleHub_LTTD/refs/heads/main/BlackHoleHub_LTTD.lua"

if not game:IsLoaded() then game.Loaded:Wait() end

---------------------------------------------------------------------
-- Повторный запуск: убираем старую копию
---------------------------------------------------------------------
local genv = (getgenv and getgenv()) or _G
if genv.BHL_LTTD and type(genv.BHL_LTTD.Cleanup) == "function" then
    pcall(genv.BHL_LTTD.Cleanup)
end
local State = { Alive = true, Conns = {} }
genv.BHL_LTTD = State
local function track(c) table.insert(State.Conns, c) return c end

---------------------------------------------------------------------
-- Сервисы
---------------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local VirtualUser       = game:GetService("VirtualUser")
local okVIM, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
if not okVIM then VIM = nil end

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local GAME_PLACE  = 131703399727686
local LOBBY_PLACE = 93712201161812
local IN_GAME     = (game.PlaceId == GAME_PLACE)

---------------------------------------------------------------------
-- Файлы / папки
---------------------------------------------------------------------
local ROOT          = "MacrosBHL_LTTD"
local PLAYER_DIR    = ROOT .. "/Player"
local MACROS_DIR    = ROOT .. "/Macros"
local SETTINGS_FILE = PLAYER_DIR .. "/Settings.json"
local PLAYER_FILE   = PLAYER_DIR .. "/Player.json"
local MAIN_FILE     = ROOT .. "/BlackHoleHub_LTTD.lua"

local FS_OK = (writefile and readfile and isfile and isfolder and makefolder) and true or false
if FS_OK then
    for _, d in ipairs({ ROOT, PLAYER_DIR, MACROS_DIR, ROOT .. "/UI" }) do
        if not isfolder(d) then pcall(makefolder, d) end
    end
end

local function readJson(path, default)
    if FS_OK and isfile(path) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
        if ok and type(data) == "table" then return data end
    end
    return default
end

local function writeJson(path, data)
    if not FS_OK then return false end
    local ok = pcall(function() writefile(path, HttpService:JSONEncode(data)) end)
    return ok
end

local function mergeDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

---------------------------------------------------------------------
-- Конфиги
---------------------------------------------------------------------
local NO_MACRO = "(нет макросов)"

local cfg = mergeDefaults(readJson(SETTINGS_FILE, {}), {
    antiAfk         = true,
    hookRemote      = false,   -- хук Remote (может крашить на некоторых executor)
    autoExecute     = false,
    stopKey         = "F8",
    countdown       = 3,
    clickOffsetY    = 0,
    hideOnRecord    = false,
    -- макросы
    selectedMacro   = "",
    recordMouseMove = true,
    sampleMs        = 1,       -- минимальный интервал между сэмплами (мс). 1 = каждый кадр
    createBak       = true,
    replayMode      = "Input", -- "Input" | "Remote"
    replayMove      = true,
    replayCamera    = true,
    waveGate        = true,
    loopMacro       = false,
    autoRunMacro    = false,
})

local pcfg = mergeDefaults(readJson(PLAYER_FILE, {}), {
    autoSkip   = false,
    autoVote   = false,
    autoReplay = false,
    waveFrom   = 1,
    waveTo     = 250,
    -- skipPos / votePos / replayPos = {x=, y=, rx=, ry=}
})

local saveQueued = false
local function saveAll()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.4, function()
        saveQueued = false
        writeJson(SETTINGS_FILE, cfg)
        writeJson(PLAYER_FILE, pcfg)
    end)
end

---------------------------------------------------------------------
-- Rayfield
---------------------------------------------------------------------
local Rayfield
do
    local urls = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    for _, url in ipairs(urls) do
        local ok, lib = pcall(function() return loadstring(game:HttpGet(url))() end)
        if ok and lib then Rayfield = lib break end
    end
end
if not Rayfield then
    warn("[BlackHoleHub_LTTD] Не удалось загрузить Rayfield")
    return
end

local function notify(title, content, duration)
    pcall(function()
        Rayfield:Notify({ Title = tostring(title), Content = tostring(content or ""), Duration = duration or 3 })
    end)
end

---------------------------------------------------------------------
-- Утилиты игры
---------------------------------------------------------------------
local function getMatchData()
    return ReplicatedStorage:FindFirstChild("MatchData")
end

-- Текущая волна (nil если MatchData нет, например в лобби)
local function curWave()
    local md = getMatchData()
    local v = md and md:FindFirstChild("CurrentWave")
    return v and v.Value or nil
end

local function getGui(...)
    local cur = PlayerGui
    for _, n in ipairs({ ... }) do
        cur = cur and cur:FindFirstChild(n)
    end
    return cur
end

local function isShown(obj)
    if not obj then return false end
    local cur = obj
    while cur and cur ~= PlayerGui do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

-- ratio -> экранные пиксели
local function toScreen(rx, ry)
    local vp = viewport()
    return Vector2.new(rx * vp.X, ry * vp.Y + (cfg.clickOffsetY or 0))
end

local function clickAt(pos, button)
    if not VIM then return false end
    button = button or 0
    pcall(function()
        VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, button, true, game, 0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, button, false, game, 0)
    end)
    return true
end

local function clickSaved(p)
    if not p then return false end
    return clickAt(toScreen(p.rx, p.ry), 0)
end

-- центр GUI-объекта в экранных координатах
local function guiCenter(obj)
    if not obj then return nil end
    local pos = obj.AbsolutePosition + obj.AbsoluteSize / 2
    local sg = obj:FindFirstAncestorOfClass("ScreenGui")
    if sg and not sg.IgnoreGuiInset then pos = pos + GuiService:GetGuiInset() end
    return pos
end

-- позиция клика из InputObject -> {x,y,rx,ry}
local function inputToPos(input)
    local vp = viewport()
    local pos
    if input.UserInputType == Enum.UserInputType.Touch then
        pos = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
    else
        pos = UIS:GetMouseLocation()
    end
    return {
        x = math.floor(pos.X), y = math.floor(pos.Y),
        rx = math.floor(pos.X / vp.X * 10000 + 0.5) / 10000,
        ry = math.floor(pos.Y / vp.Y * 10000 + 0.5) / 10000,
    }
end

---------------------------------------------------------------------
-- Запоминание позиции клика (окно 5 секунд)
---------------------------------------------------------------------
local capturing = false
local posParas = {}

local function fmtPos(p)
    if not p then return "не задана" end
    return ("x=%d  y=%d  (%.1f%% / %.1f%%)"):format(p.x, p.y, p.rx * 100, p.ry * 100)
end

local posTitles = { skipPos = "Skip", votePos = "Vote", replayPos = "RePlay" }
local function updatePosPara(key)
    local lbl = posParas[key]
    if lbl then pcall(function() lbl:Set("Позиция " .. posTitles[key] .. ": " .. fmtPos(pcfg[key])) end) end
end

local function capturePosition(key, label)
    if capturing then notify("Захват", "Уже идёт захват позиции", 2) return end
    capturing = true
    notify(label, "У тебя 5 секунд — нажми на нужную кнопку в игре", 5)
    local startT = os.clock()
    local conn
    conn = UIS.InputBegan:Connect(function(input)
        if os.clock() - startT < 0.3 then return end
        local ut = input.UserInputType
        if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
            pcfg[key] = inputToPos(input)
            capturing = false
            conn:Disconnect()
            saveAll()
            updatePosPara(key)
            notify(label, "Позиция сохранена: " .. fmtPos(pcfg[key]), 3)
        end
    end)
    task.delay(5.2, function()
        if capturing and conn and conn.Connected then
            conn:Disconnect()
            capturing = false
            notify(label, "Время вышло, позиция не сохранена", 3)
        end
    end)
end

---------------------------------------------------------------------
-- Сериализация аргументов Remote
---------------------------------------------------------------------
local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end

local function instPath(inst)
    local p, cur = {}, inst
    while cur and cur ~= game do
        local n = cur.Name
        if n == LocalPlayer.Name then n = "%LP%" end
        table.insert(p, 1, n)
        cur = cur.Parent
    end
    if cur ~= game then return nil end
    return p
end

local function resolvePath(p)
    local cur = game
    for _, n in ipairs(p) do
        if n == "%LP%" then n = LocalPlayer.Name end
        cur = cur and cur:FindFirstChild(n)
        if not cur then return nil end
    end
    return cur
end

local function ser(v, depth)
    depth = depth or 0
    if depth > 6 then return { t = "nil" } end
    local ty = typeof(v)
    if ty == "nil" then return { t = "nil" }
    elseif ty == "boolean" or ty == "string" then return v
    elseif ty == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return { t = "num", v = tostring(v) } end
        return v
    elseif ty == "Vector3" then return { t = "v3", v = { v.X, v.Y, v.Z } }
    elseif ty == "Vector2" then return { t = "v2", v = { v.X, v.Y } }
    elseif ty == "CFrame" then return { t = "cf", v = { v:GetComponents() } }
    elseif ty == "Color3" then return { t = "c3", v = { v.R, v.G, v.B } }
    elseif ty == "EnumItem" then return { t = "en", v = tostring(v) }
    elseif ty == "Instance" then
        if v == LocalPlayer then return { t = "lp" } end
        return { t = "inst", p = instPath(v), n = v.Name }
    elseif ty == "table" then
        local n = #v
        local arr, hash = {}, nil
        for i = 1, n do arr[i] = ser(v[i], depth + 1) end
        for k, val in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k) then
                hash = hash or {}
                hash[#hash + 1] = { ser(k, depth + 1), ser(val, depth + 1) }
            end
        end
        return { t = "tbl", n = n, a = arr, h = hash }
    end
    return { t = "unsup", ty = ty }
end

local function deser(v)
    if type(v) ~= "table" then return v end
    local t = v.t
    if t == "nil" or t == "unsup" then return nil
    elseif t == "num" then return tonumber(v.v)
    elseif t == "v3" then return Vector3.new(v.v[1], v.v[2], v.v[3])
    elseif t == "v2" then return Vector2.new(v.v[1], v.v[2])
    elseif t == "cf" then return CFrame.new(unpack(v.v))
    elseif t == "c3" then return Color3.new(v.v[1], v.v[2], v.v[3])
    elseif t == "en" then
        local _, _, en, item = tostring(v.v):find("^Enum%.([^%.]+)%.(.+)$")
        local ok, res = pcall(function() return Enum[en][item] end)
        return ok and res or nil
    elseif t == "lp" then return LocalPlayer
    elseif t == "inst" then return v.p and resolvePath(v.p) or nil
    elseif t == "tbl" then
        local out = {}
        for i = 1, (v.n or #v.a) do out[i] = deser(v.a[i]) end
        if v.h then
            for _, kv in ipairs(v.h) do
                local k = deser(kv[1])
                if k ~= nil then out[k] = deser(kv[2]) end
            end
        end
        return out
    end
    return nil
end

local function isExcludedRemotePath(path)
    for _, seg in ipairs(path) do
        local s = tostring(seg)
        if s:find("Test Remotes", 1, true) or s == "CmdrClient" or s == "AdminTools" then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------
-- Recorder
---------------------------------------------------------------------
local Recorder = {
    active = false, countingDown = false,
    events = {}, t0 = 0,
    lastMove = nil, lastCam = nil,
    lastSample = -1000, lastMouseMs = -1000,
}
local Replay = { playing = false }
local setStatus = function() end

local function nowMs() return math.floor((os.clock() - Recorder.t0) * 1000) end

function Recorder.add(ev)
    ev.t = nowMs()
    ev.w = curWave() or 0
    Recorder.events[#Recorder.events + 1] = ev
end

local function comps12(cf)
    local c = { cf:GetComponents() }
    for i = 1, #c do c[i] = r3(c[i]) end
    return c
end

local function sameComps(a, b)
    if not a or not b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Хук Remote (ставится один раз за сессию, логгер подменяется при каждом запуске)
local HOOK_OK = false
genv.BHL_RemoteLogger = function(remote, method, ...)
    if not Recorder.active then return end
    local packed = table.pack(...)
    pcall(function()
        if typeof(remote) ~= "Instance" then return end
        local cn = remote.ClassName
        if cn ~= "RemoteEvent" and cn ~= "RemoteFunction" and cn ~= "UnreliableRemoteEvent" then return end
        local path = instPath(remote)
        if not path or isExcludedRemotePath(path) then return end
        local args = {}
        for i = 1, packed.n do args[i] = ser(packed[i]) end
        Recorder.add({ type = "rm", r = path, m = method, n = packed.n, a = args })
    end)
end

local function installHook()
    if genv.BHL_HookInstalled then HOOK_OK = true return true end
    if not (hookmetamethod and getnamecallmethod and newcclosure and checkcaller) then return false end
    local ok = pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local m = getnamecallmethod()
            if (m == "FireServer" or m == "InvokeServer") and not checkcaller() then
                local lg = genv.BHL_RemoteLogger
                if lg then
                    lg(self, m, ...)
                    if setnamecallmethod then setnamecallmethod(m) end
                end
            end
            return old(self, ...)
        end))
    end)
    if ok then genv.BHL_HookInstalled = true HOOK_OK = true end
    return ok
end
if cfg.hookRemote then task.defer(installHook) end

---------------------------------------------------------------------
-- Макро-файлы
---------------------------------------------------------------------
local function sanitize(name)
    name = tostring(name or "")
    name = name:gsub("[\\/:%*%?\"<>|%c]", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "_")
    return name
end

local function macroPath(name) return MACROS_DIR .. "/" .. name .. ".json" end
local function macroBak(name)  return MACROS_DIR .. "/" .. name .. ".bak" end

local function listMacros()
    local out = {}
    if FS_OK and listfiles then
        local ok, files = pcall(listfiles, MACROS_DIR)
        if ok and files then
            for _, f in ipairs(files) do
                local n = tostring(f):match("([^/\\]+)%.json$")
                if n then out[#out + 1] = n end
            end
        end
    end
    table.sort(out)
    return out
end

local function saveMacro(name, data)
    if not FS_OK then return false end
    local path = macroPath(name)
    local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then return false end
    if cfg.createBak then
        local content = json
        if isfile(path) then
            local okr, old = pcall(readfile, path)
            if okr and old and #old > 2 then content = old end
        end
        pcall(writefile, macroBak(name), content)
    end
    return pcall(writefile, path, json)
end

local function loadMacro(name)
    if name == "" or name == NO_MACRO then return nil end
    return readJson(macroPath(name), nil)
end

local function createMacro(name)
    name = sanitize(name)
    if name == "" then notify("Макрос", "Введи название макроса", 3) return nil end
    if FS_OK and isfile(macroPath(name)) then notify("Макрос", "Макрос «" .. name .. "» уже существует", 3) return nil end
    local data = {
        name = name, version = 1, created = os.time(),
        placeId = game.PlaceId, duration = 0, events = {},
    }
    if not saveMacro(name, data) then notify("Макрос", "Не удалось создать файл", 3) return nil end
    notify("Макрос", "Создан: " .. name, 3)
    return name
end

---------------------------------------------------------------------
-- Запись
---------------------------------------------------------------------

local function recStatus(t) setStatus(t) end

function Recorder.start()
    if Recorder.active or Recorder.countingDown then return end
    if Replay.playing then notify("Запись", "Сначала останови воспроизведение", 3) return end
    local name = cfg.selectedMacro
    if not name or name == "" or name == NO_MACRO then
        notify("Запись", "Сначала создай и выбери макрос", 3) return
    end
    if not FS_OK then notify("Запись", "Executor не поддерживает файлы (writefile)", 4) return end
    if cfg.hookRemote then installHook() end
    Recorder.countingDown = true
    local cd = math.max(0, math.floor(cfg.countdown or 3))
    if cd > 0 then
        notify("Запись", ("Старт через %d сек. Остановка: %s"):format(cd, cfg.stopKey), cd)
        if cfg.hideOnRecord then pcall(function() Rayfield:SetVisibility(false) end) end
        task.wait(cd)
    end
    Recorder.countingDown = false
    if not State.Alive then return end

    Recorder.events = {}
    Recorder.t0 = os.clock()
    Recorder.lastMove, Recorder.lastCam = nil, nil
    Recorder.lastSample, Recorder.lastMouseMs = -1000, -1000
    Recorder.name = name
    Recorder.active = true

    -- стартовый снимок позиции и камеры
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then Recorder.lastMove = comps12(hrp.CFrame); Recorder.add({ type = "mv", c = Recorder.lastMove }) end
    local cam = workspace.CurrentCamera
    if cam then Recorder.lastCam = comps12(cam.CFrame); Recorder.add({ type = "cm", c = Recorder.lastCam }) end

    notify("Запись", "● ИДЁТ ЗАПИСЬ «" .. name .. "»  (стоп: " .. cfg.stopKey .. ")", 3)
    if not HOOK_OK then
        notify("Запись", "Remote не пишутся (включи Hook Remote в Settings) — пишутся ввод и движение", 4)
    end
    recStatus("● Запись: " .. name)
end

function Recorder.stop(byUi)
    if not Recorder.active then return end
    Recorder.active = false
    local endT = nowMs()
    local events = Recorder.events

    if byUi then
        -- вырезаем клик по кнопке «Стоп» в интерфейсе
        local cut, clean = endT - 600, {}
        for _, ev in ipairs(events) do
            local mouse = (ev.type == "mb" or ev.type == "mm" or ev.type == "wh")
            if not (mouse and ev.t >= cut) then clean[#clean + 1] = ev end
        end
        events = clean
    end

    local vp = viewport()
    local md = getMatchData()
    local mapId = md and md:FindFirstChild("MapId")
    local data = {
        name = Recorder.name, version = 1, created = os.time(),
        placeId = game.PlaceId, map = mapId and mapId.Value or nil,
        duration = endT, viewport = { x = vp.X, y = vp.Y },
        count = #events, events = events,
    }
    pcall(function() Rayfield:SetVisibility(true) end)
    local ok = saveMacro(Recorder.name, data)
    if ok then
        notify("Запись", ("■ Сохранено «%s»: %d событий, %.1f сек"):format(Recorder.name, #events, endT / 1000), 4)
    else
        notify("Запись", "Ошибка сохранения макроса!", 4)
    end
    recStatus(("Сохранено: %s (%d событий, %.1f сек)"):format(Recorder.name, #events, endT / 1000))
    Recorder.events = {}
end

-- Каждый кадр: движение персонажа и камера
track(RunService.Heartbeat:Connect(function()
    if not Recorder.active then return end
    local t = nowMs()
    if t - Recorder.lastSample < (cfg.sampleMs or 1) then return end
    Recorder.lastSample = t

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local c = comps12(hrp.CFrame)
        if not sameComps(c, Recorder.lastMove) then
            Recorder.lastMove = c
            Recorder.add({ type = "mv", c = c })
        end
    end
    local cam = workspace.CurrentCamera
    if cam then
        local c = comps12(cam.CFrame)
        if not sameComps(c, Recorder.lastCam) then
            Recorder.lastCam = c
            Recorder.add({ type = "cm", c = c })
        end
    end
end))

-- Ввод: клавиши, клики, мышь, колесо
local function mouseButtonIndex(ut)
    if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then return 1 end
    if ut == Enum.UserInputType.MouseButton2 then return 2 end
    if ut == Enum.UserInputType.MouseButton3 then return 3 end
    return nil
end

local function onInput(input, down)
    if not Recorder.active then return end
    local ut = input.UserInputType
    if ut == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Unknown then return end
        if input.KeyCode.Name == cfg.stopKey then return end
        if UIS:GetFocusedTextBox() then return end
        Recorder.add({ type = "k", k = input.KeyCode.Name, s = down and 1 or 0 })
        return
    end
    local b = mouseButtonIndex(ut)
    if b then
        local p = inputToPos(input)
        Recorder.add({ type = "mb", b = b, s = down and 1 or 0, x = p.x, y = p.y, rx = p.rx, ry = p.ry })
    end
end

track(UIS.InputBegan:Connect(function(input)
    -- горячая клавиша остановки записи / воспроизведения
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == cfg.stopKey
        and not UIS:GetFocusedTextBox() then
        if Recorder.active then Recorder.stop(false) return end
        if Replay.playing then Replay.stop() return end
    end
    onInput(input, true)
end))
track(UIS.InputEnded:Connect(function(input) onInput(input, false) end))
track(UIS.InputChanged:Connect(function(input)
    if not Recorder.active then return end
    local ut = input.UserInputType
    if ut == Enum.UserInputType.MouseMovement then
        if not cfg.recordMouseMove then return end
        local t = nowMs()
        if t - Recorder.lastMouseMs < (cfg.sampleMs or 1) then return end
        Recorder.lastMouseMs = t
        local p = inputToPos(input)
        Recorder.add({ type = "mm", x = p.x, y = p.y, rx = p.rx, ry = p.ry })
    elseif ut == Enum.UserInputType.MouseWheel then
        local p = inputToPos(input)
        Recorder.add({ type = "wh", d = input.Position.Z, rx = p.rx, ry = p.ry })
    end
end))

---------------------------------------------------------------------
-- Воспроизведение
---------------------------------------------------------------------
local heldKeys, heldMouse = {}, {}
local replayConn
local prevCamType

local function releaseAll()
    if not VIM then return end
    for kc in pairs(heldKeys) do
        pcall(function() VIM:SendKeyEvent(false, kc, false, game) end)
    end
    for b, pos in pairs(heldMouse) do
        pcall(function() VIM:SendMouseButtonEvent(pos.X, pos.Y, b - 1, false, game, 0) end)
    end
    heldKeys, heldMouse = {}, {}
end

function Replay.stop(silent)
    if not Replay.playing then return end
    Replay.playing = false
    if replayConn then replayConn:Disconnect() replayConn = nil end
    releaseAll()
    local cam = workspace.CurrentCamera
    if cam and prevCamType then pcall(function() cam.CameraType = prevCamType end) end
    prevCamType = nil
    if not silent then notify("Макрос", "■ Воспроизведение остановлено", 3) end
    setStatus("Остановлено")
end

local function execEvent(ev)
    local ty = ev.type
    if ty == "mv" then
        if cfg.replayMove then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(unpack(ev.c)) end
        end
        return
    elseif ty == "cm" then
        if cfg.replayCamera then
            local cam = workspace.CurrentCamera
            if cam then
                if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
                cam.CFrame = CFrame.new(unpack(ev.c))
            end
        end
        return
    end

    local remoteMode = tostring(cfg.replayMode):find("Remote") ~= nil

    if ty == "rm" then
        if not remoteMode then return end
        local path = ev.r
        if type(path) ~= "table" or isExcludedRemotePath(path) then return end
        local remote = resolvePath(path)
        if not remote then return end
        local args = {}
        for i = 1, (ev.n or #ev.a) do args[i] = deser(ev.a[i]) end
        local n = ev.n or #args
        if ev.m == "InvokeServer" then
            task.spawn(function() pcall(function() remote:InvokeServer(unpack(args, 1, n)) end) end)
        else
            pcall(function() remote:FireServer(unpack(args, 1, n)) end)
        end
        return
    end

    if remoteMode or not VIM then return end

    if ty == "k" then
        local ok, kc = pcall(function() return Enum.KeyCode[ev.k] end)
        if ok and kc then
            if ev.s == 1 then heldKeys[kc] = true else heldKeys[kc] = nil end
            VIM:SendKeyEvent(ev.s == 1, kc, false, game)
        end
    elseif ty == "mb" then
        local pos = toScreen(ev.rx, ev.ry)
        VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, ev.b - 1, ev.s == 1, game, 0)
        if ev.s == 1 then heldMouse[ev.b] = pos else heldMouse[ev.b] = nil end
    elseif ty == "mm" then
        local pos = toScreen(ev.rx, ev.ry)
        VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
    elseif ty == "wh" then
        local pos = toScreen(ev.rx, ev.ry)
        VIM:SendMouseWheelEvent(pos.X, pos.Y, (ev.d or 0) > 0, game)
    end
end

function Replay.start(name)
    if Replay.playing then Replay.stop(true) end
    if Recorder.active or Recorder.countingDown then notify("Макрос", "Идёт запись", 3) return end
    local macro = loadMacro(name)
    if not macro or type(macro.events) ~= "table" or #macro.events == 0 then
        notify("Макрос", "Макрос пуст или не найден", 3) return
    end
    local events = macro.events
    table.sort(events, function(a, b) return (a.t or 0) < (b.t or 0) end)

    if not tostring(cfg.replayMode):find("Remote") and not VIM then
        notify("Макрос", "VirtualInputManager недоступен — используй режим Remote", 4) return
    end

    Replay.playing = true
    local i, clock, lastStatus = 1, 0, 0
    local cam = workspace.CurrentCamera
    prevCamType = cam and cam.CameraType
    notify("Макрос", ("▶ Запуск «%s» (%d событий)"):format(name, #events), 3)

    replayConn = RunService.Heartbeat:Connect(function(dt)
        if not Replay.playing then return end
        local ev = events[i]
        if not ev then
            -- конец
            if cfg.loopMacro then
                Replay.stop(true)
                task.delay(1, function() if State.Alive then Replay.start(name) end end)
            else
                Replay.stop(true)
                notify("Макрос", "✔ Воспроизведение завершено", 3)
                setStatus("Завершено: " .. name)
            end
            return
        end

        local function waiting(e)
            if not cfg.waveGate then return false end
            local cw = curWave()
            return cw ~= nil and e.w and e.w > 0 and cw < e.w
        end

        if waiting(ev) then
            if os.clock() - lastStatus > 0.5 then
                lastStatus = os.clock()
                setStatus(("⏳ Жду волну %d (сейчас %s)  [%d/%d]"):format(ev.w, tostring(curWave()), i, #events))
            end
            return -- таймлиния на паузе
        end

        clock = clock + dt * 1000
        while ev and ev.t <= clock do
            if waiting(ev) then break end
            local ok, err = pcall(execEvent, ev)
            if not ok then warn("[BHL] event error:", err) end
            i = i + 1
            ev = events[i]
        end

        if os.clock() - lastStatus > 0.5 then
            lastStatus = os.clock()
            setStatus(("▶ %s  [%d/%d]  %.1f сек"):format(name, i - 1, #events, clock / 1000))
        end
    end)
end

---------------------------------------------------------------------
-- Anti AFK
---------------------------------------------------------------------
track(LocalPlayer.Idled:Connect(function()
    if not cfg.antiAfk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end))

task.spawn(function()
    -- дополнительная защита: лёгкий «пинг» раз в 4 минуты
    while State.Alive do
        task.wait(240)
        if cfg.antiAfk then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end
    end
end)

---------------------------------------------------------------------
-- Auto Execute
---------------------------------------------------------------------
local queueFn = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local queued = false

local function buildQueueSource()
    local loader
    if SELF_URL ~= "" then
        loader = ("loadstring(game:HttpGet(%q))()"):format(SELF_URL)
    elseif FS_OK and isfile(MAIN_FILE) then
        loader = ("loadstring(readfile(%q))()"):format(MAIN_FILE)
    else
        return nil
    end
    return ([[
if not game:IsLoaded() then game.Loaded:Wait() end
local okc, c = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(%q)) end)
if okc and type(c) == "table" and c.autoExecute then
    task.wait(2)
    %s
end
]]):format(SETTINGS_FILE, loader)
end

local function queueSelf(showNotify)
    if queued then return true end
    if not queueFn then
        if showNotify then notify("Auto Execute", "Executor не поддерживает queue_on_teleport", 4) end
        return false
    end
    local src = buildQueueSource()
    if not src then
        if showNotify then
            notify("Auto Execute", "Укажи SELF_URL в скрипте или сохрани его как\n" .. MAIN_FILE, 6)
        end
        return false
    end
    queued = true
    pcall(queueFn, src)
    if showNotify then notify("Auto Execute", "Скрипт будет запущен после телепорта", 3) end
    return true
end

track(LocalPlayer.OnTeleport:Connect(function()
    if cfg.autoExecute then queueSelf(false) end
end))

---------------------------------------------------------------------
-- Auto Skip / Auto Vote / Auto Replay
---------------------------------------------------------------------
local function inWaveRange(w)
    local a, b = pcfg.waveFrom or 1, pcfg.waveTo or 250
    if a > b then a, b = b, a end
    return w >= a and w <= b
end

task.spawn(function()
    local lastWave, tries, lastClick, voteBefore = -1, 0, 0, 0
    local voteDone, voteShownAt = false, 0
    local replayDone, replayShownAt = false, 0

    while State.Alive do
        task.wait(0.25)
        pcall(function()
            ------------------------------------------------ Skip
            if pcfg.autoSkip then
                local md = getMatchData()
                local cw  = md and md:FindFirstChild("CurrentWave")
                local csk = md and md:FindFirstChild("CanSkip")
                local vsp = md and md:FindFirstChild("VoteSkipPlayers")
                if cw and csk then
                    local wave = cw.Value
                    if wave ~= lastWave then lastWave, tries, lastClick = wave, 0, 0 end
                    if inWaveRange(wave) and csk.Value and tries < 3 and os.clock() - lastClick >= 2.5 then
                        -- повторяем только если голос не засчитался
                        if tries == 0 or (vsp and vsp.Value <= voteBefore) or not vsp then
                            local clicked = false
                            if pcfg.skipPos then
                                clicked = clickSaved(pcfg.skipPos)
                            else
                                local btn = getGui("Match", "TopFrame", "SkipWave")
                                if btn and isShown(btn) then clicked = clickAt(guiCenter(btn), 0) end
                            end
                            if clicked then
                                tries = tries + 1
                                lastClick = os.clock()
                                voteBefore = vsp and vsp.Value or 0
                            end
                        end
                    end
                end
            end

            ------------------------------------------------ Vote
            local vf = getGui("VotingFrame", "VoteFrame")
            if pcfg.autoVote and vf and isShown(vf) then
                if voteShownAt == 0 then voteShownAt = os.clock() end
                if not voteDone and pcfg.votePos then
                    voteDone = true
                    task.delay(0.8, function() clickSaved(pcfg.votePos) end)
                elseif voteDone and os.clock() - voteShownAt > 7 then
                    voteDone, voteShownAt = false, os.clock() -- повтор, если окно не закрылось
                end
            else
                voteDone, voteShownAt = false, 0
            end

            ------------------------------------------------ Replay
            local mf = getGui("Match", "MatchFinish")
            if pcfg.autoReplay and mf and isShown(mf) then
                if replayShownAt == 0 then replayShownAt = os.clock() end
                if not replayDone then
                    replayDone = true
                    task.delay(2.5, function()
                        if pcfg.replayPos then
                            clickSaved(pcfg.replayPos)
                        else
                            local btn = getGui("Match", "MatchFinish", "MatchFinishFrame", "EndOptions", "PlayAgain")
                            if btn then clickAt(guiCenter(btn), 0) end
                        end
                    end)
                elseif os.clock() - replayShownAt > 9 then
                    replayDone, replayShownAt = false, os.clock()
                end
            else
                replayDone, replayShownAt = false, 0
            end
        end)
    end
end)

---------------------------------------------------------------------
-- UI (Rayfield)
---------------------------------------------------------------------
local Window = Rayfield:CreateWindow({
    Name = "BlackHoleHub_LTTD by ART1XL1S",
    LoadingTitle = "BlackHoleHub_LTTD",
    LoadingSubtitle = "by ART1XL1S",
    ConfigurationSaving = { Enabled = false },
    Discord = { Enabled = false },
    KeySystem = false,
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
})

local function optName(o)
    if type(o) == "table" then return o.Title or o.Name or o[1] end
    return o
end

local PlayerTab   = Window:CreateTab("Player", "user")
local MacrosTab   = Window:CreateTab("Macros", "video")
local SettingsTab = Window:CreateTab("Settings", "settings")

-------------------------------------------------- Player
PlayerTab:CreateSection("Auto Skip")
PlayerTab:CreateToggle({
    Name = "Auto Skip", CurrentValue = pcfg.autoSkip,
    Callback = function(v) pcfg.autoSkip = v saveAll() end,
})
PlayerTab:CreateButton({
    Name = "Запомнить кнопку Skip (5 сек)",
    Callback = function() capturePosition("skipPos", "Skip") end,
})
posParas.skipPos = PlayerTab:CreateLabel("Позиция Skip: " .. fmtPos(pcfg.skipPos))
PlayerTab:CreateSlider({
    Name = "Скипать с волны", Range = { 1, 250 }, Increment = 1, Suffix = "",
    CurrentValue = math.clamp(pcfg.waveFrom or 1, 1, 250),
    Callback = function(v) pcfg.waveFrom = math.floor(v) saveAll() end,
})
PlayerTab:CreateSlider({
    Name = "Скипать до волны", Range = { 1, 250 }, Increment = 1, Suffix = "",
    CurrentValue = math.clamp(pcfg.waveTo or 250, 1, 250),
    Callback = function(v) pcfg.waveTo = math.floor(v) saveAll() end,
})

PlayerTab:CreateSection("Auto Vote")
PlayerTab:CreateToggle({
    Name = "Auto Vote", CurrentValue = pcfg.autoVote,
    Callback = function(v) pcfg.autoVote = v saveAll() end,
})
PlayerTab:CreateButton({
    Name = "Запомнить кнопку Vote (5 сек)",
    Callback = function() capturePosition("votePos", "Vote") end,
})
posParas.votePos = PlayerTab:CreateLabel("Позиция Vote: " .. fmtPos(pcfg.votePos))

PlayerTab:CreateSection("Auto RePlay")
PlayerTab:CreateToggle({
    Name = "Auto RePlay", CurrentValue = pcfg.autoReplay,
    Callback = function(v) pcfg.autoReplay = v saveAll() end,
})
PlayerTab:CreateButton({
    Name = "Запомнить кнопку RePlay (5 сек)",
    Callback = function() capturePosition("replayPos", "RePlay") end,
})
posParas.replayPos = PlayerTab:CreateLabel("Позиция RePlay: " .. fmtPos(pcfg.replayPos))

-------------------------------------------------- Macros
local statusLabel = MacrosTab:CreateLabel("Статус: " .. (IN_GAME and "готов" or "ты в лобби"))
setStatus = function(text)
    pcall(function() statusLabel:Set("Статус: " .. tostring(text)) end)
end

MacrosTab:CreateSection("Создать / выбрать")

local newMacroName = ""
local MacroDropdown

local function refreshMacros(selectName)
    local list = listMacros()
    local values = #list > 0 and list or { NO_MACRO }
    if selectName then cfg.selectedMacro = selectName end
    if not table.find(values, cfg.selectedMacro) then
        cfg.selectedMacro = (values[1] ~= NO_MACRO) and values[1] or ""
    end
    if MacroDropdown then
        pcall(function() MacroDropdown:Refresh(values) end)
        pcall(function() MacroDropdown:Set({ cfg.selectedMacro ~= "" and cfg.selectedMacro or NO_MACRO }) end)
    end
    saveAll()
end

MacrosTab:CreateInput({
    Name = "Название макроса", PlaceholderText = "Например: Wave1_Setup",
    RemoveTextAfterFocusLost = false,
    Callback = function(txt) newMacroName = txt end,
})
MacrosTab:CreateButton({
    Name = "Создать макрос",
    Callback = function()
        local n = createMacro(newMacroName)
        if n then refreshMacros(n) end
    end,
})

do
    local initial = listMacros()
    local values = #initial > 0 and initial or { NO_MACRO }
    if not table.find(values, cfg.selectedMacro) then
        cfg.selectedMacro = (values[1] ~= NO_MACRO) and values[1] or ""
    end
    MacroDropdown = MacrosTab:CreateDropdown({
        Name = "Выбрать макрос", Options = values,
        CurrentOption = { cfg.selectedMacro ~= "" and cfg.selectedMacro or NO_MACRO },
        MultipleOptions = false,
        Callback = function(o)
            o = optName(o)
            if o and o ~= NO_MACRO then cfg.selectedMacro = o saveAll() end
        end,
    })
end
MacrosTab:CreateButton({ Name = "Обновить список", Callback = function() refreshMacros() end })

MacrosTab:CreateSection("Запись")
MacrosTab:CreateButton({
    Name = "● Записать",
    Callback = function() task.spawn(Recorder.start) end,
})
MacrosTab:CreateButton({
    Name = "■ Остановить запись и сохранить",
    Callback = function() Recorder.stop(true) end,
})

MacrosTab:CreateSection("Запуск")
MacrosTab:CreateButton({
    Name = "▶ Запустить макрос",
    Callback = function() Replay.start(cfg.selectedMacro) end,
})
MacrosTab:CreateButton({
    Name = "■ Остановить макрос",
    Callback = function() Replay.stop() end,
})
MacrosTab:CreateButton({
    Name = "Удалить выбранный макрос",
    Callback = function()
        local n = cfg.selectedMacro
        if n and n ~= "" and FS_OK and isfile(macroPath(n)) then
            pcall(delfile, macroPath(n))
            notify("Макрос", "Удалён: " .. n .. " (.bak сохранён)", 3)
            cfg.selectedMacro = ""
            refreshMacros()
        end
    end,
})

MacrosTab:CreateSection("Параметры макросов")
MacrosTab:CreateDropdown({
    Name = "Режим: Input (клики/клавиши) или Remote",
    Options = { "Input", "Remote" }, CurrentOption = { cfg.replayMode }, MultipleOptions = false,
    Callback = function(o) cfg.replayMode = optName(o) saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Повторять движение персонажа", CurrentValue = cfg.replayMove,
    Callback = function(v) cfg.replayMove = v saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Повторять камеру", CurrentValue = cfg.replayCamera,
    Callback = function(v) cfg.replayCamera = v saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Синхронизация по волнам", CurrentValue = cfg.waveGate,
    Callback = function(v) cfg.waveGate = v saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Повторять макрос по кругу", CurrentValue = cfg.loopMacro,
    Callback = function(v) cfg.loopMacro = v saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Авто-запуск макроса при входе в матч", CurrentValue = cfg.autoRunMacro,
    Callback = function(v) cfg.autoRunMacro = v saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Записывать движение мыши", CurrentValue = cfg.recordMouseMove,
    Callback = function(v) cfg.recordMouseMove = v saveAll() end,
})
MacrosTab:CreateSlider({
    Name = "Интервал записи, мс (1 = каждый кадр)", Range = { 1, 100 }, Increment = 1, Suffix = " мс",
    CurrentValue = math.clamp(cfg.sampleMs or 1, 1, 100),
    Callback = function(v) cfg.sampleMs = math.floor(v) saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Создавать .bak файл", CurrentValue = cfg.createBak,
    Callback = function(v) cfg.createBak = v saveAll() end,
})
MacrosTab:CreateToggle({
    Name = "Hook Remote (запись вызовов сервера)", CurrentValue = cfg.hookRemote,
    Callback = function(v)
        cfg.hookRemote = v saveAll()
        if v then
            if installHook() then notify("Hook", "Включён", 2) else notify("Hook", "Executor не поддерживает hookmetamethod", 4) end
        else
            notify("Hook", "Выключится полностью после перезахода", 3)
        end
    end,
})

-------------------------------------------------- Settings
SettingsTab:CreateSection("Основное")
SettingsTab:CreateToggle({
    Name = "Anti AFK", CurrentValue = cfg.antiAfk,
    Callback = function(v) cfg.antiAfk = v saveAll() end,
})
SettingsTab:CreateToggle({
    Name = "Auto Execute", CurrentValue = cfg.autoExecute,
    Callback = function(v)
        cfg.autoExecute = v
        saveAll()
        if v then task.delay(0.6, function() queueSelf(true) end) end
    end,
})

SettingsTab:CreateSection("Запись макросов")
SettingsTab:CreateDropdown({
    Name = "Горячая клавиша СТОП",
    Options = { "F6", "F7", "F8", "F9", "F10", "RightControl", "RightShift", "Delete", "End" },
    CurrentOption = { cfg.stopKey }, MultipleOptions = false,
    Callback = function(o) cfg.stopKey = optName(o) saveAll() end,
})
SettingsTab:CreateSlider({
    Name = "Отсчёт перед записью (сек)", Range = { 0, 10 }, Increment = 1, Suffix = " с",
    CurrentValue = math.clamp(cfg.countdown or 3, 0, 10),
    Callback = function(v) cfg.countdown = math.floor(v) saveAll() end,
})
SettingsTab:CreateToggle({
    Name = "Скрывать окно во время записи", CurrentValue = cfg.hideOnRecord,
    Callback = function(v) cfg.hideOnRecord = v saveAll() end,
})
SettingsTab:CreateSlider({
    Name = "Калибровка Y для кликов (px)", Range = { -60, 60 }, Increment = 1, Suffix = " px",
    CurrentValue = math.clamp(cfg.clickOffsetY or 0, -60, 60),
    Callback = function(v) cfg.clickOffsetY = math.floor(v) saveAll() end,
})

SettingsTab:CreateSection("Информация")
SettingsTab:CreateLabel("Папка: " .. ROOT .. "  (Player / Macros)")
SettingsTab:CreateLabel(("Место: %s | FS: %s | VIM: %s | queue: %s"):format(
    IN_GAME and "Игра" or (game.PlaceId == LOBBY_PLACE and "Лобби" or tostring(game.PlaceId)),
    FS_OK and "OK" or "нет", VIM and "OK" or "нет", queueFn and "OK" or "нет"))

refreshMacros()

---------------------------------------------------------------------
-- Авто-запуск макроса при входе в матч
---------------------------------------------------------------------
if cfg.autoExecute then queueSelf(false) end

if IN_GAME and cfg.autoRunMacro and cfg.selectedMacro ~= "" then
    task.spawn(function()
        local md = ReplicatedStorage:WaitForChild("MatchData", 30)
        if not md or not State.Alive then return end
        task.wait(3)
        if State.Alive and not Replay.playing and not Recorder.active then
            Replay.start(cfg.selectedMacro)
        end
    end)
end

---------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------
function State.Cleanup()
    State.Alive = false
    Recorder.active = false
    pcall(function() Replay.stop(true) end)
    for _, c in ipairs(State.Conns) do pcall(function() c:Disconnect() end) end
    genv.BHL_RemoteLogger = nil
    pcall(function() Rayfield:Destroy() end)
end

notify("BlackHoleHub_LTTD", "by ART1XL1S — загружено", 3)
