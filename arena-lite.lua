--[[
  Delve Arena Lite - versi ringan untuk Android / Delta Executor.

  Tidak memakai BPUI, HttpGet, filtergc, hookmetamethod, atau library luar.
  Hanya butuh fungsi dasar executor: loadstring (untuk menjalankan file ini),
  game:GetService, Instance.new, task, dan remote StrataNet.

  Fitur:
    - Auto Join arena (MobRushJoin) saat pintu terbuka.
    - Auto Fight semua mob arena sampai wave selesai.
    - Radius target lebar (320 stud), jadi mob yang spawn jauh tetap dikejar.
    - Status fase / wave / mob hidup / target.
    - Tombol Join Now dan Leave.

  Cara pakai:
    loadstring(readfile("AIBridge/arena-lite.lua"))()
  atau dari GitHub:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/delve-script/main/arena-lite.lua"))()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local plr = Players.LocalPlayer

local net = ReplicatedStorage:WaitForChild("StrataNet", 20)
if not net then
    warn("[ArenaLite] StrataNet tidak ditemukan. Tunggu sampai game selesai loading.")
    return
end

local joinRemote = net:WaitForChild("MobRushJoin", 10)
local leaveRemote = net:FindFirstChild("ArenaLeave")
local swingRemote = net:WaitForChild("Swing", 10)
local weaponRemote = net:WaitForChild("WeaponDrawn", 10)
local pickaxeRemote = net:WaitForChild("PickaxeOut", 10)
if not (joinRemote and swingRemote and weaponRemote and pickaxeRemote) then
    warn("[ArenaLite] Remote tempur tidak lengkap.")
    return
end

-- Range dan rate senjata dibaca dari defs game; kalau gagal, pakai default.
local weapons = nil
pcall(function()
    weapons = require(ReplicatedStorage.Strata.Defs.Weapons)
end)

local CFG = {
    autoArena = true,
    autoJoin = true,
    autoFight = true,
    radius = 320,
    joinCooldown = 5,
    equipCooldown = 0.5,
}

local S = {
    lastJoin = 0,
    lastLeave = 0,
    lastSwing = 0,
    lastEquip = 0,
    phase = "idle",
    wave = 0,
    of = 0,
    joined = false,
    inArena = false,
    alive = 0,
    target = nil,
    mode = "idle",
    error = nil,
}

local function isInArena()
    return plr:GetAttribute("InArena") == true
end

local function getHud()
    local pg = plr:FindFirstChildOfClass("PlayerGui")
    return pg and pg:FindFirstChild("HUD")
end

-- Status arena dari HUD, tanpa filtergc. MobRushController membuat
-- RushButton di HUD saat pintu terbuka, dan DepthLine berisi teks WAVE.
local function arenaInfo()
    local hud = getHud()
    if not hud then
        return nil
    end

    local rush = hud:FindFirstChild("RushButton", true)
    if rush and rush.Visible == true then
        local label = rush:FindFirstChild("Label", true)
        local text = label and label:IsA("TextLabel") and label.Text or ""
        return {
            phase = "open",
            joined = string.find(string.lower(text), "joined", 1, true) ~= nil,
            text = text,
        }
    end

    if isInArena() then
        local pg = plr:FindFirstChildOfClass("PlayerGui")
        local runEnd = pg and pg:FindFirstChild("RunEnd")
        local phase = (runEnd and runEnd.Enabled) and "over" or "running"
        local wave, of
        local depthLine = hud:FindFirstChild("DepthLine", true)
        if depthLine and depthLine:IsA("TextLabel") then
            local a, b = depthLine.Text:match("WAVE%s*<font[^>]*>(%d+)</font>%s*/%s*(%d+)")
            if not a then
                a, b = depthLine.Text:match("WAVE%s*(%d+)%s*/%s*(%d+)")
            end
            wave, of = tonumber(a), tonumber(b)
        end
        return {
            phase = phase,
            joined = true,
            wave = wave,
            of = of,
        }
    end

    return nil
end

local function mobPart(m)
    return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
end

local function mobDistance(m, pos)
    local part = mobPart(m)
    if not part then
        return nil
    end
    local d = Vector3.new(part.Position.X - pos.X, 0, part.Position.Z - pos.Z).Magnitude
    return d, part.Position
end

local function scanMobs()
    local ch = plr.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return {}
    end

    local list = {}
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= ch then
            local mobId = m:GetAttribute("MobId")
            local guardian = m:GetAttribute("Guardian") == true
            local runId = tostring(m:GetAttribute("RunId") or "")
            local arenaTag = string.find(string.lower(runId), "arena", 1, true) ~= nil
            if mobId ~= nil or guardian or arenaTag then
                local hum = m:FindFirstChildOfClass("Humanoid")
                local part = mobPart(m)
                local name = string.lower(m.Name)
                local blocked = string.find(name, "chest", 1, true) ~= nil
                    or string.find(name, "tomb", 1, true) ~= nil
                    or string.find(name, "vase", 1, true) ~= nil
                    or string.find(name, "dummy", 1, true) ~= nil
                    or string.find(name, "gate", 1, true) ~= nil
                    or string.find(name, "portal", 1, true) ~= nil
                    or m:GetAttribute("ChestState") ~= nil
                    or m:GetAttribute("ChestRarity") ~= nil
                if part and not blocked
                    and m:GetAttribute("Dead") ~= true
                    and (not hum or hum.Health > 0) then
                    local d, pos = mobDistance(m, hrp.Position)
                    if d and d <= CFG.radius then
                        list[#list + 1] = {
                            model = m,
                            dist = d,
                            pos = pos,
                        }
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.dist < b.dist
    end)
    return list
end

local function weaponStats()
    local ch = plr.Character
    local id = ch and ch:GetAttribute("EquippedWeapon")
    if weapons and id then
        local ok, def = pcall(weapons.at, id)
        if ok and def then
            local okRange, range = pcall(weapons.range, def)
            local okRate, rate = pcall(weapons.rate, def, 1)
            if okRange and type(range) == "number" and range > 0 then
                return range, okRate and tonumber(rate) or 0.55
            end
        end
    end
    return 14, 0.55
end

local function equipWeapon()
    local ch = plr.Character
    if not ch then
        return
    end
    local now = os.clock()
    if now - S.lastEquip < CFG.equipCooldown then
        return
    end
    if ch:GetAttribute("WeaponDrawn") ~= true then
        S.lastEquip = now
        pcall(function()
            weaponRemote:FireServer(true)
        end)
        pcall(function()
            pickaxeRemote:FireServer(false)
        end)
    end
end

local function fightStep(mob, hrp, hum, range, interval)
    local d, pos = mobDistance(mob, hrp.Position)
    if not d or not pos then
        return
    end

    if d > range - 1 then
        pcall(function()
            hum:MoveTo(pos)
        end)
        return
    end

    local now = os.clock()
    if now - S.lastSwing < interval then
        return
    end

    local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
    if flat.Magnitude < 0.05 then
        return
    end
    local facing = flat.Unit

    pcall(function()
        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(pos.X, hrp.Position.Y, pos.Z))
    end)

    S.lastSwing = now
    pcall(function()
        swingRemote:FireServer(facing, nil, hrp.Position)
    end)
end

local function tick()
    S.inArena = isInArena()
    local info = arenaInfo()
    if info then
        S.phase = info.phase
        S.wave = info.wave or 0
        S.of = info.of or 0
        S.joined = info.joined == true
    else
        S.phase = "idle"
        S.wave = 0
        S.of = 0
        S.joined = false
    end

    local now = os.clock()
    if CFG.autoArena and CFG.autoJoin and not S.inArena
        and info and info.phase == "open" and not info.joined
        and now - S.lastJoin >= CFG.joinCooldown then
        S.lastJoin = now
        pcall(function()
            joinRemote:FireServer()
        end)
    end

    if not CFG.autoArena or not CFG.autoFight or not S.inArena then
        S.mode = "idle"
        S.target = nil
        S.alive = 0
        return
    end

    local ch = plr.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        return
    end

    local mobs = scanMobs()
    S.alive = #mobs
    if #mobs == 0 then
        S.mode = "idle"
        S.target = nil
        return
    end

    local target = mobs[1]
    S.mode = "fight"
    S.target = target.model
    equipWeapon()
    local range, interval = weaponStats()
    fightStep(target.model, hrp, hum, range, interval)
end

-- ============================================================
-- UI ringan (touch friendly)
-- ============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "DelveArenaLite"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.Parent = plr:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 260, 0, 250)
panel.Position = UDim2.new(0, 16, 0, 90)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(45, 45, 58)
stroke.Thickness = 1
stroke.Parent = panel

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 34)
topBar.BackgroundTransparency = 1
topBar.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -44, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Delve Arena Lite"
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 28, 0, 24)
close.Position = UDim2.new(1, -34, 0, 5)
close.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
close.Text = "X"
close.TextColor3 = Color3.fromRGB(235, 235, 240)
close.TextSize = 13
close.Font = Enum.Font.GothamBold
close.Parent = topBar
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = close

local function makeButton(text, y, onClick)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -20, 0, 30)
    button.Position = UDim2.new(0, 10, 0, y)
    button.BackgroundColor3 = Color3.fromRGB(34, 34, 43)
    button.Text = text
    button.TextColor3 = Color3.fromRGB(238, 238, 245)
    button.TextSize = 14
    button.Font = Enum.Font.GothamMedium
    button.AutoButtonColor = true
    button.Parent = panel
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = button
    button.MouseButton1Click:Connect(onClick)
    return button
end

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 74)
status.Position = UDim2.new(0, 10, 0, 166)
status.BackgroundTransparency = 1
status.Text = "Menunggu..."
status.TextColor3 = Color3.fromRGB(180, 182, 195)
status.TextSize = 12
status.Font = Enum.Font.Code
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = panel

local autoArenaButton
local autoJoinButton
local autoFightButton

local function refreshButtons()
    autoArenaButton.Text = "Auto Arena: " .. (CFG.autoArena and "ON" or "OFF")
    autoJoinButton.Text = "Auto Join: " .. (CFG.autoJoin and "ON" or "OFF")
    autoFightButton.Text = "Fight All Mobs: " .. (CFG.autoFight and "ON" or "OFF")
    autoArenaButton.BackgroundColor3 = CFG.autoArena and Color3.fromRGB(45, 110, 70) or Color3.fromRGB(34, 34, 43)
    autoJoinButton.BackgroundColor3 = CFG.autoJoin and Color3.fromRGB(45, 110, 70) or Color3.fromRGB(34, 34, 43)
    autoFightButton.BackgroundColor3 = CFG.autoFight and Color3.fromRGB(45, 110, 70) or Color3.fromRGB(34, 34, 43)
end

autoArenaButton = makeButton("Auto Arena: ON", 40, function()
    CFG.autoArena = not CFG.autoArena
    refreshButtons()
end)

autoJoinButton = makeButton("Auto Join: ON", 75, function()
    CFG.autoJoin = not CFG.autoJoin
    refreshButtons()
end)

autoFightButton = makeButton("Fight All Mobs: ON", 110, function()
    CFG.autoFight = not CFG.autoFight
    refreshButtons()
end)

local actionRow = Instance.new("Frame")
actionRow.Size = UDim2.new(1, -20, 0, 30)
actionRow.Position = UDim2.new(0, 10, 0, 145)
actionRow.BackgroundTransparency = 1
actionRow.Parent = panel

local joinButton = Instance.new("TextButton")
joinButton.Size = UDim2.new(0.48, 0, 1, 0)
joinButton.Position = UDim2.new(0, 0, 0, 0)
joinButton.BackgroundColor3 = Color3.fromRGB(50, 80, 130)
joinButton.Text = "Join Now"
joinButton.TextColor3 = Color3.fromRGB(245, 245, 250)
joinButton.TextSize = 13
joinButton.Font = Enum.Font.GothamMedium
joinButton.Parent = actionRow
local jc = Instance.new("UICorner")
jc.CornerRadius = UDim.new(0, 7)
jc.Parent = joinButton
joinButton.MouseButton1Click:Connect(function()
    local now = os.clock()
    if now - S.lastJoin < CFG.joinCooldown then
        return
    end
    S.lastJoin = now
    pcall(function()
        joinRemote:FireServer()
    end)
end)

local leaveButton = Instance.new("TextButton")
leaveButton.Size = UDim2.new(0.48, 0, 1, 0)
leaveButton.Position = UDim2.new(0.52, 0, 0, 0)
leaveButton.BackgroundColor3 = Color3.fromRGB(110, 45, 55)
leaveButton.Text = "Leave"
leaveButton.TextColor3 = Color3.fromRGB(245, 245, 250)
leaveButton.TextSize = 13
leaveButton.Font = Enum.Font.GothamMedium
leaveButton.Parent = actionRow
local lc = Instance.new("UICorner")
lc.CornerRadius = UDim.new(0, 7)
lc.Parent = leaveButton
leaveButton.MouseButton1Click:Connect(function()
    local now = os.clock()
    if now - S.lastLeave < CFG.joinCooldown then
        return
    end
    S.lastLeave = now
    if leaveRemote then
        pcall(function()
            leaveRemote:FireServer()
        end)
    end
end)

-- Drag lewat top bar.
local dragging = false
local dragStart = nil
local startPos = nil

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = panel.Position
    end
end)

topBar.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

close.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

refreshButtons()

local function updateStatus()
    local targetName = S.target and S.target.Name or "-"
    status.Text = string.format(
        "Phase: %s\nWave: %d/%d\nMob hidup: %d\nTarget: %s\nMode: %s",
        tostring(S.phase),
        tonumber(S.wave) or 0,
        tonumber(S.of) or 0,
        tonumber(S.alive) or 0,
        targetName,
        tostring(S.mode)
    )
end

task.spawn(function()
    while gui.Parent do
        local ok, err = pcall(tick)
        if not ok then
            S.error = tostring(err)
            status.Text = "Error: " .. tostring(err)
        else
            pcall(updateStatus)
        end
        task.wait(0.2)
    end
end)

-- Akses console untuk cek status / ubah setting:
--   getgenv().ArenaLite.Config.autoArena = false
--   getgenv().ArenaLite.State.phase
local okEnv, env = pcall(function()
    return getgenv()
end)
local ENV = (okEnv and type(env) == "table") and env or _G
ENV.ArenaLite = {
    Config = CFG,
    State = S,
}

print("[ArenaLite] ready. Auto Arena ON, Auto Join ON, Fight All ON.")
