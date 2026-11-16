--[[
  Delta / Android debug panel untuk Delve Hub.
  Menampilkan status remote dan menguji filtergc yang dipanggil
  sebelum UI hub dibuat. Panel sengaja kecil (90% x 38%) dan muncul
  lebih dulu, jadi kalau filtergc hang, baris terakhir tetap terbaca.

  Pakai:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/delve-script/main/delta-debug.lua"))()
]]

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local pg = plr:FindFirstChildOfClass("PlayerGui") or plr:WaitForChild("PlayerGui", 10)
if not pg then
    return
end

local old = pg:FindFirstChild("DelveDebug")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DelveDebug"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0.9, 0, 0.38, 0)
frame.Position = UDim2.new(0.05, 0, 0.03, 0)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Parent = gui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -12, 1, -40)
label.Position = UDim2.new(0, 6, 0, 34)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 12
label.TextWrapped = true
label.Font = Enum.Font.Code
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Text = "start"
label.Parent = frame

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 70, 0, 24)
close.Position = UDim2.new(1, -76, 0, 6)
close.BackgroundColor3 = Color3.fromRGB(70, 25, 30)
close.TextColor3 = Color3.new(1, 1, 1)
close.TextSize = 14
close.Text = "Tutup"
close.BorderSizePixel = 0
close.Parent = frame
close.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local lines = {}
local function log(...)
    lines[#lines + 1] = table.concat({...}, " ")
    label.Text = table.concat(lines, "\n")
end

-- Biarkan panel tampil dulu; filtergc bisa memblokir thread ini.
task.wait(0.3)

log("executor:", identifyexecutor and select(1, identifyexecutor()) or "?")
log("loadstring:", type(loadstring), "HttpGet:", type(game.HttpGet), "request:", type(request))

local net = game:GetService("ReplicatedStorage"):FindFirstChild("StrataNet")
log("StrataNet:", net ~= nil)
if net then
    for _, n in ipairs({ "Aim", "PickaxeOut", "WeaponDrawn", "Swing", "SwapLoadout", "ProfileSync" }) do
        log(n .. ":", net:FindFirstChild(n) ~= nil)
    end
end

log("filtergc type:", type(filtergc))
task.wait(0.2)
log("before filtergc...")
task.wait(0.2)

local t0 = os.clock()
local ok, res = pcall(function()
    return filtergc("table", { Keys = { "Controllers", "State" } }, true)
end)
log(string.format("filtergc ok=%s time=%.2fs type=%s", tostring(ok), os.clock() - t0, type(res)))
if not ok then
    log("err:", tostring(res))
end
log("done")
