--[[
  Delta hub test - menjalankan hub versi mobile dengan checkpoint UI.
  STATUS menunjukkan bagian UI terakhir yang sedang dibuat. Kalau hub
  berhenti, STATUS berhenti di section itu; kalau error, pesannya muncul.

  Pakai:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/delve-script/main/delta-hub-test.lua"))()
]]

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local pg = plr:FindFirstChildOfClass("PlayerGui") or plr:WaitForChild("PlayerGui", 10)
if not pg then
    return
end

local old = pg:FindFirstChild("DelveHubTest")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DelveHubTest"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0.8, 0, 0, 58)
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, 8)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Parent = gui

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -120, 0, 22)
status.Position = UDim2.new(0, 8, 0, 5)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(255, 220, 120)
status.TextSize = 12
status.Font = Enum.Font.Code
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Text = "STATUS: start"
status.Parent = frame

local beat = Instance.new("TextLabel")
beat.Size = UDim2.new(0, 100, 0, 22)
beat.Position = UDim2.new(1, -106, 0, 5)
beat.BackgroundTransparency = 1
beat.TextColor3 = Color3.fromRGB(120, 255, 120)
beat.TextSize = 11
beat.Font = Enum.Font.Code
beat.TextXAlignment = Enum.TextXAlignment.Right
beat.Text = "alive 0"
beat.Parent = frame

local logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -16, 0, 28)
logLabel.Position = UDim2.new(0, 8, 0, 28)
logLabel.BackgroundTransparency = 1
logLabel.TextColor3 = Color3.new(0.9, 0.9, 0.9)
logLabel.TextSize = 10
logLabel.TextWrapped = true
logLabel.Font = Enum.Font.Code
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.Text = ""
logLabel.Parent = frame

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 64, 0, 22)
close.Position = UDim2.new(1, -70, 0, 32)
close.BackgroundColor3 = Color3.fromRGB(70, 25, 30)
close.TextColor3 = Color3.new(1, 1, 1)
close.TextSize = 12
close.Text = "Tutup"
close.BorderSizePixel = 0
close.Parent = frame
close.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local last = "start"
local function DBG(msg)
    last = tostring(msg)
    status.Text = "STATUS: " .. last
    logLabel.Text = last
    print("[HubTest]", last)
end
_G.DBG = DBG

local alive = true
task.spawn(function()
    local n = 0
    while alive and gui.Parent do
        n = n + 1
        beat.Text = "alive " .. n
        task.wait(0.5)
    end
end)

local url = "https://raw.githubusercontent.com/demuth666/delve-script/backup/pre-rollback-20261114/inbox.lua"
local okFetch, src = pcall(function()
    return game:HttpGet(url)
end)
if not okFetch or type(src) ~= "string" or #src < 1000 then
    alive = false
    DBG("fetch gagal: " .. tostring(okFetch and "respons pendek" or src))
    return
end
DBG("source " .. #src .. " bytes")

local function inject(pattern, replacement)
    local out, n = src:gsub(pattern, replacement, 1)
    src = out
    return n
end

inject("local%s+Window%s*=%s*BPUI:CreateWindow%(", '_G.DBG("before CreateWindow")\nlocal Window = BPUI:CreateWindow(')
inject("local%s+FarmTab%s*=%s*Window:CreateTab", '_G.DBG("after CreateWindow")\nlocal FarmTab = Window:CreateTab')
src = src:gsub("local%s+([%w_]+)%s*=%s*([%w_]+):CreateSection%(%s*\"([^\"]+)\"%s*%)", '_G.DBG("section: %3")\nlocal %1 = %2:CreateSection("%3")')
inject("S%.bossThread%s*=%s*task%.spawn%(", '_G.DBG("UI done")\nS.bossThread = task.spawn(')

local fn, cerr = loadstring(src)
if not fn then
    alive = false
    DBG("compile error: " .. tostring(cerr))
    return
end
DBG("compiled, running...")
local okRun, rerr = pcall(fn)
if not okRun then
    alive = false
    DBG("RUNTIME ERROR: " .. tostring(rerr))
    warn("[HubTest] " .. tostring(rerr))
end
