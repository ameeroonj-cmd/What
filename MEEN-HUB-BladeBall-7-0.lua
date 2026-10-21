--[[
    MEEN HUB | BLADE BALL  (standalone file)
    แยกออกมาจาก MEEN HUB Library แล้ว - รันไฟล์นี้ไฟล์เดียวก็ใช้งานได้เลย
    คลัง (Library) จะโหลดไฟล์นี้ผ่านลิงก์ HUB.BladeBallURL เวลากดการ์ด Blade Ball
]]

--[[
    MEEN HUB | BLADE BALL   V 1.2 (ออโต้พาร์รี่ใหม่: ตรวจเป้าด้วย attribute+Highlight / คิดบอลเล็งตาม / เรียนรู้จังหวะเอง)
    (เดิม v4.0   (เขียนระบบใหม่ทั้งหมด / เก็บเฉพาะ UI หลัก)

    ตอนนี้มี 2 ระบบ:
      1) ออโต้พาร์รี่ : ยิงตามเวลาที่บอลจะถึงตัว (คิดความเร่ง + ชดเชยปิง) ยิงครั้งเดียวต่อรอบ ถ้าพลาดยิงซ้ำ
      2) ออโต้สแปม   : พาร์รี่รัวเมื่อบอลเล็งเราและอยู่ในระยะ ด้วยตัวนับเวลาคงที่ (ไม่ผูกกับ FPS)

    ปุ่มลัด:  RightShift = ซ่อน/แสดง   X = ออโต้พาร์รี่   C = ออโต้สแปม   Delete = ฉุกเฉิน
    มือถือ: แตะปุ่มโลโก้วงกลมที่ขอบจอ
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local RepStorage   = game:GetService("ReplicatedStorage")
local Lighting     = game:GetService("Lighting")
local TeleportSvc  = game:GetService("TeleportService")
local GuiService   = game:GetService("GuiService")
local LP           = Players.LocalPlayer

local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
local ENV = (getgenv and getgenv()) or _G

pcall(function() if ENV.__MEEN_BB_UNLOAD then ENV.__MEEN_BB_UNLOAD() end end)

------------------------------------------------------------------ CONFIG
local HUB = {Name = "MEEN HUB", Version = "V 1.2", Logo = "rbxassetid://133012946200414",
    ToggleKey = Enum.KeyCode.RightShift, SaveFile = "MeenHub_BladeBall_v110.json"}

local DEFAULTS = {
    AutoParry = false, ParryLogic = "Ref", RefAccuracy = 100, Rearm = false, ParryTarget = "Everyone", Window = 450, PingComp = true, PointBlank = 16, MinSpeed = 10, TargetOnly = true, Adaptive = true,
    Preset = "Balanced",
    AutoSpam = false, SpamRate = 16, SpamRange = 20, ClashOnly = false,
    AutoAbility = false, AbilityRange = 40,
    BallESP = false, FOVOn = false, FOV = 90, Fullbright = false,
    HitboxESP = false, ParryRing = false, BallTag = false, FPSBoost = false,
    Guard = true, AnomalyWatch = true, BanWatch = true, AutoRejoin = false, AntiAFK = true,
    HUD = true, ParryFX = true, VisualCD = true, CDms = 600,
}
local S = {}
for k, v in pairs(DEFAULTS) do S[k] = v end
pcall(function()
    if isfile and isfile(HUB.SaveFile) then
        local d = HttpService:JSONDecode(readfile(HUB.SaveFile))
        for k, v in pairs(d) do if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then S[k] = v end end
    end
end)
do
    local R = {RefAccuracy = {1, 100}, CDms = {200, 2000}, Window = {40, 600}, PointBlank = {0, 40}, MinSpeed = {0, 120}, SpamRate = {5, 60}, SpamRange = {6, 40}, AbilityRange = {10, 120}, FOV = {60, 120}}
    for k, r in pairs(R) do
        if type(S[k]) ~= "number" or S[k] ~= S[k] then S[k] = DEFAULTS[k] end
        S[k] = math.clamp(S[k], r[1], r[2])
    end
    if not ({Early = 1, Balanced = 1, Late = 1, Custom = 1})[S.Preset] then S.Preset = "Balanced" end
    -- ค่าเหล่านี้ไม่มีให้ปรับแล้ว: ทำงานเบื้องหลังเสมอ (ทับค่าที่เคยเซฟไว้)
    S.ParryLogic, S.ParryTarget, S.Rearm, S.RefAccuracy, S.Adaptive, S.PingComp = "Ref", "Everyone", false, 100, true, true
end

local C = {
    VIOLET = Color3.fromRGB(139, 92, 246), INDIGO = Color3.fromRGB(99, 102, 241), CYAN = Color3.fromRGB(56, 189, 248),
    BG = Color3.fromRGB(7, 9, 20), PANEL = Color3.fromRGB(13, 13, 30), PANEL2 = Color3.fromRGB(22, 20, 48),
    TEXT = Color3.fromRGB(226, 232, 240), MUTED = Color3.fromRGB(148, 163, 184),
    OK = Color3.fromRGB(74, 222, 128), WARN = Color3.fromRGB(251, 191, 36), BAD = Color3.fromRGB(248, 113, 113),
    OFF = Color3.fromRGB(48, 51, 88),
}
local WHITE = Color3.new(1, 1, 1)
local CK = ColorSequenceKeypoint.new

local conns, alive = {}, true
local function bind(sig, fn) local c = sig:Connect(fn) table.insert(conns, c) return c end

-- บันทึกเหตุการณ์ภายใน
local Dbg = {lines = {}}
local dbgThrottle = {}
function Dbg.log(msg, key, gap)
    local now = os.clock()
    if key then
        if dbgThrottle[key] and now - dbgThrottle[key] < (gap or 2) then return end
        dbgThrottle[key] = now
    end
    local l = Dbg.lines
    l[#l + 1] = string.format("[%7.1f] %s", now % 100000, tostring(msg))
    if #l > 80 then table.remove(l, 1) end
end

------------------------------------------------------------------ UI helpers
local function new(cls, props, kids)
    local o = Instance.new(cls)
    for k, v in pairs(props or {}) do o[k] = v end
    for _, c in ipairs(kids or {}) do c.Parent = o end
    return o
end
local function tw(o, t, p, style, dir)
    local tn = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), p)
    tn:Play() return tn
end
local function corner(r) return new("UICorner", {CornerRadius = UDim.new(0, r)}) end
local function stroke(col, th, tr) return new("UIStroke", {Color = col or C.VIOLET, Thickness = th or 1, Transparency = tr or 0.75, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}) end
local function grad(a, b, rot) return new("UIGradient", {Rotation = rot or 0, Color = ColorSequence.new({CK(0, a), CK(1, b)})}) end
local function label(parent, props, kids)
    local d = {BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.TEXT, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent}
    for k, v in pairs(props) do d[k] = v end
    return new("TextLabel", d, kids)
end
local function press(b)
    local s = new("UIScale", {Parent = b})
    b.MouseButton1Down:Connect(function() tw(s, 0.08, {Scale = 0.95}) end)
    local function up() tw(s, 0.25, {Scale = 1}, Enum.EasingStyle.Back) end
    b.MouseButton1Up:Connect(up) b.MouseLeave:Connect(up)
end
local function button(parent, props, kids)
    local d = {AutoButtonColor = false, Text = "", BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.TEXT, Parent = parent}
    for k, v in pairs(props) do d[k] = v end
    local b = new("TextButton", d, kids)
    press(b) return b
end
local function gbutton(parent, props, text, a, b, ts)
    local btn = button(parent, props, {corner(10), grad(a or C.VIOLET, b or C.INDIGO, 20)})
    btn.BackgroundColor3 = WHITE
    local l = label(btn, {Size = UDim2.fromScale(1, 1), Text = text, Font = Enum.Font.GothamBold, TextSize = ts or 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3})
    return btn, l
end
local function glass(parent, props, r)
    local d = {BackgroundColor3 = C.PANEL2, BackgroundTransparency = 0.38, BorderSizePixel = 0, Parent = parent}
    for k, v in pairs(props or {}) do d[k] = v end
    local f = new("Frame", d)
    corner(r or 14).Parent = f
    stroke(WHITE, 1, 0.91).Parent = f
    return f
end
local function bar(parent, w, h, rot, col)
    return new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w, h), Position = UDim2.fromScale(0.5, 0.5), Rotation = rot or 0,
        BackgroundColor3 = col or C.TEXT, BorderSizePixel = 0, ZIndex = 8, Parent = parent}, {corner(2)})
end

------------------------------------------------------------------ state sync
local Switches, Hooks = {}, {}
local function reg(key, fn) Switches[key] = Switches[key] or {} table.insert(Switches[key], fn) end
local saveToken = 0
local function saveSoon()
    saveToken = saveToken + 1
    local my = saveToken
    task.delay(1, function()
        if my ~= saveToken then return end
        pcall(function() if writefile then writefile(HUB.SaveFile, HttpService:JSONEncode(S)) end end)
    end)
end
local toast
local function setState(key, v)
    S[key] = v
    for _, f in ipairs(Switches[key] or {}) do pcall(f, v) end
    if Hooks[key] then pcall(Hooks[key], v) end
    saveSoon()
end

local PRESET_WIN = {Early = 520, Balanced = 450, Late = 380}
Hooks.Preset = function(v) if PRESET_WIN[v] then setState("Window", PRESET_WIN[v]) end end
Hooks.Window = function(v) if PRESET_WIN[S.Preset] ~= v and S.Preset ~= "Custom" then setState("Preset", "Custom") end end

------------------------------------------------------------------ GUI root
local gui = new("ScreenGui", {Name = "MeenHubBladeBall", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
do
    local ok = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
end

local main = new("Frame", {Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 400),
    BackgroundColor3 = C.BG, BackgroundTransparency = 0.04, BorderSizePixel = 0, ClipsDescendants = true, Active = true, Parent = gui}, {corner(20)})
local baseScale = 1
do
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    baseScale = math.clamp(math.min(vp.X / 700, vp.Y / 460), 0.55, 1)
end
local mscale = new("UIScale", {Scale = baseScale * 0.85, Parent = main})
local ring = stroke(C.VIOLET, 1.5, 0.15) ring.Parent = main
local ringG = new("UIGradient", {Color = ColorSequence.new({CK(0, C.VIOLET), CK(0.5, C.CYAN), CK(1, C.VIOLET)}), Parent = ring})
bind(RunService.Heartbeat, function(dt) ringG.Rotation = (ringG.Rotation + dt * 30) % 360 end)

local header = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 5, Parent = main})
local logoBox = new("Frame", {Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C.PANEL2, BorderSizePixel = 0, ZIndex = 6, Parent = header}, {corner(9), stroke(C.VIOLET, 1, 0.5)})
local logoImg = new("ImageLabel", {Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Image = HUB.Logo, ScaleType = Enum.ScaleType.Fit, ZIndex = 7, Parent = logoBox}, {corner(8)})
task.spawn(function()
    local t = 0
    while logoImg.Parent and not logoImg.IsLoaded and t < 6 do task.wait(0.25) t = t + 0.25 end
    if logoImg.Parent and not logoImg.IsLoaded then
        logoImg.ImageTransparency = 1
        label(logoImg, {Size = UDim2.fromScale(1, 1), Text = "M", Font = Enum.Font.GothamBlack, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center})
    end
end)
local titleLbl = label(header, {Position = UDim2.fromOffset(54, 5), Size = UDim2.fromOffset(240, 20), Text = HUB.Name .. "  |  BLADE BALL", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = WHITE, ZIndex = 6})
local titleG = new("UIGradient", {Color = ColorSequence.new({CK(0, WHITE), CK(0.5, C.CYAN), CK(1, C.VIOLET)}), Parent = titleLbl})
bind(RunService.Heartbeat, function(dt) titleG.Rotation = (titleG.Rotation + dt * 45) % 360 end)
label(header, {Position = UDim2.fromOffset(54, 24), Size = UDim2.fromOffset(240, 16), Text = HUB.Version .. "  -  ULTIMATE COMBAT ENGINE", TextSize = 11, TextColor3 = C.MUTED, ZIndex = 6})
local chip = glass(header, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -92, 0.5, 0), Size = UDim2.fromOffset(130, 24), ZIndex = 6}, 12)
local chipLbl = label(chip, {Size = UDim2.fromScale(1, 1), Text = "-- FPS  --ms", Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.CYAN, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7})
local function winBtn(x, kind, col)
    local b = button(header, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = C.PANEL2, BackgroundTransparency = 0.3, ZIndex = 7}, {corner(9)})
    if kind == "close" then bar(b, 12, 2, 45, col) bar(b, 12, 2, -45, col) else bar(b, 12, 2, 0, col) end
    return b
end
local btnMin = winBtn(-46, "min", C.TEXT)
local btnClose = winBtn(-12, "close", C.BAD)

do -- drag
    local dragLayer = new("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = main})
    local dragging, dInput, start, startPos = false, nil, nil, nil
    local function begin(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dInput, start, startPos = true, i, i.Position, main.Position
        end
    end
    header.InputBegan:Connect(begin) dragLayer.InputBegan:Connect(begin)
    bind(UIS.InputChanged, function(i)
        if not dragging then return end
        if i == dInput or i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - start
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i == dInput or i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local side = glass(main, {Position = UDim2.fromOffset(12, 54), Size = UDim2.new(0, 138, 1, -66), ZIndex = 3}, 14)
new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = side})
new("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = side})
local content = new("Frame", {Position = UDim2.fromOffset(160, 54), Size = UDim2.new(1, -172, 1, -66), BackgroundTransparency = 1, ZIndex = 3, Parent = main})

local TABS = {{"Home", "หน้าแรก"}, {"Combat", "ต่อสู้"}, {"Visual", "ภาพ"}, {"Safety", "ความปลอดภัย"}, {"Settings", "ตั้งค่า"}}
local pages, tabBtns, orders = {}, {}, {}
local function ord(p) orders[p] = (orders[p] or 0) + 1 return orders[p] end
for idx, t in ipairs(TABS) do
    local name, thai = t[1], t[2]
    pages[name] = new("ScrollingFrame", {Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.VIOLET, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false, ZIndex = 3, Parent = content},
        {new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}), new("UIPadding", {PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6)})})
    local tb = button(side, {Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.VIOLET, BackgroundTransparency = 1, LayoutOrder = idx, ZIndex = 4}, {corner(10)})
    local dot = new("Frame", {Position = UDim2.fromOffset(10, 13), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.MUTED, BorderSizePixel = 0, ZIndex = 5, Parent = tb}, {corner(3)})
    local tl = label(tb, {Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), Text = thai, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.MUTED, ZIndex = 5})
    tabBtns[name] = {btn = tb, dot = dot, lbl = tl}
end
local curPage
local function setPage(name)
    if curPage == name then return end
    curPage = name
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, t in pairs(tabBtns) do
        local on = n == name
        tw(t.btn, 0.2, {BackgroundTransparency = on and 0.75 or 1})
        tw(t.dot, 0.2, {BackgroundColor3 = on and C.CYAN or C.MUTED})
        tw(t.lbl, 0.2, {TextColor3 = on and C.TEXT or C.MUTED})
    end
end
for n, t in pairs(tabBtns) do t.btn.MouseButton1Click:Connect(function() setPage(n) end) end

do -- toast
    local tl = label(main, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(300, 28), BackgroundColor3 = C.PANEL,
        BackgroundTransparency = 1, TextTransparency = 1, Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 20}, {corner(14), stroke(C.VIOLET, 1, 0.5)})
    local id = 0
    toast = function(text)
        id = id + 1
        local my = id
        tl.Text = text
        tw(tl, 0.2, {BackgroundTransparency = 0.1, TextTransparency = 0})
        task.delay(1.8, function() if my == id and tl.Parent then tw(tl, 0.3, {BackgroundTransparency = 1, TextTransparency = 1}) end end)
    end
end

------------------------------------------------------------------ widgets
local function section(page, text)
    label(page, {Size = UDim2.new(1, -6, 0, 22), Text = string.upper(text), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.CYAN, LayoutOrder = ord(page), ZIndex = 4})
end
local function toggle(page, text, desc, key)
    local row = glass(page, {Size = UDim2.new(1, -6, 0, desc and 56 or 44), LayoutOrder = ord(page), ZIndex = 4}, 10)
    label(row, {Position = UDim2.fromOffset(14, desc and 7 or 0), Size = UDim2.new(1, -80, 0, desc and 21 or 44), Text = text, Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 5})
    if desc then label(row, {Position = UDim2.fromOffset(14, 29), Size = UDim2.new(1, -80, 0, 20), Text = desc, TextSize = 11, TextColor3 = C.MUTED, ZIndex = 5}) end
    local sw = button(row, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(44, 24), BackgroundColor3 = S[key] and C.VIOLET or C.OFF, ZIndex = 5}, {corner(12)})
    local knob = new("Frame", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, S[key] and 23 or 3, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6, Parent = sw}, {corner(9)})
    reg(key, function(v)
        tw(knob, 0.22, {Position = UDim2.new(0, v and 23 or 3, 0.5, 0)}, Enum.EasingStyle.Back)
        tw(sw, 0.2, {BackgroundColor3 = v and C.VIOLET or C.OFF})
    end)
    sw.MouseButton1Click:Connect(function() setState(key, not S[key]) end)
end
local function slider(page, text, key, mn, mx, step, fmt)
    local row = glass(page, {Size = UDim2.new(1, -6, 0, 58), LayoutOrder = ord(page), ZIndex = 4}, 10)
    label(row, {Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -110, 0, 20), Text = text, Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 5})
    local val = label(row, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 7), Size = UDim2.fromOffset(90, 20), TextXAlignment = Enum.TextXAlignment.Right,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.CYAN, ZIndex = 5})
    local track = new("Frame", {Position = UDim2.new(0, 14, 0, 40), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = C.BG, BorderSizePixel = 0, ZIndex = 5, Parent = row}, {corner(3)})
    local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6, Parent = track}, {corner(3), grad(C.VIOLET, C.CYAN, 0)})
    local knob = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 7, Parent = track}, {corner(7)})
    local hit = new("TextButton", {Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 28), Size = UDim2.new(1, -28, 0, 28), ZIndex = 8, Parent = row})
    local function render(v)
        local a = math.clamp((v - mn) / (mx - mn), 0, 1)
        fill.Size = UDim2.fromScale(a, 1) knob.Position = UDim2.fromScale(a, 0.5)
        val.Text = fmt and fmt(v) or tostring(v)
    end
    render(S[key]) reg(key, render)
    local dragging = false
    local function setFrom(x)
        local a = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
        local v = math.clamp(math.floor((mn + a * (mx - mn)) / step + 0.5) * step, mn, mx)
        setState(key, tonumber(string.format("%.3f", v)))
    end
    local function stopDrag() dragging = false pcall(function() page.ScrollingEnabled = true end) end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true pcall(function() page.ScrollingEnabled = false end) setFrom(i.Position.X)
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFrom(i.Position.X) end
    end)
    bind(UIS.InputEnded, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then stopDrag() end
    end)
end
local function cycle(page, text, key, options, display)
    local row = glass(page, {Size = UDim2.new(1, -6, 0, 44), LayoutOrder = ord(page), ZIndex = 4}, 10)
    label(row, {Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -160, 1, 0), Text = text, Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 5})
    local function shown(v) return display and display[v] or tostring(v) end
    local b, l = gbutton(row, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(120, 28), ZIndex = 5}, shown(S[key]), C.VIOLET, C.INDIGO, 11)
    reg(key, function(v) l.Text = shown(v) end)
    b.MouseButton1Click:Connect(function()
        local n = 1
        for i, o in ipairs(options) do if o == S[key] then n = i end end
        setState(key, options[n % #options + 1])
    end)
end
local function action(page, text, btnText, fn, col)
    local row = glass(page, {Size = UDim2.new(1, -6, 0, 44), LayoutOrder = ord(page), ZIndex = 4}, 10)
    label(row, {Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -160, 1, 0), Text = text, Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 5})
    local b = gbutton(row, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(120, 28), ZIndex = 5}, btnText, col or C.VIOLET, col and Color3.fromRGB(190, 60, 60) or C.INDIGO, 11)
    b.MouseButton1Click:Connect(function() pcall(fn) end)
end
local function note(page, text, h)
    label(page, {Size = UDim2.new(1, -6, 0, h or 34), Text = text, TextSize = 11, TextColor3 = C.MUTED, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = ord(page), ZIndex = 4})
end

local Engine = {}   -- ฟังก์ชันที่ UI เรียก (ผูกทีหลัง)
local msFmt = function(v) return v .. " ms" end
local stFmt = function(v) return v .. " หน่วย" end

------------------------------------------------------------------ PAGES
local fpsV, pingV, ballV, statusLbl, infoLbl, whyLbl, statLbl, safeLbl, banLbl, eventLbl
local chartBars = {}
do
    local pg = pages.Home
    local welcome = glass(pg, {Size = UDim2.new(1, -6, 0, 72), LayoutOrder = ord(pg), ZIndex = 4}, 14)
    label(welcome, {Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 28), Text = "ยินดีต้อนรับ, " .. LP.DisplayName, Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 5})
    statusLbl = label(welcome, {Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 22), Text = "-", TextSize = 12, TextColor3 = C.MUTED, ZIndex = 5})

    local statRow = new("Frame", {Size = UDim2.new(1, -6, 0, 60), BackgroundTransparency = 1, LayoutOrder = ord(pg), ZIndex = 4, Parent = pg})
    local function chipStat(i, title)
        local f = glass(statRow, {Position = UDim2.new((i - 1) / 3, i > 1 and 3 or 0, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), ZIndex = 4}, 12)
        label(f, {Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 0, 16), Text = title, TextSize = 11, TextColor3 = C.MUTED, ZIndex = 5})
        return label(f, {Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -24, 0, 28), Text = "--", Font = Enum.Font.GothamBold, TextSize = 20, ZIndex = 5})
    end
    fpsV = chipStat(1, "FPS") pingV = chipStat(2, "ปิง (ms)") ballV = chipStat(3, "ความเร็วบอล")

    local chart = glass(pg, {Size = UDim2.new(1, -6, 0, 84), LayoutOrder = ord(pg), ZIndex = 4}, 12)
    label(chart, {Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 0, 16), Text = "ประวัติ FPS", TextSize = 11, TextColor3 = C.MUTED, ZIndex = 5})
    local area = new("Frame", {Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 50), BackgroundTransparency = 1, ZIndex = 5, Parent = chart})
    local NB = 28
    for i = 1, NB do
        chartBars[i] = new("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new((i - 1) / NB, 1, 1, 0), Size = UDim2.new(1 / NB, -2, 0.05, 0),
            BackgroundColor3 = C.VIOLET, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 6, Parent = area}, {corner(2)})
    end

    section(pg, "สวิตช์ด่วน")
    toggle(pg, "ออโต้พาร์รี่", "ปุ่มลัด: X", "AutoParry")
    toggle(pg, "ออโต้สแปม", "ปุ่มลัด: C", "AutoSpam")
    toggle(pg, "ออโต้สกิล", nil, "AutoAbility")

    local live = glass(pg, {Size = UDim2.new(1, -6, 0, 112), LayoutOrder = ord(pg), ZIndex = 4}, 12)
    label(live, {Position = UDim2.fromOffset(14, 5), Size = UDim2.new(1, -28, 0, 16), Text = "บอลสด", TextSize = 11, TextColor3 = C.CYAN, Font = Enum.Font.GothamBold, ZIndex = 5})
    infoLbl = label(live, {Position = UDim2.fromOffset(14, 23), Size = UDim2.new(1, -28, 0, 20), Text = "ไม่มีบอลในสนาม", TextSize = 12, ZIndex = 5})
    whyLbl = label(live, {Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 20), Text = "สถานะ: -", TextSize = 12, TextColor3 = C.WARN, Font = Enum.Font.GothamBold, ZIndex = 5})
    statLbl = label(live, {Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -28, 0, 36), Text = "-", TextSize = 11, TextColor3 = C.MUTED, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5})
end

do
    local pg = pages.Combat
    section(pg, "ออโต้พาร์รี่")
    toggle(pg, "ออโต้พาร์รี่", "จังหวะ / รีโมท / เป้าหมาย คำนวณและทำงานเบื้องหลังอัตโนมัติ ยิงรอบละครั้ง", "AutoParry")

    section(pg, "ออโต้สแปม")
    toggle(pg, "ออโต้สแปม", "พาร์รี่รัวเมื่อบอลเล็งเราและอยู่ใกล้", "AutoSpam")
    slider(pg, "ความเร็วสแปม", "SpamRate", 5, 60, 1, function(v) return v .. " ครั้ง/วิ" end)
    slider(pg, "ระยะสแปม", "SpamRange", 6, 40, 1, stFmt)
    note(pg, "สแปมทำงานเฉพาะตอนปะทะ: มีศัตรูอยู่ใกล้ (30 หน่วย) หรือบอลเด้งกลับมาติดๆ กัน  ส่วนบอลที่เข้ามาครั้งแรกใช้ออโต้พาร์รี่ตีให้", 36)

    section(pg, "สกิล")
    toggle(pg, "ออโต้สกิล", "ใช้สกิลเมื่อบอลที่เล็งคุณเข้าใกล้", "AutoAbility")
    slider(pg, "ระยะใช้สกิล", "AbilityRange", 10, 120, 1, stFmt)
end

do
    local pg = pages.Visual
    section(pg, "ภาพ")
    toggle(pg, "ไฮไลต์บอล", "แดง = เล็งมาที่คุณ  ฟ้า = เล็งคนอื่น", "BallESP")
    toggle(pg, "ปรับมุมมองกล้อง", nil, "FOVOn")
    slider(pg, "มุมมองกล้อง (FOV)", "FOV", 60, 120, 1, function(v) return v .. " องศา" end)
    toggle(pg, "สว่างเต็มที่", "ปิดหมอก/เงา ให้เห็นบอลชัดขึ้น", "Fullbright")
    section(pg, "ฮิตบอกซ์ & ข้อมูลบอล")
    toggle(pg, "แสดงฮิตบอกซ์บอล", "ทรงกลมรอบบอล (แดง = เล็งคุณ) ตามรัศมีที่สคริปต์ใช้คำนวณ", "HitboxESP")
    toggle(pg, "แสดงวงระยะพาร์รี่", "วงรอบตัวคุณ ถ้าบอลเข้าวงนี้ ออโต้จะยิง", "ParryRing")
    toggle(pg, "ป้ายข้อมูลบอล", "แสดงความเร็ว + เวลาถึงตัว เหนือบอล", "BallTag")
    section(pg, "ลูกเล่น")
    toggle(pg, "แถบสถานะลอยบนจอ", "โชว์ PARRY / SPAM + คอมโบ ตอนซ่อนเมนู", "HUD")
    toggle(pg, "แถบคูลดาวน์พาร์รี่", "แถบเล็กกลางจอ: เหลือง = เพิ่งยิง รอ  เขียว = พร้อมยิงอีกครั้ง", "VisualCD")
    slider(pg, "เวลาคูลดาวน์ที่แสดง", "CDms", 200, 2000, 50, msFmt)
    toggle(pg, "แฟลชเมื่อพาร์รี่สำเร็จ", "จอวาบสีฟ้าเบาๆ ทุกครั้งที่ตีโดน", "ParryFX")
    section(pg, "ประสิทธิภาพ")
    toggle(pg, "ลดกราฟิก (เพิ่ม FPS)", "ปิดเงา/พาร์ติเคิล/เอฟเฟกต์ ลดภาพกระตุก", "FPSBoost")
end

do
    local pg = pages.Safety
    section(pg, "สถานะความปลอดภัย")
    local box = glass(pg, {Size = UDim2.new(1, -6, 0, 70), LayoutOrder = ord(pg), ZIndex = 4}, 12)
    safeLbl = label(box, {Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22), Text = "ปกติ", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.OK, ZIndex = 5})
    banLbl = label(box, {Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 28), Text = "เฝ้าระวังการโดนเตะ/แบน: ยังไม่พบอะไรผิดปกติ", TextSize = 11, TextColor3 = C.MUTED,
        TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5})

    section(pg, "ตรวจความผิดปกติ")
    toggle(pg, "ระบบกันพลาด", "หยุดออโต้ชั่วคราวเมื่อบอลวาร์ป / ตัวละครวาร์ป / แล็กกระตุก", "Guard")
    toggle(pg, "ตรวจความผิดปกติของออโต้", "เตือน + พักออโต้เมื่อพลาดติดกัน / ยิงถี่ผิดปกติ / FPS ต่ำนาน / รีโมทไม่พร้อม", "AnomalyWatch")

    section(pg, "เฝ้าระวังการโดนเตะ / แบน")
    toggle(pg, "ตรวจจับโดนเตะ/แบน", "ปิดออโต้ทันที + บันทึกเวลา เมื่อเกมขึ้นข้อความเตะ/แบน/หลุด", "BanWatch")
    toggle(pg, "เข้าเซิร์ฟเวอร์ใหม่อัตโนมัติ", "ใช้เมื่อหลุด/ถูกเตะ (ถ้าโดนแบนจะไม่รีจอยน์)", "AutoRejoin")
    toggle(pg, "กันหลุดเพราะ AFK", nil, "AntiAFK")
    note(pg, "หมายเหตุ: ระบบนี้ตรวจจับ 'หลังเกิดเหตุ' เท่านั้น ไม่สามารถป้องกันการโดนแบนล่วงหน้าได้", 34)

    section(pg, "เหตุการณ์ล่าสุด")
    eventLbl = label(pg, {Size = UDim2.new(1, -6, 0, 110), Text = "(ยังไม่มีเหตุการณ์)", TextSize = 11, TextColor3 = C.MUTED, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = ord(pg), ZIndex = 4})
    action(pg, "ฉุกเฉิน: ปิดทุกฟีเจอร์ + ซ่อนหน้าต่าง", "ปิดทั้งหมด", function() Engine.panic() end, C.WARN)
    action(pg, "เข้าเซิร์ฟเวอร์ใหม่", "รีจอยน์", function() TeleportSvc:Teleport(game.PlaceId, LP) end)
end

do
    local pg = pages.Settings
    section(pg, "หน้าต่าง")
    note(pg, "ซ่อน/แสดง: RightShift   พาร์รี่: X   สแปม: C   ฉุกเฉิน: Delete   (มือถือ: ปุ่มโลโก้)", 36)
    note(pg, "ไม่มีอะไรการันตีว่าบัญชีปลอดภัย ใช้ด้วยความเสี่ยงของตัวเอง", 24)
    section(pg, "คอนฟิก")
    action(pg, "รีเซ็ตการตั้งค่าทั้งหมด", "รีเซ็ต", function()
        for k, v in pairs(DEFAULTS) do setState(k, v) end
        toast("รีเซ็ตการตั้งค่าแล้ว")
    end)
    action(pg, "ปิดสคริปต์", "ปิดสคริปต์", function() Engine.unload() end, C.BAD)
end

------------------------------------------------------------------ 1) ADAPTER  (แก้ตรงนี้ถ้าเกมอัปเดต)
-- คืนรายการบอลจริง (ถ้ามี attribute realBall จะกรองเอาเฉพาะ true)
local function getBalls()
    local list, anyAttr = {}, false
    for _, name in ipairs({"Balls", "TrainingBalls"}) do
        local f = workspace:FindFirstChild(name)
        if f then
            for _, b in ipairs(f:GetChildren()) do
                if b:IsA("BasePart") then
                    local r = b:GetAttribute("realBall")
                    if r ~= nil then anyAttr = true end
                    list[#list + 1] = {b, r}
                end
            end
        end
    end
    local out = {}
    for _, e in ipairs(list) do
        if (not anyAttr) or e[2] == true then out[#out + 1] = e[1] end
    end
    return out
end

local function ballVelocity(b)
    local z = b:FindFirstChild("zoomies")
    if z then
        local ok, r = pcall(function() return z.VectorVelocity end)
        if ok and typeof(r) == "Vector3" then return r end   -- เกมใช้ zoomies เป็นความเร็วจริง (ไม่ตัดค่าต่ำ ไม่งั้นไปใช้ความเร็วฟิสิกส์ที่เพี้ยน)
    end
    local pv = b.AssemblyLinearVelocity
    if pv.Magnitude > 0.5 then return pv end
    return nil
end

local function targetOf(b) return b:GetAttribute("target") end

local function getPing()
    local ok, v = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok and type(v) == "number" then return v end
    local ok2, p = pcall(function() return LP:GetNetworkPing() * 1000 end)
    return ok2 and p or 0
end

------------------------------------------------------------------ 2) ช่องทางพาร์รี่
-- ===== รีโมท: พาร์รี่ผ่านระบบของเกมเอง =====
-- ขั้น 1 (PRY): เรียกฟังก์ชันพาร์รี่ของเกมเอง เกมสร้างโทเค็นและยิงรีโมทให้เอง
-- ขั้น 2 (REPLAY): ถ้าไม่เจอ PRY ให้ดักรีโมทจริงตอนพาร์รี่เองครั้งแรก แล้วยิงซ้ำด้วยโทเค็นใหม่
-- ถ้าทั้งสองขั้นไม่ได้ จะยิงพาร์รี่ไม่ออก (ไม่มีวิธีสำรอง) ให้ลองพาร์รี่เองในเกมสักครั้งเพื่อให้ระบบจำค่า
local Remote = {stage = "-", captured = {}, hooked = {}, originals = {}, count = 0, windowAt = 0,
    pryAt = -10, hookAt = -10, warned = false, failStreak = 0, healAt = -100, warmupDone = false}

-- หา PRY ของเกมสดๆ (ใช้ทั้งตอนเริ่มและตอนตรวจว่าค่าที่จำไว้ยังตรงไหม)
-- PRY เป็น ModuleScript ลูกของ SwordsController: require(SwordsController.PRY) ได้ตัวฟังก์ชันพาร์รี่
-- คืน: ฟังก์ชัน PRY, โมดูล Signal, วิธีที่หาเจอ
function Remote.findPry()
    local pk = RepStorage:FindFirstChild("Packages")
    local sigMod = pk and pk:FindFirstChild("Signal")
    assert(sigMod, "ไม่พบ Packages.Signal")
    local function load(m)
        if m and m:IsA("ModuleScript") then
            local okR, fn = pcall(require, m)
            if okR and type(fn) == "function" then return fn end
        end
    end
    local ctrls = RepStorage:FindFirstChild("Controllers")
    if ctrls then
        for _, c in ipairs(ctrls:GetChildren()) do
            if string.find(c.Name, "SwordsController", 1, true) == 1 then
                local fn = load(c:FindFirstChild("PRY"))
                if fn then return fn, sigMod, "Controllers" end
            end
        end
    end
    -- สำรอง: ModuleScript ชื่อ PRY ที่ไหนก็ได้ใน ReplicatedStorage (เผื่อเกมย้ายที่)
    for _, d in ipairs(RepStorage:GetDescendants()) do
        if d.Name == "PRY" then
            local fn = load(d)
            if fn then return fn, sigMod, "ค้นทั้งหมด" end
        end
    end
    if getloadedmodules then
        for _, m in ipairs(getloadedmodules()) do
            if m.Name == "PRY" then
                local fn = load(m)
                if fn then return fn, sigMod, "loaded" end
            end
        end
    end
    error("ไม่พบโมดูล PRY (Controllers/SwordsController*/PRY)")
end

function Remote.dropPry()
    local sig = Remote.signal
    Remote.signal, Remote.pry = nil, nil
    Remote.pryAt = os.clock()   -- หน่วง 5 วิก่อนหาใหม่ กันวนถี่
    if sig then pcall(function() sig:Destroy() end) end
end

function Remote.initPry()
    if Remote.pry then return true end
    local now = os.clock()
    if now - Remote.pryAt < 5 then return false end
    Remote.pryAt = now
    local ok, err = pcall(function()
        local pry, sigMod, how = Remote.findPry()
        local sig = require(sigMod).new()
        sig:Connect(pry)
        Remote.signal = sig
        Remote.pry = pry
        Remote.pryHow = how
    end)
    if not ok then Remote.pryErr = tostring(err) Dbg.log("รีโมท/PRY: " .. tostring(err), "pry", 5) end
    return Remote.pry ~= nil
end

-- อาร์กิวเมนต์ที่เกมต้องการ (arg5-arg7)
--   arg5 = CFrame ของกล้อง
--   arg6 = { ชื่อผู้เล่น = Vector3(x, y, ความลึก) } ตำแหน่งบนจอ (WorldToScreenPoint)
--          ล็อกเป้าอัตโนมัติ = เฉพาะคนที่อยู่ใกล้กลางจอที่สุด (ไม่นับตัวเอง) | ไม่เจอเป้า = ทุกคนใน workspace.Alive
--   arg7 = กลางหน้าจอ { x, y }
-- arg5 = CFrame กล้อง | arg6 = { [ชื่อ] = WorldToScreenPoint } (Z > 0)  Everyone = ทุกคนใน Alive / Lock = เป้าเดียว
-- arg7 = { x, y } จุดเล็ง: เป้า (WorldToViewportPoint) > เมาส์ > กลางจอ   (ตรงตามสคริปต์ตัวอย่าง)
function Remote.pickTarget(cam)
    local aliveF = workspace:FindFirstChild("Alive")
    if not aliveF then return nil end
    local list = {}
    for _, m in ipairs(aliveF:GetChildren()) do
        if m.Name ~= LP.Name and m.PrimaryPart then list[#list + 1] = m end
    end
    if #list == 0 then return nil end
    local cf = cam.CFrame
    local origin, look = cf.Position, cf.LookVector
    local dir
    if UIS.MouseEnabled then
        local ml = UIS:GetMouseLocation()
        dir = cam:ScreenPointToRay(ml.X, ml.Y).Direction
    else
        local vs = cam.ViewportSize
        dir = cam:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5).Direction
    end
    local best, bestDot = nil, -math.huge
    for _, m in ipairs(list) do
        local d = m.PrimaryPart.Position - origin
        if d.Magnitude > 0 then
            local u = d.Unit
            if look:Dot(u) > 0 then
                local dot = dir:Dot(u)
                if bestDot < dot then bestDot, best = dot, m end
            end
        end
    end
    return best or list[1]
end

function Remote.screen(lock)
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local target = Remote.pickTarget(cam)
    local tpp = target and target.PrimaryPart
    local aim
    if tpp then
        local v = cam:WorldToViewportPoint(tpp.Position)
        aim = {v.X, v.Y}
    elseif UIS.MouseEnabled then
        local ml = UIS:GetMouseLocation()
        aim = {ml.X, ml.Y}
    else
        local vs = cam.ViewportSize
        aim = {vs.X * 0.5, vs.Y * 0.5}
    end
    local pos = {}
    if lock and tpp then
        local sp = cam:WorldToScreenPoint(tpp.Position)
        if sp.Z > 0 then pos[target.Name] = sp end
    end
    if next(pos) == nil then   -- โหมดทุกคน หรือหาเป้าล็อกไม่ได้
        local aliveF = workspace:FindFirstChild("Alive")
        if aliveF then
            for _, m in ipairs(aliveF:GetChildren()) do
                local pp = m.PrimaryPart
                if pp then
                    local sp = cam:WorldToScreenPoint(pp.Position)
                    if sp and sp.Z > 0 then pos[m.Name] = sp end
                end
            end
        end
    end
    return cam.CFrame, pos, aim, target
end

-- หาฟังก์ชันสร้างโทเค็นของเกม (ทำครั้งเดียว ในเธรดแยก กันจอค้าง)
function Remote.findToken()
    if Remote.tokenFn then return true end
    if Remote.tokenTried then return false end
    Remote.tokenTried = true
    if not (getgc and debug and debug.info and debug.getupvalues) then return false end
    pcall(function()
        local n = 0
        for _, f in ipairs(getgc(true)) do
            if type(f) == "function" then
                local okS, src = pcall(debug.info, f, "s")
                if okS and type(src) == "string" and string.find(src, "PRY", 1, true) then
                    local okU, ups = pcall(debug.getupvalues, f)
                    if okU and type(ups) == "table" then
                        for _, u in pairs(ups) do
                            if type(u) == "function" then Remote.tokenFn = u return end
                        end
                    end
                end
            end
            n = n + 1
            if n % 3000 == 0 then task.wait() end
        end
    end)
    return Remote.tokenFn ~= nil
end

function Remote.tokenize(seed)
    local t = tostring(math.floor(workspace:GetServerTimeNow() * 100))
    local k = Remote.tokenFn(seed, "TIME")
    local out = table.create(#t)
    for i = 1, #t do
        out[i] = string.char(bit32.bxor((string.byte(t, i) + i) % 256, string.byte(k, (i - 1) % #k + 1)))
    end
    return table.concat(out)
end

function Remote.validArgs(a)
    return a.n == 8 and type(a[2]) == "string" and type(a[3]) == "string" and type(a[4]) == "number"
        and typeof(a[5]) == "CFrame" and type(a[6]) == "table" and type(a[7]) == "table" and type(a[8]) == "boolean"
end

function Remote.unhook()
    for mt, orig in pairs(Remote.originals) do
        pcall(function() setreadonly(mt, false) mt.__index = orig setreadonly(mt, true) end)
    end
    table.clear(Remote.hooked) table.clear(Remote.originals)
end

-- ดักรีโมทจริงของเกม 1 ครั้ง แล้วถอดตัวดักออกทันที
function Remote.hook()
    if next(Remote.captured) ~= nil or next(Remote.hooked) ~= nil then return end
    if not (getrawmetatable and setreadonly) then return end
    if os.clock() - Remote.hookAt < 10 then return end
    Remote.hookAt = os.clock()
    local ref
    for _, d in ipairs(RepStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then ref = d break end
    end
    if not ref then return end
    local ok, err = pcall(function()
        local mt = getrawmetatable(ref)
        local index = mt.__index
        if type(index) ~= "function" then error("__index ไม่ใช่ฟังก์ชัน") end
        Remote.hooked[mt] = true
        Remote.originals[mt] = index
        setreadonly(mt, false)
        mt.__index = function(self, key)
            if key == "FireServer" or key == "InvokeServer" then
                local cls = index(self, "ClassName")
                if (key == "FireServer" and cls == "RemoteEvent") or (key == "InvokeServer" and cls == "RemoteFunction") then
                    local fn = index(self, key)
                    return function(s, ...)
                        local a = table.pack(...)
                        if next(Remote.captured) == nil and Remote.validArgs(a) then
                            Remote.captured[self] = a
                            task.defer(function()
                                Remote.unhook()
                                if toast then toast("รีโมท: จำค่าพาร์รี่ของเกมได้แล้ว") end
                            end)
                        end
                        return fn(s, ...)
                    end
                end
            end
            return index(self, key)
        end
        setreadonly(mt, true)
    end)
    if ok then task.spawn(Remote.findToken)
    else Remote.originals = {} Remote.hooked = {} Dbg.log("รีโมท/ดัก: " .. tostring(err), "hook", 5) end
end

function Remote.available()
    if Remote.initPry() then return true end
    if next(Remote.captured) ~= nil and Remote.tokenFn then return true end
    if not Remote.warmupDone then return false end   -- ยังหา PRY อยู่ ไม่ต้องรบกวนผู้เล่น
    Remote.hook()                                     -- ทางสุดท้าย: ดักค่าจากพาร์รี่จริง
    if not Remote.warned then
        Remote.warned = true
        if toast then toast("รีโมท: ไม่พบ PRY ของเกม (เกมอาจอัปเดต) ใช้โหมดดักค่า: พาร์รี่เองสักครั้ง") end
    end
    return false
end

function Remote.replay(power, cf, pos, aim)
    if not Remote.tokenFn or next(Remote.captured) == nil then return false end
    local sent = false
    for r, a in pairs(Remote.captured) do
        if r.Parent then
            local okT, tok = pcall(Remote.tokenize, a[2])
            if not okT then
                -- ฟังก์ชันโทเค็นที่จำไว้ใช้ไม่ได้แล้ว: ทิ้งแล้วหาใหม่
                Remote.tokenFn, Remote.tokenTried = nil, false
                Dbg.log("โทเค็น error: " .. tostring(tok), "tok", 5)
                task.spawn(Remote.findToken)
                return false
            end
            -- arg1, arg2 = ค่าที่ดักได้จากรีโมทจริง | arg3 = โทเค็นใหม่ทุกครั้ง | arg4 = power | arg5-7 = กล้อง/ตำแหน่ง/กลางจอ | arg8 = false
            local args = {a[1], a[2], tok, power, cf, pos, aim, false}
            if r:IsA("RemoteEvent") then
                r:FireServer(table.unpack(args, 1, 8)) sent = true
            elseif r:IsA("RemoteFunction") then
                task.spawn(function() pcall(function() r:InvokeServer(table.unpack(args, 1, 8)) end) end) sent = true
            end
        end
    end
    return sent
end

-- ตรวจค่าที่จำไว้ว่ายังใช้ได้ไหม แล้วซ่อมเฉพาะส่วนที่เสีย (ไม่ล้างทิ้งทั้งหมด จะได้ไม่ต้องพาร์รี่เองใหม่โดยไม่จำเป็น)
function Remote.heal()
    local now = os.clock()
    if now - Remote.healAt < 15 then return end
    Remote.healAt = now
    local fixed = {}
    if Remote.pry then
        local ok, fresh = pcall(Remote.findPry)
        if not ok or fresh ~= Remote.pry then
            Remote.dropPry()
            Remote.pryAt = -10   -- ให้หาใหม่ได้ทันที
            fixed[#fixed + 1] = "PRY"
        end
    end
    for r in pairs(Remote.captured) do
        if not r.Parent then Remote.captured[r] = nil fixed[#fixed + 1] = "ดักค่า" end
    end
    if #fixed > 0 then
        Dbg.log("รีโมทซ่อม: " .. table.concat(fixed, ","))
        if toast then toast("รีโมท: ค่าที่จำไว้เสีย ซ่อมใหม่แล้ว (" .. table.concat(fixed, ", ") .. ")") end
    else
        Dbg.log("รีโมทพลาดติดกันแต่ค่าปกติ (น่าจะเป็นเรื่องจังหวะ)")
    end
end

function Remote.noteFail()
    Remote.failStreak = Remote.failStreak + 1
    if Remote.failStreak >= 3 then
        Remote.failStreak = 0
        Remote.heal()
    end
end
function Remote.noteOk() Remote.failStreak = 0 end

-- arg4 (power): สคริปต์ตัวอย่างส่ง 0.5 ทุกครั้ง ทั้งพาร์รี่ปกติและสแปม (ถ้าจะลองค่าอื่นสำหรับสแปม แก้ POWER_SPAM)
local POWER_NORMAL, POWER_SPAM = 0.5, 0.5

-- ยิงพาร์รี่ 1 ครั้ง  isSpam = true/false  (arg6 ตาม S.ParryTarget: Everyone | Lock)
local function fireparry(isSpam)
    local now = os.clock()
    if now - Remote.windowAt > 0.5 then Remote.windowAt, Remote.count = now, 0 end
    if Remote.count >= 8 then return false end   -- จำกัดความถี่ ไม่ให้รัวเกินจนผิดปกติ
    Remote.count = Remote.count + 1
    local cf, pos, aim = Remote.screen(S.ParryTarget == "Lock")
    if not cf then return false end
    local power = isSpam and POWER_SPAM or POWER_NORMAL   -- arg4
    -- ทางที่ 1: เรียก PRY ของเกม (เกมประกอบ arg1-arg3 ให้เอง)
    if Remote.initPry() then
        if pcall(function() Remote.signal:Fire(power, cf, pos, aim, false) end) then
            Remote.stage = "PRY" return true
        end
        Remote.dropPry()   -- Signal ใช้ไม่ได้แล้ว: ทิ้งแล้วสร้างใหม่รอบหน้า
    end
    -- ทางที่ 2: ยิงรีโมทที่ดักไว้ซ้ำ ด้วยโทเค็นใหม่
    if Remote.replay(power, cf, pos, aim) then Remote.stage = "REPLAY" return true end
    Remote.stage = "ไม่พร้อม"
    return false
end
-- วอร์มอัป: รอเกมโหลดแล้วหา PRY เองเบื้องหลัง (สูงสุด 25 วิ) ผู้เล่นไม่ต้องพาร์รี่ก่อน
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local t0 = os.clock()
    while alive and not Remote.pry and os.clock() - t0 < 25 do
        Remote.pryAt = -10
        Remote.initPry()
        if Remote.pry then break end
        task.wait(0.75)
    end
    Remote.warmupDone = true
    if not alive then return end
    if Remote.pry then
        Dbg.log("รีโมท: พบ PRY (" .. tostring(Remote.pryHow) .. ")")
        if toast then toast("รีโมทพร้อมใช้งาน") end
    else
        Dbg.log("รีโมท: หา PRY ไม่เจอ -> " .. tostring(Remote.pryErr))
        pcall(Remote.available)
    end
end)

local Stat = {sent = 0, ok = 0, fail = 0, combo = 0, best = 0, lastPath = "-", lastErr = "ไม่มี", errCount = 0}
local lastPress, warnedNoPath = 0, false

------------------------------------------------------------------ คูลดาวน์พาร์รี่ของเกม (Remotes.VisualCD)
-- เซิร์ฟเวอร์ส่ง 3 ค่า (true, true, 1.3) = เริ่มคูลดาวน์ -> ล็อกการยิงพาร์รี่ไว้
-- เซิร์ฟเวอร์ส่งค่าเดียว (true)         = คูลดาวน์จบ -> ปลดจริงหลัง 0.07 วิ (task.delay)
-- ถ้าล็อกนานเกิน 0.67 วิ ปลดเองทันที (ไม่รอ 1.3 วิเต็ม)
-- ใช้ task.delay ได้ทีละตัว: มีตัวใหม่เข้ามา = task.cancel ตัวเก่าก่อนเสมอ
local Cd = {active = false, startedAt = 0, duration = 1.3, handle = nil, hooked = false, MAX = 0.67, REL = 0.07}

function Cd.schedule(sec, fn)
    if Cd.handle then pcall(task.cancel, Cd.handle) Cd.handle = nil end
    local h
    h = task.delay(sec, function()
        if Cd.handle == h then Cd.handle = nil end
        fn()
    end)
    Cd.handle = h
end

function Cd.release() Cd.active = false end

function Cd.onEvent(...)
    local n = select("#", ...)
    local a, _, c = ...
    if n >= 3 then                                  -- (true, true, 1.3) เริ่มคูลดาวน์
        Cd.active = true
        Cd.startedAt = os.clock()
        Cd.duration = tonumber(c) or Cd.duration
        Cd.schedule(Cd.MAX, Cd.release)             -- เพดาน 0.67 วิ
    elseif n == 1 and a == true and Cd.active then  -- (true) คูลดาวน์จบก่อนครบ 0.67 วิ
        Cd.schedule(Cd.REL, Cd.release)         -- ปลดจริงหลัง 0.07 วิ (ยกเลิกตัวเดิมแล้ว)
    end
end

task.spawn(pcall, function()
    local rem = RepStorage:WaitForChild("Remotes", 10)
    local ev = rem and rem:WaitForChild("VisualCD", 10)
    if not ev then return end
    bind(ev.OnClientEvent, Cd.onEvent)
    Cd.hooked = true
end)

-- ยิงพาร์รี่ 1 ครั้ง (ผ่านรีโมทอย่างเดียว) คืน true ถ้าส่งสำเร็จ
local function doParry(minGap, isSpam)
    local now = os.clock()
    if now - lastPress < (minGap or 0.03) then return false end
    if Cd.active then Stat.lastPath = "คูลดาวน์ของเกม" return false end   -- เกมยังติดคูลดาวน์: ไม่ยิง
    if not Remote.available() then
        Stat.lastPath = "รีโมทไม่พร้อม"
        Dbg.log("รีโมทไม่พร้อม", "nopath", 3)
        if Remote.warmupDone and not warnedNoPath then warnedNoPath = true toast("ส่งพาร์รี่ไม่ได้: รีโมทยังไม่พร้อม") end
        return false
    end
    lastPress = now
    local ok = false
    local okc, err = pcall(function() ok = fireparry(isSpam) end)
    if not okc then Dbg.log("รีโมท error: " .. tostring(err), "pe", 3) end
    if ok then
        warnedNoPath = false
        Stat.lastPath = "รีโมท" Stat.sent = Stat.sent + 1
        return true
    end
    Stat.lastPath = "รีโมท (ส่งไม่ออก)"
    return false
end

local testing = false
function Engine.test()
    if testing then return end
    if not Remote.available() then toast(Remote.warmupDone and "รีโมทยังไม่พร้อม: ลองพาร์รี่เองในเกมสักครั้งให้ระบบจำค่า" or "กำลังหารีโมท รอสักครู่") return end
    testing = true
    task.spawn(function()
        local ok = false
        pcall(function() ok = fireparry(false) end)
        toast("ทดสอบรีโมท [" .. Remote.stage .. "]" .. (ok and " (ส่งแล้ว)" or " (ไม่สำเร็จ)"))
        Dbg.log("ทดสอบรีโมท -> " .. tostring(ok))
        task.wait(1.5)
        testing = false
    end)
end

------------------------------------------------------------------ สกิล
local abRemote, abRemoteAt, abBtn, abBtnAt = nil, 0, nil, 0
local function useAbility()
    local now = os.clock()
    if not (abRemote and abRemote.Parent) then
        abRemote = nil
        if now - abRemoteAt > 2 then
            abRemoteAt = now
            pcall(function()
                local r = RepStorage:FindFirstChild("Remotes")
                abRemote = (r and r:FindFirstChild("AbilityButtonPress")) or RepStorage:FindFirstChild("AbilityButtonPress", true)
            end)
        end
    end
    if abRemote then
        local ok = false
        pcall(function()
            if abRemote:IsA("RemoteEvent") then abRemote:FireServer() ok = true
            elseif abRemote:IsA("BindableEvent") then abRemote:Fire() ok = true end
        end)
        if ok then return true end
    end
    if not (abBtn and abBtn.Parent) then
        abBtn = nil
        if now - abBtnAt > 3 then
            abBtnAt = now
            local pg = LP:FindFirstChildOfClass("PlayerGui")
            if pg then
                pcall(function()
                    for _, d in ipairs(pg:GetDescendants()) do
                        if d:IsA("GuiButton") and not d:IsDescendantOf(gui) then
                            local nm = string.lower(d.Name)
                            if d:IsA("TextButton") then nm = nm .. " " .. string.lower(d.Text) end
                            if string.find(nm, "ability", 1, true) then abBtn = d return end
                        end
                    end
                end)
            end
        end
    end
    if abBtn then
        local ok = false
        for _, nm in ipairs({"Activated", "MouseButton1Down", "MouseButton1Click", "MouseButton1Up"}) do
            local sig = abBtn[nm]
            if firesignal then
                if pcall(function() firesignal(sig) end) then ok = true end
            end
            if getconnections then
                pcall(function()
                    for _, cn in ipairs(getconnections(sig)) do
                        if cn.Function then cn:Fire() ok = true end
                    end
                end)
            end
        end
        return ok
    end
    return false
end

------------------------------------------------------------------ ภาพ (ESP / FOV / สว่าง)
local espMap = {}
local function clearEsp()
    for b, h in pairs(espMap) do pcall(function() h:Destroy() end) espMap[b] = nil end
end
local fovApplied, lightApplied, origLight, lastLightAt = false, false, nil, 0
local function applyVisual(now)
    local cam = workspace.CurrentCamera
    if S.FOVOn and cam then cam.FieldOfView = S.FOV fovApplied = true
    elseif fovApplied and cam then cam.FieldOfView = 70 fovApplied = false end
    if S.Fullbright then
        if not origLight then
            origLight = {Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
                GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient}
        end
        if now - lastLightAt > 1 then
            lastLightAt = now
            Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e5
            Lighting.GlobalShadows = false Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            lightApplied = true
        end
    elseif lightApplied and origLight then
        for k, v in pairs(origLight) do pcall(function() Lighting[k] = v end) end
        lightApplied = false
    end
end
Hooks.BallESP = function(v) if not v then clearEsp() end end

------------------------------------------------------------------ ความปลอดภัย (ตรวจความผิดปกติ + เฝ้าระวังโดนเตะ/แบน)
local Safety = {events = {}, guardUntil = 0, guardWhy = "-", warnAt = {}}
local function safeEvent(msg, key, gap)
    local now = os.clock()
    if key then
        if Safety.warnAt[key] and now - Safety.warnAt[key] < (gap or 5) then return end
        Safety.warnAt[key] = now
    end
    local t = Safety.events
    t[#t + 1] = os.date("%H:%M:%S") .. "  " .. msg
    if #t > 7 then table.remove(t, 1) end
    Dbg.log(msg)
    if eventLbl then
        local rev = {}
        for i = #t, 1, -1 do rev[#rev + 1] = t[i] end
        eventLbl.Text = table.concat(rev, "\n")
    end
end
local function guardFor(sec, why)
    Safety.guardUntil = math.max(Safety.guardUntil, os.clock() + sec)
    Safety.guardWhy = why
    safeEvent("ระบบกันพลาด: " .. why, "g" .. why, 4)
end

-- ตรวจความผิดปกติของสคริปต์/เกมเราเอง (เตือน + พักออโต้สั้น ๆ ไม่ได้ปิดถาวร)
local Anom = {fail = 0, ok = 0, sent = 0, streak = 0, sentTimes = {}, lowSince = nil, remoteBad = 0}
local function anomalyStep(now, dt)
    if not S.AnomalyWatch then return end
    -- 1) พลาดติดกัน
    if Stat.fail > Anom.fail then Anom.streak = Anom.streak + (Stat.fail - Anom.fail) end
    if Stat.ok > Anom.ok then Anom.streak = 0 end
    Anom.fail, Anom.ok = Stat.fail, Stat.ok
    if Anom.streak >= 6 then
        Anom.streak = 0
        guardFor(1, "พลาดติดกัน 6 ครั้ง: เช็กจังหวะ/พรีเซ็ต")
        pcall(function() toast("พลาดติดกัน 6 ครั้ง: พักออโต้ 1 วิ ลองปรับพรีเซ็ตจังหวะ") end)
    end
    -- 2) ยิงพาร์รี่ถี่เกินปกติ
    if Stat.sent > Anom.sent then
        for _ = 1, Stat.sent - Anom.sent do Anom.sentTimes[#Anom.sentTimes + 1] = now end
    end
    Anom.sent = Stat.sent
    while Anom.sentTimes[1] and now - Anom.sentTimes[1] > 1 do table.remove(Anom.sentTimes, 1) end
    if #Anom.sentTimes > 14 then
        table.clear(Anom.sentTimes)
        guardFor(1.5, "ยิงพาร์รี่ถี่ผิดปกติ (>14 ครั้ง/วิ)")
    end
    -- 3) FPS ต่ำต่อเนื่อง
    if dt > 0.05 then
        Anom.lowSince = Anom.lowSince or now
        if now - Anom.lowSince > 3 then
            Anom.lowSince = now
            safeEvent("FPS ต่ำต่อเนื่อง (<20) จังหวะพาร์รี่จะเพี้ยน ลองเปิด 'ลดกราฟิก'", "lowfps", 20)
        end
    else
        Anom.lowSince = nil
    end
    -- 4) รีโมทไม่พร้อม
    if S.AutoParry and Remote.warmupDone and Remote.stage == "ไม่พร้อม" then
        Anom.remoteBad = Anom.remoteBad + 1
        if Anom.remoteBad == 1 then
            safeEvent("รีโมทไม่พร้อม (ไม่พบ PRY/ยังไม่จำค่า) ออโต้พาร์รี่จะยิงไม่ออก ลองพาร์รี่เองในเกมสักครั้ง", "remotebad", 30)
        end
    else
        Anom.remoteBad = 0
    end
end
pcall(function()
    bind(TeleportSvc.TeleportInitFailed, function(_, res, msg)
        safeEvent("เทเลพอร์ตล้มเหลว: " .. tostring(res) .. " " .. tostring(msg):sub(1, 60), "tpfail", 5)
    end)
end)

local banned = false
local function classifyMsg(msg)
    local m = string.lower(msg or "")
    if m == "" then return nil end
    if string.find(m, "banned", 1, true) or string.find(m, "%f[%a]ban%f[%A]") then return "ban" end
    if string.find(m, "kick", 1, true) then return "kick" end
    if string.find(m, "disconnect", 1, true) or string.find(m, "lost connection", 1, true) or string.find(m, "shut down", 1, true)
        or string.find(m, "error code", 1, true) or string.find(m, "connection", 1, true) then return "disc" end
    return "other"
end
local function onGameMessage(msg)
    if not S.BanWatch or banned then return end
    local kind = classifyMsg(msg)
    if not kind then return end
    banned = true
    setState("AutoParry", false) setState("AutoSpam", false) setState("AutoAbility", false)
    local th = ({ban = "ถูกแบน", kick = "ถูกเตะ", disc = "หลุดการเชื่อมต่อ", other = "เกมขึ้นข้อความแจ้งเตือน"})[kind]
    local short = tostring(msg):sub(1, 90)
    safeEvent("ตรวจพบ: " .. th .. " — " .. short)
    if banLbl then
        banLbl.Text = "ตรวจพบ: " .. th .. " (" .. os.date("%H:%M:%S") .. ")\n" .. short
        banLbl.TextColor3 = C.BAD
    end
    if safeLbl then safeLbl.Text = th safeLbl.TextColor3 = C.BAD end
    pcall(function()
        if writefile then writefile("MeenHub_BB_lastEvent.txt", os.date("%Y-%m-%d %H:%M:%S") .. "  " .. th .. "\n" .. tostring(msg)) end
    end)
    pcall(function() toast("ตรวจพบ: " .. th .. " — ปิดออโต้แล้ว") end)
    if S.AutoRejoin and kind ~= "ban" then
        task.delay(4, function()
            if alive then pcall(function() TeleportSvc:Teleport(game.PlaceId, LP) end) end
        end)
    end
end
bind(GuiService.ErrorMessageChanged, function(msg)
    local m = msg
    if type(m) ~= "string" or m == "" then m = GuiService:GetErrorMessage() end
    onGameMessage(m)
end)
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    local overlay = CoreGui:WaitForChild("RobloxPromptGui", 3):WaitForChild("promptOverlay", 3)
    bind(overlay.ChildAdded, function(ch)
        task.wait(0.2)
        local txt
        pcall(function()
            for _, d in ipairs(ch:GetDescendants()) do
                if d:IsA("TextLabel") and d.Name == "ErrorMessage" then txt = d.Text end
            end
        end)
        onGameMessage(txt or GuiService:GetErrorMessage() or "")
    end)
end)

bind(LP.Idled, function()
    if not S.AntiAFK then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end)

------------------------------------------------------------------ 3) ตัวตรวจจับ + ออโต้พาร์รี่ + ออโต้สแปม
local trk = setmetatable({}, {__mode = "k"})
local pending = {}
local hudUpdate, flashFn = function() end, function() end
local Learn = {shift = 0, early = 0, late = 0}   -- ระบบเรียนรู้จังหวะ: shift (วินาที) บวก = ยิงเร็วขึ้น
local Info = {has = false, speed = 0, dist = 0, tti = math.huge, target = "-", me = false, why = "-"}
local pingMs, spamAcc, lastAbility, maxSpeed = 0, 0, 0, 0
local fpsNow, fpsHist = 60, {}
local fpsAcc, fpsN, lastFpsAt, lastUiAt, lastDiagAt = 0, 0, 0, 0, 0
local HIT_RADIUS = 4

local function logErr(e)
    Stat.errCount = Stat.errCount + 1
    Stat.lastErr = tostring(e):sub(1, 140)
    Dbg.log("ERROR: " .. tostring(e):sub(1, 200), "err" .. tostring(e):sub(1, 30), 3)
end

-- เวลาถึงตัว (บอลเล็งตาม = ไล่ล่าเป้าที่กำลังเคลื่อนที่)
--   T = d * (s + vA) / (s^2 - |vm|^2)
--   d = ระยะ (หักรัศมีโดน) | s = ความเร็วบอล | vm = ความเร็วตัวเรา | vA = ส่วนของ vm ที่วิ่ง "หนี" บอล (ติดลบ = วิ่งเข้าหา)
--   ตรวจแล้ว: อยู่นิ่ง T=d/s | วิ่งหนีตรงๆ T=d/(s-v) | วิ่งเข้าหา T=d/(s+v)
--   ถ้าบอลเร่งความเร็ว ใช้ความเร็วเฉลี่ยตลอดช่วงที่เหลือ (วนคิด 2 รอบ)
local function pursuitTime(dist, sp, vA, vm2, accel)
    local d = math.max(dist - HIT_RADIUS, 0)
    if d <= 0 then return 0 end
    local function T(x)
        if x <= 1 or x * x <= vm2 * 1.1025 then return math.huge end   -- บอลช้ากว่าที่เราวิ่งหนี = ไม่มีทางถึง
        return d * (x + vA) / (x * x - vm2)
    end
    local t = T(sp)
    local a = math.clamp(accel or 0, 0, sp * 1.5)
    if a > 1 and t ~= math.huge then
        for _ = 1, 2 do
            local t2 = T(sp + a * math.min(t, 1) * 0.5)
            if t2 == math.huge then break end
            t = t2
        end
    end
    return t
end

local function enemyNear(ctx, r)
    if ctx.enemy ~= nil then return ctx.enemy end
    ctx.enemy = false
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local h = p.Character:FindFirstChild("HumanoidRootPart")
            local hm = p.Character:FindFirstChildOfClass("Humanoid")
            if h and hm and hm.Health > 0 and (h.Position - ctx.hrp.Position).Magnitude <= r then ctx.enemy = true break end
        end
    end
    return ctx.enemy
end

local function rollJitter(tr)
    tr.jit = 0
end

------------------------------------------------------------------ ฮิตบอกซ์ / ป้ายบอล / วงระยะพาร์รี่
-- แยกจากระบบออโต้ทั้งหมด: ถ้าส่วนนี้พัง จะถูกปิดเองและออโต้ยังทำงานต่อ
local hbMap, ringAd, featErrs = {}, nil, {}
local function featErr(name, e)
    featErrs[name] = (featErrs[name] or 0) + 1
    Dbg.log("FEATURE " .. name .. ": " .. tostring(e):sub(1, 160), "fe" .. name, 3)
    if featErrs[name] >= 20 then
        featErrs[name] = 0
        if name == "hitbox" then setState("HitboxESP", false) setState("BallTag", false) setState("ParryRing", false)
        elseif name == "visual" then setState("FOVOn", false) setState("Fullbright", false) end
        toast("ฟีเจอร์ภาพพัง: ปิดให้แล้ว (ออโต้ยังทำงานปกติ)")
    end
end
local function clearHb()
    for b, e in pairs(hbMap) do
        pcall(function() if e.adorn then e.adorn:Destroy() end if e.tag then e.tag:Destroy() end end)
        hbMap[b] = nil
    end
    if ringAd then pcall(function() ringAd:Destroy() end) ringAd = nil end
end
local function updateHitVisuals(balls, ctx)
    local cam = workspace.CurrentCamera
    if not (S.HitboxESP or S.BallTag or S.ParryRing) then
        if next(hbMap) or ringAd then clearHb() end
        return
    end
    local seen = {}
    for _, b in ipairs(balls) do
        seen[b] = true
        local tr = trk[b]
        local mine = tr ~= nil and tr.wasMe
        local e = hbMap[b]
        if not e then e = {} hbMap[b] = e end
        if S.HitboxESP then
            if not (e.adorn and e.adorn.Parent) then
                local a = Instance.new("SphereHandleAdornment")
                a.Adornee = b a.Radius = HIT_RADIUS a.Transparency = 0.7 a.AlwaysOnTop = true a.ZIndex = 1
                a.Parent = cam or workspace
                e.adorn = a
            end
            e.adorn.Color3 = mine and C.BAD or C.CYAN
        elseif e.adorn then
            e.adorn:Destroy() e.adorn = nil
        end
        if S.BallTag then
            if not (e.tag and e.tag.Parent) then
                local g = Instance.new("BillboardGui")
                g.Adornee = b g.Size = UDim2.fromOffset(130, 34) g.StudsOffset = Vector3.new(0, 4, 0) g.AlwaysOnTop = true
                g.Parent = gui
                local l = Instance.new("TextLabel")
                l.Size = UDim2.fromScale(1, 1) l.BackgroundColor3 = C.BG l.BackgroundTransparency = 0.3 l.TextColor3 = C.TEXT
                l.Font = Enum.Font.GothamBold l.TextSize = 12 l.Text = "-"
                corner(8).Parent = l
                l.Parent = g
                e.tag, e.lbl = g, l
            end
            if tr and ctx.hrp then
                local tti = tr.tti or math.huge
                e.lbl.Text = string.format("%d u/s   %s", math.floor(tr.speed), tti == math.huge and "--" or string.format("%.2fs", tti))
                e.lbl.TextColor3 = mine and C.BAD or C.TEXT
            end
        elseif e.tag then
            e.tag:Destroy() e.tag, e.lbl = nil, nil
        end
    end
    for b, e in pairs(hbMap) do
        if not seen[b] or not b.Parent then
            pcall(function() if e.adorn then e.adorn:Destroy() end if e.tag then e.tag:Destroy() end end)
            hbMap[b] = nil
        end
    end
    if S.ParryRing and ctx.hrp and ctx.alive then
        if not (ringAd and ringAd.Parent) then
            ringAd = Instance.new("SphereHandleAdornment")
            ringAd.Transparency = 0.88 ringAd.AlwaysOnTop = true ringAd.ZIndex = 0 ringAd.Color3 = C.VIOLET
            ringAd.Parent = cam or workspace
        end
        ringAd.Adornee = ctx.hrp
        local sp = Info.has and Info.speed or 0
        ringAd.Radius = math.clamp(math.max(S.PointBlank, sp * ctx.lead + HIT_RADIUS), 4, 250)
    elseif ringAd then
        ringAd:Destroy() ringAd = nil
    end
end

-- ตำแหน่งบอลจริงที่เซิร์ฟเวอร์ส่งมา (สดกว่า Position ของพาร์ทฝั่งเรา ซึ่งอัปเดตเป็นช่วงๆ และดีเลย์)
local BallNet = {pos = setmetatable({}, {__mode = "k"}), at = setmetatable({}, {__mode = "k"})}
task.spawn(function()
    pcall(function()
        local pk = RepStorage:WaitForChild("Packages", 15)
        local idx = pk and pk:WaitForChild("_Index", 15)
        if not idx then return end
        local net
        for _, c in ipairs(idx:GetChildren()) do
            if string.find(c.Name, "sleitnick_net", 1, true) == 1 then
                net = c:FindFirstChild("net")
                if net then break end
            end
        end
        if not net then return end
        local n = 0
        for _, r in ipairs(net:GetChildren()) do
            if r:IsA("UnreliableRemoteEvent") and r.Name ~= "URE/ReplicateBallPosition" then
                n = n + 1
                bind(r.OnClientEvent, function(ball, p)
                    if typeof(ball) == "Instance" and typeof(p) == "Vector3" and ball:IsA("BasePart") and ball:GetAttribute("realBall") == true then
                        BallNet.pos[ball] = p
                        BallNet.at[ball] = os.clock()
                    end
                end)
            end
        end
        Dbg.log("ตำแหน่งบอลสด: ฟัง " .. n .. " ช่อง")
    end)
end)
local function ballPos(b, now, v)
    local p = BallNet.pos[b]
    if p then
        local age = now - (BallNet.at[b] or 0)
        if age < 0.3 then
            if v and age > 0 then p = p + v * math.min(age, 0.1) end
            return p
        end
    end
    return b.Position
end

------------------------------------------------------------------ ตรรกะจังหวะตรงตามสคริปต์ตัวอย่าง
-- ยิงเมื่อ: เป้าบอล = เรา และ ระยะ <= clamp(ปิง/100, 5, 17) + max(ความเร็ว / n, 9.5)
--   ความเร็ว = zoomies.VectorVelocity  ระยะ = ตำแหน่งบอลที่ส่งมาแบบ unreliable (ไม่เดาล่วงหน้า)
-- ยิงแล้วหยุดจนกว่าเป้าบอลจะเปลี่ยน / มีบอลใหม่ / บอลหาย  (นี่คือตัวกันตีซ้ำ)
local Ref = {debounce = false, untilAt = 0, state = {aero = os.clock(), lerp = 0, lastWarp = os.clock(), curving = os.clock()}}
function Ref.reset() Ref.debounce, Ref.untilAt = false, 0 end

-- ตำแหน่งบอลที่ส่งมาแบบ unreliable + ชดเชยอายุข้อมูล (สูงสุด 0.1 วิ) ให้ระยะตรงกับตำแหน่งจริงตอนนี้
function Ref.pos(b, now, v) return ballPos(b, now or os.clock(), v) end

function Ref.firstBall()
    for _, bb in ipairs(getBalls()) do
        if bb:GetAttribute("realBall") then return bb end
    end
    return getBalls()[1]
end

-- บอลโค้ง/หักเลี้ยว: ถ้าใช่ จะไม่พาร์รี่ (ตามตัวอย่าง)
function Ref.curved(b, now)
    local ok, res = pcall(function()
        local z = b:FindFirstChild("zoomies")
        if not z then return false end
        local ch = LP.Character
        local pp = ch and ch.PrimaryPart
        if not pp then return false end
        local ping = getPing()
        local vv = z.VectorVelocity
        local mag = vv.Magnitude
        if mag < 1e-3 then return false end
        local unit = vv.Unit
        local position = pp.Position
        local delta = position - Ref.pos(b, now, vv)
        local dist = delta.Magnitude
        if dist < 1e-3 then return false end
        local unit2 = delta.Unit
        local dot = unit2:Dot(unit)
        local v90 = math.min(mag / 100, 40)
        local n31 = dot - unit2:Dot((unit - vv).Unit)
        local n32 = 0.5 - ping / 1000
        local n33 = dist / mag - ping / 1000
        local n34 = 15 - math.min(dist / 1000, 15) + v90
        local st = Ref.state
        st.lerp = st.lerp + (math.rad(math.asin(math.clamp(dot, -1, 1))) - st.lerp) * 0.8
        if mag > 100 and n33 > ping / 10 then n34 = math.max(n34 - 15, 15) end
        if dist < n34 then return false end
        if n31 < n32 then return true end
        if st.lerp < 0.018 then st.lastWarp = now end
        if now - st.lastWarp < n33 / 1.5 then return true end
        if now - st.curving < n33 / 1.5 then return true end
        return dot < n32
    end)
    return ok and res or false
end

-- คืน (ควรยิงไหม, เหตุผล)
function Ref.check(b, now)
    if Ref.debounce or now < Ref.untilAt then return false, "ยิงแล้ว รอเป้าบอลเปลี่ยน" end
    local ch = LP.Character
    local pp = ch and ch.PrimaryPart
    if not pp then return false, "ไม่มีตัวละคร" end
    local z = b:FindFirstChild("zoomies")
    if not z then return false, "บอลไม่มี zoomies" end
    local speed = z.VectorVelocity.Magnitude
    local vel = z.VectorVelocity
    local toMe = pp.Position - Ref.pos(b, now, vel)
    local d = toMe.Magnitude
    local ping = getPing()
    local pterm = math.clamp(ping / 10 / 10, 5, 17)
    local acc = (S.RefAccuracy - 1) * 0.015151515151515152
    local n = (2.4 + math.min(math.max(speed - 9.5, 0), 650) * 0.002) * acc
    local reach = pterm + math.max(speed / n, 9.5)
    local rt = workspace:FindFirstChild("Runtime")
    local tornado = rt and rt:FindFirstChild("Tornado")
    local aero = b:FindFirstChild("AeroDynamicSlashVFX")
    if aero then pcall(function() game:GetService("Debris"):AddItem(aero, 0) end) Ref.state.aero = now end
    if tornado and now - Ref.state.aero < (tornado:GetAttribute("TornadoTime") or 1) + 0.314159 then return false, "พายุ/Aerodynamic" end
    local first = Ref.firstBall()
    if first and first:GetAttribute("target") == LP.Name and Ref.curved(b, now) then
        -- ตามตัวอย่าง บอลโค้งจะรอจนบอลเข้าใกล้มาก (ราว 15-55 หน่วย) ซึ่งที่ความเร็วสูงจะยิงช้าเกินไป
        -- แก้: ถ้าเวลาถึงตัว (ประมาณ) เหลือไม่เกิน 'ปิง + 0.09 วิ' ต้องยิงเลย ไม่รอต่อ
        local closing = d > 0.01 and vel:Dot(toMe / d) or 0
        local tti = closing > 1 and math.max(d - HIT_RADIUS, 0) / closing or math.huge
        local lead = ping / 1000 + 0.09 + math.clamp(Learn.shift, -0.05, 0.15)
        if tti > lead then return false, string.format("บอลโค้ง: รอ (ถึงใน %.2f วิ ยิงที่ %.2f)", tti, lead) end
    end
    if b:GetAttribute("target") == LP.Name then
        if d <= reach then return true end
        return false, string.format("รอ: ระยะ %.0f / ยิงที่ %.0f", d, reach)
    end
    return false, "บอลไม่ได้เล็งคุณ"
end

-- ตรงกับตัวอย่าง: พาร์รี่สำเร็จแล้วมีคนอื่นรับ ถ้าบอลอยู่ไกล = ถือว่าบอลกำลังโค้ง
task.spawn(pcall, function()   -- รันเบื้องหลัง ไม่ให้รอโหลดค้างตอนเริ่มสคริปต์
    local rem = RepStorage:WaitForChild("Remotes", 10)
    local ev = rem and rem:WaitForChild("ParrySuccessAll", 10)
    if not ev then return end
    bind(ev.OnClientEvent, function(_, part)
        local ch = LP.Character
        local pp = ch and ch.PrimaryPart
        local ball = Ref.firstBall()
        local z = ball and ball:FindFirstChild("zoomies")
        if not (pp and z) then return end
        local mag = z.VectorVelocity.Magnitude
        if mag < 1e-3 then return end
        local dist = (pp.Position - Ref.pos(ball, os.clock(), z.VectorVelocity)).Magnitude
        local ping = getPing()
        local n31 = dist / mag - ping / 1000
        local n32 = 15 - math.min(dist / 1000, 15) + math.min(mag / 100, 40)
        if mag > 100 and n31 > ping / 10 then n32 = math.max(n32 - 15, 15) end
        if part ~= pp and dist > n32 then Ref.state.curving = os.clock() end
    end)
end)

local function processBall(b, ctx, dt, now)
    local tr = trk[b]
    if not tr then
        tr = {pos = b.Position, t = now, speed = 0, accel = 0, vel = Vector3.zero, armed = true, firedAt = 0, wasMe = false, jit = 0, init = false, retry = 0, sw = {}, posT = now, second = false}
        rollJitter(tr)
        trk[b] = tr
        pcall(function()
            b:GetAttributeChangedSignal("target"):Connect(function()
                Ref.reset()
                if b:GetAttribute("target") == LP.Name then tr.armed = true tr.retry = 0 tr.second = false rollJitter(tr) end
            end)
        end)
        Ref.reset()
        Dbg.log("บอลใหม่ " .. b.Name .. " target=" .. tostring(targetOf(b)) .. " realBall=" .. tostring(b:GetAttribute("realBall")))
    end

    -- ความเร็ว / ความเร่ง
    local dtt = now - tr.t
    local v = ballVelocity(b)
    if not v then
        local el = now - tr.posT
        if tr.init and el > 0.001 and el < 0.25 and b.Position ~= tr.pos then v = tr.vel:Lerp((b.Position - tr.pos) / el, 0.6)
        elseif tr.init then v = tr.vel else v = Vector3.zero end
    end
    if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return end
    local speed = v.Magnitude
    if tr.init and dtt > 0.001 and dtt < 0.25 then
        local a = (speed - tr.speed) / dtt
        tr.accel = math.clamp(tr.accel * 0.85 + a * 0.15, -speed * 3, speed * 3)
    else
        tr.accel = 0
    end
    local bpNow = b.Position
    if tr.init and bpNow ~= tr.pos then
        -- ตำแหน่งบอลฝั่งเราอัปเดตเป็นช่วงๆ ไม่ใช่ทุกเฟรม: เทียบระยะที่ขยับกับเวลาตั้งแต่ตำแหน่งเปลี่ยนครั้งก่อน
        -- (ของเดิมเทียบกับเวลาต่อเฟรม ทำให้บอลเร็วถูกมองเป็นวาร์ปแล้วระบบกันพลาดหยุดออโต้ = ตีช้า)
        local el = math.clamp(now - tr.posT, 0.001, 0.5)
        local jump = (bpNow - tr.pos).Magnitude
        if S.Guard and jump > 40 and jump > speed * el * 3 + 40 then
            tr.accel = 0
            guardFor(0.15, "บอลวาร์ป/กระโดดตำแหน่ง")
        end
        tr.pos, tr.posT = bpNow, now
    end
    tr.vel, tr.t, tr.speed, tr.init = v, now, speed, true
    if speed > maxSpeed then maxSpeed = speed end

    -- เป้าหมาย
    local tgt = targetOf(b)
    local targetMe
    if tgt ~= nil then
        targetMe = (tgt == LP.Name)                 -- attribute เป็นตัวหลัก
        if not targetMe and ctx.hl and ctx.ballCount == 1 then targetMe = true end   -- Highlight บนตัวเรา = บอลมาหาเรา (กัน attribute อัปเดตช้า)
    elseif ctx.anyTarget then
        targetMe = false                            -- บอลลูกนี้ไม่มีเป้า แต่มีลูกอื่นที่มี
    else
        targetMe = true                             -- ไม่มี attribute เลย (โหมดซ้อม/เกมเปลี่ยน): ถือว่าเล็งเรา แล้วให้เงื่อนไขอื่นกรอง
    end
    if targetMe and not tr.wasMe then tr.armed = true tr.retry = 0 tr.second = false rollJitter(tr) end   -- เพิ่งเปลี่ยนมาเล็งเรา = เริ่มรอบใหม่
    if targetMe ~= tr.wasMe then tr.sw[#tr.sw + 1] = now end
    if targetMe ~= tr.wasMe then Dbg.log("เป้าหมายบอลเปลี่ยน -> " .. tostring(tgt) .. (targetMe and " (คุณ)" or "")) end
    tr.wasMe = targetMe

    if S.BallESP then
        pcall(function()
        local h = espMap[b]
        if not h or not h.Parent then
            h = Instance.new("Highlight")
            h.Adornee = b h.FillTransparency = 0.55 h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = workspace.CurrentCamera or workspace
            espMap[b] = h
        end
        local col = targetMe and C.BAD or C.CYAN
        h.FillColor = col h.OutlineColor = col
        end)
    end

    if not ctx.alive then return end
    local toMe = ctx.hrp.Position - ballPos(b, now, v)
    local dist = toMe.Magnitude
    local closing = dist > 0.01 and v:Dot(toMe / dist) or 0
    -- บอล Blade Ballเป็นบอลเล็งตาม (homing): ถ้าเล็งเรา ความเร็วที่ใช้คิดเวลาควรใกล้เคียงความเร็วบอลจริง ไม่ใช่แค่ส่วนที่ตรงเข้าหาเรา
    local ce = closing
    if targetMe and speed > 1 and closing > 1 then
        -- facing = บอลหันเข้าหาเรามากแค่ไหน (1 = ตรงเต็ม, ต่ำ = กำลังโค้ง/เฉียง)
        -- บอลโค้ง: อย่าเชื่อว่าความเร็วเข้าหาเราเต็ม 80% ไม่งั้นจะยิงเร็วเกินไป ให้ค่อยๆ ผสมตามระดับที่บอลหันมา
        local facing = math.clamp(closing / speed, 0, 1)
        local trust = math.clamp((facing - 0.2) / 0.6, 0, 1)
        ce = closing + (math.max(closing, speed * 0.8) - closing) * trust
    end
    -- ความเร็วตัวเราเอง: วิ่งหนีบอล = บอลใช้เวลานานขึ้น (ของเดิมไม่คิดส่วนนี้ เลยยิงเร็วเกินตอนวิ่งหนี)
    local vm = ctx.hrp.AssemblyLinearVelocity
    if vm.X ~= vm.X or vm.Magnitude > 150 then vm = Vector3.zero end   -- กันค่าเพี้ยนตอนวาร์ป/เกิดใหม่
    local nDir = dist > 0.01 and toMe / dist or Vector3.zero
    local tti = pursuitTime(dist, ce, vm:Dot(nDir), vm:Dot(vm), tr.accel)
    tr.tti = tti
    local relevant = targetMe or not S.TargetOnly
    local nearE = enemyNear(ctx, 30)   -- มีศัตรูอยู่ใกล้ = ตีไวขึ้น
    local why

    ---------------- ออโต้พาร์รี่
    if ctx.guard then
        why = "ระบบกันพลาดหยุดชั่วคราว (" .. tostring(Safety.guardWhy) .. ")"
    elseif S.AutoParry and S.ParryLogic == "Ref" then
        if not relevant then why = "บอลไม่ได้เล็งคุณ"
        elseif speed < S.MinSpeed then why = "บอลยังช้า / ยังไม่ปล่อย"
        else
            -- เปิด 'ยิงซ้ำถ้าพลาด': ยิงแล้วบอลยังเล็งเราเกินเวลารอผล = ปลดล็อกให้ยิงอีก (สูงสุด 3 ครั้งต่อรอบ)
            if S.Rearm and Ref.debounce and targetMe and tr.retry < 3
                and now - tr.firedAt > math.clamp(0.2 + pingMs / 1000 * 1.2, 0.2, 0.5) then
                Ref.reset() tr.retry = tr.retry + 1
            end
            local fire, rw = Ref.check(b, now)
            if fire then
                if doParry(0.05) then
                    Ref.debounce, Ref.untilAt = true, now + 1
                    tr.armed, tr.firedAt, tr.fireTti = false, now, tti
                    if ctx.anyTarget and targetMe then pending[#pending + 1] = {b = b, t = now, tti = tti, dist = dist} end
                    why = "พาร์รี่! (รีโมท • ตรงตามตัวอย่าง)"
                else
                    why = Cd.active and "คูลดาวน์ของเกม รอปลด" or "ถึงจังหวะแล้วแต่ส่งไม่ออก"
                end
            else
                why = rw or "รอจังหวะ"
            end
        end
    elseif S.AutoParry then
        if not relevant then why = "บอลไม่ได้เล็งคุณ"
        elseif speed < S.MinSpeed then why = "บอลยังช้า / ยังไม่ปล่อย"
        elseif closing <= 1 then why = "บอลไม่ได้พุ่งเข้าหาคุณ"
        else
            -- ตอนยิงบอลยังอีกไกล (>0.25 วิ) แล้วบอลยังเล็งเราอยู่ = พาร์รี่อาจหมดก่อนบอลถึง: ยิงซ้ำอีก 1 ครั้งตอนบอลใกล้จริง
            if S.Rearm and not tr.armed and not tr.second and tr.fireTti and tr.fireTti > 0.25
                and now - tr.firedAt >= 0.2 and tti <= 0.12 + pingMs / 2000 then
                tr.armed, tr.second = true, true
            end
            -- ยิงแล้วบอลยังเล็งเราอยู่เกินเวลารอผล = พลาด/ติดคูลดาวน์ -> เปิดให้ยิงซ้ำ
            if S.Rearm and not tr.armed and tr.retry < 3 and now - tr.firedAt > math.clamp(0.2 + pingMs / 1000 * 1.2, 0.2, 0.5) then tr.armed = true tr.retry = tr.retry + 1 end
            if tr.armed then
                local pbd = math.max(S.PointBlank, speed * 0.12)
                if nearE then pbd = pbd * 1.25 end
                local point = pbd > 0 and dist <= pbd
                -- บอลเร็วมากยิงเร็วขึ้นอีกนิด (สูงสุด +25ms)
                local leadNow = ctx.lead + (nearE and 0.03 or 0) + math.clamp((speed - 200) / 1500, 0, 1) * 0.025
                if point or tti <= leadNow + tr.jit then
                    local sent = doParry(0.05)
                    if sent then
                        tr.armed, tr.firedAt, tr.fireTti = false, now, tti
                        rollJitter(tr)
                        if ctx.anyTarget and targetMe then pending[#pending + 1] = {b = b, t = now, tti = tti, dist = dist} end
                        why = "พาร์รี่! (รีโมท)"
                    else
                        why = "ถึงจังหวะแล้วแต่ส่งไม่ออก"
                    end
                else
                    why = string.format("รอจังหวะ: ถึงใน %.2f วิ (ยิงที่ %.2f วิ)", tti, leadNow)
                end
            else
                why = "ยิงแล้ว กำลังรอผล"
            end
        end
    else
        why = "ออโต้พาร์รี่ปิดอยู่"
    end

    ---------------- ออโต้สแปม
    while tr.sw[1] and now - tr.sw[1] > 2 do table.remove(tr.sw, 1) end
    local clash = nearE or #tr.sw >= 2   -- ปะทะ = ศัตรูอยู่ใกล้ หรือบอลเด้งกลับมาติดๆ กัน
    local spamR = math.max(S.SpamRange, speed * 0.30)
    if S.AutoSpam and not ctx.guard and targetMe and clash and speed >= S.MinSpeed and closing > 1
        and (dist <= spamR or tti <= 0.45) then
        local rate = S.SpamRate
        if nearE then rate = math.min(rate * 1.3, 40) end
        -- ยิ่งบอลใกล้ ยิ่งรัวเต็มอัตรา / ยังไกลรัวเบาลง ไม่เปลืองจังหวะ
        rate = rate * math.clamp(1.15 - tti / 0.6, 0.45, 1)
        spamAcc = spamAcc + dt * rate
        local n = 0
        while spamAcc >= 1 and n < 3 do
            spamAcc = spamAcc - 1
            n = n + 1
            doParry(math.max(0.02, 0.8 / rate), true)
        end
        if spamAcc > 3 then spamAcc = 0 end
        if not S.AutoParry then why = "สแปมพาร์รี่" end
    end

    if S.AutoAbility and not ctx.guard and targetMe and closing > 1 and dist <= S.AbilityRange and now - lastAbility > 3.5 then
        lastAbility = now
        pcall(useAbility)
    end

    if targetMe then
        Dbg.log(string.format("%s | spd %d dist %d close %d tti %s", tostring(why), math.floor(speed), math.floor(dist), math.floor(closing),
            tti == math.huge and "inf" or string.format("%.2f", tti)), "why", 1.2)
    end

    -- บอลโฟกัสสำหรับหน้าจอ (เป้าหมายเราก่อน แล้วใกล้สุด)
    if dist < ctx.focusDist and (targetMe or not ctx.focusMe) then
        ctx.focusDist, ctx.focusMe = dist, targetMe
        Info.speed, Info.dist, Info.tti, Info.target, Info.me, Info.has, Info.why = speed, dist, tti, tgt or "-", targetMe, true, why
    end
end

-- ตรวจผลหลังพาร์รี่: ถ้ายังเล็งเราอยู่ = พลาด
local function verifyPending(now, aliveMe)
    if not aliveMe then
        -- ตายขณะมีพาร์รี่ค้างผล: เทียบเวลาที่บอลมาถึงจริงกับที่คาดไว้ตอนยิง
        --   ถึงเร็วกว่าคาด = ยิงช้า -> ยิงเร็วขึ้น | ถึงช้ากว่าคาด = ยิงเร็วไปจนพาร์รี่หมดก่อน -> ยิงช้าลง
        if #pending > 0 and S.Adaptive then
            local p = pending[#pending]
            local took = now - p.t
            if p.tti ~= math.huge and p.tti >= 0.05 then
                if took < p.tti - 0.04 then
                    Learn.late = Learn.late + 1
                    Learn.shift = math.clamp(Learn.shift + 0.012, -0.08, 0.12)
                    Dbg.log("เรียนรู้: ช้าไป shift=" .. string.format("%.0f", Learn.shift * 1000) .. "ms")
                elseif took > p.tti + 0.04 then
                    Learn.early = Learn.early + 1
                    Learn.shift = math.clamp(Learn.shift - 0.012, -0.08, 0.12)
                    Dbg.log("เรียนรู้: เร็วไป shift=" .. string.format("%.0f", Learn.shift * 1000) .. "ms")
                end
            end
        end
        table.clear(pending)
        return
    end
    local after = 0.28 + math.min(pingMs, 500) / 1000
    local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    for i = #pending, 1, -1 do
        local p = pending[i]
        if not p.b.Parent then
            table.remove(pending, i)
        elseif now - p.t > after then
            if targetOf(p.b) == LP.Name then
                Stat.fail = Stat.fail + 1
                Stat.combo = 0
                Remote.noteFail()
                -- พลาดแต่บอลยังอยู่ไกล = ยิงเร็วเกินจนหน้าต่างพาร์รี่หมดก่อนบอลถึง -> ถ่วงให้ช้าลงนิดหน่อย
                if S.Adaptive and myHrp then
                    local dnow = (p.b.Position - myHrp.Position).Magnitude
                    if dnow > HIT_RADIUS * 3 then
                        Learn.early = Learn.early + 1
                        Learn.shift = math.clamp(Learn.shift - 0.008, -0.08, 0.12)
                        Dbg.log("เรียนรู้: น่าจะเร็วไป shift=" .. string.format("%.0f", Learn.shift * 1000) .. "ms")
                    end
                end
            else
                Stat.ok = Stat.ok + 1
                Stat.combo = Stat.combo + 1
                if Stat.combo > Stat.best then Stat.best = Stat.combo end
                if S.ParryFX then flashFn() end
                Remote.noteOk()
            end
            table.remove(pending, i)
        end
    end
end

------------------------------------------------------------------ 4) อัปเดตหน้าจอ
local function updateUi(now)
    if now - lastUiAt < 0.1 then return end
    lastUiAt = now
    hudUpdate(now)
    chipLbl.Text = string.format("%d FPS  %dms", fpsNow, math.floor(pingMs))
    fpsV.Text = tostring(fpsNow)
    pingV.Text = tostring(math.floor(pingMs))
    ballV.Text = Info.has and tostring(math.floor(Info.speed)) or "--"
    local on = {}
    if S.AutoParry then on[#on + 1] = "พาร์รี่" end
    if S.AutoSpam then on[#on + 1] = "สแปม" end
    if S.AutoAbility then on[#on + 1] = "สกิล" end
    statusLbl.Text = #on > 0 and ("เปิดอยู่: " .. table.concat(on, " + ")) or "ออโต้ปิดอยู่ทั้งหมด"
    statusLbl.TextColor3 = #on > 0 and C.OK or C.MUTED
    if Info.has then
        infoLbl.Text = string.format("เป้าหมาย: %s%s | ระยะ %d | เร็ว %d", tostring(Info.target), Info.me and " (คุณ)" or "", math.floor(Info.dist), math.floor(Info.speed))
        whyLbl.Text = "สถานะ: " .. tostring(Info.why)
        whyLbl.TextColor3 = Info.me and C.BAD or C.WARN
    else
        infoLbl.Text = "ไม่มีบอลในสนาม"
        whyLbl.Text = "สถานะ: -"
        whyLbl.TextColor3 = C.WARN
    end
    if not banned then
        if now < Safety.guardUntil then safeLbl.Text = "เตือน: " .. tostring(Safety.guardWhy) safeLbl.TextColor3 = C.WARN
        elseif S.Guard then safeLbl.Text = "ปกติ" safeLbl.TextColor3 = C.OK
        else safeLbl.Text = "ระบบกันพลาดปิดอยู่" safeLbl.TextColor3 = C.MUTED end
    end
    statLbl.Text = string.format("ส่งพาร์รี่ %d | สำเร็จ %d | พลาด %d | คอมโบ %d (สูงสุด %d) | บอลเร็วสุด %d | ช่อง: %s", Stat.sent, Stat.ok, Stat.fail, Stat.combo, Stat.best, math.floor(maxSpeed), Stat.lastPath)
end

local function step(dt, now)
    fpsAcc, fpsN = fpsAcc + dt, fpsN + 1
    if now - lastFpsAt >= 0.5 then
        fpsNow = math.floor(fpsN / math.max(fpsAcc, 0.001) + 0.5)
        fpsAcc, fpsN, lastFpsAt = 0, 0, now
        local rawPing = math.clamp(getPing(), 0, 800)
        pingMs = (pingMs > 0) and (pingMs * 0.6 + rawPing * 0.4) or rawPing   -- เฉลี่ยค่าปิง กันกระชาก
        table.insert(fpsHist, fpsNow)
        if #fpsHist > #chartBars then table.remove(fpsHist, 1) end
        for i, bar_ in ipairs(chartBars) do
            local f = fpsHist[i - (#chartBars - #fpsHist)]
            if f then
                bar_.Size = UDim2.new(1 / #chartBars, -2, math.clamp(f / 120, 0.05, 1), 0)
                bar_.BackgroundColor3 = f >= 50 and C.VIOLET or (f >= 30 and C.WARN or C.BAD)
            end
        end
    end

    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local aliveMe = hrp ~= nil and hum ~= nil and hum.Health > 0
    local hlOn = false
    if ch then
        local h = ch:FindFirstChild("Highlight") or ch:FindFirstChildOfClass("Highlight")
        hlOn = h ~= nil
    end
    local balls = getBalls()
    local anyTarget = false
    for _, b in ipairs(balls) do
        if b:GetAttribute("target") ~= nil then anyTarget = true break end
    end
    local ctx = {hrp = hrp, alive = aliveMe, anyTarget = anyTarget, hl = hlOn, ballCount = #balls, focusDist = math.huge, focusMe = false,
        lead = S.Window / 1000 + (S.PingComp and pingMs / 1000 or 0) + (S.Adaptive and math.min(dt, 0.1) * 1.5 or 0) + (S.Adaptive and Learn.shift or 0), guard = false}
    if S.Guard then
        if dt > 0.4 then guardFor(0.3, "แล็กกระตุก") end
        if pingMs > 500 then safeEvent(string.format("ปิงสูงมาก (%d ms) จังหวะพาร์รี่อาจคลาดเคลื่อน", math.floor(pingMs)), "hiping", 15) end
        if aliveMe then
            if Safety.lastPos and (hrp.Position - Safety.lastPos).Magnitude > 80 then guardFor(0.8, "ตัวละครวาร์ป/เกิดใหม่") end
            Safety.lastPos = hrp.Position
        else
            Safety.lastPos = nil
        end
    end
    do local oka, ea = pcall(anomalyStep, now, dt) if not oka then featErr("anomaly", ea) end end
    ctx.guard = now < Safety.guardUntil
    do local okv, ev = pcall(applyVisual, now) if not okv then featErr("visual", ev) end end
    for b, h in pairs(espMap) do
        if not b.Parent or not S.BallESP then pcall(function() h:Destroy() end) espMap[b] = nil end
    end
    Info.has = false
    for _, b in ipairs(balls) do
        local ok, err = pcall(processBall, b, ctx, dt, now)
        if not ok then logErr(err) end
    end
    if #balls == 0 then spamAcc = 0 maxSpeed = 0 Ref.reset() end
    verifyPending(now, aliveMe)
    do local okh, eh = pcall(updateHitVisuals, balls, ctx) if not okh then featErr("hitbox", eh) end end
    updateUi(now)
end

local errStreak = 0
bind(RunService.Heartbeat, function(dt)
    if not alive then return end
    local ok, err = pcall(step, dt, os.clock())
    if ok then
        errStreak = 0
    else
        logErr(err)
        errStreak = errStreak + 1
        if errStreak >= 60 then   -- พังติดกันนาน = ปิดออโต้กันค้าง
            errStreak = 0
            setState("AutoParry", false) setState("AutoSpam", false)
            toast("ระบบเกิดข้อผิดพลาดซ้ำ: ปิดออโต้แล้ว")
        end
    end
end)

------------------------------------------------------------------ ปุ่มลัด / หน้าต่าง / ปิดสคริปต์
local shown = true
local function setShown(v)
    shown = v
    if v then
        main.Visible = true
        tw(mscale, 0.35, {Scale = baseScale}, Enum.EasingStyle.Back)
    else
        tw(mscale, 0.2, {Scale = baseScale * 0.85}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.2, function() if not shown then main.Visible = false end end)
    end
end
btnMin.MouseButton1Click:Connect(function() setShown(false) end)

function Engine.panic()
    for _, k in ipairs({"AutoParry", "AutoSpam", "AutoAbility", "BallESP", "FOVOn", "Fullbright", "HitboxESP", "ParryRing", "BallTag"}) do setState(k, false) end
    table.clear(pending)
    shown = false
    main.Visible = false
end

bind(UIS.InputBegan, function(i, gp)
    if i.KeyCode == Enum.KeyCode.Delete then Engine.panic() return end
    if gp then return end
    if i.KeyCode == HUB.ToggleKey then setShown(not shown)
    elseif i.KeyCode == Enum.KeyCode.X then setState("AutoParry", not S.AutoParry)
    elseif i.KeyCode == Enum.KeyCode.C then setState("AutoSpam", not S.AutoSpam) end
end)

local bubble = button(gui, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = C.PANEL2, ZIndex = 40}, {corner(21), stroke(C.VIOLET, 1.5, 0.3)})
local bubbleImg = new("ImageLabel", {Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, Image = HUB.Logo, ScaleType = Enum.ScaleType.Crop, ZIndex = 41, Parent = bubble}, {corner(21)})
task.spawn(function()
    local t = 0
    while bubbleImg.Parent and not bubbleImg.IsLoaded and t < 6 do task.wait(0.25) t = t + 0.25 end
    if bubbleImg.Parent and not bubbleImg.IsLoaded then
        bubbleImg.ImageTransparency = 1
        label(bubbleImg, {Size = UDim2.fromScale(1, 1), Text = "M", Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42})
    end
end)
do
    local hud = new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(200, 26), BackgroundColor3 = C.PANEL,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false, ZIndex = 30, Parent = gui}, {corner(13), stroke(C.VIOLET, 1, 0.35)})
    local dot = new("Frame", {Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = C.OK, BorderSizePixel = 0, ZIndex = 31, Parent = hud}, {corner(4)})
    local hl = label(hud, {Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -32, 1, 0), Text = "", Font = Enum.Font.GothamBold, TextSize = 11, ZIndex = 31})
    hudUpdate = function()
        local on = alive and S.HUD and (S.AutoParry or S.AutoSpam)
        hud.Visible = on and true or false
        if not on then return end
        local mode = (S.AutoParry and S.AutoSpam) and "PARRY + SPAM" or (S.AutoParry and "AUTO PARRY" or "AUTO SPAM")
        hl.Text = string.format("%s   x%d   %dms", mode, Stat.combo, math.floor(pingMs))
        dot.BackgroundColor3 = (Info.has and Info.me) and C.BAD or C.OK
    end
    local fl = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.CYAN, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = gui})
    flashFn = function() fl.BackgroundTransparency = 0.85 tw(fl, 0.35, {BackgroundTransparency = 1}) end
end
bubble.MouseButton1Click:Connect(function() setShown(not shown) end)

-- แถบคูลดาวน์พาร์รี่ (นับจากครั้งล่าสุดที่สคริปต์ยิง)
do
    local cd = new("Frame", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.fromOffset(120, 6),
        BackgroundColor3 = C.PANEL, BackgroundTransparency = 0.25, BorderSizePixel = 0, Visible = false, ZIndex = 30, Parent = gui}, {corner(3), stroke(C.VIOLET, 1, 0.5)})
    local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.WARN, BorderSizePixel = 0, ZIndex = 31, Parent = cd}, {corner(3)})
    bind(RunService.RenderStepped, function()
        if not alive then return end
        local show = S.VisualCD and (S.AutoParry or S.AutoSpam)
        cd.Visible = show and true or false
        if not show then return end
        local p
        if Cd.hooked then   -- ใช้สถานะคูลดาวน์จริงของเกม
            p = Cd.active and math.clamp((os.clock() - Cd.startedAt) / Cd.MAX, 0, 0.99) or 1
        else
            p = math.clamp((os.clock() - lastPress) / (S.CDms / 1000), 0, 1)
        end
        fill.Size = UDim2.fromScale(p, 1)
        fill.BackgroundColor3 = p >= 1 and C.OK or C.WARN
    end)
end

function Engine.unload()
    pcall(function() if Cd.handle then task.cancel(Cd.handle) Cd.handle = nil end end)
    if not alive then return end
    alive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(trk) table.clear(pending)
    clearEsp() pcall(clearHb)
    pcall(Remote.unhook)
    pcall(function() if Remote.signal then Remote.signal:Destroy() end end)
    pcall(function() Hooks.FPSBoost(false) end)
    pcall(function() if fovApplied and workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = 70 end end)
    pcall(function() if lightApplied and origLight then for k, v in pairs(origLight) do Lighting[k] = v end end end)
    pcall(function() gui:Destroy() end)
end
btnClose.MouseButton1Click:Connect(Engine.unload)
pcall(function() ENV.__MEEN_BB_UNLOAD = Engine.unload end)

-- ลดกราฟิก
local fpsBoostState = nil
Hooks.FPSBoost = function(v)
    if v then
        if fpsBoostState then return end
        local st = {parts = {}}
        fpsBoostState = st
        pcall(function() st.quality = settings().Rendering.QualityLevel end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        st.shadows = Lighting.GlobalShadows
        Lighting.GlobalShadows = false
        task.spawn(function()
            local n = 0
            for _, d in ipairs(workspace:GetDescendants()) do
                if not alive or fpsBoostState ~= st then return end
                if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
                    if d.Enabled then d.Enabled = false table.insert(st.parts, d) end
                end
                n = n + 1
                if n % 400 == 0 then task.wait() end
            end
        end)
    else
        local st = fpsBoostState
        if not st then return end
        fpsBoostState = nil
        pcall(function() if st.quality then settings().Rendering.QualityLevel = st.quality end end)
        pcall(function() Lighting.GlobalShadows = st.shadows end)
        for _, d in ipairs(st.parts) do pcall(function() d.Enabled = true end) end
    end
end
if S.FPSBoost then pcall(Hooks.FPSBoost, true) end


setPage("Home")
tw(mscale, 0.5, {Scale = baseScale}, Enum.EasingStyle.Back)
toast("โหลด MEEN HUB | Blade Ball V 1.2 เรียบร้อย")

