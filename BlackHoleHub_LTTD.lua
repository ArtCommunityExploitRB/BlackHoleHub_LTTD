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

local function pcMode() -- авто-определение устройства
    return not (UIS.TouchEnabled and not UIS.KeyboardEnabled)
end

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
    replayMode      = "Input",
    clickMode       = "Roblox", -- "Roblox" (VirtualInputManager) | "Human" (реальный курсор/клавиатура ОС)
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
    if not State.Alive then return end
    Recorder.downRec = {}

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

    notify("Запись", "● ИДЁТ ЗАПИСЬ «" .. name .. "»  (стоп: F8)", 3)
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

-- клик попал в окно Rayfield? (такие клики не пишем)
local rfMain
local function overUI(x, y)
    if not rfMain or not rfMain.Parent then
        rfMain = nil
        pcall(function()
            local root = (gethui and gethui()) or game:GetService("CoreGui")
            local g = root:FindFirstChild("Rayfield")
            rfMain = g and g:FindFirstChild("Main")
        end)
    end
    if not rfMain or not rfMain.Visible then return false end
    local pos, size = rfMain.AbsolutePosition, rfMain.AbsoluteSize
    local inset = GuiService:GetGuiInset()
    for _, off in ipairs({ Vector2.new(0, 0), inset }) do
        local p = pos + off
        if x >= p.X - 4 and x <= p.X + size.X + 4 and y >= p.Y - 4 and y <= p.Y + size.Y + 4 then
            return true
        end
    end
    return false
end

local function onInput(input, down)
    if not Recorder.active then return end
    local ut = input.UserInputType
    if ut == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Unknown then return end
        local kn = input.KeyCode.Name
        if pcMode() and (kn == "F8" or kn == "F5") then return end
        if UIS:GetFocusedTextBox() then return end
        Recorder.add({ type = "k", k = input.KeyCode.Name, s = down and 1 or 0 })
        return
    end
    local b = mouseButtonIndex(ut)
    if b then
        local p = inputToPos(input)
        local dr = Recorder.downRec
        if down then
            if overUI(p.x, p.y) then return end
            dr[b] = true
        else
            if not dr[b] then return end -- «отпускание» без нажатия не пишем
            dr[b] = nil
        end
        Recorder.add({ type = "mb", b = b, s = down and 1 or 0, x = p.x, y = p.y, rx = p.rx, ry = p.ry })
    end
end

track(UIS.InputBegan:Connect(function(input)
    -- горячая клавиша остановки записи / воспроизведения
    if pcMode() and input.UserInputType == Enum.UserInputType.Keyboard
        and not UIS:GetFocusedTextBox() then
        local kn = input.KeyCode.Name
        if kn == "F8" then -- запись: старт/стоп мгновенно
            if Recorder.active then Recorder.stop(false) else task.spawn(Recorder.start) end
            return
        elseif kn == "F5" then -- макрос: запуск/стоп
            if Replay.playing then Replay.stop() else Replay.start(cfg.selectedMacro) end
            return
        end
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
        if overUI(p.x, p.y) then return end
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

-- Способ ввода: "Roblox" = VirtualInputManager (внутри Roblox, не двигает реальный курсор)
--               "Human"  = реальный курсор и клавиатура ОС (mousemoveabs/mouse1press/keypress), только ПК
local HUMAN_OK = (mousemoveabs and mouse1press and mouse1release) and true or false
local function humanMode()
    return cfg.clickMode == "Human" and HUMAN_OK and pcMode()
end

local VK = {
    Space = 0x20, Return = 0x0D, Tab = 0x09, Backspace = 0x08, Escape = 0x1B,
    LeftShift = 0xA0, RightShift = 0xA1, LeftControl = 0xA2, RightControl = 0xA3,
    LeftAlt = 0xA4, RightAlt = 0xA5, Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28,
    Delete = 0x2E, End = 0x23, Home = 0x24, PageUp = 0x21, PageDown = 0x22, Insert = 0x2D,
    Backquote = 0xC0, Minus = 0xBD, Equals = 0xBB, Comma = 0xBC, Period = 0xBE, Slash = 0xBF,
    One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, Five = 0x35,
    Six = 0x36, Seven = 0x37, Eight = 0x38, Nine = 0x39, Zero = 0x30,
}
local function vkOf(kc)
    local n = kc.Name
    if #n == 1 and n:match("%a") then return string.byte(n:upper()) end
    local f = n:match("^F(%d+)$")
    if f and tonumber(f) >= 1 and tonumber(f) <= 12 then return 0x6F + tonumber(f) end
    return VK[n]
end

local function sendMouseMove(pos)
    if humanMode() then
        pcall(mousemoveabs, pos.X, pos.Y)
    elseif VIM then
        VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
    end
end

local function sendMouseButton(b, down, pos)
    local hp, hr
    if b == 1 then hp, hr = mouse1press, mouse1release
    elseif b == 2 then hp, hr = mouse2press, mouse2release end
    if humanMode() and hp and hr then
        pcall(mousemoveabs, pos.X, pos.Y)
        -- небольшая задержка, как у человека: курсор успевает прийти в точку
        task.delay(0.015, function() pcall(down and hp or hr) end)
    elseif VIM then
        VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, b - 1, down, game, 0)
    end
end

local function sendKey(kc, down)
    local vk = humanMode() and keypress and keyrelease and vkOf(kc)
    if vk then
        pcall(down and keypress or keyrelease, vk)
    elseif VIM then
        VIM:SendKeyEvent(down, kc, false, game)
    end
end

local function sendWheel(pos, d)
    if humanMode() and mousescroll then
        pcall(mousescroll, d > 0 and 120 or -120)
    elseif VIM then
        VIM:SendMouseWheelEvent(pos.X, pos.Y, d > 0, game)
    end
end

local function releaseAll()
    for kc in pairs(heldKeys) do pcall(sendKey, kc, false) end
    for b, pos in pairs(heldMouse) do pcall(sendMouseButton, b, false, pos) end
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

    if remoteMode or (not VIM and not humanMode()) then return end

    if ty == "k" then
        local ok, kc = pcall(function() return Enum.KeyCode[ev.k] end)
        if ok and kc then
            if ev.s == 1 then heldKeys[kc] = true else heldKeys[kc] = nil end
            sendKey(kc, ev.s == 1)
        end
    elseif ty == "mb" then
        local pos = toScreen(ev.rx, ev.ry)
        sendMouseButton(ev.b, ev.s == 1, pos)
        if ev.s == 1 then heldMouse[ev.b] = pos else heldMouse[ev.b] = nil end
    elseif ty == "mm" then
        sendMouseMove(toScreen(ev.rx, ev.ry))
    elseif ty == "wh" then
        sendWheel(toScreen(ev.rx, ev.ry), ev.d or 0)
    end
end

function Replay.start(name)
    if Replay.playing then Replay.stop(true) end
    if Recorder.active or Recorder.countingDown then notify("Макрос", "Идёт запись", 3) return end
    cfg.replayMode = "Input"
    local macro = loadMacro(name)
    if not macro or type(macro.events) ~= "table" or #macro.events == 0 then
        notify("Макрос", "Макрос пуст или не найден", 3) return
    end
    local events = macro.events
    table.sort(events, function(a, b) return (a.t or 0) < (b.t or 0) end)

    if not VIM and not humanMode() then
        notify("Макрос", "Нет способа ввода (VirtualInputManager недоступен)", 4) return
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
    if Recorder.active then Recorder.stop(false) end -- не теряем запись при телепорте
    if cfg.autoExecute then queueSelf(false) end
end))

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

local MacrosTab   = Window:CreateTab("Macros", "video")
local SettingsTab = Window:CreateTab("Settings", "settings")

-------------------------------------------------- Macros
local newMacroName = ""
local MacroDropdown
local statusLabel

setStatus = function(text)
    if statusLabel then pcall(function() statusLabel:Set(tostring(text)) end) end
end

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
    Name = "Macros Name", PlaceholderText = "Название макроса",
    RemoveTextAfterFocusLost = false,
    Callback = function(txt) newMacroName = txt end,
})
MacrosTab:CreateButton({
    Name = "Create",
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
        Name = "Select", Options = values,
        CurrentOption = { cfg.selectedMacro ~= "" and cfg.selectedMacro or NO_MACRO },
        MultipleOptions = false,
        Callback = function(o)
            o = optName(o)
            if o and o ~= NO_MACRO then cfg.selectedMacro = o saveAll() end
        end,
    })
end

-- ПК: только F8 (запись) / F5 (запуск) — кнопки меню не работают, чтобы клик не включал запись.
-- Телефон: работают кнопки.
local function buttonsAllowed()
    if pcMode() then
        notify("Macros", "ПК: F8 — запись, F5 — запуск/стоп", 3)
        return false
    end
    return true
end

MacrosTab:CreateButton({
    Name = "Record",
    Callback = function()
        if not buttonsAllowed() then return end
        if Recorder.active then Recorder.stop(true) else task.spawn(Recorder.start) end
    end,
})
MacrosTab:CreateButton({
    Name = "Play",
    Callback = function()
        if not buttonsAllowed() then return end
        if Recorder.active then notify("Macros", "Идёт запись — сначала останови", 3) return end
        if Replay.playing then Replay.stop() else Replay.start(cfg.selectedMacro) end
    end,
})

MacrosTab:CreateDropdown({
    Name = "Click: Roblox / Human (реальный курсор, ПК)",
    Options = { "Roblox", "Human" }, CurrentOption = { cfg.clickMode == "Human" and "Human" or "Roblox" },
    MultipleOptions = false,
    Callback = function(o)
        local m = optName(o)
        if m == "Human" and not (HUMAN_OK and pcMode()) then
            cfg.clickMode = "Roblox"
            notify("Click", "Human недоступен (нужен ПК и mousemoveabs/mouse1press) — оставил Roblox", 4)
        else
            cfg.clickMode = m
            if m == "Human" then notify("Click", "Human: окно Roblox должно быть в полноэкранном режиме (F11)", 4) end
        end
        saveAll()
    end,
})
MacrosTab:CreateToggle({
    Name = "Auto Execute", CurrentValue = cfg.autoExecute,
    Callback = function(v)
        cfg.autoExecute = v
        saveAll()
        if v then task.delay(0.6, function() queueSelf(true) end) end
    end,
})
MacrosTab:CreateToggle({
    Name = "AutoPlay every match", CurrentValue = cfg.autoRunMacro,
    Callback = function(v) cfg.autoRunMacro = v saveAll() end,
})
statusLabel = MacrosTab:CreateLabel(pcMode() and "ПК: F8 запись | F5 запуск/стоп" or "Телефон: кнопки Record / Play")

-------------------------------------------------- Settings
SettingsTab:CreateToggle({
    Name = "Anti AFK", CurrentValue = cfg.antiAfk,
    Callback = function(v) cfg.antiAfk = v saveAll() end,
})
SettingsTab:CreateSlider({
    Name = "Калибровка Y для кликов (px)", Range = { -60, 60 }, Increment = 1, Suffix = " px",
    CurrentValue = math.clamp(cfg.clickOffsetY or 0, -60, 60),
    Callback = function(v) cfg.clickOffsetY = math.floor(v) saveAll() end,
})

refreshMacros()

---------------------------------------------------------------------
-- Авто-запуск макроса при входе в матч
---------------------------------------------------------------------
if cfg.autoExecute then queueSelf(false) end

-- AutoPlay every match: скрипт только загрузился в матче -> через 5 сек запускаем выбранный макрос
if IN_GAME and cfg.autoRunMacro and cfg.selectedMacro ~= "" then
    task.spawn(function()
        task.wait(5)
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
