--[[
  Delve Hub - auto rock farm + auto fight, dengan UI BPUI.

  Fitur yang dikendalikan dari UI:
    1. Cari rock di workspace.StrataPlate (nama model = Grid.key(cellX, cellZ)).
    2. Teleport langsung ke sel rock itu sendiri (bawaan). Kalau toggle
       Teleport Langsung dimatikan, kembali ke sel di sebelah rock.
       Y tetap dari raycast lantai, bukan tebakan.
    3. Kirim Aim(x, z, true) 20x per detik supaya server menambang rock itu.
    4. Kalau ada mob hidup dalam radius, lepas Aim, ganti ke weapon, hadap mob, kirim Swing.
    5. Kalau mob hilang, balik ke pickaxe dan lanjut rock berikutnya.
    6. Fly manual (WASD, Space naik, LeftCtrl turun) + hover otomatis di atas
       batu/mob saat Auto Farm jalan. Saat Teleport Langsung aktif, badan
       dipindah seketika ke titik hover, bukan terbang mendekat.
       Ketinggian hover diatur di tab Terbang.
    7. Ambil chest otomatis dengan prioritas tertinggi: begitu chest muncul,
       karakter langsung teleport ke chest itu. Kalau state-nya locked, mob
       wave di sekitar chest diserang dulu sampai chest jadi unlocked, lalu
       chest disentuh supaya terbuka dan hadiahnya diambil. Setelah itu karakter
       diam di titik chest sampai chest hilang, lalu Auto Farm lanjut mencari
       batu dari situ.
    8. Auto pilih relic: relic yang dipilih di tab Relic diutamakan. Kalau
       tidak ada di draft, fallback ke rarity tertinggi. Pilihan dikirim
       lewat StrataNet.PickRelic setelah draft muncul. Draft berbentuk kartu
       (shrine relic/blessing) ikut dipilih. Pilihan path dan pembelian
       trader diatur di bagian "Path & Trader" (default manual).
    9. Auto ganti equipment set (loadout): pilih set pedang, set mining, dan
       set diam lewat dropdown di tab Farm > Equipment Set. Saat pedang
       terhunus karakter pindah ke set pedang, saat pickaxe keluar pindah ke
       set mining.

  Catatan protokol (dibaca dari StrataClient.Controllers):
    - MiningInput mengirim StrataNet.Aim:FireServer(x, z, true) lalu Aim(0, 0, false) saat lepas.
      Server menganggap aim basi setelah 0.5 detik, jadi Aim harus dikirim terus.
    - PickaxeController mengirim StrataNet.PickaxeOut:FireServer(true/false).
    - WeaponController mengirim StrataNet.WeaponDrawn:FireServer(true/false).
    - WeaponController mengirim StrataNet.Swing:FireServer(facing, sweepSide, position).
    - Status server terlihat di atribut Character: PickaxeOut, WeaponDrawn, EquippedWeapon.
    - ChestController hanya membaca atribut ChestRarity / ChestState; server yang
      membuka chest saat karakter menyentuhnya. Chest yang boleh diambil adalah
      milik sendiri (Owner == UserId) atau tanpa Owner/RunId milik pemain lain,
      dan berada dekat plate sendiri (dibatasi radius).
    - GateController menerima StrataNet.RelicOffer (choices = daftar id relic)
      lalu mengirim StrataNet.PickRelic:FireServer(index 1..n). Offer dengan
      cards = trader (mode "trader"), shrine blessing (mode "shrine"), atau
      pilihan path (mode "choice"). offer.closed = true berarti draft ditutup.

  Pemakaian:
    loadstring(readfile("AIBridge/inbox.lua"))()
    RightShift = sembunyikan / tampilkan window (bawaan BPUI)
    getgenv().DelveFarm.Start() / .Pause() / .Resume() / .Stop() / .Destroy()
    getgenv().DelveFarm.SetFly(true/false) / .ToggleFly()
    getgenv().DelveFarm.SetRelicPriority({ "blast", "echo" })
    getgenv().DelveFarm.SetPathPick("safe" / "cursed" / "manual")
    getgenv().DelveFarm.SetTraderMode("manual" / "priority" / "relic" / "cheapest", hargaMaks)
    getgenv().DelveFarm.SetLoadoutAuto(true/false)
    getgenv().DelveFarm.SetLoadoutSets(setPedang, setMining, setIdle)

  Catatan:
    - Auto Farm sengaja mulai dalam keadaan mati. Nyalakan lewat toggle di tab Farm.
    - Tombol pause memakai keybind BPUI (default F2), bukan RightShift, karena
      RightShift dipakai BPUI untuk menyembunyikan window.
]]

local BPUI_OK, BPUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/bypasshubpremium/BPUINEW/main/BPUI.lua"))()
end)
if not BPUI_OK or type(BPUI) ~= "table" then
    warn("[DelveFarm] gagal memuat BPUI: " .. tostring(BPUI))
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local plr = Players.LocalPlayer

-- ============================================================
-- Konfigurasi (diubah langsung oleh elemen UI)
-- ============================================================

local CFG = {
    -- saklar fitur
    mine = true,
    fight = true,
    autoEquip = true,
    chase = true,

    -- mining
    aimHz = 20,                -- sama dengan Config.Mining.AimSendRate
    directRock = true,         -- teleport tepat ke sel batu, bukan ke sel sebelahnya
    standOffset = 6,           -- jarak berdiri dari titik tengah rock (dipakai kalau directRock mati)
    teleportTolerance = 2.5,   -- kalau sudah sedekat ini, tidak teleport lagi
    groundWait = 0.35,         -- tunggu setelah teleport sebelum kirim Aim
    rockTimeout = 20,          -- detik sebelum rock dianggap gagal dan di-blacklist
    rockBlacklist = 20,        -- lama rock di-blacklist
    rockScanInterval = 0.5,

    -- combat
    mobScanInterval = 0.25,
    mobDetect = 30,            -- mulai pakai weapon kalau mob sedekat ini
    mobRelease = 42,           -- baru balik ke pickaxe kalau mob sudah lebih jauh
    chaseStop = 7,
    equipRetry = 0.35,         -- jeda minimum antar PickaxeOut / WeaponDrawn

    -- equipment set (loadout 1..3), nilai awal; bisa diubah dari dropdown UI
    loadoutAuto = true,        -- ganti equipment set otomatis
    loadoutCombat = 1,         -- default set saat pedang terhunus
    loadoutMining = 2,         -- default set saat menambang / pickaxe keluar
    loadoutIdle = 0,           -- default set saat tidak pedang/pickaxe, 0 = tidak diganti
    loadoutDebounce = 0.6,     -- status harus stabil selama ini sebelum ganti
    loadoutCooldown = 5.2,     -- jeda aman antar swap (server membatasi 5 detik)

    -- chest
    chest = true,              -- ambil chest otomatis saat Auto Farm jalan
    chestScan = 0.2,           -- frekuensi scan chest, detik
    chestRadius = 200,         -- hanya chest sedekat ini dari badan (plate sendiri)
    chestTimeout = 2,          -- batas waktu menyentuh satu chest unlocked
    chestLockTimeout = 40,     -- batas waktu membersihkan wave chest locked
    chestWaveRadius = 240,     -- radius mob wave yang dicari saat chest locked
    chestOpenHold = 6,         -- maksimal diam di chest open (berhenti lebih awal kalau chest hilang)
    chestCooldown = 8,         -- jeda sebelum chest yang gagal dicoba lagi

    -- relic
    autoRelic = true,          -- pilih relic otomatis saat draft muncul
    relicFallback = true,      -- kalau tidak ada prioritas, ambil rarity tertinggi
    relicDelay = 0.25,         -- jeda sebelum mengirim pilihan, detik
    pathPick = "manual",       -- "manual" / "safe" / "cursed"
    traderMode = "manual",     -- "manual" / "priority" / "relic" / "cheapest"
    traderMaxPrice = 0,        -- 0 = tanpa batas harga

    -- fly / hover
    fly = false,               -- modul terbang aktif (manual + hover)
    flySpeed = 60,             -- kecepatan horizontal, stud/detik
    flyVert = 40,              -- kecepatan naik/turun, stud/detik
    hover = true,              -- hover otomatis saat Auto Farm berjalan
    hoverMine = true,          -- hover saat mode menambang
    hoverFight = true,         -- hover saat mode menyerang
    hoverHeight = 10,          -- ketinggian badan di atas target, stud
    hoverRock = true,          -- true = di atas batu, false = di atas sel berdiri
    hoverOffset = 4,           -- geser horizontal saat menyerang supaya arah Swing valid

    -- swing dari ketinggian
    swingFake = true,          -- kirim titik pukulan di dekat mob, bukan posisi badan
    swingGap = 1.5,            -- jarak titik pukulan dari mob, stud
    swingDiveAuto = true,      -- otomatis dive kalau 3 swing tidak mengenai mob
    swingDive = false,         -- paksa dive di setiap swing (fallback manual)
    swingDiveTime = 0.28,      -- lama badan berada di titik pukulan
    swingDiveDelay = 0.12,     -- jeda sebelum Swing saat dive, biar posisi sempat replikasi
}

-- ============================================================
-- Remote
-- ============================================================

local net = ReplicatedStorage:WaitForChild("StrataNet", 20)
if not net then
    BPUI:Notify({ Title = "Delve Hub", Content = "StrataNet tidak ditemukan.", Type = "Error", Duration = 6 })
    return
end

local aimRemote = net:WaitForChild("Aim", 10)
local pickaxeRemote = net:WaitForChild("PickaxeOut", 10)
local weaponRemote = net:WaitForChild("WeaponDrawn", 10)
local swingRemote = net:WaitForChild("Swing", 10)
if not (aimRemote and pickaxeRemote and weaponRemote and swingRemote) then
    BPUI:Notify({ Title = "Delve Hub", Content = "Remote StrataNet tidak lengkap.", Type = "Error", Duration = 6 })
    return
end

-- Defs dipakai hanya untuk tahu jangkauan dan jeda swing senjata yang sedang dipakai.
local weapons = nil
pcall(function()
    weapons = require(ReplicatedStorage.Strata.Defs.Weapons)
end)

-- Relic hanya untuk fitur auto pilih relic. Kalau gagal dibaca, hub tetap jalan.
local Relics = nil
local RarityDefs = nil
pcall(function()
    local strata = ReplicatedStorage:FindFirstChild("Strata") or ReplicatedStorage:WaitForChild("Strata", 10)
    if strata then
        Relics = require(strata.Defs.Relics)
        RarityDefs = require(strata.Defs.Rarity)
    end
end)

local relicOfferRemote = net:WaitForChild("RelicOffer", 5)
local relicPickRemote = net:WaitForChild("PickRelic", 5)

-- Equipment set. Kalau remote ini tidak ada, fitur auto set dimatikan.
local loadoutRemote = net:FindFirstChild("SwapLoadout")
local profileSyncRemote = net:FindFirstChild("ProfileSync")
if not loadoutRemote then
    CFG.loadoutAuto = false
    warn("[DelveFarm] SwapLoadout tidak ditemukan, auto equipment set dimatikan.")
end

-- ============================================================
-- State
-- ============================================================

local S = {
    alive = true,
    uiAlive = true,
    running = false,
    paused = false,
    mode = nil,          -- "mine" atau "fight"
    want = nil,          -- "pickaxe" atau "weapon"
    wantAt = 0,
    aimX = 0,
    aimZ = 0,
    aiming = false,
    guardAim = false,
    lastAimSent = 0,
    lastSwing = 0,
    teleportedAt = 0,
    rock = nil,
    rockX = 0,
    rockZ = 0,
    rockSince = 0,
    rockPos = nil,
    stand = nil,
    snappedRock = nil,
    rocks = {},
    rocksAt = 0,
    mobs = {},
    mobsAt = 0,
    blacklist = {},
    warned = false,
    chaseAt = 0,
    chasing = false,
    oldNamecall = nil,
    connChar = nil,
    thread = nil,
    swingCache = nil,
    keybind = nil,
    toggle = nil,

    -- fly
    flyOn = false,
    flyBv = nil,
    flyBg = nil,
    flyTarget = nil,
    flyHeightNow = 0,
    flyToggle = nil,
    flyKeybind = nil,
    flyCard = nil,
    flyManualAt = 0,

    -- swing
    diveUntil = 0,
    divePoint = nil,
    pendingSwing = nil,
    trackedMob = nil,
    trackedHp = 0,
    trackedAt = 0,
    trackedSwings = 0,
    forceDive = false,

    -- chest
    chestBusy = false,
    chestTarget = nil,
    chestRestore = nil,
    chestRestoreChar = nil,
    chestState = nil,
    chestSince = 0,
    chestClaimUntil = 0,
    chestAt = 0,
    chestFound = nil,
    chestCooldownUntil = {},
    chestTaken = 0,

    -- relic
    relicPriority = {},    -- set id -> true
    relicOrder = {},       -- id urut sesuai pilihan pemain
    relicStatus = "Belum ada draft relic.",
    relicSeq = 0,
    relicLast = nil,
    relicPicks = 0,
    connRelic = nil,
    relicDropdown = nil,
    relicCard = nil,

    -- equipment set (loadout)
    app = nil,
    appTriedAt = -1e9,
    loadoutActive = nil,
    loadoutWant = nil,
    loadoutWantAt = 0,
    loadoutPending = nil,
    loadoutLastFire = 0,
    loadoutWarned = false,
    connLoadout = nil,
    loadoutToggle = nil,
    loadoutCombatDropdown = nil,
    loadoutMiningDropdown = nil,
    loadoutIdleDropdown = nil,
}

local function sign(v)
    if v >= 0 then
        return 1
    end
    return -1
end

local function floorAt(x, z, y)
    local ch = plr.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { ch }
    -- Rock dan VFX tidak collide; raycast harus mengenai lantai plate, bukan mesh batu.
    pcall(function()
        params.RespectCanCollide = true
    end)
    local hit = workspace:Raycast(Vector3.new(x, y + 30, z), Vector3.new(0, -90, 0), params)
    if hit then
        return hit.Position
    end
    return nil
end

local function scanRocks()
    local plate = workspace:FindFirstChild("StrataPlate")
    local list = {}
    if not plate then
        return list
    end
    for _, inst in ipairs(plate:GetDescendants()) do
        if inst:IsA("Model") then
            local key = tonumber(inst.Name)
            if key and key >= 1024 and key < 67108864 then
                local x = math.floor(key / 1024)
                local z = key - x * 1024
                local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
                if x >= 1 and z >= 1 and part then
                    table.insert(list, { model = inst, x = x, z = z })
                end
            end
        end
    end
    return list
end

local function scanMobs()
    local list = {}
    local myRun = plr:GetAttribute("RunId")
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("MobId") ~= nil and m.PrimaryPart then
            if m:GetAttribute("Dead") ~= true then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health > 0 then
                    local mobRun = m:GetAttribute("RunId")
                    if myRun == nil or mobRun == nil or mobRun == myRun then
                        table.insert(list, m)
                    end
                end
            end
        end
    end
    return list
end

local function nearestMob(pos)
    local now = os.clock()
    if now - S.mobsAt > CFG.mobScanInterval then
        S.mobs = scanMobs()
        S.mobsAt = now
    end
    local radius = CFG.mobDetect
    if S.mode == "fight" then
        radius = CFG.mobRelease
    end
    local best, bestD
    for _, m in ipairs(S.mobs) do
        local pp = m.PrimaryPart
        if pp and m.Parent then
            local p = pp.Position
            local d = (Vector3.new(p.X - pos.X, 0, p.Z - pos.Z)).Magnitude
            if d <= radius and (not bestD or d < bestD) then
                best, bestD = m, d
            end
        end
    end
    return best, bestD
end

local function weaponStats()
    local ch = plr.Character
    local id = ch and ch:GetAttribute("EquippedWeapon")
    if S.swingCache and S.swingCache.id == id then
        return S.swingCache.range, S.swingCache.interval
    end
    local range, interval = 14, 0.55
    if weapons and id then
        local ok, def = pcall(weapons.at, id)
        if ok and def then
            local okR, r = pcall(weapons.range, def)
            if okR and type(r) == "number" and r > 0 then
                range = r
            end
            local okT, t = pcall(weapons.rate, def, 1)
            if okT and type(t) == "number" and t > 0 then
                interval = math.max(t, 0.15)
            end
        end
    end
    S.swingCache = { id = id, range = range, interval = interval }
    return range, interval
end

local function releaseAim()
    if not S.aiming then
        S.guardAim = false
        return
    end
    S.aiming = false
    S.guardAim = false
    pcall(function()
        aimRemote:FireServer(0, 0, false)
    end)
end

local function teleportTo(point, lookAt)
    local ch = plr.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false
    end
    local cf
    if lookAt then
        local flat = Vector3.new(lookAt.X - point.X, 0, lookAt.Z - point.Z)
        if flat.Magnitude > 0.1 then
            cf = CFrame.lookAt(point, point + flat)
        else
            -- Tepat di atas batu: arah hadap tidak bisa dihitung dari titik itu,
            -- pertahankan rotasi badan yang sekarang.
            cf = CFrame.new(point) * (hrp.CFrame - hrp.CFrame.Position)
        end
    else
        cf = CFrame.new(point)
    end
    pcall(function()
        hrp.CFrame = cf
    end)
    S.teleportedAt = os.clock()
    return true
end

-- ============================================================
-- Chest
-- ============================================================

-- Combat didefinisikan setelah bagian ini; deklarasikan dulu supaya chest
-- bisa memakai weapon saat harus membersihkan wave.
local enterFight
local fightStep

local function chestOwned(chest)
    local viewer = chest:GetAttribute("Viewer")
    if viewer ~= nil and viewer ~= plr.UserId then
        return false
    end
    if chest:GetAttribute("HiddenFor_" .. plr.UserId) then
        return false
    end
    local owner = chest:GetAttribute("Owner")
    if owner ~= nil and owner ~= plr.UserId then
        return false
    end
    local myRun = plr:GetAttribute("RunId")
    local chestRun = chest:GetAttribute("RunId")
    if myRun ~= nil and chestRun ~= nil and chestRun ~= myRun then
        return false
    end
    return true
end

local function chestPivot(chest)
    local ok, pivot = pcall(function()
        return chest:GetPivot()
    end)
    if not ok then
        return nil
    end
    return pivot
end

local function chestPoint(chest)
    local pivot = chestPivot(chest)
    if not pivot then
        return nil
    end
    return pivot.Position + Vector3.new(0, 3.2, 0)
end

local function scanChest(hrp)
    local now = os.clock()
    if now - S.chestAt < CFG.chestScan then
        return S.chestFound
    end
    S.chestAt = now
    S.chestFound = nil

    local best, bestScore
    for _, inst in ipairs(workspace:GetChildren()) do
        local state = inst:GetAttribute("ChestState")
        if inst:GetAttribute("ChestRarity") ~= nil
            and (state == "locked" or state == "unlocked")
            and now >= (S.chestCooldownUntil[inst] or 0)
            and chestOwned(inst)
        then
            local pivot = chestPivot(inst)
            if pivot then
                local d = (pivot.Position - hrp.Position).Magnitude
                if d <= CFG.chestRadius then
                    -- Unlocked didahulukan karena bisa keburu hilang.
                    local score = d + (state == "unlocked" and 0 or 1000)
                    if not bestScore or score < bestScore then
                        best, bestScore = inst, score
                    end
                end
            end
        end
    end

    S.chestFound = best
    return best
end

local function chestAbort(keepPosition)
    if not keepPosition and S.chestRestore and S.chestRestoreChar == plr.Character then
        local ch = plr.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                hrp.CFrame = S.chestRestore
            end)
        end
    end
    S.chestBusy = false
    S.chestTarget = nil
    S.chestRestore = nil
    S.chestRestoreChar = nil
    S.chestFound = nil
    S.chestState = nil
    S.chestSince = 0
    S.chestClaimUntil = 0
end

local function mobOwned(m)
    local owner = m:GetAttribute("Owner")
    if owner ~= nil and owner == plr.UserId then
        return true
    end
    local myRun = plr:GetAttribute("RunId")
    local mobRun = m:GetAttribute("RunId")
    if myRun ~= nil and mobRun ~= nil and mobRun == myRun then
        return true
    end
    return owner == nil and mobRun == nil
end

local function nearestChestMob(pos, radius)
    local now = os.clock()
    if now - S.mobsAt > CFG.mobScanInterval then
        S.mobs = scanMobs()
        S.mobsAt = now
    end
    local best, bestD
    for _, m in ipairs(S.mobs) do
        local pp = m.PrimaryPart
        if pp and m.Parent and mobOwned(m) then
            local p = pp.Position
            local d = (Vector3.new(p.X - pos.X, 0, p.Z - pos.Z)).Magnitude
            if d <= radius and (not bestD or d < bestD) then
                best, bestD = m, d
            end
        end
    end
    return best
end

local function chestChasePoint(pos, hrp)
    local flat = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
    local dir
    if flat.Magnitude > 0.5 then
        dir = flat.Unit
    else
        dir = Vector3.new(0, 0, -1)
    end
    local off = math.clamp(CFG.hoverOffset, 1, 6)
    local height = 2.5
    if S.flyOn and CFG.hover and CFG.hoverFight then
        height = math.max(CFG.hoverHeight, 6)
    end
    return Vector3.new(pos.X + dir.X * off, pos.Y + height, pos.Z + dir.Z * off)
end

local function chestStep(hrp, hum)
    local now = os.clock()
    local chest = S.chestTarget

    if not CFG.chest then
        if chest then
            chestAbort()
        end
        return false
    end

    if chest and not chest.Parent then
        local wasOpen = chest:GetAttribute("ChestState") == "open"
        chestAbort(wasOpen or S.chestClaimUntil > 0)
        chest = nil
    end

    if not chest then
        chest = scanChest(hrp)
        if not chest then
            return false
        end
        local point = chestPoint(chest)
        if not point then
            return false
        end

        releaseAim()
        S.chestTarget = chest
        S.chestRestore = hrp.CFrame
        S.chestRestoreChar = plr.Character
        S.chestBusy = true
        S.chestState = chest:GetAttribute("ChestState")
        S.chestSince = now
        S.chestClaimUntil = 0
        -- Langsung teleport ke chest, termasuk saat state masih locked.
        pcall(function()
            hrp.CFrame = CFrame.new(point)
        end)
        S.teleportedAt = now
        return true
    end

    local state = chest:GetAttribute("ChestState")
    if state == nil then
        chestAbort(S.chestClaimUntil > 0)
        return false
    end
    if state ~= S.chestState then
        S.chestState = state
        S.chestSince = now
    end

    local point = chestPoint(chest)
    if not point then
        chestAbort()
        return false
    end
    local flat = Vector3.new(hrp.Position.X - point.X, 0, hrp.Position.Z - point.Z)
    local chestDist = flat.Magnitude

    if state == "open" then
        -- Sentuhan terakhir untuk mengambil hadiah; karakter diam di titik chest
        -- sampai chest hilang (atau batas waktu tercapai).
        if S.chestClaimUntil == 0 then
            pcall(function()
                hrp.CFrame = CFrame.new(point)
            end)
            S.teleportedAt = now
            S.chestClaimUntil = now + CFG.chestOpenHold
            S.chestTaken = S.chestTaken + 1
            print("[DelveFarm] chest diambil (" .. tostring(chest:GetAttribute("ChestRarity")) .. ")")
        end
        if now < S.chestClaimUntil then
            pcall(function()
                hrp.CFrame = CFrame.new(point)
            end)
            return true
        end
        -- Chest berhasil diambil: tetap di titik chest, jangan kembali ke posisi lama.
        chestAbort(true)
        return false
    end

    if state == "unlocked" then
        if chestDist > CFG.teleportTolerance then
            pcall(function()
                hrp.CFrame = CFrame.new(point)
            end)
            S.teleportedAt = now
        end
        if now - S.chestSince > CFG.chestTimeout then
            S.chestCooldownUntil[chest] = now + CFG.chestCooldown
            chestAbort()
            return false
        end
        return true
    end

    -- locked: bersihkan wave dulu. Karakter menyerang mob yang muncul,
    -- lalu kembali ke chest setelah tidak ada mob hidup.
    if now - S.chestSince > CFG.chestLockTimeout then
        S.chestCooldownUntil[chest] = now + CFG.chestCooldown
        chestAbort()
        return false
    end

    local mob = nearestChestMob(hrp.Position, CFG.chestWaveRadius)
    if mob then
        enterFight()
        S.mob = mob
        local pp = mob.PrimaryPart
        if pp then
            local pos = pp.Position
            local range = weaponStats()
            local toMob = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
            if toMob.Magnitude > range - 1 then
                local p = chestChasePoint(pos, hrp)
                pcall(function()
                    hrp.CFrame = CFrame.lookAt(p, Vector3.new(pos.X, p.Y, pos.Z))
                end)
                S.teleportedAt = now
                releaseAim()
                return true
            end
        end
        local ch = plr.Character
        if ch and ch:GetAttribute("WeaponDrawn") ~= true then
            return true
        end
        fightStep(mob, hrp, hum)
        return true
    end

    -- Tidak ada mob hidup: tunggu di chest sampai server mengubah state.
    S.mob = nil
    if chestDist > CFG.teleportTolerance then
        pcall(function()
            hrp.CFrame = CFrame.new(point)
        end)
        S.teleportedAt = now
    end
    return true
end

-- ============================================================
-- Relic picker
-- ============================================================

local RELIC_PREFS_FILE = "AIBridge/relic_prefs.json"
local relicLabelToId = {}
local relicIdToLabel = {}
local relicNameToId = {}
local relicOptions = {}

local PATH_LABELS = { manual = "Manual", safe = "Safe Path", cursed = "Cursed Path" }
local TRADER_LABELS = {
    manual = "Manual",
    priority = "Relic prioritas",
    relic = "Relic apa saja",
    cheapest = "Termurah",
}
local TRADER_MODES = { manual = true, priority = true, relic = true, cheapest = true }

local function relicRank(def)
    if not def then
        return 0
    end
    if def.rarity == "blessing" then
        -- Blessing tidak punya rank di Rarity (0). Di game dianggap 5 untuk
        -- efek kartu, tapi untuk auto pick ditaruh sedikit di atas legendary
        -- supaya blessing tidak kalah tie-break dari legendary.
        return 5.5
    end
    if RarityDefs then
        local ok, rank = pcall(function()
            return RarityDefs.rank(def.rarity)
        end)
        if ok and type(rank) == "number" then
            return rank
        end
    end
    return 1
end

local function relicName(id)
    local def = Relics and Relics:Find(id)
    if not def then
        return tostring(id)
    end
    return string.format("%s [%s]", def.name, tostring(def.rarity))
end

local function buildRelicOptions()
    relicLabelToId = {}
    relicIdToLabel = {}
    relicNameToId = {}
    relicOptions = {}
    if not Relics then
        return
    end

    local ok, ordered = pcall(function()
        return Relics:Ordered()
    end)
    if not ok or type(ordered) ~= "table" then
        return
    end

    local list = {}
    local used = {}
    for _, def in ipairs(ordered) do
        if def.id and def.name then
            local tag = tostring(def.rarity)
            if def.retired then
                tag = tag .. ", retired"
            end
            local label = string.format("%s [%s]", def.name, tag)
            if used[label] then
                label = label .. " (" .. def.id .. ")"
            end
            used[label] = true
            relicLabelToId[label] = def.id
            relicIdToLabel[def.id] = label
            relicNameToId[string.upper(def.name)] = def.id
            list[#list + 1] = {
                label = label,
                id = def.id,
                name = def.name,
                rank = relicRank(def),
                retired = def.retired and true or false,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end
        if a.retired ~= b.retired then
            return (not a.retired) and b.retired
        end
        return a.name < b.name
    end)

    for _, item in ipairs(list) do
        relicOptions[#relicOptions + 1] = item.label
    end
end

local function setRelicPriority(ids)
    local order = {}
    local set = {}
    for _, id in ipairs(ids or {}) do
        if type(id) == "string" and relicIdToLabel[id] and not set[id] then
            order[#order + 1] = id
            set[id] = true
        end
    end
    S.relicOrder = order
    S.relicPriority = set
end

local function saveRelicPrefs()
    pcall(function()
        local json = HttpService:JSONEncode({
            auto = CFG.autoRelic,
            fallback = CFG.relicFallback,
            delay = CFG.relicDelay,
            path = CFG.pathPick,
            trader = CFG.traderMode,
            traderMax = CFG.traderMaxPrice,
            ids = S.relicOrder,
        })
        writefile(RELIC_PREFS_FILE, json)
    end)
end

local function loadRelicPrefs()
    local ok, data = pcall(function()
        if type(isfile) == "function" and not isfile(RELIC_PREFS_FILE) then
            return nil
        end
        local raw = readfile(RELIC_PREFS_FILE)
        if type(raw) ~= "string" or raw == "" then
            return nil
        end
        return HttpService:JSONDecode(raw)
    end)
    if not ok or type(data) ~= "table" then
        return
    end
    if type(data.auto) == "boolean" then
        CFG.autoRelic = data.auto
    end
    if type(data.fallback) == "boolean" then
        CFG.relicFallback = data.fallback
    end
    if type(data.delay) == "number" then
        CFG.relicDelay = math.clamp(data.delay, 0, 2)
    end
    if data.path == "safe" or data.path == "cursed" or data.path == "manual" then
        CFG.pathPick = data.path
    end
    if type(data.trader) == "string" and TRADER_MODES[data.trader] then
        CFG.traderMode = data.trader
    end
    if type(data.traderMax) == "number" then
        CFG.traderMaxPrice = math.clamp(data.traderMax, 0, 5000000)
    end
    local ids = {}
    for _, id in ipairs(data.ids or {}) do
        if type(id) == "string" then
            ids[#ids + 1] = id
        end
    end
    setRelicPriority(ids)
end

-- Kartu offer (trader, shrine, path) memakai judul, bukan id. Cocokkan dulu
-- ke id relic supaya prioritas dan rarity tetap bisa dipakai.
local function resolveRelicId(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if Relics then
        local ok, def = pcall(function()
            return Relics:Find(value)
        end)
        if ok and def then
            return value
        end
    end
    return relicNameToId[string.upper(value)]
end

-- candidates: { index = number, id = string?, rank = number }
local function chooseBest(candidates)
    local bestPriority, bestPriorityRank, bestPriorityOrder
    for _, c in ipairs(candidates) do
        if c.id and S.relicPriority[c.id] then
            local order = table.find(S.relicOrder, c.id) or 999
            if not bestPriority
                or c.rank > bestPriorityRank
                or (c.rank == bestPriorityRank and order < bestPriorityOrder)
            then
                bestPriority = c.index
                bestPriorityRank = c.rank
                bestPriorityOrder = order
            end
        end
    end
    if bestPriority then
        return bestPriority, "prioritas"
    end

    if CFG.relicFallback then
        local best, bestRank
        for _, c in ipairs(candidates) do
            if not best or c.rank > bestRank then
                best = c.index
                bestRank = c.rank
            end
        end
        if best then
            return best, "rarity tertinggi"
        end
    end

    return nil, "tidak ada yang cocok"
end

local function chooseRelicIndex(choices)
    if type(choices) ~= "table" or #choices == 0 or not Relics then
        return nil, "tidak ada pilihan"
    end

    local candidates = {}
    for i, id in ipairs(choices) do
        local def = Relics:Find(id)
        if def then
            candidates[#candidates + 1] = { index = i, id = id, rank = relicRank(def) }
        end
    end
    if #candidates == 0 then
        return nil, "tidak ada yang cocok"
    end
    return chooseBest(candidates)
end

local RELIC_TIERS = {
    common = true,
    uncommon = true,
    rare = true,
    epic = true,
    blessing = true,
    legendary = true,
    mythic = true,
}

local function cardPrice(card)
    local price = tonumber(card.price)
    if price then
        return price
    end
    local digits = tostring(card.action or ""):match("%$(%d+)")
    return tonumber(digits)
end

-- Offer path (SAFE PATH / CURSED PATH). Pilihan diambil dari judul kartu.
local function choosePathIndex(cards)
    local want = CFG.pathPick
    if want ~= "safe" and want ~= "cursed" then
        return nil, "path manual"
    end

    local needle = want == "safe" and "SAFE" or "CURSED"
    local reason = want == "safe" and "path aman" or "path terkutuk"
    for i, card in ipairs(cards) do
        if type(card) == "table" then
            local title = string.upper(tostring(card.title or card.name or ""))
            local action = string.upper(tostring(card.action or ""))
            if title:find(needle, 1, true) or action:find(needle, 1, true) then
                return i, reason
            end
        end
    end

    -- Urutan kartu path di game: 1 = SAFE PATH, 2 = CURSED PATH.
    if #cards >= 2 then
        return (want == "safe") and 1 or 2, reason
    end
    return nil, "path tidak cocok"
end

-- Offer trader (mode "trader"). Kartu berharga cash, sebagai gantinya kartu
-- relic biasa (Tier EPIC RELIC / BLESSING RELIC) bisa punya rarity.
local function chooseTraderIndex(cards)
    local mode = CFG.traderMode
    if not TRADER_MODES[mode] or mode == "manual" then
        return nil, "trader manual"
    end

    local maxPrice = tonumber(CFG.traderMaxPrice) or 0

    local best, bestRank, bestPrice
    for i, card in ipairs(cards) do
        if type(card) == "table" and card.afford ~= false then
            local price = cardPrice(card) or 0
            if maxPrice <= 0 or price <= maxPrice then
                local id = resolveRelicId(card.id) or resolveRelicId(card.title)
                local def = id and Relics and Relics:Find(id) or nil
                local rank = 0
                if def then
                    rank = relicRank(def)
                elseif RELIC_TIERS[card.rarity] then
                    rank = relicRank({ rarity = card.rarity })
                end
                local isRelic = rank > 0

                local wanted = false
                if mode == "cheapest" then
                    wanted = true
                elseif mode == "relic" then
                    wanted = isRelic
                elseif mode == "priority" then
                    wanted = id ~= nil and S.relicPriority[id] == true
                end

                if wanted then
                    if mode == "cheapest" then
                        if not best or price < bestPrice then
                            best = i
                            bestRank = rank
                            bestPrice = price
                        end
                    elseif not best or rank > bestRank or (rank == bestRank and price < bestPrice) then
                        -- Rarity tertinggi dulu, harga termurah sebagai penentu.
                        best = i
                        bestRank = rank
                        bestPrice = price
                    end
                end
            end
        end
    end

    if best then
        local reasons = {
            priority = "trader prioritas",
            relic = "trader relic",
            cheapest = "trader termurah",
        }
        return best, reasons[mode] or ("trader " .. tostring(mode))
    end
    return nil, "tidak ada item trader yang cocok"
end

-- Offer berbentuk cards dipakai trader (berbayar), shrine relic/blessing, dan
-- pilihan path. Hanya kartu relic yang dikerjakan otomatis; kartu berbayar dan
-- pilihan path dibiarkan manual.
local function chooseCardIndex(cards, offer)
    if type(cards) ~= "table" or #cards == 0 then
        return nil, "tidak ada kartu"
    end

    local mode = type(offer) == "table" and offer.mode or nil
    if mode == "choice" then
        return choosePathIndex(cards)
    end
    if mode == "trader" then
        return chooseTraderIndex(cards)
    end

    local candidates = {}
    for i, card in ipairs(cards) do
        if type(card) == "table" then
            local id = resolveRelicId(card.id) or resolveRelicId(card.title)
            local def = id and Relics and Relics:Find(id) or nil
            local affordable = card.afford ~= false
            if def then
                if affordable then
                    candidates[#candidates + 1] = { index = i, id = id, rank = relicRank(def) }
                end
            elseif RELIC_TIERS[card.rarity] then
                -- Nama kartu tidak cocok dengan def, tapi tier-nya relic. Tetap
                -- ikut dipilih lewat fallback rarity supaya blessing tidak lewat.
                if affordable then
                    candidates[#candidates + 1] = {
                        index = i,
                        id = nil,
                        rank = relicRank({ rarity = card.rarity }),
                    }
                end
            elseif mode == "shrine" and affordable then
                -- Semua kartu shrine adalah blessing. Kalau nama dan tier tidak
                -- dikenali, tetap dianggap blessing supaya tidak dilewati.
                candidates[#candidates + 1] = {
                    index = i,
                    id = nil,
                    rank = relicRank({ rarity = "blessing" }),
                }
            end
        end
    end

    if #candidates == 0 then
        return nil, "bukan kartu relic"
    end
    return chooseBest(candidates)
end

local function cardName(card)
    if type(card) ~= "table" then
        return tostring(card)
    end
    local id = resolveRelicId(card.id) or resolveRelicId(card.title)
    if id and relicIdToLabel[id] then
        return relicName(id)
    end
    return tostring(card.title or card.name or card.id or "?")
end

local function onRelicOffer(offer)
    if type(offer) ~= "table" then
        return
    end

    if offer.closed then
        S.relicSeq = S.relicSeq + 1
        S.relicStatus = "Draft relic ditutup."
        return
    end

    local isCards = type(offer.cards) == "table"
    local choices = offer.choices

    if not isCards and (type(choices) ~= "table" or #choices == 0) then
        return
    end

    local names = {}
    local index, reason
    if isCards then
        for _, card in ipairs(offer.cards) do
            names[#names + 1] = cardName(card)
        end
        if CFG.autoRelic then
            index, reason = chooseCardIndex(offer.cards, offer)
        end
    else
        for _, id in ipairs(choices) do
            names[#names + 1] = relicName(id)
        end
        if CFG.autoRelic then
            index, reason = chooseRelicIndex(choices)
        end
    end

    S.relicSeq = S.relicSeq + 1
    local seq = S.relicSeq

    if not CFG.autoRelic then
        S.relicStatus = "Draft: " .. table.concat(names, " | ")
        return
    end

    if not (relicPickRemote and Relics) then
        S.relicStatus = "Fitur relic tidak tersedia."
        return
    end

    if not index then
        local prefix = isCards and "Kartu: " or "Draft: "
        S.relicStatus = prefix .. table.concat(names, " | ") .. " (" .. tostring(reason) .. ")"
        if isCards and reason ~= "path manual" and reason ~= "trader manual" then
            print("[DelveFarm] relic: kartu dilewati (" .. tostring(reason) .. ")")
        end
        return
    end

    local label
    if isCards then
        label = cardName(offer.cards[index])
    else
        label = relicName(choices[index])
    end

    local delay = math.clamp(tonumber(CFG.relicDelay) or 0, 0, 2)
    S.relicStatus = string.format(
        "Draft: %s. Memilih %s (%s) dalam %.2fs.",
        table.concat(names, " | "),
        label,
        reason,
        delay
    )

    local ends = tonumber(offer.ends) or 0
    task.delay(delay, function()
        if not S.alive or seq ~= S.relicSeq then
            return
        end
        if ends > 0 and workspace:GetServerTimeNow() > ends then
            S.relicStatus = "Draft lewat batas waktu, batal memilih."
            return
        end
        local gui = plr.PlayerGui:FindFirstChild("RelicDraft")
        if gui and gui:IsA("ScreenGui") and not gui.Enabled then
            S.relicStatus = "Draft sudah ditutup (mungkin dipilih manual)."
            return
        end
        local ok = pcall(function()
            relicPickRemote:FireServer(index)
        end)
        if not ok then
            S.relicStatus = "Gagal mengirim PickRelic."
            return
        end
        if gui and gui:IsA("ScreenGui") then
            pcall(function()
                gui.Enabled = false
            end)
        end
        S.relicPicks = S.relicPicks + 1
        S.relicLast = label
        S.relicStatus = string.format("Terpilih: %s (%s).", label, reason)
        print("[DelveFarm] relic: " .. label .. " (" .. reason .. ")")
    end)
end

local function relicStatusText()
    local lines = {}
    lines[#lines + 1] = S.relicStatus
    lines[#lines + 1] = "Prioritas: " .. tostring(#S.relicOrder) .. " relic"
    if #S.relicOrder > 0 then
        local names = {}
        for i, id in ipairs(S.relicOrder) do
            if i <= 8 then
                names[#names + 1] = relicName(id)
            end
        end
        local more = #S.relicOrder > 8 and (" (+" .. tostring(#S.relicOrder - 8) .. " lagi)") or ""
        lines[#lines + 1] = table.concat(names, ", ") .. more
    end
    lines[#lines + 1] = "Dipilih otomatis: " .. tostring(S.relicPicks)
    lines[#lines + 1] = "Path: " .. (PATH_LABELS[CFG.pathPick] or "Manual")
    local traderLine = "Trader: " .. (TRADER_LABELS[CFG.traderMode] or "Manual")
    if CFG.traderMode ~= "manual" and (tonumber(CFG.traderMaxPrice) or 0) > 0 then
        traderLine = traderLine .. " (maks " .. tostring(math.floor(CFG.traderMaxPrice)) .. ")"
    end
    lines[#lines + 1] = traderLine
    if S.relicLast then
        lines[#lines + 1] = "Terakhir: " .. S.relicLast
    end
    return table.concat(lines, "\n")
end

local function refreshRelicStatus()
    if not S.relicCard then
        return
    end
    pcall(function()
        S.relicCard:SetContent(relicStatusText())
    end)
end

buildRelicOptions()
loadRelicPrefs()

if relicOfferRemote and relicPickRemote and Relics then
    S.connRelic = relicOfferRemote.OnClientEvent:Connect(onRelicOffer)
end

local function grounded(hum)
    if not hum then
        return false
    end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
        return false
    end
    return hum.FloorMaterial ~= Enum.Material.Air
end

local function pumpEquip()
    local ch = plr.Character
    if not ch or not S.want or not CFG.autoEquip then
        return
    end
    local now = os.clock()
    if now - S.wantAt < CFG.equipRetry then
        return
    end
    if S.want == "pickaxe" then
        if ch:GetAttribute("PickaxeOut") ~= true or ch:GetAttribute("WeaponDrawn") == true then
            S.wantAt = now
            pcall(function()
                pickaxeRemote:FireServer(true)
            end)
            pcall(function()
                weaponRemote:FireServer(false)
            end)
        end
    else
        if ch:GetAttribute("WeaponDrawn") ~= true or ch:GetAttribute("PickaxeOut") == true then
            S.wantAt = now
            pcall(function()
                weaponRemote:FireServer(true)
            end)
            pcall(function()
                pickaxeRemote:FireServer(false)
            end)
        end
    end
end

-- ============================================================
-- Equipment set (loadout)
-- ============================================================

local function findStrataApp()
    if type(filtergc) ~= "function" then
        return nil
    end
    local ok, app = pcall(filtergc, "table", { Keys = { "Controllers", "State" } }, true)
    if ok and type(app) == "table" and type(app.Controllers) == "table" and type(app.State) == "table" then
        return app
    end
    return nil
end

local function ensureStrataApp(now)
    if S.app then
        return S.app
    end
    -- Scan ulang maksimal sekali tiap 5 detik kalau app belum ketemu.
    if now - S.appTriedAt < 5 then
        return nil
    end
    S.appTriedAt = now
    S.app = findStrataApp()
    return S.app
end

local function readActiveLoadout(now)
    local app = ensureStrataApp(now)
    local profile = app and app.State and app.State.profile
    local value = profile and tonumber(profile.loadoutActive)
    if value then
        S.loadoutActive = math.clamp(math.floor(value), 1, 3)
    end
    return S.loadoutActive
end

local function loadoutSetNumber(value)
    local number_ = tonumber(value)
    if not number_ then
        return 0
    end
    number_ = math.floor(number_)
    if number_ < 1 or number_ > 3 then
        return 0
    end
    return number_
end

local function loadoutSetLabel(value, allowOff)
    local number_ = loadoutSetNumber(value)
    if number_ == 0 then
        return allowOff and "Mati" or "Set 1"
    end
    return "Set " .. tostring(number_)
end

local function loadoutSetFromLabel(label)
    if label == "Set 1" then
        return 1
    end
    if label == "Set 2" then
        return 2
    end
    if label == "Set 3" then
        return 3
    end
    return 0
end

local function loadoutTarget()
    local ch = plr.Character
    if not ch then
        return 0
    end
    local weapon = ch:GetAttribute("WeaponDrawn") == true
    local pickaxe = ch:GetAttribute("PickaxeOut") == true
    if weapon and not pickaxe then
        return loadoutSetNumber(CFG.loadoutCombat)
    end
    if pickaxe and not weapon then
        return loadoutSetNumber(CFG.loadoutMining)
    end
    return loadoutSetNumber(CFG.loadoutIdle)
end

local function pumpLoadout(now)
    if not CFG.loadoutAuto or not loadoutRemote then
        S.loadoutWant = nil
        return
    end

    local target = loadoutTarget()
    if target ~= S.loadoutWant then
        S.loadoutWant = target
        S.loadoutWantAt = now
    end

    -- Tunggu konfirmasi ProfileSync untuk swap yang sudah dikirim.
    if S.loadoutPending then
        if S.loadoutActive == S.loadoutPending then
            S.loadoutPending = nil
        elseif now - S.loadoutLastFire > 3 then
            -- Server tidak mengonfirmasi (ditolak / sync terlewat). Coba lagi nanti.
            S.loadoutPending = nil
        else
            return
        end
    end

    local want = S.loadoutWant
    if not want or want == 0 then
        return
    end
    if now - S.loadoutWantAt < CFG.loadoutDebounce then
        return
    end

    local active = readActiveLoadout(now)
    if active == want then
        return
    end
    if now - S.loadoutLastFire < CFG.loadoutCooldown then
        return
    end

    S.loadoutLastFire = now
    S.loadoutPending = want
    local ok, err = pcall(function()
        loadoutRemote:FireServer(want)
    end)
    if not ok then
        S.loadoutPending = nil
        if not S.loadoutWarned then
            S.loadoutWarned = true
            warn("[DelveFarm] equipment set: " .. tostring(err))
        end
        return
    end
    print("[DelveFarm] equipment set ->", want)
end

if profileSyncRemote then
    S.connLoadout = profileSyncRemote.OnClientEvent:Connect(function(profile)
        local value = type(profile) == "table" and tonumber(profile.loadoutActive)
        if not value then
            return
        end
        value = math.clamp(math.floor(value), 1, 3)
        local previous = S.loadoutActive
        S.loadoutActive = value
        if S.loadoutPending == value then
            S.loadoutPending = nil
        end
        -- Swap manual dari menu inventory juga memakai cooldown server yang sama.
        if previous ~= nil and previous ~= value then
            S.loadoutLastFire = math.max(S.loadoutLastFire, os.clock())
        end
    end)
end

readActiveLoadout(os.clock())

-- ============================================================
-- Fly / hover
-- ============================================================

local function syncFly(value)
    if not S.flyToggle then
        return
    end
    pcall(function()
        S.flyToggle:Set(value, true)
    end)
end

local function syncFlyKey(value)
    if not S.flyKeybind then
        return
    end
    pcall(function()
        S.flyKeybind:Set(value, true)
    end)
end

local function flyActive()
    return S.flyOn and S.flyBv ~= nil
end

local function flyCleanup()
    if S.flyBv then
        pcall(function()
            S.flyBv:Destroy()
        end)
        S.flyBv = nil
    end
    if S.flyBg then
        pcall(function()
            S.flyBg:Destroy()
        end)
        S.flyBg = nil
    end
    S.flyTarget = nil
end

local function flyEnable()
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then
        return false
    end
    flyCleanup()
    pcall(function()
        hum.PlatformStand = true
        hum.AutoRotate = false
    end)
    local bv = Instance.new("BodyVelocity")
    bv.Name = "DelveFly"
    bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bv.P = 12500
    bv.Velocity = Vector3.zero
    bv.Parent = hrp
    local bg = Instance.new("BodyGyro")
    bg.Name = "DelveFlyGyro"
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.P = 10000
    bg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + hrp.CFrame.LookVector)
    bg.Parent = hrp
    S.flyBv = bv
    S.flyBg = bg
    return true
end

local function flyDisable()
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    flyCleanup()
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.AutoRotate = true
        end)
    end
end

local function flyKeys()
    local cam = workspace.CurrentCamera
    local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
    look = Vector3.new(look.X, 0, look.Z)
    if look.Magnitude < 0.001 then
        look = Vector3.new(0, 0, -1)
    end
    look = look.Unit
    local right = Vector3.new(-look.Z, 0, look.X)

    local x, z = 0, 0
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        z = z + 1
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        z = z - 1
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        x = x + 1
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        x = x - 1
    end
    local flat = look * z + right * x
    if flat.Magnitude > 0 then
        flat = flat.Unit
    end

    local y = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        y = y + 1
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
        y = y - 1
    end
    return flat, y
end

local function hoverTargetFor(hrp)
    if not (S.flyOn and CFG.hover and S.running and not S.paused) then
        return nil
    end
    if S.chestBusy then
        return nil
    end

    if S.mode == "fight" and CFG.hoverFight then
        local mob = S.mob
        local pp = mob and mob.Parent and mob.PrimaryPart
        if not pp then
            return nil
        end
        local pos = pp.Position
        local flat = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
        local dir
        if flat.Magnitude > 0.5 then
            dir = flat.Unit
        else
            local cam = workspace.CurrentCamera
            local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
            dir = Vector3.new(look.X, 0, look.Z)
            if dir.Magnitude < 0.001 then
                dir = Vector3.new(0, 0, -1)
            end
            dir = dir.Unit
        end
        local off = math.clamp(CFG.hoverOffset, 0, 6)
        S.flyHeightNow = CFG.hoverHeight
        return Vector3.new(pos.X + dir.X * off, pos.Y + CFG.hoverHeight, pos.Z + dir.Z * off)
    end

    if S.mode == "mine" and CFG.hoverMine then
        local rock = S.rock
        if not rock or not rock.Parent then
            return nil
        end
        local base = CFG.hoverRock and S.rockPos or S.stand
        if not base then
            return nil
        end
        local top = base.Y
        if CFG.hoverRock then
            local ok, cf, size = pcall(function()
                local c, s = rock:GetBoundingBox()
                return c, s
            end)
            if ok and cf and size then
                top = cf.Position.Y + size.Y * 0.5
            end
        elseif S.stand then
            top = S.stand.Y - 3.2
        end
        S.flyHeightNow = CFG.hoverHeight
        return Vector3.new(base.X, top + CFG.hoverHeight, base.Z)
    end

    return nil
end

local function flyStep(dt)
    if not S.flyOn then
        return
    end
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then
        flyDisable()
        return
    end
    if not S.flyBv or S.flyBv.Parent ~= hrp then
        if not flyEnable() then
            return
        end
    end

    local now = os.clock()
    if S.diveUntil > now and S.divePoint then
        if S.flyBv then
            pcall(function()
                S.flyBv.Velocity = Vector3.zero
            end)
        end
        pcall(function()
            hrp.CFrame = CFrame.new(S.divePoint) * (hrp.CFrame - hrp.CFrame.Position)
        end)
        return
    end

    local flat, vy = flyKeys()
    local target = hoverTargetFor(hrp)
    S.flyTarget = target

    local vel
    local face
    if flat.Magnitude > 0 or vy ~= 0 then
        vel = flat * CFG.flySpeed + Vector3.new(0, vy * CFG.flyVert, 0)
        if flat.Magnitude > 0 then
            face = flat
        end
    elseif target then
        local delta = target - hrp.Position
        local dist = delta.Magnitude
        if dist > 0.2 then
            local sp = math.min(dist * 8, math.max(CFG.flySpeed, 90))
            vel = delta.Unit * sp
        else
            vel = Vector3.zero
        end
        local hflat = Vector3.new(delta.X, 0, delta.Z)
        if hflat.Magnitude > 0.5 then
            face = hflat.Unit
        end
    else
        vel = Vector3.zero
    end

    if S.flyBv then
        pcall(function()
            S.flyBv.Velocity = vel
        end)
    end
    if S.flyBg and face then
        pcall(function()
            S.flyBg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + face)
        end)
    end
end


local function standFor(rockModel, hrpPos)
    local ok, pivot = pcall(function()
        return rockModel:GetPivot().Position
    end)
    if not ok or not pivot then
        return nil, nil
    end
    if CFG.directRock then
        -- Langsung ke sel batu itu sendiri. Lantai di bawah batu dicari dengan
        -- raycast supaya Y tetap benar walau pivot batu tidak sejajar lantai.
        local floor = floorAt(pivot.X, pivot.Z, pivot.Y)
        local baseY = floor and floor.Y or pivot.Y
        return Vector3.new(pivot.X, baseY + 3.2, pivot.Z), pivot
    end
    local dx = hrpPos.X - pivot.X
    local dz = hrpPos.Z - pivot.Z
    local dir
    if math.abs(dx) >= math.abs(dz) then
        dir = Vector3.new(sign(dx), 0, 0)
    else
        dir = Vector3.new(0, 0, sign(dz))
    end
    local sx = pivot.X + dir.X * CFG.standOffset
    local sz = pivot.Z + dir.Z * CFG.standOffset
    local floor = floorAt(sx, sz, pivot.Y)
    if not floor then
        return nil, pivot
    end
    return Vector3.new(floor.X, floor.Y + 3.2, floor.Z), pivot
end

local function pickRock(hrp)
    local now = os.clock()
    if now - S.rocksAt > CFG.rockScanInterval then
        S.rocks = scanRocks()
        S.rocksAt = now
    end
    local best, bestD, bestStand, bestPivot
    for _, r in ipairs(S.rocks) do
        if r.model.Parent then
            local until_ = S.blacklist[r.model]
            if not until_ or until_ <= now then
                local ok, pivot = pcall(function()
                    return r.model:GetPivot().Position
                end)
                if ok and pivot then
                    local d = (Vector3.new(pivot.X - hrp.Position.X, 0, pivot.Z - hrp.Position.Z)).Magnitude
                    if not bestD or d < bestD then
                        local stand, pv = standFor(r.model, hrp.Position)
                        if stand then
                            best, bestD, bestStand, bestPivot = r, d, stand, pv
                        else
                            S.blacklist[r.model] = now + 5
                        end
                    end
                end
            end
        end
    end
    if not best then
        return false
    end
    S.rock = best.model
    S.rockX = best.x
    S.rockZ = best.z
    S.rockSince = now
    S.stand = bestStand
    S.rockPos = bestPivot
    S.snappedRock = nil
    return true
end

local function enterMine()
    if S.mode == "mine" then
        return
    end
    S.mode = "mine"
    S.want = "pickaxe"
    S.lastSwing = 0
end

function enterFight()
    if S.mode == "fight" then
        return
    end
    S.mode = "fight"
    releaseAim()
    S.want = "weapon"
    S.rock = nil
end

local function sendAim(now)
    S.guardAim = true
    if now - S.lastAimSent >= (1 / CFG.aimHz) - 0.005 then
        S.lastAimSent = now
        S.aimX = S.rockX
        S.aimZ = S.rockZ
        S.aiming = true
        pcall(function()
            aimRemote:FireServer(S.rockX, S.rockZ, true)
        end)
    end
end

local function mineStep(hrp, hum)
    local now = os.clock()
    if S.rock and not S.rock.Parent then
        S.rock = nil
    end
    if S.rock and now - S.rockSince > CFG.rockTimeout then
        S.blacklist[S.rock] = now + CFG.rockBlacklist
        S.rock = nil
    end
    if not S.rock then
        if not pickRock(hrp) then
            releaseAim()
            return
        end
    end

    -- Saat hover aktif, badan diarahkan ke titik hover di atas target.
    -- Dengan Teleport Langsung, badan dipindah seketika ke titik itu;
    -- tanpa toggle, fly loop yang mengantar perlahan.
    if flyActive() and CFG.hover and CFG.hoverMine and S.running and not S.paused then
        local target = hoverTargetFor(hrp)
        if not target then
            releaseAim()
            return
        end
        local d = Vector3.new(hrp.Position.X - target.X, 0, hrp.Position.Z - target.Z).Magnitude
        if CFG.directRock and S.snappedRock ~= S.rock then
            -- Sekali per batu: pindah seketika ke titik hover. Setelah itu
            -- kontrol manual dan fly loop tetap bebas seperti sebelumnya.
            if d > CFG.teleportTolerance then
                teleportTo(target, S.rockPos)
                if S.flyBv then
                    pcall(function()
                        S.flyBv.Velocity = Vector3.zero
                    end)
                end
                S.snappedRock = S.rock
                releaseAim()
                return
            end
            S.snappedRock = S.rock
        end
        if d > 6 then
            releaseAim()
            return
        end
        sendAim(now)
        return
    end

    local stand = S.stand
    if not stand then
        S.rock = nil
        releaseAim()
        return
    end
    local flat = Vector3.new(hrp.Position.X - stand.X, 0, hrp.Position.Z - stand.Z)
    if flat.Magnitude > CFG.teleportTolerance then
        teleportTo(stand, S.rockPos)
        releaseAim()
        return
    end
    if now - S.teleportedAt < CFG.groundWait or (not flyActive() and not grounded(hum)) then
        releaseAim()
        return
    end
    sendAim(now)
end

local function mobHealth(mob)
    local h = mob and mob:FindFirstChildOfClass("Humanoid")
    return h and h.Health or nil
end

local function noteSwing(mob, hp, now)
    if not CFG.swingDiveAuto or not hp then
        return
    end
    if S.trackedMob ~= mob then
        S.trackedMob = mob
        S.trackedHp = hp
        S.trackedAt = now
        S.trackedSwings = 0
    end
    S.trackedSwings = S.trackedSwings + 1
    if S.trackedSwings >= 5 and now - S.trackedAt >= 2.2 then
        if hp >= S.trackedHp - 0.01 then
            S.forceDive = true
        else
            S.trackedHp = hp
            S.trackedAt = now
            S.trackedSwings = 0
        end
    end
end

function fightStep(mob, hrp, hum)
    local pp = mob.PrimaryPart
    if not pp or not mob.Parent then
        return
    end
    local pos = pp.Position
    local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
    local dist = flat.Magnitude
    local range = weaponStats()
    local now = os.clock()

    if S.trackedMob ~= mob then
        S.trackedMob = mob
        S.trackedHp = mobHealth(mob) or 0
        S.trackedAt = now
        S.trackedSwings = 0
        S.forceDive = false
    end

    -- Swing yang tertunda karena dive: baru dikirim setelah posisi turun.
    if S.pendingSwing then
        local p = S.pendingSwing
        if now >= p.at then
            S.pendingSwing = nil
            if p.mob == mob and mob.Parent then
                S.lastSwing = now
                pcall(function()
                    swingRemote:FireServer(p.facing, nil, p.point)
                end)
                noteSwing(mob, mobHealth(mob), now)
            end
        elseif now > p.at + 0.4 or p.mob ~= mob then
            S.pendingSwing = nil
        end
    end

    local flying = flyActive() and CFG.hover and CFG.hoverFight and S.running and not S.paused
    if dist > range - 1 then
        if not flying and CFG.chase and dist > CFG.chaseStop and now - (S.chaseAt or 0) > 0.2 then
            S.chaseAt = now
            S.chasing = true
            pcall(function()
                hum:MoveTo(pos)
            end)
        end
        return
    end
    if S.chasing then
        S.chasing = false
        if not flying then
            pcall(function()
                hum:MoveTo(hrp.Position)
            end)
        end
    end
    if dist < 0.05 then
        return
    end
    local _, interval = weaponStats()
    if now - S.lastSwing < interval then
        return
    end

    local facing = flat.Unit
    local point = hrp.Position
    local fakePos = Vector3.new(pos.X - facing.X * CFG.swingGap, pos.Y + 1, pos.Z - facing.Z * CFG.swingGap)
    local dive = CFG.swingDive or S.forceDive
    local sendPos = CFG.swingFake and fakePos or point

    pcall(function()
        hrp.CFrame = CFrame.lookAt(point, Vector3.new(pos.X, point.Y, pos.Z))
    end)

    if dive then
        local divePos = Vector3.new(fakePos.X, pos.Y + 2.5, fakePos.Z)
        S.divePoint = divePos
        S.diveUntil = now + CFG.swingDiveTime
        S.lastSwing = now
        S.pendingSwing = {
            mob = mob,
            at = now + CFG.swingDiveDelay,
            facing = facing,
            point = divePos,
        }
        return
    end

    S.lastSwing = now
    pcall(function()
        swingRemote:FireServer(facing, nil, sendPos)
    end)
    noteSwing(mob, mobHealth(mob), now)
end

local function tick()
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then
        releaseAim()
        return
    end
    pumpEquip()
    if chestStep(hrp, hum) then
        return
    end
    if CFG.fight then
        local mob = nearestMob(hrp.Position)
        S.mob = mob
        if mob then
            enterFight()
            fightStep(mob, hrp, hum)
            return
        end
    else
        S.mob = nil
    end
    if CFG.mine then
        enterMine()
        mineStep(hrp, hum)
    else
        releaseAim()
    end
end

local function installGuard()
    if S.oldNamecall then
        return true
    end
    local ok, err = pcall(function()
        S.oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and self == aimRemote and not checkcaller() then
                if S.guardAim and not S.paused then
                    return nil
                end
            end
            return S.oldNamecall(self, ...)
        end)
    end)
    if not ok then
        warn("[DelveFarm] hook __namecall gagal: " .. tostring(err))
        S.oldNamecall = nil
        return false
    end
    return true
end

local function uninstallGuard()
    if not S.oldNamecall then
        return
    end
    local old = S.oldNamecall
    S.oldNamecall = nil
    pcall(function()
        hookmetamethod(game, "__namecall", old)
    end)
end

-- ============================================================
-- API (dipakai UI dan console)
-- ============================================================

local api = {}

local function syncKeybind(value)
    if not S.keybind then
        return
    end
    pcall(function()
        S.keybind:Set(value, true)
    end)
end

local function syncToggle(value)
    if not S.toggle then
        return
    end
    pcall(function()
        S.toggle:Set(value, true)
    end)
end

function api.Start()
    if S.running then
        S.paused = false
        return
    end
    S.running = true
    S.paused = false
    S.mode = nil
    S.rock = nil
    S.stand = nil
    S.rockPos = nil
    S.lastAimSent = 0
    S.warned = false
    S.forceDive = false
    S.trackedMob = nil
    S.trackedSwings = 0
    S.pendingSwing = nil
    S.diveUntil = 0
    S.chestAt = 0
    S.chestFound = nil
    installGuard()
    syncToggle(true)
end

function api.Pause()
    if not S.running then
        return
    end
    S.paused = true
    releaseAim()
    chestAbort()
    syncKeybind(true)
end

function api.Resume()
    if not S.running then
        return
    end
    S.paused = false
    S.mode = nil
    syncKeybind(false)
end

function api.Stop()
    S.running = false
    S.paused = false
    S.mode = nil
    S.rock = nil
    S.stand = nil
    S.rockPos = nil
    S.pendingSwing = nil
    S.forceDive = false
    S.trackedMob = nil
    releaseAim()
    chestAbort()
    uninstallGuard()
    syncKeybind(false)
    syncToggle(false)
end

function api.SetFly(on)
    on = on and true or false
    if on then
        if not flyEnable() then
            S.flyOn = false
            syncFly(false)
            syncFlyKey(false)
            return false
        end
        S.flyOn = true
    else
        S.flyOn = false
        flyDisable()
    end
    syncFly(S.flyOn)
    syncFlyKey(S.flyOn)
    return true
end

function api.ToggleFly()
    return api.SetFly(not S.flyOn)
end

function api.SetLoadoutAuto(on)
    CFG.loadoutAuto = on and true or false
    if not CFG.loadoutAuto then
        S.loadoutWant = nil
        S.loadoutPending = nil
    end
    if S.loadoutToggle then
        pcall(function()
            S.loadoutToggle:Set(CFG.loadoutAuto, true)
        end)
    end
    return CFG.loadoutAuto
end

function api.SetLoadoutSets(combat, mining, idle)
    local combatSet = loadoutSetNumber(combat)
    local miningSet = loadoutSetNumber(mining)
    if combatSet == 0 or miningSet == 0 then
        return false
    end
    CFG.loadoutCombat = combatSet
    CFG.loadoutMining = miningSet
    if idle ~= nil then
        CFG.loadoutIdle = loadoutSetNumber(idle)
    end
    if S.loadoutCombatDropdown then
        pcall(function()
            S.loadoutCombatDropdown:Set(loadoutSetLabel(CFG.loadoutCombat, false), true)
        end)
    end
    if S.loadoutMiningDropdown then
        pcall(function()
            S.loadoutMiningDropdown:Set(loadoutSetLabel(CFG.loadoutMining, false), true)
        end)
    end
    if S.loadoutIdleDropdown then
        pcall(function()
            S.loadoutIdleDropdown:Set(loadoutSetLabel(CFG.loadoutIdle, true), true)
        end)
    end
    S.loadoutWant = nil
    return true
end

function api.SetRelicPriority(list)
    local ids = {}
    for _, v in ipairs(list or {}) do
        if relicIdToLabel[v] then
            ids[#ids + 1] = v
        else
            local id = relicLabelToId[v]
            if id then
                ids[#ids + 1] = id
            end
        end
    end
    setRelicPriority(ids)
    if S.relicDropdown then
        local labels = {}
        for _, id in ipairs(S.relicOrder) do
            local label = relicIdToLabel[id]
            if label then
                labels[#labels + 1] = label
            end
        end
        pcall(function()
            S.relicDropdown:Set(labels, true)
        end)
    end
    saveRelicPrefs()
    refreshRelicStatus()
end

function api.GetRelicPriority()
    local out = {}
    for i, id in ipairs(S.relicOrder) do
        out[i] = { id = id, name = relicName(id) }
    end
    return out
end

function api.RelicChoose(choices)
    local index, reason = chooseRelicIndex(choices)
    return index, reason, index and choices[index] or nil
end

function api.RelicChooseCards(cards, mode)
    local index, reason = chooseCardIndex(cards, { mode = mode })
    return index, reason, index and cards[index] or nil
end

function api.SetPathPick(value)
    if value ~= "manual" and value ~= "safe" and value ~= "cursed" then
        return false
    end
    CFG.pathPick = value
    if S.pathDropdown then
        pcall(function()
            S.pathDropdown:Set(PATH_LABELS[value], true)
        end)
    end
    saveRelicPrefs()
    refreshRelicStatus()
    return true
end

function api.SetTraderMode(value, maxPrice)
    if type(value) ~= "string" or not TRADER_MODES[value] then
        return false
    end
    CFG.traderMode = value
    if maxPrice ~= nil then
        CFG.traderMaxPrice = math.clamp(tonumber(maxPrice) or 0, 0, 5000000)
    end
    if S.traderDropdown then
        pcall(function()
            S.traderDropdown:Set(TRADER_LABELS[value], true)
        end)
    end
    saveRelicPrefs()
    refreshRelicStatus()
    return true
end

function api.Destroy()
    S.uiAlive = false
    api.SetFly(false)
    S.alive = false
    api.Stop()
    if S.connRelic then
        pcall(function()
            S.connRelic:Disconnect()
        end)
        S.connRelic = nil
    end
    if S.connChar then
        pcall(function()
            S.connChar:Disconnect()
        end)
        S.connChar = nil
    end
    if S.connLoadout then
        pcall(function()
            S.connLoadout:Disconnect()
        end)
        S.connLoadout = nil
    end
    if getgenv().DelveFarm == api then
        getgenv().DelveFarm = nil
    end
end

api.Config = CFG
api.State = S

local previous = getgenv().DelveFarm
if type(previous) == "table" and type(previous.Destroy) == "function" then
    pcall(previous.Destroy)
end
getgenv().DelveFarm = api

S.connChar = plr.CharacterAdded:Connect(function(char)
    S.rock = nil
    S.stand = nil
    S.mode = nil
    S.teleportedAt = 0
    S.mobsAt = 0
    S.rocksAt = 0
    S.chasing = false
    S.mob = nil
    S.pendingSwing = nil
    S.forceDive = false
    S.trackedMob = nil
    S.diveUntil = 0
    S.divePoint = nil
    S.chestBusy = false
    S.chestTarget = nil
    S.chestRestore = nil
    S.chestFound = nil
    S.chestAt = 0
    flyDisable()
    if S.flyOn then
        task.defer(function()
            char:WaitForChild("HumanoidRootPart", 15)
            task.wait(0.25)
            if S.flyOn and plr.Character == char then
                if not flyEnable() then
                    S.flyOn = false
                    syncFly(false)
                end
            end
        end)
    end
end)

-- ============================================================
-- Teks status
-- ============================================================

local function statusText()
    local lines = {}
    if not S.running then
        lines[#lines + 1] = "Farm: mati"
    elseif S.paused then
        lines[#lines + 1] = "Farm: dijeda"
    else
        lines[#lines + 1] = "Farm: berjalan"
    end

    local mode = "menunggu"
    if S.mode == "mine" then
        mode = "menambang"
    elseif S.mode == "fight" then
        mode = "lawan mob"
    end
    lines[#lines + 1] = "Mode: " .. mode

    if S.rock and S.rock.Parent then
        lines[#lines + 1] = string.format("Target: %s (x=%d, z=%d)", S.rock.Name, S.rockX, S.rockZ)
    else
        lines[#lines + 1] = "Target: belum ada"
    end

    lines[#lines + 1] = "Batu terdeteksi: " .. tostring(#S.rocks)
    lines[#lines + 1] = "Mob terdeteksi: " .. tostring(#S.mobs)
    lines[#lines + 1] = "Kirim aim: " .. tostring(math.floor(CFG.aimHz)) .. "/detik"
    if CFG.loadoutAuto then
        lines[#lines + 1] = string.format(
            "Equipment set: %s (pedang %s / mining %s)",
            S.loadoutActive and tostring(S.loadoutActive) or "?",
            tostring(CFG.loadoutCombat),
            tostring(CFG.loadoutMining)
        )
    end
    if CFG.directRock then
        lines[#lines + 1] = "Teleport: langsung ke batu"
    else
        lines[#lines + 1] = "Teleport: sel di sebelah batu"
    end
    if not CFG.chest then
        lines[#lines + 1] = "Auto chest: mati"
    elseif S.chestTarget and S.chestTarget.Parent then
        local rarity = tostring(S.chestTarget:GetAttribute("ChestRarity"))
        local state = S.chestTarget:GetAttribute("ChestState")
        if state == "locked" then
            lines[#lines + 1] = "Chest: bersihkan wave (" .. rarity .. ")"
        elseif state == "unlocked" then
            lines[#lines + 1] = "Chest: buka (" .. rarity .. ")"
        else
            lines[#lines + 1] = "Chest: ambil hadiah (" .. rarity .. ")"
        end
    else
        lines[#lines + 1] = "Chest diambil: " .. tostring(S.chestTaken)
    end

    if S.flyOn then
        if S.flyTarget then
            lines[#lines + 1] = string.format("Fly: hover %.1f stud di atas target", S.flyHeightNow or CFG.hoverHeight)
        else
            lines[#lines + 1] = "Fly: aktif (manual)"
        end
    else
        lines[#lines + 1] = "Fly: mati"
    end

    if CFG.swingDive or S.forceDive then
        lines[#lines + 1] = "Swing: dive" .. (S.forceDive and " (auto)" or " (paksa)")
    elseif CFG.swingFake then
        lines[#lines + 1] = "Swing: titik dekat mob"
    else
        lines[#lines + 1] = "Swing: posisi badan"
    end

    local ch = plr.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp and S.rockPos then
        local d = (Vector3.new(hrp.Position.X - S.rockPos.X, 0, hrp.Position.Z - S.rockPos.Z)).Magnitude
        lines[#lines + 1] = string.format("Jarak ke target: %.1f stud", d)
    end

    return table.concat(lines, "\n")
end

-- ============================================================
-- UI
-- ============================================================

local Window = BPUI:CreateWindow({
    Title = "Delve Hub",
    Subtitle = "Auto Rock Farm",
    Icon = "hammer",
    Theme = "Void",
    ToggleKey = Enum.KeyCode.RightShift,
    CloseBehavior = "Hide",
    OnDestroy = api.Destroy,
})

local FarmTab = Window:CreateTab({ Name = "Farm", Icon = "activity" })
local MineTab = Window:CreateTab({ Name = "Mining", Icon = "gem" })
local CombatTab = Window:CreateTab({ Name = "Combat", Icon = "sword" })
local FlyTab = Window:CreateTab({ Name = "Terbang", Icon = "wind" })
local RelicTab = Window:CreateTab({ Name = "Relic", Icon = "sparkles" })
local InfoTab = Window:CreateTab({ Name = "Info", Icon = "info" })

-- ------------------------------------------------------------
-- Tab Farm
-- ------------------------------------------------------------

local MainSection = FarmTab:CreateSection("Auto Farm")

local farmToggle

farmToggle = MainSection:AddToggle({
    Name = "Auto Farm",
    Description = "Cari batu, teleport, aim, dan lawan mob secara otomatis.",
    Flag = "DelveFarmOn",
    Default = false,
    Callback = function(on)
        if on then
            api.Start()
            BPUI:Notify({ Title = "Delve Hub", Content = "Auto farm dimulai.", Type = "Success", Duration = 3 })
        else
            api.Stop()
            BPUI:Notify({ Title = "Delve Hub", Content = "Auto farm dihentikan.", Type = "Info", Duration = 3 })
        end
    end,
})

S.toggle = farmToggle

MainSection:AddToggle({
    Name = "Auto Mining",
    Description = "Matikan kalau hanya ingin mode lawan mob.",
    Flag = "DelveFarmMine",
    Default = true,
    Callback = function(on)
        CFG.mine = on
        if not on and S.mode == "mine" then
            releaseAim()
            S.rock = nil
            S.mode = nil
        end
    end,
})

MainSection:AddToggle({
    Name = "Auto Lawan Mob",
    Description = "Pindah ke weapon dan swing otomatis saat ada mob dalam radius.",
    Flag = "DelveFarmFight",
    Default = true,
    Callback = function(on)
        CFG.fight = on
        if not on and S.mode == "fight" then
            S.mode = nil
            S.want = "pickaxe"
        end
    end,
})

MainSection:AddToggle({
    Name = "Auto Equip",
    Description = "Kirim PickaxeOut / WeaponDrawn sesuai mode yang sedang jalan.",
    Flag = "DelveFarmEquip",
    Default = true,
    Callback = function(on)
        CFG.autoEquip = on
    end,
})

S.keybind = MainSection:AddKeybind({
    Name = "Tombol Jeda",
    Description = "Jeda dan lanjutkan farm. Berbeda dari RightShift milik BPUI.",
    Flag = "DelveFarmPauseKey",
    Default = Enum.KeyCode.F2,
    Mode = "Toggle",
    Callback = function(on)
        if not S.running then
            syncKeybind(false)
            return
        end
        if on then
            api.Pause()
        else
            api.Resume()
        end
    end,
})

local EquipmentSection = FarmTab:CreateSection("Equipment Set")

S.loadoutToggle = EquipmentSection:AddToggle({
    Name = "Auto Ganti Equipment Set",
    Description = "Pindah loadout otomatis mengikuti pedang dan pickaxe.",
    Flag = "DelveFarmLoadout",
    Default = CFG.loadoutAuto,
    Callback = function(on)
        CFG.loadoutAuto = on and true or false
        if not CFG.loadoutAuto then
            S.loadoutWant = nil
            S.loadoutPending = nil
        end
    end,
})

S.loadoutCombatDropdown = EquipmentSection:AddDropdown({
    Name = "Set Saat Pakai Pedang",
    Description = "Loadout yang dipakai saat pedang terhunus.",
    Options = { "Set 1", "Set 2", "Set 3" },
    Default = loadoutSetLabel(CFG.loadoutCombat, false),
    Flag = "DelveLoadoutCombat",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        local number_ = loadoutSetFromLabel(label)
        if number_ > 0 then
            CFG.loadoutCombat = number_
            S.loadoutWant = nil
        end
    end,
})

S.loadoutMiningDropdown = EquipmentSection:AddDropdown({
    Name = "Set Saat Mining",
    Description = "Loadout yang dipakai saat pickaxe keluar.",
    Options = { "Set 1", "Set 2", "Set 3" },
    Default = loadoutSetLabel(CFG.loadoutMining, false),
    Flag = "DelveLoadoutMining",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        local number_ = loadoutSetFromLabel(label)
        if number_ > 0 then
            CFG.loadoutMining = number_
            S.loadoutWant = nil
        end
    end,
})

S.loadoutIdleDropdown = EquipmentSection:AddDropdown({
    Name = "Set Saat Diam",
    Description = "Dipakai saat tidak memegang pedang atau pickaxe. Pilih Mati kalau tidak ingin diganti.",
    Options = { "Mati", "Set 1", "Set 2", "Set 3" },
    Default = loadoutSetLabel(CFG.loadoutIdle, true),
    Flag = "DelveLoadoutIdle",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        CFG.loadoutIdle = loadoutSetFromLabel(label)
        S.loadoutWant = nil
    end,
})

EquipmentSection:AddParagraph({
    Title = "Cara Pakai",
    Content = "Pilih set untuk pedang dan mining di atas. Saat pedang terhunus, "
        .. "karakter otomatis pindah ke set pedang. Saat pickaxe keluar, pindah ke set mining. "
        .. "Server hanya mengizinkan satu swap setiap 5 detik, jadi perubahan bisa tertunda.",
})

local ChestSection = FarmTab:CreateSection("Chest")

ChestSection:AddToggle({
    Name = "Auto Ambil Chest",
    Description = "Saat Auto Farm jalan: chest yang muncul langsung didatangi lewat teleport. Kalau masih locked, wave mob dibereskan dulu, lalu chest dibuka dan hadiahnya diambil.",
    Flag = "DelveFarmChest",
    Default = true,
    Callback = function(on)
        CFG.chest = on
        if not on then
            chestAbort()
        end
    end,
})

ChestSection:AddSlider({
    Name = "Radius Chest",
    Description = "Hanya chest sedekat ini dari badan yang diambil, supaya chest pemain lain tidak terambil.",
    Min = 40,
    Max = 400,
    Default = 200,
    Increment = 10,
    Suffix = " stud",
    Flag = "DelveChestRadius",
    Callback = function(v)
        CFG.chestRadius = v
    end,
})

ChestSection:AddSlider({
    Name = "Batas Bersihkan Wave",
    Description = "Chest locked dilepas kalau wave tidak selesai dalam waktu ini, lalu Auto Farm lanjut menambang.",
    Min = 10,
    Max = 120,
    Default = 40,
    Increment = 5,
    Suffix = " detik",
    Flag = "DelveChestWaveTimeout",
    Callback = function(v)
        CFG.chestLockTimeout = v
    end,
})

ChestSection:AddParagraph({
    Title = "Cara Kerja",
    Content = "Chest dengan ChestRarity dan Owner kosong atau milik sendiri langsung "
        .. "didatangi, baik state-nya locked maupun unlocked. Saat locked, hub "
        .. "menyerang mob wave di sekitar chest sampai state berubah unlocked. "
        .. "Chest unlocked disentuh lewat teleport supaya terbuka, lalu karakter "
        .. "diam di titik chest sampai chest hilang dan mining lanjut dari situ.",
})

local ActionSection = FarmTab:CreateSection("Aksi")

ActionSection:AddButton({
    Name = "Jeda / Lanjut",
    Style = "Default",
    Callback = function()
        if not S.running then
            BPUI:Notify({ Title = "Delve Hub", Content = "Auto farm sedang mati.", Type = "Warning", Duration = 3 })
            return
        end
        if S.paused then
            api.Resume()
        else
            api.Pause()
        end
    end,
})

ActionSection:AddButton({
    Name = "Lepas Aim Sekarang",
    Description = "Kirim Aim(0, 0, false) tanpa menghentikan farm.",
    Callback = function()
        releaseAim()
    end,
})

ActionSection:AddButton({
    Name = "Hentikan Auto Farm",
    Style = "Danger",
    Callback = function()
        if farmToggle then
            farmToggle:Set(false)
        else
            api.Stop()
        end
    end,
})

local StatusSection = FarmTab:CreateSection("Status")

local statusCard = StatusSection:AddParagraph({
    Title = "Status",
    Content = statusText(),
})

-- ------------------------------------------------------------
-- Tab Mining
-- ------------------------------------------------------------

local TargetSection = MineTab:CreateSection("Target Batu")

TargetSection:AddButton({
    Name = "Teleport ke Batu Terdekat",
    Style = "Accent",
    Description = "Sekali jalan ke batu terdekat, tanpa menyalakan Auto Farm. Mengikuti toggle Teleport Langsung.",
    Callback = function()
        local ch = plr.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not hrp then
            BPUI:Notify({ Title = "Teleport", Content = "Karakter belum siap.", Type = "Warning", Duration = 3 })
            return
        end
        if pickRock(hrp) and S.stand then
            teleportTo(S.stand, S.rockPos)
            BPUI:Notify({ Title = "Teleport", Content = "Pindah ke batu " .. S.rock.Name .. ".", Type = "Success", Duration = 3 })
        else
            BPUI:Notify({ Title = "Teleport", Content = "Tidak ada batu yang bisa dijangkau.", Type = "Warning", Duration = 3 })
        end
    end,
})

TargetSection:AddButton({
    Name = "Reset Blacklist",
    Description = "Batu yang sempat dilewati boleh dipilih lagi.",
    Callback = function()
        S.blacklist = {}
        S.rock = nil
        BPUI:Notify({ Title = "Mining", Content = "Blacklist dibersihkan.", Type = "Info", Duration = 3 })
    end,
})

local MiningSection = MineTab:CreateSection("Penempatan")

MiningSection:AddToggle({
    Name = "Teleport Langsung ke Batu",
    Description = "Badan dipindah tepat ke sel batu, bukan ke sel di sebelahnya. Saat hover aktif, badan langsung dipindah ke titik hover, bukan terbang mendekat.",
    Flag = "DelveDirectRock",
    Default = true,
    Callback = function(on)
        CFG.directRock = on
        S.rock = nil
        S.stand = nil
        S.rockPos = nil
        releaseAim()
    end,
})

MiningSection:AddSlider({
    Name = "Jarak Berdiri dari Batu",
    Description = "Dipakai kalau Teleport Langsung dimatikan: jarak dari titik tengah batu.",
    Min = 2,
    Max = 12,
    Default = 6,
    Increment = 0.5,
    Suffix = " stud",
    Flag = "DelveStandOffset",
    Callback = function(v)
        CFG.standOffset = v
    end,
})

MiningSection:AddSlider({
    Name = "Toleransi Teleport",
    Description = "Kalau sudah sedekat ini, teleport dilewati.",
    Min = 0.5,
    Max = 8,
    Default = 2.5,
    Increment = 0.5,
    Suffix = " stud",
    Flag = "DelveTeleportTolerance",
    Callback = function(v)
        CFG.teleportTolerance = v
    end,
})

MiningSection:AddSlider({
    Name = "Jeda Setelah Mendarat",
    Min = 0,
    Max = 1.5,
    Default = 0.35,
    Increment = 0.05,
    Suffix = "s",
    Flag = "DelveGroundWait",
    Callback = function(v)
        CFG.groundWait = v
    end,
})

local AimSection = MineTab:CreateSection("Aim")

AimSection:AddSlider({
    Name = "Kirim Aim per Detik",
    Description = "Game asli memakai 20. Server menganggap aim basi setelah 0.5 detik.",
    Min = 5,
    Max = 30,
    Default = 20,
    Increment = 1,
    Suffix = "/s",
    Flag = "DelveAimHz",
    Callback = function(v)
        CFG.aimHz = v
    end,
})

AimSection:AddSlider({
    Name = "Batas Waktu per Batu",
    Description = "Batu yang tidak pecah dalam waktu ini dilewati sementara.",
    Min = 5,
    Max = 60,
    Default = 20,
    Increment = 1,
    Suffix = "s",
    Flag = "DelveRockTimeout",
    Callback = function(v)
        CFG.rockTimeout = v
    end,
})

AimSection:AddSlider({
    Name = "Lama Blacklist Batu",
    Min = 5,
    Max = 120,
    Default = 20,
    Increment = 5,
    Suffix = "s",
    Flag = "DelveRockBlacklist",
    Callback = function(v)
        CFG.rockBlacklist = v
    end,
})

AimSection:AddSlider({
    Name = "Frekuensi Scan Batu",
    Min = 0.1,
    Max = 2,
    Default = 0.5,
    Increment = 0.1,
    Suffix = "s",
    Flag = "DelveRockScan",
    Callback = function(v)
        CFG.rockScanInterval = v
    end,
})

-- ------------------------------------------------------------
-- Tab Combat
-- ------------------------------------------------------------

local MobSection = CombatTab:CreateSection("Deteksi Mob")

MobSection:AddToggle({
    Name = "Kejar Mob",
    Description = "Pakai Humanoid MoveTo kalau mob masih di luar jangkauan senjata.",
    Flag = "DelveFarmChase",
    Default = true,
    Callback = function(on)
        CFG.chase = on
    end,
})

MobSection:AddSlider({
    Name = "Radius Deteksi",
    Description = "Mulai pakai weapon kalau mob sedekat ini.",
    Min = 5,
    Max = 80,
    Default = 30,
    Increment = 1,
    Suffix = " stud",
    Flag = "DelveMobDetect",
    Callback = function(v)
        CFG.mobDetect = v
    end,
})

MobSection:AddSlider({
    Name = "Radius Lepas Target",
    Description = "Balik ke pickaxe setelah mob lebih jauh dari jarak ini.",
    Min = 10,
    Max = 120,
    Default = 42,
    Increment = 1,
    Suffix = " stud",
    Flag = "DelveMobRelease",
    Callback = function(v)
        CFG.mobRelease = v
    end,
})

MobSection:AddSlider({
    Name = "Jarak Berhenti Kejar",
    Description = "Berhenti mendekat kalau jarak sudah di bawah nilai ini.",
    Min = 0,
    Max = 20,
    Default = 7,
    Increment = 1,
    Suffix = " stud",
    Flag = "DelveChaseStop",
    Callback = function(v)
        CFG.chaseStop = v
    end,
})

MobSection:AddSlider({
    Name = "Jeda Scan Mob",
    Min = 0.1,
    Max = 1,
    Default = 0.25,
    Increment = 0.05,
    Suffix = "s",
    Flag = "DelveMobScan",
    Callback = function(v)
        CFG.mobScanInterval = v
    end,
})

-- ------------------------------------------------------------
-- Tab Terbang
-- ------------------------------------------------------------

local FlyMain = FlyTab:CreateSection("Fly Manual")

S.flyToggle = FlyMain:AddToggle({
    Name = "Aktifkan Fly",
    Description = "WASD bergerak, Space naik, LeftCtrl turun. Saat Auto Farm jalan, hover otomatis mengambil alih.",
    Flag = "DelveFlyOn",
    Default = false,
    Callback = function(on)
        api.SetFly(on)
    end,
})

S.flyKeybind = FlyMain:AddKeybind({
    Name = "Tombol Fly",
    Description = "Toggle cepat tanpa membuka window. Ganti kalau bentrok dengan tombol game.",
    Flag = "DelveFlyKey",
    Default = Enum.KeyCode.F,
    Mode = "Toggle",
    Callback = function(on)
        api.SetFly(on)
    end,
})

FlyMain:AddSlider({
    Name = "Kecepatan Horizontal",
    Min = 10,
    Max = 150,
    Default = 60,
    Increment = 5,
    Suffix = " stud/s",
    Flag = "DelveFlySpeed",
    Callback = function(v)
        CFG.flySpeed = v
    end,
})

FlyMain:AddSlider({
    Name = "Kecepatan Naik/Turun",
    Min = 10,
    Max = 100,
    Default = 40,
    Increment = 5,
    Suffix = " stud/s",
    Flag = "DelveFlyVert",
    Callback = function(v)
        CFG.flyVert = v
    end,
})

local HoverSection = FlyTab:CreateSection("Hover Otomatis")

HoverSection:AddToggle({
    Name = "Hover saat Auto Farm",
    Description = "Master switch. Kalau mati, Fly hanya bekerja manual.",
    Flag = "DelveHoverOn",
    Default = true,
    Callback = function(on)
        CFG.hover = on
    end,
})

HoverSection:AddToggle({
    Name = "Hover saat Menambang",
    Description = "Melayang di atas batu selama mengirim Aim. Matikan kalau mining tidak jalan di ketinggian.",
    Flag = "DelveHoverMine",
    Default = true,
    Callback = function(on)
        CFG.hoverMine = on
    end,
})

HoverSection:AddToggle({
    Name = "Hover saat Menyerang",
    Description = "Melayang di atas mob supaya serangan melee-nya tidak sampai kalau jarak vertikal cukup.",
    Flag = "DelveHoverFight",
    Default = true,
    Callback = function(on)
        CFG.hoverFight = on
    end,
})

HoverSection:AddSlider({
    Name = "Ketinggian Hover",
    Description = "Tinggi badan di atas target. Kalau Swing meleset, turunkan mendekati jangkauan senjata.",
    Min = 4,
    Max = 30,
    Default = 10,
    Increment = 1,
    Suffix = " stud",
    Flag = "DelveHoverHeight",
    Callback = function(v)
        CFG.hoverHeight = v
    end,
})

HoverSection:AddSlider({
    Name = "Geser Horizontal (Combat)",
    Description = "Supaya badan tidak tepat di atas mob dan arah Swing tetap valid.",
    Min = 0,
    Max = 6,
    Default = 4,
    Increment = 1,
    Suffix = " stud",
    Flag = "DelveHoverOffset",
    Callback = function(v)
        CFG.hoverOffset = v
    end,
})

HoverSection:AddToggle({
    Name = "Hover di Atas Batu",
    Description = "Nyala = tepat di atas batu. Mati = di atas sel tempat berdiri, lebih aman untuk Aim.",
    Flag = "DelveHoverRock",
    Default = true,
    Callback = function(on)
        CFG.hoverRock = on
    end,
})

HoverSection:AddParagraph({
    Title = "Catatan",
    Content = "Saat Teleport Langsung aktif, titik hover dicapai seketika, bukan terbang mendekat. "
        .. "Hover hanya bergerak saat Auto Farm menyala. Kalau menyentuh WASD, kontrol manual menang "
        .. "sampai tombol dilepas.\n\n"
        .. "Mob punya jangkauan serangan sendiri. Kalau masih kena, naikkan ketinggian. "
        .. "Kalau Swing tidak mengenai mob, turunkan sampai masih di dalam jangkauan senjata.",
})

local SwingSection = FlyTab:CreateSection("Swing dari Ketinggian")

SwingSection:AddToggle({
    Name = "Posisi Pukulan di Dekat Mob",
    Description = "Swing mengirim titik di depan mob, bukan posisi badan yang tinggi. Ini yang membuat pedang tetap kena tanpa menurunkan hover.",
    Flag = "DelveSwingFake",
    Default = true,
    Callback = function(on)
        CFG.swingFake = on
    end,
})

SwingSection:AddSlider({
    Name = "Jarak Titik Pukulan",
    Description = "Titik pukulan digeser dari tengah mob ke arah player.",
    Min = 0.5,
    Max = 4,
    Default = 1.5,
    Increment = 0.5,
    Suffix = " stud",
    Flag = "DelveSwingGap",
    Callback = function(v)
        CFG.swingGap = v
    end,
})

SwingSection:AddToggle({
    Name = "Dive Otomatis",
    Description = "Kalau 5 swing berturut-turut tidak mengurangi HP mob, karakter turun sebentar ke titik pukulan lalu naik lagi.",
    Flag = "DelveSwingDiveAuto",
    Default = true,
    Callback = function(on)
        CFG.swingDiveAuto = on
        if not on then
            S.forceDive = false
        end
    end,
})

SwingSection:AddToggle({
    Name = "Paksa Dive Setiap Swing",
    Description = "Pakai ini kalau posisi pukulan tetap tidak kena. Lebih lambat, tapi hampir pasti masuk.",
    Flag = "DelveSwingDive",
    Default = false,
    Callback = function(on)
        CFG.swingDive = on
    end,
})

SwingSection:AddSlider({
    Name = "Lama Dive",
    Description = "Berapa lama badan berada di titik pukulan sebelum naik lagi.",
    Min = 0.1,
    Max = 0.6,
    Default = 0.28,
    Increment = 0.02,
    Suffix = "s",
    Flag = "DelveSwingDiveTime",
    Callback = function(v)
        CFG.swingDiveTime = v
    end,
})

SwingSection:AddParagraph({
    Title = "Urutan Kerja",
    Content = "1. Normal: Swing dikirim dengan titik di dekat mob, badan tetap tinggi.\n"
        .. "2. Kalau HP mob tidak turun setelah 5 swing, Dive Otomatis aktif untuk mob itu.\n"
        .. "3. Kalau masih mau paksa, nyalakan Paksa Dive Setiap Swing.\n\n"
        .. "Tinggi hover tidak perlu diturunkan. Dive hanya terjadi sebentar saat menyerang.",
})

local FlyControl = FlyTab:CreateSection("Kontrol")

FlyControl:AddParagraph({
    Title = "Tombol",
    Content = "W / A / S / D = bergerak mengikuti arah kamera\n"
        .. "Space = naik\n"
        .. "LeftCtrl = turun\n"
        .. "Tombol Fly (default F) = nyala / mati",
})

FlyControl:AddButton({
    Name = "Matikan Fly",
    Description = "Turun dari posisi hover dan kembali ke fisika normal.",
    Style = "Danger",
    Callback = function()
        api.SetFly(false)
        BPUI:Notify({ Title = "Terbang", Content = "Fly dimatikan.", Type = "Info", Duration = 3 })
    end,
})

-- ------------------------------------------------------------
-- Tab Relic
-- ------------------------------------------------------------

local RelicAutoSection = RelicTab:CreateSection("Auto Pilih")

RelicAutoSection:AddToggle({
    Name = "Auto Pilih Relic",
    Description = "Saat draft relic muncul, pilihan dikirim otomatis sesuai prioritas.",
    Flag = "DelveRelicAuto",
    Default = CFG.autoRelic,
    Callback = function(on)
        CFG.autoRelic = on
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

RelicAutoSection:AddToggle({
    Name = "Fallback Rarity Tertinggi",
    Description = "Kalau tidak ada relic prioritas di draft, ambil rarity paling tinggi.",
    Flag = "DelveRelicFallback",
    Default = CFG.relicFallback,
    Callback = function(on)
        CFG.relicFallback = on
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

RelicAutoSection:AddSlider({
    Name = "Jeda Sebelum Memilih",
    Description = "Beri waktu sebentar supaya kartu sempat terlihat sebelum dipilih.",
    Min = 0,
    Max = 2,
    Default = CFG.relicDelay,
    Increment = 0.05,
    Suffix = "s",
    Flag = "DelveRelicDelay",
    Callback = function(v)
        CFG.relicDelay = v
        saveRelicPrefs()
    end,
})

RelicAutoSection:AddParagraph({
    Title = "Aturan Pilih",
    Content = "1. Relic yang ada di daftar prioritas selalu menang.\n"
        .. "2. Kalau beberapa prioritas muncul, diambil rarity tertinggi; kalau sama, urutan pilih kamu yang menang.\n"
        .. "3. Kalau tidak ada prioritas, fallback mengambil rarity tertinggi di draft.\n"
        .. "4. Draft berbentuk kartu (shrine relic atau blessing) ikut dipilih otomatis.\n"
        .. "5. Pilihan path dan pembelian trader diatur di bagian 'Path & Trader' (default manual).",
})

local RelicPickSection = RelicTab:CreateSection("Prioritas Relic")

if #relicOptions > 0 then
    S.relicDropdown = RelicPickSection:AddDropdown({
        Name = "Relic Prioritas",
        Description = "Pilih satu atau beberapa relic. Ada kotak filter di dalam daftar untuk mencari cepat.",
        Options = relicOptions,
        Multi = true,
        Searchable = true,
        Flag = "DelveRelicPriority",
        Callback = function(values)
            local ids = {}
            for _, label in ipairs(values or {}) do
                local id = relicLabelToId[label]
                if id then
                    ids[#ids + 1] = id
                end
            end
            setRelicPriority(ids)
            saveRelicPrefs()
            refreshRelicStatus()
        end,
    })

    if #S.relicOrder > 0 then
        local labels = {}
        for _, id in ipairs(S.relicOrder) do
            local label = relicIdToLabel[id]
            if label then
                labels[#labels + 1] = label
            end
        end
        S.relicDropdown:Set(labels, true)
    end
else
    RelicPickSection:AddParagraph({
        Title = "Data Relic",
        Content = "Strata.Defs.Relics tidak bisa dibaca, fitur prioritas tidak tersedia.",
    })
end

RelicPickSection:AddButton({
    Name = "Kosongkan Prioritas",
    Style = "Danger",
    Callback = function()
        if S.relicDropdown then
            S.relicDropdown:Set({}, true)
        end
        setRelicPriority({})
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

local RelicOfferSection = RelicTab:CreateSection("Path & Trader")

local function labelKey(labels, label)
    for key, text in pairs(labels) do
        if text == label then
            return key
        end
    end
    return nil
end

S.pathDropdown = RelicOfferSection:AddDropdown({
    Name = "Pilihan Path",
    Description = "Saat gate bercabang, hub memilih SAFE PATH atau CURSED PATH sesuai ini.",
    Options = { "Manual", "Safe Path", "Cursed Path" },
    Default = PATH_LABELS[CFG.pathPick] or "Manual",
    Flag = "DelvePathPick",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        local key = labelKey(PATH_LABELS, label)
        if key then
            CFG.pathPick = key
            saveRelicPrefs()
            refreshRelicStatus()
        end
    end,
})

S.traderDropdown = RelicOfferSection:AddDropdown({
    Name = "Trader",
    Description = "Atur item trader mana yang dibeli otomatis. Manual = tidak membeli apa pun.",
    Options = { "Manual", "Relic prioritas", "Relic apa saja", "Termurah" },
    Default = TRADER_LABELS[CFG.traderMode] or "Manual",
    Flag = "DelveTraderMode",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        local key = labelKey(TRADER_LABELS, label)
        if key then
            CFG.traderMode = key
            saveRelicPrefs()
            refreshRelicStatus()
        end
    end,
})

RelicOfferSection:AddSlider({
    Name = "Batas Harga Trader",
    Description = "0 = tanpa batas. Item yang lebih mahal dari nilai ini tidak dibeli.",
    Min = 0,
    Max = 5000000,
    Default = CFG.traderMaxPrice,
    Increment = 25000,
    Flag = "DelveTraderMax",
    Callback = function(v)
        CFG.traderMaxPrice = v
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

RelicOfferSection:AddParagraph({
    Title = "Catatan",
    Content = "Path: default Manual. Kalau dipilih, hub langsung menekan kartu yang cocok.\n"
        .. "Trader 'Relic prioritas' hanya membeli relic yang ada di daftar prioritas. "
        .. "'Relic apa saja' membeli kartu relic dengan rarity tertinggi. "
        .. "'Termurah' membeli item termurah yang ada.\n"
        .. "Item dengan afford = false tidak pernah dibeli, dan semua pembelian tetap "
        .. "dihitung server.",
})

local RelicStatusSection = RelicTab:CreateSection("Status")

S.relicCard = RelicStatusSection:AddParagraph({
    Title = "Status Relic",
    Content = relicStatusText(),
})

-- ------------------------------------------------------------
-- Tab Info
-- ------------------------------------------------------------

local HelpSection = InfoTab:CreateSection("Cara Pakai")

HelpSection:AddParagraph({
    Title = "Langkah",
    Content = "1. Masuk ke sesi Delve sampai dunia dan StrataPlate muncul.\n"
        .. "2. Buka tab Farm, nyalakan Auto Farm.\n"
        .. "3. Atur jarak berdiri dan radius mob kalau posisi teleport terasa aneh.\n"
        .. "4. Buka tab Terbang, nyalakan Fly. Atur ketinggian hover sesuai kebutuhan.\n"
        .. "5. RightShift menyembunyikan window. Tombol jeda memakai keybind sendiri (default F2).",
})

HelpSection:AddParagraph({
    Title = "Catatan Fly",
    Content = "Fly memakai BodyVelocity + BodyGyro di HumanoidRootPart, jadi karakter tetap bisa "
        .. "menambang dan Swing lewat remote. Saat Auto Farm menyala dan toggle hover aktif, "
        .. "badan otomatis ditarik ke titik di atas batu atau mob. WASD/ Space / LeftCtrl "
        .. "menimpa hover selama tombol ditahan.\n\n"
        .. "Kalau mob masih bisa menyerang, naikkan Ketinggian Hover. Kalau Swing meleset, "
        .. "pakai bagian 'Swing dari Ketinggian' di tab Terbang: posisi pukulan dikirim dekat "
        .. "mob, dan Dive Otomatis dipakai sebagai fallback. Kalau mining berhenti bekerja "
        .. "saat melayang, matikan Hover saat Menambang.",
})

HelpSection:AddParagraph({
    Title = "Auto Ambil Chest",
    Content = "Aktif secara default saat Auto Farm jalan dan selalu didahulukan di atas "
        .. "menambang. Chest yang muncul langsung didatangi lewat teleport. "
        .. "Kalau chest masih locked, hub menyerang mob wave di sekitarnya sampai "
        .. "state berubah unlocked, lalu menyentuh chest supaya terbuka. "
        .. "Setelah hadiah diambil, karakter diam di titik chest sampai chest "
        .. "hilang, lalu mining lanjut dari sana. "
        .. "Kalau wave terlalu lama, kurangi Radius Chest atau naikkan "
        .. "Batas Bersihkan Wave di tab Farm.",
})

HelpSection:AddParagraph({
    Title = "Catatan Protokol",
    Content = "Aim dikirim terus ke StrataNet.Aim karena server menganggap aim basi setelah 0.5 detik. "
        .. "Saat mode lawan mob, Aim dilepas dulu lalu WeaponDrawn dan Swing dikirim. "
        .. "Semua pengiriman remote dibungkus pcall.",
})

local ConsoleSection = InfoTab:CreateSection("Console")

ConsoleSection:AddButton({
    Name = "Mulai dari Console",
    Description = "Sama dengan getgenv().DelveFarm.Start().",
    Callback = function()
        api.Start()
        BPUI:Notify({ Title = "Delve Hub", Content = "Auto farm dimulai.", Type = "Success", Duration = 3 })
    end,
})

ConsoleSection:AddButton({
    Name = "Hentikan dari Console",
    Description = "Sama dengan getgenv().DelveFarm.Stop().",
    Callback = function()
        api.Stop()
        BPUI:Notify({ Title = "Delve Hub", Content = "Auto farm dihentikan.", Type = "Info", Duration = 3 })
    end,
})

-- ============================================================
-- Loop
-- ============================================================

S.thread = task.spawn(function()
    while S.alive do
        if S.running and not S.paused then
            local ok, err = pcall(tick)
            if not ok and not S.warned then
                S.warned = true
                warn("[DelveFarm] " .. tostring(err))
            end
        end
        task.wait(1 / math.max(CFG.aimHz, 1))
    end
end)

-- Equipment set tetap jalan walau Auto Farm mati, supaya ikut pedang/pickaxe manual.
S.loadoutThread = task.spawn(function()
    while S.alive do
        if CFG.loadoutAuto then
            local ok, err = pcall(pumpLoadout, os.clock())
            if not ok and not S.loadoutWarned then
                S.loadoutWarned = true
                warn("[DelveFarm] equipment set: " .. tostring(err))
            end
        end
        task.wait(0.1)
    end
end)

RunService.RenderStepped:Connect(function(dt)
    if not S.alive or not S.flyOn then
        return
    end
    local ok, err = pcall(flyStep, dt)
    if not ok and not S.warnedFly then
        S.warnedFly = true
        warn("[DelveFarm] fly: " .. tostring(err))
    end
end)

task.spawn(function()
    while S.uiAlive do
        pcall(function()
            statusCard:SetContent(statusText())
        end)
        pcall(function()
            if S.relicCard then
                S.relicCard:SetContent(relicStatusText())
            end
        end)
        task.wait(0.5)
    end
end)

print("[DelveFarm] siap. Nyalakan Auto Farm di tab Farm. RightShift = sembunyikan window.")
