--[[
    BlackHoleHub_LTTD  by  ART1XL1S      (UI: Rayfield)
    Игра: Legacy   PlaceId игры 131703399727686 | лобби 93712201161812

    Папка MacrosBHL_LTTD/
        Player/Settings.json   настройки скрипта
        Player/Player.json     выбранный макрос, AutoPlay
        Macros/<имя>.json      макрос (Actions: Place / Upgrade / Target / Sell / Skip / Vote ...)
        Macros/<имя>.bak       резервная копия

    ПК:      F8 = запись старт/стоп, F5 = запуск/стоп макроса
    Телефон: кнопки Record / Play

    Для Auto Execute: SELF_URL (raw-ссылка на этот файл) ИЛИ файл MacrosBHL_LTTD/BlackHoleHub_LTTD.lua
]]

local SELF_URL = "https://raw.githubusercontent.com/ArtCommunityExploitRB/BlackHoleHub_LTTD/refs/heads/main/BlackHoleHub_LTTD.lua"

if not game:IsLoaded() then game.Loaded:Wait() end

local genv = (getgenv and getgenv()) or _G
if genv.BHL_LTTD and type(genv.BHL_LTTD.Cleanup) == "function" then
    pcall(genv.BHL_LTTD.Cleanup)
end
local State = { Alive = true, Conns = {} }
genv.BHL_LTTD = State
local function track(c) State.Conns[#State.Conns + 1] = c return c end

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

-- Устройство определяется автоматически
local function pcMode()
    return not (UIS.TouchEnabled and not UIS.KeyboardEnabled)
end

---------------------------------------------------------------------
-- Файлы
---------------------------------------------------------------------
local ROOT          = "MacrosBHL_LTTD"
local PLAYER_DIR    = ROOT .. "/Player"
local MACROS_DIR    = ROOT .. "/Macros"
local SETTINGS_FILE = PLAYER_DIR .. "/Settings.json"
local PLAYER_FILE   = PLAYER_DIR .. "/Player.json"
local MAIN_FILE     = ROOT .. "/BlackHoleHub_LTTD.lua"

local FS_OK = (writefile and readfile and isfile and isfolder and makefolder) and true or false
if FS_OK then
    for _, d in ipairs({ ROOT, PLAYER_DIR, MACROS_DIR }) do
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
    return (pcall(function() writefile(path, HttpService:JSONEncode(data)) end))
end

local function mergeDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

local NO_MACRO = "(нет макросов)"

local cfg = mergeDefaults(readJson(SETTINGS_FILE, {}), {
    antiAfk      = true,
    autoExecute  = false,
    clickMode    = "Roblox", -- "Roblox" (внутри игры) | "Human" (реальный курсор ПК)
    clickOffsetY = 0,
})
local pcfg = mergeDefaults(readJson(PLAYER_FILE, {}), {
    selectedMacro = "",
    autoPlay      = false,
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
-- Утилиты
---------------------------------------------------------------------
local Rayfield -- загружается позже, в потоке интерфейса
local function notify(title, content, duration)
    if not Rayfield then return end
    pcall(function()
        Rayfield:Notify({ Title = tostring(title), Content = tostring(content or ""), Duration = duration or 3 })
    end)
end

local setStatus = function() end

local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end

local function curWave()
    local md = ReplicatedStorage:FindFirstChild("MatchData")
    local v = md and md:FindFirstChild("CurrentWave")
    return v and v.Value or 0
end

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

local function toScreen(rx, ry)
    local vp = viewport()
    return Vector2.new(rx * vp.X, ry * vp.Y + (cfg.clickOffsetY or 0))
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

-- точка внутри GUI-объекта (ox, oy от 0 до 1) в координатах экрана
local function guiPoint(obj, ox, oy)
    local ap, sz = obj.AbsolutePosition, obj.AbsoluteSize
    local pos = Vector2.new(ap.X + sz.X * ox, ap.Y + sz.Y * oy)
    local sg = obj:FindFirstAncestorOfClass("ScreenGui")
    if sg and not sg.IgnoreGuiInset then pos = pos + GuiService:GetGuiInset() end
    return pos
end

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

local function resolveFrom(root, path)
    local cur = root
    for _, n in ipairs(path) do
        cur = cur and cur:FindFirstChild(n)
        if not cur then return nil end
    end
    return cur
end

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
    local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then return false end
    local path = macroPath(name)
    -- .bak = предыдущая версия файла (если была), иначе копия текущей
    local bak = json
    if isfile(path) then
        local okr, old = pcall(readfile, path)
        if okr and old and #old > 50 then bak = old end
    end
    pcall(writefile, macroBak(name), bak)
    return (pcall(writefile, path, json))
end

local function loadMacro(name)
    if not name or name == "" or name == NO_MACRO then return nil end
    return readJson(macroPath(name), nil)
end

local function newMacroData(name)
    local vp = viewport()
    return {
        Name = name, Game = "LegacyTD", Version = 2, Created = os.time(),
        Device = pcMode() and "PC" or "Mobile",
        Viewport = { X = vp.X, Y = vp.Y },
        TimeOrigin = "Start", TimeBasis = "Seconds",
        Duration = 0, ActionCount = 0, Actions = {},
    }
end

local function createMacro(name)
    name = sanitize(name)
    if name == "" then notify("Macros", "Введи название макроса", 3) return nil end
    if FS_OK and isfile(macroPath(name)) then notify("Macros", "«" .. name .. "» уже существует", 3) return nil end
    if not saveMacro(name, newMacroData(name)) then notify("Macros", "Не удалось создать файл", 3) return nil end
    notify("Macros", "Создан: " .. name, 3)
    return name
end

---------------------------------------------------------------------
-- Поиск целей клика: GUI-кнопка / точка в мире / юнит
---------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function guiPathOf(obj)
    local p, cur = {}, obj
    while cur and cur ~= PlayerGui do
        table.insert(p, 1, cur.Name)
        cur = cur.Parent
    end
    if cur ~= PlayerGui then return nil end
    return p
end

-- реальные элементы интерфейса, а не прозрачные контейнеры
local function meaningful(o)
    if o:IsA("GuiButton") then return true end
    if o:IsA("TextLabel") then return o.Text ~= "" end
    if o:IsA("ImageLabel") then return o.ImageTransparency < 1 end
    return o.BackgroundTransparency < 1
end

-- возвращает путь к самому «точному» элементу под курсором и смещение внутри него
local function guiTargetAt(x, y)
    local vp = viewport()
    local inset = GuiService:GetGuiInset()
    local best, bestBtn
    for _, ignore in ipairs({ false, true }) do
        local ok, list = pcall(function()
            return PlayerGui:GetGuiObjectsAtPosition(x, ignore and y or (y - inset.Y))
        end)
        if ok and list then
            for _, o in ipairs(list) do
                local sg = o:FindFirstAncestorOfClass("ScreenGui")
                local sz = o.AbsoluteSize
                if sg and sg.IgnoreGuiInset == ignore and sz.X > 0 and sz.Y > 0
                    and sz.X < vp.X * 0.6 and sz.Y < vp.Y * 0.6 and meaningful(o) then
                    local area = sz.X * sz.Y
                    local item = { o = o, a = area, gy = ignore and y or (y - inset.Y) }
                    if o:IsA("GuiButton") and (not bestBtn or area < bestBtn.a) then bestBtn = item end
                    if not best or area < best.a then best = item end
                end
            end
        end
    end
    local pick = bestBtn or best
    if not pick then return nil end
    local o = pick.o
    local ap, sz = o.AbsolutePosition, o.AbsoluteSize
    local ox = math.clamp((x - ap.X) / sz.X, 0, 1)
    local oy = math.clamp((pick.gy - ap.Y) / sz.Y, 0, 1)
    return guiPathOf(o), { r3(ox), r3(oy) }
end

local function worldInfo(x, y)
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local ok, res = pcall(function()
        local filter = {}
        local char = LocalPlayer.Character
        if char then filter[#filter + 1] = char end
        local pm = workspace:FindFirstChild("PlacingModels")
        if pm then filter[#filter + 1] = pm end
        rayParams.FilterDescendantsInstances = filter
        local ray = cam:ViewportPointToRay(x, y)
        local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
        local pt = hit and hit.Position or (ray.Origin + ray.Direction * 500)
        local info = { Pos = { r3(pt.X), r3(pt.Y), r3(pt.Z) } }
        local troops = workspace:FindFirstChild("Troops")
        if hit and troops then
            local cur = hit.Instance
            while cur and cur ~= workspace do
                if cur.Parent == troops then
                    local pv = cur:GetPivot().Position
                    info.Model = cur
                    info.UnitPos = { r3(pv.X), r3(pv.Y), r3(pv.Z) }
                    info.Off = { r3(pt.X - pv.X), r3(pt.Y - pv.Y), r3(pt.Z - pv.Z) }
                    break
                end
                cur = cur.Parent
            end
        end
        return info
    end)
    return ok and res or nil
end

-- Вид действия по GUI-элементу
local function classifyGui(path)
    local s = table.concat(path, "/")
    if s:find("SkipWave") then return "Skip" end
    if s:find("AutoSkip") then return "AutoSkip" end
    if path[1] == "VotingFrame" or s:find("VoteFrame") then return "Vote" end
    if s:find("PlayAgain") then return "PlayAgain" end
    if s:find("ReturnToLobby") then return "Lobby" end
    if s:find("Upgrade") then return "Upgrade" end
    if s:find("Target") then return "Target" end
    if s:find("Sell") then return "Sell" end
    if s:find("Troop%d") then return "Slot" end
    return "Click"
end

---------------------------------------------------------------------
-- Ввод (воспроизведение): Roblox / Human / Touch
---------------------------------------------------------------------
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

local heldKeys = {}

local function sendKey(kc, down)
    local vk = humanMode() and keypress and keyrelease and vkOf(kc)
    if vk then
        pcall(down and keypress or keyrelease, vk)
    elseif VIM then
        pcall(function() VIM:SendKeyEvent(down, kc, false, game) end)
    end
end

local function sendMouse(button, down, pos)
    local hp, hr
    if button == 1 then hp, hr = mouse1press, mouse1release
    elseif button == 2 then hp, hr = mouse2press, mouse2release end
    if humanMode() and hp and hr then
        pcall(mousemoveabs, pos.X, pos.Y)
        pcall(down and hp or hr)
    elseif VIM then
        pcall(function()
            VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
            VIM:SendMouseButtonEvent(pos.X, pos.Y, button - 1, down, game, 0)
        end)
    end
end

local function sendMove(pos)
    if humanMode() then
        pcall(mousemoveabs, pos.X, pos.Y)
    elseif VIM then
        pcall(function() VIM:SendMouseMoveEvent(pos.X, pos.Y, game) end)
    end
end

local function sendWheel(pos, d)
    if humanMode() and mousescroll then
        pcall(mousescroll, d > 0 and 120 or -120)
    elseif VIM then
        pcall(function() VIM:SendMouseWheelEvent(pos.X, pos.Y, d > 0, game) end)
    end
end

-- клик с задержкой (курсор успевает прийти в точку) — в отдельном потоке
local function doClick(pos, button, hold)
    task.spawn(function()
        local touched = false
        if (not pcMode()) and VIM and button == 1 and not humanMode() then
            touched = pcall(function() VIM:SendTouchEvent(1, 0, pos.X, pos.Y) end)
        end
        if not touched then
            sendMove(pos)
            task.wait(0.04)
            sendMouse(button, true, pos)
        end
        task.wait(math.max(hold or 0, 0.04))
        if touched then
            pcall(function() VIM:SendTouchEvent(1, 2, pos.X, pos.Y) end)
        else
            sendMouse(button, false, pos)
        end
    end)
end

local function doKey(kc, hold)
    task.spawn(function()
        heldKeys[kc] = true
        sendKey(kc, true)
        task.wait(math.max(hold or 0, 0.03))
        sendKey(kc, false)
        heldKeys[kc] = nil
    end)
end

---------------------------------------------------------------------
-- Запись
---------------------------------------------------------------------
local Recorder = {
    active = false, starting = false, t0 = 0, actions = {},
    pendClick = {}, pendKey = {}, unitKey = {}, nextKey = 0,
    selectedKey = nil, lastWorld = nil, lastWorldClock = 0,
    lastMove = nil, lastCam = nil,
}
local Replay = { playing = false, token = 0, sameView = false, cross = false }

local function nowSec() return math.floor((os.clock() - Recorder.t0) * 1000 + 0.5) / 1000 end

local function addAction(a)
    a.Time = nowSec()
    a.Wave = curWave()
    Recorder.actions[#Recorder.actions + 1] = a
    return a
end

local function unitKeyFor(model)
    local k = Recorder.unitKey[model]
    if not k then
        Recorder.nextKey = Recorder.nextKey + 1
        k = "T" .. Recorder.nextKey
        Recorder.unitKey[model] = k
    end
    return k
end

-- Rayfield-окно: клики по нему не пишем
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
        if x >= p.X - 6 and x <= p.X + size.X + 6 and y >= p.Y - 6 and y <= p.Y + size.Y + 6 then
            return true
        end
    end
    return false
end

function Recorder.start()
    if Recorder.active or Recorder.starting then return end
    if Replay.playing then notify("Запись", "Сначала останови макрос", 3) return end
    local name = pcfg.selectedMacro
    if not name or name == "" or name == NO_MACRO then
        notify("Запись", "Сначала создай и выбери макрос", 3) return
    end
    if not FS_OK then notify("Запись", "Executor без writefile", 4) return end

    Recorder.actions, Recorder.pendClick, Recorder.pendKey = {}, {}, {}
    Recorder.unitKey, Recorder.nextKey, Recorder.selectedKey = {}, 0, nil
    Recorder.lastWorld, Recorder.lastMove, Recorder.lastCam = nil, nil, nil
    Recorder.t0 = os.clock()
    Recorder.name = name
    Recorder.active = true

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        Recorder.lastMove = comps12(hrp.CFrame)
        addAction({ Kind = "Move", CFrame = Recorder.lastMove })
    end
    local cam = workspace.CurrentCamera
    if cam then
        Recorder.lastCam = comps12(cam.CFrame)
        addAction({ Kind = "Camera", CFrame = Recorder.lastCam })
    end
    notify("Запись", "● ИДЁТ ЗАПИСЬ «" .. name .. "»", 3)
    setStatus("● Запись: " .. name)
end

function Recorder.stop(byUi)
    if not Recorder.active then return end
    Recorder.active = false
    local endT = nowSec()

    -- закрываем незавершённые нажатия
    for _, a in pairs(Recorder.pendClick) do a.Hold = r3(math.max(endT - a.Time, 0.05)) end
    for _, a in pairs(Recorder.pendKey) do a.Hold = r3(math.max(endT - a.Time, 0.05)) end
    Recorder.pendClick, Recorder.pendKey = {}, {}

    local actions = Recorder.actions
    if byUi then
        -- вырезаем клик по кнопке «Record» (последние 0.6 сек)
        local clean = {}
        for _, a in ipairs(actions) do
            if not (a.Button and a.Time >= endT - 0.6) then clean[#clean + 1] = a end
        end
        actions = clean
    end

    local data = newMacroData(Recorder.name)
    local md = ReplicatedStorage:FindFirstChild("MatchData")
    local mapId = md and md:FindFirstChild("MapId")
    data.Map = mapId and mapId.Value or nil
    data.Duration = endT
    data.ActionCount = #actions
    data.Actions = actions

    local ok = saveMacro(Recorder.name, data)
    if ok then
        notify("Запись", ("■ Сохранено «%s»: %d действий, %.0f сек"):format(Recorder.name, #actions, endT), 4)
    else
        notify("Запись", "Ошибка сохранения!", 4)
    end
    setStatus(("Сохранено: %s (%d действий)"):format(Recorder.name, #actions))
    Recorder.actions = {}
end

-- каждый кадр: движение и камера
track(RunService.Heartbeat:Connect(function()
    if not Recorder.active then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local c = comps12(hrp.CFrame)
        if not sameComps(c, Recorder.lastMove) then
            Recorder.lastMove = c
            addAction({ Kind = "Move", CFrame = c })
        end
    end
    local cam = workspace.CurrentCamera
    if cam then
        local c = comps12(cam.CFrame)
        if not sameComps(c, Recorder.lastCam) then
            Recorder.lastCam = c
            addAction({ Kind = "Camera", CFrame = c })
        end
    end
end))

local function buttonIndex(ut)
    if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then return 1 end
    if ut == Enum.UserInputType.MouseButton2 then return 2 end
    if ut == Enum.UserInputType.MouseButton3 then return 3 end
    return nil
end

local function onInput(input, down, gp)
    if not Recorder.active then return end
    local ut = input.UserInputType

    if ut == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Unknown then return end
        local kn = input.KeyCode.Name
        if pcMode() and (kn == "F8" or kn == "F5") then return end
        if UIS:GetFocusedTextBox() then return end
        if down then
            local a = addAction({ Kind = "Key", Key = kn, Hold = 0 })
            Recorder.pendKey[kn] = a
        else
            local a = Recorder.pendKey[kn]
            if a then a.Hold = r3(math.max(nowSec() - a.Time, 0.03)) Recorder.pendKey[kn] = nil end
        end
        return
    end

    local b = buttonIndex(ut)
    if not b then return end
    local p = inputToPos(input)

    if down then
        if overUI(p.x, p.y) then return end
        local gui, go = guiTargetAt(p.x, p.y)
        -- тач, который съела игра и не привязан к кнопке (джойстик, прыжок) — пропускаем
        if ut == Enum.UserInputType.Touch and gp and not gui then return end

        local a = { Kind = "Click", Button = b, Hold = 0, Rx = p.rx, Ry = p.ry, X = p.x, Y = p.y }
        if gui then
            a.Gui, a.Go = gui, go
            a.Kind = classifyGui(gui)
            if a.Kind == "Vote" then a.Name = gui[#gui] end
            if a.Kind == "Upgrade" or a.Kind == "Target" or a.Kind == "Sell" then a.Key = Recorder.selectedKey end
        else
            local w = worldInfo(p.x, p.y)
            if w then
                a.Pos = w.Pos
                if w.Model then
                    a.Kind = "Select"
                    a.Key = unitKeyFor(w.Model)
                    a.Name = w.Model.Name
                    a.UnitPos, a.Off = w.UnitPos, w.Off
                    Recorder.selectedKey = a.Key
                else
                    Recorder.lastWorld, Recorder.lastWorldClock = a, os.clock()
                end
            end
        end
        addAction(a)
        Recorder.pendClick[b] = a
    else
        local a = Recorder.pendClick[b]
        if a then
            a.Hold = r3(math.max(nowSec() - a.Time, 0.04))
            Recorder.pendClick[b] = nil
        end
    end
end

-- Новый юнит в Workspace.Troops сразу после клика по земле = Place
if IN_GAME then
    task.spawn(function()
        local troops = workspace:WaitForChild("Troops", 15)
        if not troops or not State.Alive then return end
        track(troops.ChildAdded:Connect(function(child)
            if not Recorder.active then return end
            local a = Recorder.lastWorld
            if not a or os.clock() - Recorder.lastWorldClock > 2.5 then return end
            Recorder.lastWorld = nil
            task.wait(0.1)
            pcall(function()
                local pv = child:GetPivot().Position
                a.Kind = "Place"
                a.Name = child.Name
                a.Key = unitKeyFor(child)
                a.UnitPos = { r3(pv.X), r3(pv.Y), r3(pv.Z) }
                Recorder.selectedKey = a.Key
            end)
        end))
    end)
end

---------------------------------------------------------------------
-- Воспроизведение
---------------------------------------------------------------------
local prevCamType

function Replay.stop(silent)
    if not Replay.playing then return end
    Replay.playing = false
    Replay.token = Replay.token + 1
    if Replay.conn then Replay.conn:Disconnect() Replay.conn = nil end
    for kc in pairs(heldKeys) do sendKey(kc, false) end
    heldKeys = {}
    local cam = workspace.CurrentCamera
    if cam and prevCamType then pcall(function() cam.CameraType = prevCamType end) end
    prevCamType = nil
    if not silent then notify("Macros", "■ Остановлено", 2) end
    setStatus("Остановлено")
end

-- Куда кликнуть на ЭТОМ экране
local function resolveClick(a)
    -- тот же размер окна: просто повторяем точку записи
    if Replay.sameView and a.Rx and a.Ry then return toScreen(a.Rx, a.Ry) end

    local off = Vector2.new(0, cfg.clickOffsetY or 0)

    -- 1) кнопка интерфейса (Skip / Vote / Upgrade / Target / Slot ...)
    if a.Gui then
        local obj = resolveFrom(PlayerGui, a.Gui)
        if obj and obj:IsA("GuiObject") and isShown(obj) then
            local ox = a.Go and a.Go[1] or 0.5
            local oy = a.Go and a.Go[2] or 0.5
            return guiPoint(obj, ox, oy) + off
        end
        if a.Rx and a.Ry then return toScreen(a.Rx, a.Ry) end
        return nil
    end

    local cam = workspace.CurrentCamera
    if not cam then return nil end

    -- 2) юнит: ищем его заново рядом с записанной позицией
    if a.UnitPos then
        local troops = workspace:FindFirstChild("Troops")
        if troops then
            local want = Vector3.new(a.UnitPos[1], a.UnitPos[2], a.UnitPos[3])
            local best, bestD
            for _, m in ipairs(troops:GetChildren()) do
                local okp, pv = pcall(function() return m:GetPivot().Position end)
                if okp then
                    local d = (pv - want).Magnitude
                    if d < 8 and (not bestD or d < bestD) and (not a.Name or m.Name == a.Name) then
                        best, bestD = pv, d
                    end
                end
            end
            if best then
                local o = a.Off and Vector3.new(a.Off[1], a.Off[2], a.Off[3]) or Vector3.zero
                local v, on = cam:WorldToViewportPoint(best + o)
                if on and v.Z > 0 then return Vector2.new(v.X, v.Y) + off end
            end
        end
    end

    -- 3) точка в мире (постановка юнита и т.п.)
    if a.Pos then
        local v, on = cam:WorldToViewportPoint(Vector3.new(a.Pos[1], a.Pos[2], a.Pos[3]))
        if on and v.Z > 0 then return Vector2.new(v.X, v.Y) + off end
    end

    if a.Rx and a.Ry then return toScreen(a.Rx, a.Ry) end
    return nil
end

local function execAction(a)
    local k = a.Kind
    if k == "Move" then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and a.CFrame then hrp.CFrame = CFrame.new(unpack(a.CFrame)) end
    elseif k == "Camera" then
        local cam = workspace.CurrentCamera
        if cam and a.CFrame then
            if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
            cam.CFrame = CFrame.new(unpack(a.CFrame))
        end
    elseif k == "Key" then
        local ok, kc = pcall(function() return Enum.KeyCode[a.Key] end)
        if ok and kc then doKey(kc, a.Hold) end
    elseif k == "Wheel" then
        if Replay.cross then return end
        sendWheel(toScreen(a.Rx or 0.5, a.Ry or 0.5), a.Dir or 0)
    elseif a.Button then
        local pos = resolveClick(a)
        if pos then doClick(pos, a.Button, a.Hold) end
    end
end

function Replay.start(name)
    if Replay.playing then Replay.stop(true) end
    if Recorder.active then notify("Macros", "Идёт запись", 3) return end
    local macro = loadMacro(name)
    if not macro or type(macro.Actions) ~= "table" or #macro.Actions == 0 then
        notify("Macros", "Макрос пуст или в старом формате — запиши заново", 4) return
    end
    if not VIM and not humanMode() then
        notify("Macros", "Нет способа ввода (VirtualInputManager)", 4) return
    end

    local actions = macro.Actions
    local vp = viewport()
    local mv = macro.Viewport
    Replay.sameView = (mv and math.abs((mv.X or 0) - vp.X) <= 2 and math.abs((mv.Y or 0) - vp.Y) <= 2) and true or false
    local dev = pcMode() and "PC" or "Mobile"
    Replay.cross = (macro.Device ~= nil and macro.Device ~= dev)

    Replay.playing = true
    Replay.token = Replay.token + 1
    local cam = workspace.CurrentCamera
    prevCamType = cam and cam.CameraType

    local i, clock, lastStatus = 1, 0, 0
    notify("Macros", ("▶ «%s» — %d действий"):format(name, #actions), 3)

    Replay.conn = RunService.Heartbeat:Connect(function(dt)
        if not Replay.playing then return end
        clock = clock + dt
        local a = actions[i]
        while a and (a.Time or 0) <= clock do
            local ok, err = pcall(execAction, a)
            if not ok then warn("[BHL] action error:", err) end
            i = i + 1
            a = actions[i]
        end
        if not a then
            Replay.stop(true)
            notify("Macros", "✔ Готово", 3)
            setStatus("Готово: " .. name)
            return
        end
        if os.clock() - lastStatus > 0.5 then
            lastStatus = os.clock()
            setStatus(("▶ %d/%d"):format(i - 1, #actions))
        end
    end)
end

---------------------------------------------------------------------
-- Ввод: горячие клавиши и запись
---------------------------------------------------------------------
track(UIS.InputBegan:Connect(function(input, gp)
    if pcMode() and input.UserInputType == Enum.UserInputType.Keyboard and not UIS:GetFocusedTextBox() then
        local kn = input.KeyCode.Name
        if kn == "F8" then
            if Recorder.active then Recorder.stop(false) else task.spawn(Recorder.start) end
            return
        elseif kn == "F5" then
            if Replay.playing then Replay.stop() else Replay.start(pcfg.selectedMacro) end
            return
        end
    end
    onInput(input, true, gp)
end))
track(UIS.InputEnded:Connect(function(input, gp) onInput(input, false, gp) end))
track(UIS.InputChanged:Connect(function(input)
    if not Recorder.active then return end
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        local p = inputToPos(input)
        addAction({ Kind = "Wheel", Dir = input.Position.Z > 0 and 1 or -1, Rx = p.rx, Ry = p.ry })
    end
end))

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
    task.wait(1)
    %s
end
]]):format(SETTINGS_FILE, loader)
end

local function queueSelf(showNotify)
    if queued then return true end
    if not queueFn then
        if showNotify then notify("Auto Execute", "Нет queue_on_teleport", 4) end
        return false
    end
    local src = buildQueueSource()
    if not src then
        if showNotify then notify("Auto Execute", "Укажи SELF_URL или сохрани скрипт как " .. MAIN_FILE, 6) end
        return false
    end
    queued = true
    pcall(queueFn, src)
    if showNotify then notify("Auto Execute", "Запустится после телепорта", 3) end
    return true
end

track(LocalPlayer.OnTeleport:Connect(function()
    if Recorder.active then Recorder.stop(false) end -- запись не теряется при телепорте
    if cfg.autoExecute then queueSelf(false) end
end))
if cfg.autoExecute then task.defer(queueSelf, false) end

---------------------------------------------------------------------
-- AutoPlay every match: скрипт загрузился в матче -> через 5 сек запуск макроса
-- (стартует сразу при загрузке, не ждёт интерфейс)
---------------------------------------------------------------------
if IN_GAME and pcfg.autoPlay and pcfg.selectedMacro ~= "" then
    task.spawn(function()
        task.wait(5)
        if State.Alive and not Replay.playing and not Recorder.active then
            Replay.start(pcfg.selectedMacro)
        end
    end)
end

---------------------------------------------------------------------
-- Интерфейс Rayfield (создаётся последним, в отдельном потоке)
---------------------------------------------------------------------
function State.Cleanup()
    State.Alive = false
    Recorder.active = false
    pcall(function() Replay.stop(true) end)
    for _, c in ipairs(State.Conns) do pcall(function() c:Disconnect() end) end
    pcall(function() if Rayfield then Rayfield:Destroy() end end)
end

task.spawn(function()
    local urls = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    for _, url in ipairs(urls) do
        local ok, lib = pcall(function() return loadstring(game:HttpGet(url))() end)
        if ok and lib then Rayfield = lib break end
    end
    if not Rayfield or not State.Alive then
        warn("[BlackHoleHub_LTTD] Rayfield не загрузился (скрипт работает по F8 / F5)")
        return
    end

    -- уменьшаем окно как только оно появится
    task.spawn(function()
        for _ = 1, 100 do
            local done = false
            pcall(function()
                local root = (gethui and gethui()) or game:GetService("CoreGui")
                local g = root:FindFirstChild("Rayfield")
                local main = g and g:FindFirstChild("Main")
                if main then
                    if not main:FindFirstChild("BHL_Scale") then
                        local sc = Instance.new("UIScale")
                        sc.Name = "BHL_Scale"
                        sc.Scale = pcMode() and 0.78 or 0.6
                        sc.Parent = main
                    end
                    done = true
                end
            end)
            if done then break end
            task.wait(0.05)
        end
    end)

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
    if not State.Alive then return end

    local function optName(o)
        if type(o) == "table" then return o.Title or o.Name or o[1] end
        return o
    end

    local MacrosTab   = Window:CreateTab("Macros", "video")
    local SettingsTab = Window:CreateTab("Settings", "settings")

    ---------------------------------------------- Macros
    local newMacroName = ""
    local MacroDropdown
    local statusLabel

    setStatus = function(text)
        if statusLabel then pcall(function() statusLabel:Set(tostring(text)) end) end
    end

    local function refreshMacros(selectName)
        local list = listMacros()
        local values = #list > 0 and list or { NO_MACRO }
        if selectName then pcfg.selectedMacro = selectName end
        if not table.find(values, pcfg.selectedMacro) then
            pcfg.selectedMacro = (values[1] ~= NO_MACRO) and values[1] or ""
        end
        if MacroDropdown then
            pcall(function() MacroDropdown:Refresh(values) end)
            pcall(function() MacroDropdown:Set({ pcfg.selectedMacro ~= "" and pcfg.selectedMacro or NO_MACRO }) end)
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
        if not table.find(values, pcfg.selectedMacro) then
            pcfg.selectedMacro = (values[1] ~= NO_MACRO) and values[1] or ""
        end
        MacroDropdown = MacrosTab:CreateDropdown({
            Name = "Select", Options = values,
            CurrentOption = { pcfg.selectedMacro ~= "" and pcfg.selectedMacro or NO_MACRO },
            MultipleOptions = false,
            Callback = function(o)
                o = optName(o)
                if o and o ~= NO_MACRO then pcfg.selectedMacro = o saveAll() end
            end,
        })
    end

    -- ПК: кнопки меню отключены (только F8 / F5), чтобы клик не включал запись. Телефон: кнопки.
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
            if Recorder.active then notify("Macros", "Идёт запись", 3) return end
            if Replay.playing then Replay.stop() else Replay.start(pcfg.selectedMacro) end
        end,
    })
    MacrosTab:CreateDropdown({
        Name = "Click Mode",
        Options = { "Roblox", "Human" }, CurrentOption = { cfg.clickMode == "Human" and "Human" or "Roblox" },
        MultipleOptions = false,
        Callback = function(o)
            local m = optName(o)
            if m == "Human" and not (HUMAN_OK and pcMode()) then
                cfg.clickMode = "Roblox"
                notify("Click", "Human недоступен (нужен ПК и mousemoveabs) — Roblox", 4)
            else
                cfg.clickMode = m
                if m == "Human" then notify("Click", "Human: Roblox в полноэкранном режиме (F11)", 4) end
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
        Name = "AutoPlay every match", CurrentValue = pcfg.autoPlay,
        Callback = function(v) pcfg.autoPlay = v saveAll() end,
    })
    statusLabel = MacrosTab:CreateLabel(pcMode() and "ПК: F8 запись | F5 запуск/стоп" or "Телефон: Record / Play")

    ---------------------------------------------- Settings
    SettingsTab:CreateToggle({
        Name = "Anti AFK", CurrentValue = cfg.antiAfk,
        Callback = function(v) cfg.antiAfk = v saveAll() end,
    })
    SettingsTab:CreateSlider({
        Name = "Калибровка Y кликов (px)", Range = { -60, 60 }, Increment = 1, Suffix = " px",
        CurrentValue = math.clamp(cfg.clickOffsetY or 0, -60, 60),
        Callback = function(v) cfg.clickOffsetY = math.floor(v) saveAll() end,
    })

    refreshMacros()
    notify("BlackHoleHub_LTTD", "by ART1XL1S — загружено", 2)
end)
