--[[
  Delta debug v2 - pinpoint langkah yang berhenti.
  STATUS kuning = langkah terbaru, alive = heartbeat (kalau angka
  berhenti, VM-nya freeze; kalau terus jalan tapi STATUS berhenti,
  berarti ada error dan pesannya muncul di bawah).

  Pakai:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/delve-script/main/delta-debug2.lua"))()
]]

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local pg = plr:FindFirstChildOfClass("PlayerGui") or plr:WaitForChild("PlayerGui", 10)
if not pg then
    return
end

local old = pg:FindFirstChild("DelveDebug2")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DelveDebug2"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0.9, 0, 0.45, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Parent = gui

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -82, 0, 24)
status.Position = UDim2.new(0, 6, 0, 5)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(255, 220, 120)
status.TextSize = 12
status.Font = Enum.Font.Code
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Text = "STATUS: start"
status.Parent = frame

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 70, 0, 24)
close.Position = UDim2.new(1, -76, 0, 5)
close.BackgroundColor3 = Color3.fromRGB(70, 25, 30)
close.TextColor3 = Color3.new(1, 1, 1)
close.TextSize = 14
close.Text = "Tutup"
close.BorderSizePixel = 0
close.Parent = frame
close.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local beat = Instance.new("TextLabel")
beat.Size = UDim2.new(0, 110, 0, 18)
beat.Position = UDim2.new(1, -116, 1, -23)
beat.BackgroundTransparency = 1
beat.TextColor3 = Color3.fromRGB(120, 255, 120)
beat.TextSize = 11
beat.Font = Enum.Font.Code
beat.TextXAlignment = Enum.TextXAlignment.Right
beat.Text = "alive 0"
beat.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -12, 1, -58)
label.Position = UDim2.new(0, 6, 0, 32)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 11
label.TextWrapped = true
label.Font = Enum.Font.Code
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Text = ""
label.Parent = frame

local lines = {}
local function log(...)
    local line = table.concat({...}, " ")
    status.Text = "STATUS: " .. line
    lines[#lines + 1] = line
    label.Text = table.concat(lines, "\n")
end

local alive = true
task.spawn(function()
    local n = 0
    while alive and gui.Parent do
        n = n + 1
        beat.Text = "alive " .. n
        task.wait(0.5)
    end
end)

local ok, err = pcall(function()
    task.wait(0.3)
    log("1 executor:", identifyexecutor and select(1, identifyexecutor()) or "?")
    task.wait(0.15)
    log("2 loadstring:", type(loadstring), "HttpGet:", type(game.HttpGet), "request:", type(request))
    task.wait(0.15)

    local rs = game:GetService("ReplicatedStorage")
    log("3 ReplicatedStorage ok")
    task.wait(0.15)

    local net = rs:FindFirstChild("StrataNet")
    log("4 StrataNet:", net ~= nil)
    task.wait(0.15)

    if net then
        for _, n in ipairs({ "Aim", "PickaxeOut", "WeaponDrawn", "Swing", "SwapLoadout", "ProfileSync" }) do
            log("5", n .. ":", net:FindFirstChild(n) ~= nil)
            task.wait(0.1)
        end
    end

    log("6 filtergc type:", type(filtergc))
    task.wait(0.15)
    log("7 before filtergc...")
    task.wait(0.3)

    local t0 = os.clock()
    local fok, res = pcall(function()
        return filtergc("table", { Keys = { "Controllers", "State" } }, true)
    end)
    log(string.format("8 filtergc ok=%s time=%.2fs type=%s", tostring(fok), os.clock() - t0, type(res)))
    if not fok then
        log("9 err:", tostring(res))
    end
end)

if not ok then
    log("ERROR:", tostring(err))
end
alive = false
log("done")
