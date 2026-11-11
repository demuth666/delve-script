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
       Ketinggian hover diatur di tab Farm > Fly.
    7. Ambil chest otomatis dengan prioritas tertinggi: begitu chest muncul,
       karakter langsung teleport ke chest itu. Kalau state-nya locked, mob
       wave di sekitar chest diserang dulu sampai chest jadi unlocked, lalu
       chest disentuh supaya terbuka dan hadiahnya diambil. Begitu hadiah
       tercatat, karakter langsung lanjut mining tanpa menunggu chest hilang.
    8. Auto pilih relic: relic yang dipilih di tab Relic diutamakan. Kalau
       tidak ada di draft, fallback ke rarity tertinggi. Pilihan dikirim
       lewat StrataNet.PickRelic setelah draft muncul. Draft berbentuk kartu
       (shrine relic/blessing) ikut dipilih. Pilihan path dan pembelian
       trader diatur di bagian "Path & Trader" (default manual).
    9. Auto ganti equipment set (loadout): pilih set pedang, set mining, dan
       set diam lewat dropdown di tab Farm > Equipment Set. Saat pedang
       terhunus karakter pindah ke set pedang, saat pickaxe keluar pindah ke
       set mining.
   10. Auto ascend: saat Heart di room 50 membuka cabang Rift, game mengirim
       draft berisi kartu The Hollow dan The Heavens. Hub memilih salah satu
       sesuai dropdown di tab Relic > Auto Ascend, jadi pemain tidak perlu
       menekan kartu manual.

    11. Keluar run: tab Run punya tombol Rerun dan Ke Hub. Kalau layar hasil
        sedang terbuka, hub memakai SummaryController:Hide (jalur yang sama
        dengan tombol Again/Hub). Di tengah run, hub mengirim LeaveRun langsung.
        Rerun lalu mengirim StartSession(worldId) setelah server benar-benar
        keluar dari sesi lama. Mode otomatis bisa memilih salah satu saat layar
        hasil muncul. Auto leave kedalaman memantau angka DEPTH di HUD dan
        mengirim LeaveRun begitu target meter yang dipilih tercapai, tanpa
        menunggu run selesai.
    12. Fokus mining (Delve): mob di room tambang biasa tidak wajib dibunuh.
        Saat toggle aktif, hub hanya menyerang mob ketika room sekarang adalah
        gate/boss yang harus dibersihkan untuk membuka tempat berikutnya. Wave
        chest locked tetap dibersihkan oleh fitur Auto Ambil Chest.
    13. Prioritas batu belakang (Delve): kalau ada batu dengan sel kedalaman
        (sumbu X grid) lebih kecil dari sel pemain, batu itu ditambang dulu
        sebelum batu yang lebih dekat di depan. Toggle ada di tab Farm >
        Auto Farm.
    14. Anti AFK: merespons sinyal Idled Roblox dengan satu klik virtual supaya
        sesi tidak ditendang setelah 20 menit tanpa input. Tidak ada klik
        berkala; toggle-nya ada di tab Farm > Anti AFK.
    15. Mode tengah (Delve): karakter berdiri di lane tengah shaft, bukan di
        sel batu, lalu Aim diarahkan ke batu paling dekat titik tengah baris.
        Batu di kiri-kanan ikut kena radius pickaxe, jadi tidak perlu teleport
        ke tiap sel. Cocok kalau Mining Range (Radius) pickaxe sudah lebar.
        Toggle-nya ada di tab Farm > Auto Farm.

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
    - SummaryController:Hide("rerun"/"hub") menutup layar hasil, memanggil
      RunEndStage:Leave(), lalu mengirim StrataNet.LeaveRun. LeaveRun hanya
      mengakhiri sesi lama; run baru dimulai oleh StrataNet.StartSession(worldId)
      dari MenuController:StartRun. StartSession ditolak server ("already in a
      run") kalau sesi lama belum selesai, jadi harus dikirim setelah hub.
    - Tombol LEAVE MINE di HUD memakai StrataNet.EndSession. Di tengah run,
      EndSession yang menutup sesi dan membuka layar hasil; LeaveRun baru
      dikirim dari layar hasil lewat SummaryController:Hide.

  Pemakaian:
    loadstring(readfile("AIBridge/inbox.lua"))()
    RightShift = sembunyikan / tampilkan window (bawaan BPUI)
    getgenv().DelveFarm.Start() / .Pause() / .Resume() / .Stop() / .Destroy()
    getgenv().DelveFarm.SetFly(true/false) / .ToggleFly()
    getgenv().DelveFarm.SetRelicPriority({ "blast", "echo" })
    getgenv().DelveFarm.SetAutoAscend(true/false)
    getgenv().DelveFarm.SetAscendTo("hollow" / "farside")
    getgenv().DelveFarm.SetPathPick("safe" / "cursed" / "manual")
    getgenv().DelveFarm.SetTraderMode("manual" / "priority" / "relic" / "cheapest", hargaMaks)
    getgenv().DelveFarm.SetLoadoutAuto(true/false)
    getgenv().DelveFarm.SetLoadoutSets(setPedang, setMining, setIdle)
    getgenv().DelveFarm.LeaveRun("rerun" / "hub")
    getgenv().DelveFarm.SetLeaveMode("rerun" / "hub")
    getgenv().DelveFarm.SetAutoLeave(true/false)
    getgenv().DelveFarm.SetDepthLeave(true/false)
    getgenv().DelveFarm.SetDepthTarget(500)
    getgenv().DelveFarm.SetFocusMining(true/false)
    getgenv().DelveFarm.SetBehindFirst(true/false)
    getgenv().DelveFarm.SetCenterMine(true/false)
    getgenv().DelveFarm.SetAntiAfk(true/false)
    getgenv().DelveFarm.AntiAfkPulse()

  Catatan:
    - Auto Farm sengaja mulai dalam keadaan mati. Nyalakan lewat toggle di tab Farm.
    - Pause/Resume tersedia lewat console: getgenv().DelveFarm.Pause() / .Resume().
]]

local BPUI_OK, BPUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/bypasshubpremium/BPUINEW/main/BPUI.lua"))()
end)
if not BPUI_OK or type(BPUI) ~= "table" then
    warn("[DelveFarm] failed to load BPUI: " .. tostring(BPUI))
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local plr = Players.LocalPlayer

-- VirtualUser dipakai anti AFK. Di beberapa executor service ini tidak bisa
-- diakses, jadi pemakaiannya selalu dibungkus pcall dan ada fallback keypress.
local VirtualUser = nil
pcall(function()
    VirtualUser = game:GetService("VirtualUser")
end)

-- ============================================================
-- Konfigurasi (diubah langsung oleh elemen UI)
-- ============================================================

local CFG = {
    -- saklar fitur
    mine = true,
    fight = true,
    autoEquip = true,
    chase = true,
    focusMining = true,        -- Delve: mob hanya dilawan di room gate/boss

    -- anti AFK
    antiAfk = true,            -- cegah kick idle Roblox lewat sinyal Idled

    -- mining
    aimHz = 20,                -- sama dengan Config.Mining.AimSendRate
    directRock = true,         -- teleport tepat ke sel batu, bukan ke sel sebelahnya
    standOffset = 6,           -- jarak berdiri dari titik tengah rock (dipakai kalau directRock mati)
    teleportTolerance = 2.5,   -- kalau sudah sedekat ini, tidak teleport lagi
    groundWait = 0.35,         -- tunggu setelah teleport sebelum kirim Aim
    rockTimeout = 20,          -- detik sebelum rock dianggap gagal dan di-blacklist
    rockBlacklist = 20,        -- lama rock di-blacklist
    rockScanInterval = 0.5,
    behindFirst = true,        -- Delve: batu di sel kedalaman belakang ditambang dulu
    centerMine = true,         -- Delve: berdiri di lane tengah, aim ke tengah baris

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
    chestOpenHold = 0.25,      -- kontak singkat di chest open supaya server sempat mencatat hadiah
    chestCooldown = 8,         -- jeda sebelum chest yang gagal dicoba lagi

    -- relic
    autoRelic = true,          -- pilih relic otomatis saat draft muncul
    relicFallback = true,      -- kalau tidak ada prioritas, ambil rarity tertinggi
    relicDelay = 0.25,         -- jeda sebelum mengirim pilihan, detik
    pathPick = "manual",       -- "manual" / "safe" / "cursed"
    traderMode = "manual",     -- "manual" / "priority" / "relic" / "cheapest"
    traderMaxPrice = 0,        -- 0 = tanpa batas harga

    -- auto ascend: pilih The Hollow / The Heavens saat Heart membuka cabang Rift
    autoAscend = true,         -- pilih realm otomatis
    ascendTo = "hollow",       -- "hollow" / "farside"
    ascendDelay = 0.35,        -- jeda sebelum mengirim pilihan ascend, detik

    -- keluar run (StrataNet.LeaveRun)
    leaveMode = "rerun",       -- "rerun" / "hub", tujuan tombol otomatis
    autoLeave = false,         -- keluar otomatis saat layar hasil muncul
    autoLeaveDelay = 2,        -- jeda sebelum keluar otomatis, detik
    depthLeave = false,        -- keluar otomatis saat kedalaman mencapai target
    depthLeaveAt = 500,        -- target kedalaman, meter (angka DEPTH di HUD)
    depthLeaveDelay = 0.5,     -- jeda singkat sebelum LeaveRun, detik
    leaveCooldown = 3,         -- jeda minimum antar perintah LeaveRun, detik

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
    swingDive = false,         -- paksa dive di setiap swing (fallback manual)
    swingDiveTime = 0.28,      -- lama badan berada di titik pukulan
    swingDiveDelay = 0.12,     -- jeda sebelum Swing saat dive, biar posisi sempat replikasi
}

-- ============================================================
-- Remote
-- ============================================================

local net = ReplicatedStorage:WaitForChild("StrataNet", 20)
if not net then
    return
end

local aimRemote = net:WaitForChild("Aim", 10)
local pickaxeRemote = net:WaitForChild("PickaxeOut", 10)
local weaponRemote = net:WaitForChild("WeaponDrawn", 10)
local swingRemote = net:WaitForChild("Swing", 10)
if not (aimRemote and pickaxeRemote and weaponRemote and swingRemote) then
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

-- Kedalaman yang tampil di HUD dihitung dari Delve.metresAt(chamber) ditambah
-- metresBase (prestige). Modulnya dipakai untuk auto leave kedalaman.
local DelveShared = nil
pcall(function()
    local strata = ReplicatedStorage:FindFirstChild("Strata")
    if strata then
        DelveShared = require(strata.Shared.Delve)
    end
end)

-- Grid dipakai untuk membaca sel kedalaman pemain. Di shaft Delve, sel X
-- adalah arah turun shaft (makin besar = makin dalam), jadi sel X lebih
-- stabil daripada arah hadap karakter untuk menentukan batu "di belakang".
local GridShared = nil
pcall(function()
    local strata = ReplicatedStorage:FindFirstChild("Strata")
    if strata then
        GridShared = require(strata.Shared.Grid)
    end
end)

local relicOfferRemote = net:WaitForChild("RelicOffer", 5)
local relicPickRemote = net:WaitForChild("PickRelic", 5)

-- Equipment set. Kalau remote ini tidak ada, fitur auto set dimatikan.
local loadoutRemote = net:FindFirstChild("SwapLoadout")
local profileSyncRemote = net:FindFirstChild("ProfileSync")
if not loadoutRemote then
    CFG.loadoutAuto = false
    warn("[DelveFarm] SwapLoadout not found, auto equipment set disabled.")
end

-- Keluar run. Remote LeaveRun hanya mengakhiri sesi; run baru dimulai oleh
-- StartSession (dipakai MenuController:StartRun).
local leaveRunRemote = net:FindFirstChild("LeaveRun")
local endSessionRemote = net:FindFirstChild("EndSession")
local startSessionRemote = net:FindFirstChild("StartSession")
if not leaveRunRemote then
    warn("[DelveFarm] LeaveRun not found, leave run feature disabled.")
end

-- Ringkasan run (SummaryController) hanya bisa dipanggil lewat tabel controller
-- milik StrataClient. Tabel itu diambil lewat helper equipment set supaya
-- filtergc tidak dipanggil berkali-kali.
local ensureStrataApp

local function getApp()
    if type(ensureStrataApp) ~= "function" then
        return nil
    end
    return ensureStrataApp(os.clock())
end

local function getSummary()
    local app = getApp()
    if not app or type(app.Controllers) ~= "table" then
        return nil
    end
    local summary = app.Controllers.SummaryController
    if type(summary) == "table" and type(summary.Hide) == "function" then
        return summary
    end
    return nil
end

-- Cadangan kalau app.State dan SummaryController tidak terbaca (executor
-- mobile tertentu): teks "Where" di layar hasil menyebut nama dunia.
local RUNEND_WORLD_HINTS = {
    ["DELVE"] = "delve",
    ["GRASSLANDS"] = "starter_mine",
    ["SUN FLATS"] = "sun_flats",
    ["PIRATES COVE"] = "pirates_cove",
    ["INFERNIA"] = "dragons_peak",
    ["THE ABYSS"] = "abyss",
    ["FROSTBITE"] = "frostbite",
}

local function currentWorldId()
    local app = getApp()
    local area = app and app.State and app.State.aim and app.State.aim.area
    if area and type(area.worldId) == "string" and not area.isHub then
        return area.worldId
    end

    local summary = getSummary()
    if summary and type(summary.lastSummary) == "table" then
        local worldId = summary.lastSummary.worldId
        if type(worldId) == "string" and worldId ~= "" then
            return worldId
        end
    end

    local pg = plr:FindFirstChildOfClass("PlayerGui")
    local runEnd = pg and pg:FindFirstChild("RunEnd")
    local results = runEnd and runEnd:FindFirstChild("Results")
    local where = results and results:FindFirstChild("Where")
    local text = where and where.Text
    if type(text) == "string" and text ~= "" then
        local upper = string.upper(text)
        for hint, id in pairs(RUNEND_WORLD_HINTS) do
            if string.find(upper, hint, 1, true) then
                return id
            end
        end
    end

    return nil
end

local function isHubArea()
    local app = getApp()
    local area = app and app.State and app.State.aim and app.State.aim.area
    return area ~= nil and area.isHub == true
end

-- Setelah LeaveRun, server butuh waktu untuk menutup sesi lama. StartSession
-- yang dikirim terlalu cepat ditolak dengan "already in a run", jadi coba
-- berulang sampai plate baru muncul. Jangan bergantung pada app.State.aim:
-- di beberapa executor mobile tabel itu tidak terbaca, dan dulu itulah yang
-- membuat rerun berhenti di hub.
local function startWorldRun(worldId, oldPlate, oldSession)
    if not startSessionRemote or type(worldId) ~= "string" or worldId == "" then
        return false
    end

    -- Kalau layar hasil masih terbuka dan SummaryController tidak bisa
    -- dipakai, tutup GUI-nya di client. Kalau tidak, SessionChanged milik
    -- game akan memanggil Hide() saat sesi baru aktif dan bisa mengirim
    -- LeaveRun lagi.
    local pg = plr:FindFirstChildOfClass("PlayerGui")
    local runEnd = pg and pg:FindFirstChild("RunEnd")
    if runEnd and runEnd:IsA("ScreenGui") and runEnd.Enabled then
        pcall(function()
            runEnd.Enabled = false
        end)
    end

    local attempts = 0
    local deadline = os.clock() + 30

    while os.clock() < deadline do
        local plate = workspace:FindFirstChild("StrataPlate")
        if plate and plate ~= oldPlate then
            local app = getApp()
            local session = app and app.State and app.State.session
            -- Plate baru saja belum cukup: transisi game bisa membangun
            -- ulang plate lama tanpa memulai sesi. Kalau app terbaca, tunggu
            -- session aktif. Kalau app tidak terbaca (executor mobile),
            -- plate baru adalah satu-satunya bukti yang tersedia.
            if session
                and session ~= oldSession
                and session.active ~= false
            then
                return true
            end
            if not app then
                return true
            end
        end

        if attempts < 40 then
            attempts = attempts + 1
            pcall(function()
                startSessionRemote:FireServer(worldId)
            end)
        end

        task.wait(0.75)
    end

    return false
end

local LEAVE_LABELS = { rerun = "Rerun", hub = "To Hub" }
local LEAVE_KEYS = { ["Rerun"] = "rerun", ["To Hub"] = "hub" }

-- StrataPlate hanya ada saat run berjalan. Layar hasil bisa muncul saat plate
-- sudah hilang, jadi keduanya dipakai untuk memastikan pemain memang di run.
local function isInRun()
    return workspace:FindFirstChild("StrataPlate") ~= nil
end

local function isRunEndVisible()
    local pg = plr:FindFirstChildOfClass("PlayerGui")
    local gui = pg and pg:FindFirstChild("RunEnd")
    return gui ~= nil and gui:IsA("ScreenGui") and gui.Enabled
end

-- Tombol Again/Hub milik game memakai jalur yang sama dengan layar hasil.
-- Jangan hanya memanggil SummaryController:Hide(mode) lalu StartSession
-- manual: di Android/executor mobile Hide tanpa callback sering hanya
-- menutup sesi lama, jadi pemain mendarat di hub. Menekan tombol Again game
-- membuat callback StartRun bawaan game yang ikut berjalan.
local function runEndVerbButton(name)
    local pg = plr:FindFirstChildOfClass("PlayerGui")
    local gui = pg and pg:FindFirstChild("RunEnd")
    if not (gui and gui:IsA("ScreenGui") and gui.Enabled) then
        return nil
    end

    local verbs = gui:FindFirstChild("Verbs")
    local holder = verbs or gui:FindFirstChild("Results")
    local button = holder and holder:FindFirstChild(name)
    if not button then
        button = gui:FindFirstChild(name, true)
    end
    if not button then
        return nil
    end

    local hit = button:FindFirstChild("Hit")
    if hit and hit:IsA("GuiButton") then
        return hit
    end
    if button:IsA("GuiButton") then
        return button
    end
    return nil
end

local function fireRunEndVerb(name)
    local button = runEndVerbButton(name)
    if not button then
        return false
    end
    local gui = button:FindFirstAncestorOfClass("ScreenGui")

    local function waitClosed(timeout)
        if not gui then
            return true
        end
        local deadline = os.clock() + timeout
        while os.clock() < deadline do
            local ok, enabled = pcall(function()
                return gui.Enabled
            end)
            if not ok or not enabled then
                return true
            end
            task.wait(0.05)
        end
        return false
    end

    if type(getconnections) == "function" then
        local ok, conns = pcall(getconnections, button.Activated)
        if ok and type(conns) == "table" then
            local fired = false
            for _, conn in ipairs(conns) do
                if type(conn) == "table"
                    and type(conn.Fire) == "function"
                    and conn.Enabled ~= false
                then
                    local okFire = pcall(function()
                        conn:Fire()
                    end)
                    if okFire then
                        fired = true
                    end
                end
            end
            if fired then
                return waitClosed(0.6)
            end
        end
    end

    if type(firesignal) == "function" then
        local ok = pcall(firesignal, button.Activated)
        if ok then
            -- Di sebagian executor firesignal tidak benar-benar memanggil
            -- koneksi. Baru dianggap berhasil kalau layar hasil tertutup.
            return waitClosed(0.6)
        end
    end

    return false
end

-- Meter yang tampil di HUD: Delve.metresAt(depth + 1) + metresBase. Kalau
-- modul Delve tidak bisa dibaca, teks DepthLine di HUD dipakai sebagai cadangan.
local function liveDepthMetres()
    if not isInRun() then
        return nil
    end
    local app = getApp()
    local session = app and app.State and app.State.session
    if not session or session.active == false then
        return nil
    end
    local worldId = session.worldId
    if type(worldId) == "string" and worldId ~= "delve" then
        return nil
    end

    local depth = tonumber(session.depth)
    if depth and DelveShared and type(DelveShared.metresAt) == "function" then
        local ok, metres = pcall(DelveShared.metresAt, math.floor(depth) + 1)
        if ok and type(metres) == "number" then
            return math.floor(metres + (tonumber(session.metresBase) or 0))
        end
    end

    local pg = plr:FindFirstChildOfClass("PlayerGui")
    local hud = pg and pg:FindFirstChild("HUD")
    local line = hud and hud:FindFirstChild("DepthLine")
    if line and line:IsA("TextLabel") then
        local digits = line.Text:match("DEPTH%s*<font[^>]*>([%d,]+)</font>%s*M")
        if digits then
            return tonumber((digits:gsub(",", "")))
        end
    end
    return nil
end

-- ============================================================
-- Fokus mining (Delve)
-- ============================================================

-- Room "gate" wajib dibersihkan dari mob sebelum tempat berikutnya terbuka.
-- Di room tambang biasa mob hanya gangguan dan tidak perlu dilawan.
local FOCUS_COMBAT_KINDS = { mob = true, boss = true, milestone = true }

local function delveSession()
    local app = getApp()
    local session = app and app.State and app.State.session
    if type(session) == "table" then
        return session
    end
    return nil
end

local function delveRoomKind(session)
    session = session or delveSession()
    if not session or session.worldId ~= "delve" then
        return nil
    end
    local chamber = tonumber(session.chamber)
    if not chamber then
        local depth = tonumber(session.depth)
        chamber = depth and (math.floor(depth) + 1) or nil
    end
    if not chamber or not DelveShared or type(DelveShared.kind) ~= "function" then
        return nil, chamber
    end
    local ok, kind = pcall(DelveShared.kind, math.max(math.floor(chamber), 1))
    if ok and type(kind) == "string" then
        return kind, chamber
    end
    return nil, chamber
end

-- true = room sekarang butuh mob dibersihkan (gate/boss), false = boleh fokus mining.
local function delveNeedsCombat(session)
    session = session or delveSession()
    if not session or session.worldId ~= "delve" then
        return true
    end

    -- Boss dan milestone selalu wajib. "mob" biasa tidak dipakai sendirian
    -- karena arena/nest juga mengirim waveKind "mob" padahal opsional.
    local waveKind = session.waveKind
    if waveKind == "boss" or waveKind == "milestone" then
        return true
    end

    local kind = delveRoomKind(session)
    if kind then
        return kind == "gate" or kind == "mob"
    end

    -- Kalau modul Delve tidak terbaca, pakai wave yang sedang berjalan.
    return type(waveKind) == "string" and FOCUS_COMBAT_KINDS[waveKind] == true
end

local function focusMiningActive(session)
    if not CFG.focusMining then
        return false
    end
    session = session or delveSession()
    return session ~= nil and session.worldId == "delve"
end

local function combatWanted(session)
    if not CFG.fight then
        return false
    end
    if not focusMiningActive(session) then
        return true
    end
    return delveNeedsCombat(session)
end

-- Mode tengah hanya berlaku di Delve, sama seperti Prioritas Batu Belakang.
local function centerMineActive()
    if not CFG.centerMine then
        return false
    end
    local session = delveSession()
    if session and type(session.worldId) == "string" and session.worldId ~= "" then
        return session.worldId == "delve"
    end
    return currentWorldId() == "delve"
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
    focusKind = nil,     -- jenis room Delve terakhir: "ore" / "gate"
    focusCombat = false, -- hasil terakhir combatWanted()
    focusToggle = nil,
    behindToggle = nil,
    centerToggle = nil,
    centerRow = nil,     -- baris kedalaman yang sedang ditambang mode tengah
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
    toggle = nil,

    -- keluar run
    lastLeaveAt = 0,
    lastWorldId = nil,
    rerunPending = false,
    rerunAt = 0,
    rerunSeenAt = 0,
    rerunGuard = false,
    rerunOldPlate = nil,
    rerunOldSession = nil,
    connRerunGui = nil,
    autoLeaveArmed = false,
    depthLeaveArmed = false,
    depthNow = nil,
    runCard = nil,
    depthToggle = nil,
    depthInput = nil,
    depthCard = nil,

    -- fly
    flyOn = false,
    flyBv = nil,
    flyBg = nil,
    flyTarget = nil,
    flyHeightNow = 0,
    flyToggle = nil,
    flyCard = nil,
    flyManualAt = 0,

    -- anti AFK
    antiAfkToggle = nil,
    antiAfkCard = nil,
    antiAfkCount = 0,
    antiAfkLast = 0,
    antiAfkMethod = nil,
    antiAfkSource = nil,
    antiAfkWarned = false,
    connIdled = nil,

    -- swing
    diveUntil = 0,
    divePoint = nil,
    pendingSwing = nil,

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

    -- auto ascend
    ascendPicks = 0,
    ascendLast = nil,
    ascendToggle = nil,
    ascendDropdown = nil,

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
    elseif keepPosition then
        -- Karakter tetap di titik chest. Lupakan target rock lama supaya
        -- mining langsung memilih batu terdekat dari posisi ini.
        S.rock = nil
        S.stand = nil
        S.rockPos = nil
        S.snappedRock = nil
        S.centerRow = nil
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
        -- Sentuhan terakhir untuk mengambil hadiah. Kontak hanya sebentar
        -- supaya server sempat mencatat hadiah, lalu karakter langsung lanjut
        -- mining tanpa menunggu chest hilang.
        if S.chestClaimUntil == 0 then
            pcall(function()
                hrp.CFrame = CFrame.new(point)
            end)
            S.teleportedAt = now
            S.chestClaimUntil = now + CFG.chestOpenHold
            S.chestTaken = S.chestTaken + 1
            print("[DelveFarm] chest collected (" .. tostring(chest:GetAttribute("ChestRarity")) .. ")")
        end
        if now < S.chestClaimUntil then
            pcall(function()
                hrp.CFrame = CFrame.new(point)
            end)
            return true
        end
        -- Hadiah sudah tercatat: lepas chest di posisi sekarang dan lanjut mining.
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
    priority = "Priority relic",
    relic = "Any relic",
    cheapest = "Cheapest",
}
local TRADER_MODES = { manual = true, priority = true, relic = true, cheapest = true }
local ASCEND_LABELS = { hollow = "The Hollow", farside = "The Heavens" }
local ASCEND_KEYS = { hollow = true, farside = true }
local ASCEND_LABEL_TO_KEY = {
    [ASCEND_LABELS.hollow] = "hollow",
    [ASCEND_LABELS.farside] = "farside",
}

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
            ascend = CFG.autoAscend,
            ascendTo = CFG.ascendTo,
            ascendDelay = CFG.ascendDelay,
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
    if type(data.ascend) == "boolean" then
        CFG.autoAscend = data.ascend
    end
    if type(data.ascendTo) == "string" and ASCEND_KEYS[data.ascendTo] then
        CFG.ascendTo = data.ascendTo
    end
    if type(data.ascendDelay) == "number" then
        CFG.ascendDelay = math.clamp(data.ascendDelay, 0, 2)
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

-- Auto ascend. Pilihan realm memakai draft kartu yang sama dengan relic:
-- satu kartu The Hollow dan satu kartu The Heavens. Keduanya harus ada
-- supaya item trader yang namanya mirip tidak ikut terpilih.
local function normalizeRealmText(value)
    if type(value) ~= "string" then
        return ""
    end
    local text = string.upper(value)
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function textHasName(text, name)
    local start = 1
    while true do
        local at = text:find(name, start, true)
        if not at then
            return false
        end
        local after = text:sub(at + #name, at + #name)
        if after == "" or not after:match("%a") then
            return true
        end
        start = at + #name
    end
end

local function realmFromText(value)
    local text = normalizeRealmText(value)
    if text == "" then
        return nil
    end
    if text == "HOLLOW" or textHasName(text, "THE HOLLOW") then
        return "hollow"
    end
    if text == "HEAVEN"
        or text == "HEAVENS"
        or textHasName(text, "THE HEAVEN")
        or textHasName(text, "THE HEAVENS")
    then
        return "farside"
    end
    return nil
end

local function realmFromId(value)
    if type(value) ~= "string" then
        return nil
    end
    local id = string.lower(value)
    if ASCEND_KEYS[id] then
        return id
    end
    if id == "heaven" or id == "heavens" then
        return "farside"
    end
    return nil
end

local function realmOfCard(card)
    if type(card) ~= "table" then
        return nil
    end
    local id = realmFromId(card.id)
    if id then
        return id
    end
    return realmFromText(card.title)
        or realmFromText(card.name)
        or realmFromText(card.tier)
        or realmFromText(card.bonus)
        or realmFromText(card.stat)
end

local function realmIndices(cards)
    local hollowIndex, farsideIndex
    for i, card in ipairs(cards or {}) do
        local realm = realmOfCard(card)
        if realm == "hollow" and not hollowIndex then
            hollowIndex = i
        elseif realm == "farside" and not farsideIndex then
            farsideIndex = i
        end
    end
    if hollowIndex and farsideIndex then
        return hollowIndex, farsideIndex
    end
    return nil
end

local function chooseAscendIndex(cards)
    local hollowIndex, farsideIndex = realmIndices(cards)
    if not hollowIndex then
        return nil
    end
    if CFG.ascendTo == "farside" then
        return farsideIndex, "ascend ke " .. ASCEND_LABELS.farside
    end
    return hollowIndex, "ascend ke " .. ASCEND_LABELS.hollow
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

    -- Cabang Rift (The Hollow / The Heavens) memakai kartu yang sama.
    -- Cek ini lebih dulu supaya pilihan ascend tidak dianggap path biasa.
    if CFG.autoAscend then
        local ascendIndex, ascendReason = chooseAscendIndex(cards)
        if ascendIndex then
            return ascendIndex, ascendReason
        end
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
    local isAscend = false
    if isCards then
        for _, card in ipairs(offer.cards) do
            names[#names + 1] = cardName(card)
        end
        if CFG.autoAscend then
            index, reason = chooseAscendIndex(offer.cards)
            isAscend = index ~= nil
        end
        if not index and CFG.autoRelic then
            index, reason = chooseCardIndex(offer.cards, offer)
        end
    else
        local realmCards = {}
        for _, id in ipairs(choices) do
            names[#names + 1] = relicName(id)
            realmCards[#realmCards + 1] = { id = id }
        end
        if CFG.autoAscend then
            index, reason = chooseAscendIndex(realmCards)
            isAscend = index ~= nil
        end
        if not index and CFG.autoRelic then
            index, reason = chooseRelicIndex(choices)
        end
    end

    S.relicSeq = S.relicSeq + 1
    local seq = S.relicSeq

    if not CFG.autoRelic and not isAscend then
        S.relicStatus = "Draft: " .. table.concat(names, " | ")
        return
    end

    if not relicPickRemote then
        S.relicStatus = "Fitur draft tidak tersedia."
        return
    end

    if not index then
        local prefix = isCards and "Kartu: " or "Draft: "
        S.relicStatus = prefix .. table.concat(names, " | ") .. " (" .. tostring(reason) .. ")"
        if isCards and reason ~= "path manual" and reason ~= "trader manual" then
            print("[DelveFarm] relic: card skipped (" .. tostring(reason) .. ")")
        end
        return
    end

    local label
    if isCards then
        label = cardName(offer.cards[index])
    else
        label = relicName(choices[index])
    end

    local delayValue = isAscend and CFG.ascendDelay or CFG.relicDelay
    local delay = math.clamp(tonumber(delayValue) or 0, 0, 2)
    S.relicStatus = string.format(
        "%s: %s. Memilih %s (%s) dalam %.2fs.",
        isAscend and "Ascend" or "Draft",
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
        if isAscend then
            S.ascendPicks = S.ascendPicks + 1
            S.ascendLast = label
            S.relicStatus = string.format("Ascend terpilih: %s.", label)
            print("[DelveFarm] ascend: " .. label)
        else
            S.relicPicks = S.relicPicks + 1
            S.relicLast = label
            S.relicStatus = string.format("Terpilih: %s (%s).", label, reason)
            print("[DelveFarm] relic: " .. label .. " (" .. reason .. ")")
        end
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
    local ascendLine = "Ascend: "
    if CFG.autoAscend then
        ascendLine = ascendLine .. (ASCEND_LABELS[CFG.ascendTo] or "The Hollow") .. " (otomatis)"
    else
        ascendLine = ascendLine .. "Manual"
    end
    lines[#lines + 1] = ascendLine
    if S.ascendPicks > 0 then
        local last = S.ascendLast and (" (" .. S.ascendLast .. ")") or ""
        lines[#lines + 1] = "Ascend dipilih: " .. tostring(S.ascendPicks) .. last
    end
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

if relicOfferRemote and relicPickRemote then
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

local function getEquipControllers()
    local app = getApp()
    local controllers = app and app.Controllers
    if type(controllers) ~= "table" then
        return nil, nil
    end
    return controllers.PickaxeController, controllers.WeaponController
end

local function controllerEquipped(controller)
    if type(controller) ~= "table" or type(controller.IsEquipped) ~= "function" then
        return nil
    end
    local ok, value = pcall(controller.IsEquipped, controller)
    if ok and type(value) == "boolean" then
        return value
    end
    return nil
end

-- Ganti pickaxe/pedang lewat controller milik game, bukan remote mentah.
-- Controller yang menyimpan status visual dan urutan remote yang benar; kalau
-- hanya remote yang dikirim, server bisa sudah memakai pickaxe sementara
-- karakter masih memegang pedang. Remote langsung hanya dipakai untuk
-- menyamakan status server ketika controller sudah berada di posisi yang benar.
local function pumpEquip()
    local ch = plr.Character
    if not ch or not S.want or not CFG.autoEquip then
        return
    end
    local now = os.clock()
    if now - S.wantAt < CFG.equipRetry then
        return
    end

    local pickaxe, weapon = getEquipControllers()
    if S.want == "pickaxe" then
        local controllerOn = controllerEquipped(pickaxe)
        local serverOn = ch:GetAttribute("PickaxeOut") == true
            and ch:GetAttribute("WeaponDrawn") ~= true
        if controllerOn == true and serverOn then
            return
        end

        S.wantAt = now
        if controllerOn == false and type(pickaxe.SetEquipped) == "function" then
            local ok = pcall(function()
                pickaxe:SetEquipped(true)
            end)
            if ok then
                return
            end
        end

        pcall(function()
            weaponRemote:FireServer(false)
        end)
        pcall(function()
            pickaxeRemote:FireServer(true)
        end)
    else
        local controllerOn = controllerEquipped(weapon)
        local serverOn = ch:GetAttribute("WeaponDrawn") == true
            and ch:GetAttribute("PickaxeOut") ~= true
        if controllerOn == true and serverOn then
            return
        end

        S.wantAt = now
        if controllerOn == false and type(weapon.SetEquipped) == "function" then
            local ok = pcall(function()
                weapon:SetEquipped(true)
            end)
            if ok then
                return
            end
        end

        pcall(function()
            weaponRemote:FireServer(true)
        end)
        pcall(function()
            pickaxeRemote:FireServer(false)
        end)
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

ensureStrataApp = function(now)
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
        return allowOff and "Off" or "Set 1"
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
        -- Mode tengah: hover di atas lane tengah, bukan di atas batu, supaya
        -- badan tidak bergeser setiap kali target aim berganti ke batu lain.
        local centered = centerMineActive() and S.stand ~= nil
        local base = centered and S.stand or (CFG.hoverRock and S.rockPos or S.stand)
        if not base then
            return nil
        end
        local top = base.Y
        if centered then
            top = S.stand.Y - 3.2
        elseif CFG.hoverRock then
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

local function flatUnit(v)
    local flat = Vector3.new(v.X, 0, v.Z)
    if flat.Magnitude < 0.001 then
        return nil
    end
    return flat.Unit
end

-- Sel kedalaman pemain (sumbu X grid). Di shaft Delve, makin besar sel X =
-- makin dalam, jadi batu dengan sel X lebih kecil berarti ada di belakang
-- menuju pintu masuk. Grid.fromWorld memakai plate yang sama dengan game.
local function playerCellX(hrp)
    if type(GridShared) ~= "table" or type(GridShared.fromWorld) ~= "function" then
        return nil
    end
    local app = getApp()
    local plate = app and app.State and (app.State.plate or app.State.area)
    if type(plate) ~= "table" then
        return nil
    end
    local ok, cx = pcall(GridShared.fromWorld, plate, hrp.Position)
    if ok and type(cx) == "number" then
        return cx
    end
    return nil
end

-- Cadangan kalau plate/Grid tidak terbaca: pakai arah hadap karakter.
-- BodyGyro saat fly mempertahankan rotasi ini, jadi arahnya stabil selama
-- teleport antar batu.
local function behindFacing(hrp)
    local facing = flatUnit(hrp.CFrame.LookVector)
    if facing then
        return facing
    end
    local cam = workspace.CurrentCamera
    local look = cam and cam.CFrame.LookVector
    if look then
        return flatUnit(look)
    end
    return nil
end

local function behindFirstActive()
    if not CFG.behindFirst then
        return false
    end
    local session = delveSession()
    if session and type(session.worldId) == "string" and session.worldId ~= "" then
        return session.worldId == "delve"
    end
    return currentWorldId() == "delve"
end

-- Lebar lane shaft untuk satu baris kedalaman. Delve.spanAt dipakai game
-- sendiri saat menggambar lantai (PlateRenderer), jadi lane tengah di sini
-- sama dengan tengah shaft yang sedang aktif.
local function centerLaneFor(row)
    local app = getApp()
    local plate = app and app.State and (app.State.plate or app.State.area)
    if DelveShared and type(DelveShared.spanAt) == "function" then
        local extra = 0
        if type(plate) == "table" and type(DelveShared.extraOf) == "function" then
            local ok, value = pcall(DelveShared.extraOf, plate)
            if ok and type(value) == "number" then
                extra = value
            end
        end
        local ok, lo, hi = pcall(DelveShared.spanAt, row, extra)
        if ok and type(lo) == "number" and type(hi) == "number" then
            return (lo + hi) * 0.5
        end
    end
    return 4.5
end

local CELL_SIZE = 8
pcall(function()
    local strata = ReplicatedStorage:FindFirstChild("Strata")
    local config = strata and require(strata.Config)
    local size = config and config.Grid and config.Grid.CellSize
    if type(size) == "number" and size > 0 then
        CELL_SIZE = size
    end
end)

-- Titik dunia satu sel grid. Grid.toWorld butuh plate; kalau app tidak
-- terbaca (executor mobile), posisi batu di baris yang sama digeser sepanjang
-- sumbu lane (world X), karena shaft Delve memakai X untuk lane.
local function cellWorld(row, lane, refPivot, refZ)
    local app = getApp()
    local plate = app and app.State and (app.State.plate or app.State.area)
    if type(GridShared) == "table" and type(GridShared.toWorld) == "function" and type(plate) == "table" then
        local ok, pos = pcall(GridShared.toWorld, plate, row, lane)
        if ok and typeof(pos) == "Vector3" then
            return pos
        end
    end
    if refPivot and type(refZ) == "number" then
        return Vector3.new(refPivot.X + (lane - refZ) * CELL_SIZE, refPivot.Y, refPivot.Z)
    end
    return nil
end

-- Jarak aim yang diizinkan server, dalam sel. Sama dengan MiningInput:_reach().
local function mineReach()
    local session = delveSession()
    local reach = session and session.stats and tonumber(session.stats.Reach)
    if reach and reach > 0.2 then
        return reach
    end
    return 1.1
end

-- Mode tengah: pilih satu baris kedalaman, berdiri di lane tengah baris itu,
-- lalu aim ke batu yang paling dekat dengan titik tengah baris. Batu kiri dan
-- kanan tetap kena karena radius pickaxe dihitung dari sel aim.
local function pickRockCenter(hrp, now)
    local useBehind = behindFirstActive()
    local playerX = useBehind and playerCellX(hrp) or nil
    local rows = {}
    for _, r in ipairs(S.rocks) do
        if r.model.Parent then
            local until_ = S.blacklist[r.model]
            if not until_ or until_ <= now then
                local ok, pivot = pcall(function()
                    return r.model:GetPivot().Position
                end)
                if ok and pivot then
                    local d = (Vector3.new(pivot.X - hrp.Position.X, 0, pivot.Z - hrp.Position.Z)).Magnitude
                    local row = rows[r.x]
                    if not row then
                        row = {
                            x = r.x,
                            minD = d,
                            behind = playerX ~= nil and r.x < playerX,
                            rocks = {},
                        }
                        rows[r.x] = row
                    end
                    if d < row.minD then
                        row.minD = d
                    end
                    row.rocks[#row.rocks + 1] = { rock = r, pivot = pivot, d = d }
                end
            end
        end
    end

    -- Baris yang sedang berjalan dipertahankan selama masih ada batunya supaya
    -- karakter tidak bolak-balik antar baris hanya karena satu batu habis.
    local row = S.centerRow and rows[S.centerRow] or nil
    if not row then
        local bestScore
        for _, candidate in pairs(rows) do
            -- Baris belakang tetap menang kalau Prioritas Batu Belakang aktif.
            local score = candidate.minD + (candidate.behind and 0 or 100000)
            if not bestScore or score < bestScore then
                row, bestScore = candidate, score
            end
        end
    end
    if not row then
        S.centerRow = nil
        return false
    end

    local lane = centerLaneFor(row.x)
    local aim
    for _, entry in ipairs(row.rocks) do
        if not aim or math.abs(entry.rock.z - lane) < math.abs(aim.rock.z - lane) then
            aim = entry
        end
    end
    if not aim then
        return false
    end

    -- Kalau Reach masih kecil, jangan paksa aim dari tengah: bergeser sedikit
    -- ke arah batu supaya sel aim tetap masuk jangkauan server.
    local reach = mineReach()
    local maxOff = math.max(reach - 0.35, 0.6)
    local standLane = lane
    local diff = lane - aim.rock.z
    if math.abs(diff) > maxOff then
        standLane = aim.rock.z + sign(diff) * maxOff
    end

    local world = cellWorld(row.x, standLane, aim.pivot, aim.rock.z)
    local stand, rockPos
    if world then
        local floor = floorAt(world.X, world.Z, aim.pivot.Y)
        if floor then
            stand = Vector3.new(world.X, floor.Y + 3.2, world.Z)
            rockPos = aim.pivot
        end
    end
    if not stand then
        -- Lane tengah tidak ada lantainya: kembali ke cara lama (sel batu).
        stand, rockPos = standFor(aim.rock.model, hrp.Position)
    end
    if not stand then
        S.blacklist[aim.rock.model] = now + 5
        return false
    end

    S.rock = aim.rock.model
    S.rockX = aim.rock.x
    S.rockZ = aim.rock.z
    S.rockSince = now
    S.stand = stand
    S.rockPos = rockPos
    S.snappedRock = nil
    S.centerRow = row.x
    return true
end

local function pickRock(hrp, nearestOnly)
    local now = os.clock()
    if now - S.rocksAt > CFG.rockScanInterval then
        S.rocks = scanRocks()
        S.rocksAt = now
    end
    if not nearestOnly and centerMineActive() and pickRockCenter(hrp, now) then
        return true
    end
    local useBehind = not nearestOnly and behindFirstActive()
    local playerX = useBehind and playerCellX(hrp) or nil
    local facing = useBehind and not playerX and behindFacing(hrp) or nil

    -- Kumpulkan dulu semua kandidat, lalu urutkan: batu di belakang arah
    -- kedalaman (sel X lebih kecil) menang dulu, yang terdekat di antara
    -- mereka, baru batu terdekat lainnya.
    local candidates = {}
    for _, r in ipairs(S.rocks) do
        if r.model.Parent then
            local until_ = S.blacklist[r.model]
            if not until_ or until_ <= now then
                local ok, pivot = pcall(function()
                    return r.model:GetPivot().Position
                end)
                if ok and pivot then
                    local d = (Vector3.new(pivot.X - hrp.Position.X, 0, pivot.Z - hrp.Position.Z)).Magnitude
                    local behind = false
                    if playerX then
                        behind = r.x < playerX
                    elseif facing then
                        local dir = flatUnit(Vector3.new(pivot.X - hrp.Position.X, 0, pivot.Z - hrp.Position.Z))
                        if dir and dir:Dot(facing) < -0.05 then
                            behind = true
                        end
                    end
                    table.insert(candidates, { rock = r, d = d, behind = behind })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.behind ~= b.behind then
            return a.behind
        end
        return a.d < b.d
    end)

    for _, c in ipairs(candidates) do
        local stand, pv = standFor(c.rock.model, hrp.Position)
        if stand then
            S.rock = c.rock.model
            S.rockX = c.rock.x
            S.rockZ = c.rock.z
            S.rockSince = now
            S.stand = stand
            S.rockPos = pv
            S.snappedRock = nil
            return true
        end
        S.blacklist[c.rock.model] = now + 5
    end
    return false
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
    local dive = CFG.swingDive
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
end

local function tick()
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then
        releaseAim()
        return
    end
    local session = delveSession()
    if session and type(session.worldId) == "string" and session.worldId ~= "" then
        S.lastWorldId = session.worldId
    end
    pumpEquip()
    if chestStep(hrp, hum) then
        return
    end
    S.focusKind = delveRoomKind()
    S.focusCombat = combatWanted()
    if S.focusCombat then
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
        warn("[DelveFarm] hook __namecall failed: " .. tostring(err))
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
-- Anti AFK
-- ============================================================

-- Kirim satu input kecil supaya timer idle Roblox kembali ke nol. VirtualUser
-- adalah jalur utama karena tetap bekerja walau window game tidak fokus.
-- keypress hanya cadangan untuk executor yang tidak menyediakan VirtualUser.
local function antiAfkClick()
    if VirtualUser then
        local ok = pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        if ok then
            return "klik virtual"
        end
    end
    if type(keypress) == "function" and type(keyrelease) == "function" then
        local ok = pcall(function()
            keypress(0x57)
            task.delay(0.06, function()
                pcall(keyrelease, 0x57)
            end)
        end)
        if ok then
            return "tombol W"
        end
    end
    return nil
end

local function antiAfkPulse(source)
    if not CFG.antiAfk then
        return false, "nonaktif"
    end
    local method = antiAfkClick()
    if not method then
        if not S.antiAfkWarned then
            S.antiAfkWarned = true
            warn("[DelveFarm] anti AFK: VirtualUser and keypress unavailable.")
        end
        return false, "input tidak tersedia"
    end
    S.antiAfkLast = os.clock()
    S.antiAfkCount = S.antiAfkCount + 1
    S.antiAfkMethod = method
    S.antiAfkSource = source
    return true, method
end

local function antiAfkStatusText()
    local lines = {}
    lines[#lines + 1] = "Anti AFK: " .. (CFG.antiAfk and "aktif" or "mati")
    lines[#lines + 1] = "Klik: hanya saat Idled / tombol tes"
    if S.antiAfkCount > 0 then
        lines[#lines + 1] = string.format(
            "Klik terakhir: %.0f detik lalu (%s)",
            math.max(os.clock() - S.antiAfkLast, 0),
            S.antiAfkMethod or "?"
        )
        lines[#lines + 1] = "Total klik: " .. tostring(S.antiAfkCount)
        if S.antiAfkSource then
            lines[#lines + 1] = "Pemicu terakhir: " .. tostring(S.antiAfkSource)
        end
    else
        lines[#lines + 1] = "Belum ada klik."
    end
    if VirtualUser then
        lines[#lines + 1] = "Metode: klik VirtualUser"
    elseif type(keypress) == "function" and type(keyrelease) == "function" then
        lines[#lines + 1] = "Metode: tombol W executor"
    else
        lines[#lines + 1] = "Metode: tidak tersedia"
    end
    return table.concat(lines, "\n")
end

-- ============================================================
-- API (dipakai UI dan console)
-- ============================================================

local api = {}

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
    S.centerRow = nil
    S.lastAimSent = 0
    S.warned = false
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
end

function api.Resume()
    if not S.running then
        return
    end
    S.paused = false
    S.mode = nil
end

function api.Stop()
    S.running = false
    S.paused = false
    S.rerunPending = false
    S.rerunSeenAt = 0
    S.rerunOldSession = nil
    S.mode = nil
    S.rock = nil
    S.stand = nil
    S.rockPos = nil
    S.centerRow = nil
    S.pendingSwing = nil
    releaseAim()
    chestAbort()
    uninstallGuard()
    syncToggle(false)
end

function api.SetFly(on)
    on = on and true or false
    if on then
        if not flyEnable() then
            S.flyOn = false
            syncFly(false)
            return false
        end
        S.flyOn = true
    else
        S.flyOn = false
        flyDisable()
    end
    syncFly(S.flyOn)
    return true
end

function api.ToggleFly()
    return api.SetFly(not S.flyOn)
end

function api.SetAntiAfk(on)
    on = on and true or false
    CFG.antiAfk = on
    if S.antiAfkToggle then
        pcall(function()
            S.antiAfkToggle:Set(CFG.antiAfk, true)
        end)
    end
    return CFG.antiAfk
end

function api.AntiAfkPulse()
    return antiAfkPulse("manual")
end

function api.SetFocusMining(on)
    CFG.focusMining = on and true or false
    if not CFG.focusMining then
        S.mob = nil
    end
    if S.focusToggle then
        pcall(function()
            S.focusToggle:Set(CFG.focusMining, true)
        end)
    end
    return CFG.focusMining
end

function api.SetBehindFirst(on)
    CFG.behindFirst = on and true or false
    if S.behindToggle then
        pcall(function()
            S.behindToggle:Set(CFG.behindFirst, true)
        end)
    end
    return CFG.behindFirst
end

function api.SetCenterMine(on)
    CFG.centerMine = on and true or false
    if not CFG.centerMine then
        S.centerRow = nil
    end
    if S.centerToggle then
        pcall(function()
            S.centerToggle:Set(CFG.centerMine, true)
        end)
    end
    return CFG.centerMine
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

function api.SetAutoAscend(on)
    CFG.autoAscend = on and true or false
    if S.ascendToggle then
        pcall(function()
            S.ascendToggle:Set(CFG.autoAscend, true)
        end)
    end
    saveRelicPrefs()
    refreshRelicStatus()
    return CFG.autoAscend
end

function api.SetAscendTo(value)
    if type(value) ~= "string" or not ASCEND_KEYS[value] then
        return false
    end
    CFG.ascendTo = value
    if S.ascendDropdown then
        pcall(function()
            S.ascendDropdown:Set(ASCEND_LABELS[value], true)
        end)
    end
    saveRelicPrefs()
    refreshRelicStatus()
    return true
end

function api.SetLeaveMode(value)
    if type(value) ~= "string" or not LEAVE_LABELS[value] then
        return false
    end
    CFG.leaveMode = value
    if S.leaveDropdown then
        pcall(function()
            S.leaveDropdown:Set(LEAVE_LABELS[value], true)
        end)
    end
    return true
end

function api.SetAutoLeave(on)
    CFG.autoLeave = on and true or false
    if not CFG.autoLeave then
        S.autoLeaveArmed = false
    end
    if S.leaveToggle then
        pcall(function()
            S.leaveToggle:Set(CFG.autoLeave, true)
        end)
    end
    return CFG.autoLeave
end

function api.SetDepthLeave(on)
    CFG.depthLeave = on and true or false
    if not CFG.depthLeave then
        S.depthLeaveArmed = false
    end
    if S.depthToggle then
        pcall(function()
            S.depthToggle:Set(CFG.depthLeave, true)
        end)
    end
    return CFG.depthLeave
end

function api.SetDepthTarget(meters)
    local value = tonumber(meters)
    if not value then
        if S.depthInput then
            pcall(function()
                S.depthInput:Set(tostring(CFG.depthLeaveAt), true)
            end)
        end
        return false
    end
    CFG.depthLeaveAt = math.clamp(math.floor(value + 0.5), 50, 20000)
    if CFG.depthLeave then
        S.depthLeaveArmed = false
    end
    if S.depthInput then
        pcall(function()
            S.depthInput:Set(tostring(CFG.depthLeaveAt), true)
        end)
    end
    return CFG.depthLeaveAt
end

function api.LeaveRun(mode)
    if type(mode) ~= "string" or not LEAVE_LABELS[mode] then
        mode = CFG.leaveMode
    end
    if not leaveRunRemote then
        return false
    end
    if not (isInRun() or isRunEndVisible()) then
        return false
    end

    local now = os.clock()
    if now - S.lastLeaveAt < CFG.leaveCooldown then
        return false
    end
    S.lastLeaveAt = now
    if mode == "rerun" then
        S.rerunPending = true
        S.rerunAt = now
        S.rerunSeenAt = 0
        S.rerunOldPlate = workspace:FindFirstChild("StrataPlate")
        S.rerunOldSession = delveSession()
        if S.connRerunGui then
            pcall(function()
                S.connRerunGui:Disconnect()
            end)
            S.connRerunGui = nil
        end
        -- Jangan matikan GUI hasil sebelum SummaryController:Hide dipanggil.
        -- Hide() hanya jalan saat RunEnd.Enabled masih true. Kalau GUI
        -- dimatikan lebih dulu (guard lama), Hide() tidak melakukan apa-apa:
        -- LeaveRun tidak terkirim dan rerun berhenti/stuck setelah summary.
        -- Guard baru dipasang setelah Hide berhasil (lihat startRerunGuard).
        S.rerunGuard = false
    else
        S.rerunPending = false
        S.rerunSeenAt = 0
        S.rerunGuard = false
        if S.connRerunGui then
            pcall(function()
                S.connRerunGui:Disconnect()
            end)
            S.connRerunGui = nil
        end
    end

    -- World harus dibaca sebelum run ditutup, karena area berubah ke hub
    -- begitu server mengeluarkan pemain. S.lastWorldId adalah cadangan kalau
    -- filtergc/app tidak terbaca di executor mobile.
    local session = delveSession()
    if session and type(session.worldId) == "string" and session.worldId ~= "" then
        S.lastWorldId = session.worldId
    end
    local worldId = currentWorldId() or S.lastWorldId
    local oldPlate = workspace:FindFirstChild("StrataPlate")
    local summary = getSummary()

    -- Bersihkan target lama supaya Auto Farm memindai plate baru setelah
    -- karakter berpindah, bukan mengejar rock dari run sebelumnya.
    chestAbort()
    releaseAim()
    S.mode = nil
    S.rock = nil
    S.rockX = 0
    S.rockZ = 0
    S.rockPos = nil
    S.stand = nil
    S.centerRow = nil
    S.rocks = {}
    S.rocksAt = 0
    S.teleportedAt = 0
    S.pendingSwing = nil

    if mode == "hub" then
        api.Stop()
    end

    task.spawn(function()
        if not S.alive then
            return
        end
        summary = summary or getSummary()

        local function rerunWorldId()
            local id = worldId or currentWorldId() or S.lastWorldId
            if not id and summary and type(summary.lastSummary) == "table" then
                id = summary.lastSummary.worldId
            end
            if type(id) == "string" and id ~= "" then
                return id
            end
            return nil
        end

        -- Jalur tombol Again game: SummaryController:Hide("rerun", callback)
        -- lalu callback memanggil MenuController:StartRun. Ini yang dipakai
        -- game sendiri, jadi tidak bergantung pada StartSession manual.
        local function startNewRun()
            if not S.alive or mode ~= "rerun" then
                return
            end
            local id = rerunWorldId()
            if not id then
                return
            end

            local menu = nil
            local app = getApp()
            if app and app.Controllers then
                menu = app.Controllers.MenuController
            end
            if menu and type(menu.StartRun) == "function" then
                pcall(function()
                    menu:StartRun(id)
                end)
            end
        end

        -- Kalau game sempat mengirim StartSession terlalu cepat (terutama di
        -- Android yang transisinya lebih lambat), sesi baru tidak pernah
        -- terbangun dan pemain berhenti di hub. Setelah beberapa detik,
        -- periksa lagi lalu mulai manual kalau memang belum ada run.
        local function watchRerunStart()
            task.spawn(function()
                local app = getApp()
                local sawNewRun = false
                local deadline = os.clock() + 6
                while os.clock() < deadline do
                    task.wait(0.25)
                    local session = delveSession()
                    local plate = workspace:FindFirstChild("StrataPlate")
                    if plate and plate ~= oldPlate then
                        if not app then
                            sawNewRun = true
                            break
                        end
                        if session
                            and session ~= S.rerunOldSession
                            and session.active ~= false
                        then
                            sawNewRun = true
                            break
                        end
                    end
                end
                if not S.alive or sawNewRun then
                    return
                end
                local id = rerunWorldId()
                if not id then
                    return
                end
                startWorldRun(id, oldPlate, S.rerunOldSession)
            end)
        end

        -- 1. SummaryController:Hide dengan callback yang sama seperti tombol
        -- Again. Hide tanpa callback hanya menutup sesi lama dan mendarat
        -- di hub, jadi callback StartRun wajib ikut.
        --
        -- Guard GUI baru dipasang SETELAH Hide berhasil. Guard lama dipasang
        -- sebelum Hide, sehingga RunEnd.Enabled sudah false saat Hide dipanggil;
        -- Hide() hanya bekerja ketika GUI masih enabled, jadi LeaveRun tidak
        -- pernah terkirim dan rerun berhenti/stuck setelah summary.
        local function startRerunGuard()
            if mode ~= "rerun" then
                return
            end
            S.rerunGuard = true
            if S.connRerunGui then
                pcall(function()
                    S.connRerunGui:Disconnect()
                end)
                S.connRerunGui = nil
            end
            local pg = plr:FindFirstChildOfClass("PlayerGui")
            local gui = pg and pg:FindFirstChild("RunEnd")
            if gui and gui:IsA("ScreenGui") then
                S.connRerunGui = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if S.rerunPending and S.rerunGuard and gui.Enabled then
                        pcall(function()
                            gui.Enabled = false
                        end)
                    end
                end)
            end
        end

        local usedHide = false
        local function hideSummary()
            if not summary then
                return false
            end
            local ok = pcall(function()
                summary:Hide(mode, mode == "rerun" and startNewRun or nil)
            end)
            if ok then
                usedHide = true
                startRerunGuard()
            end
            return ok
        end

        local function useRunEndVerb()
            local verb = mode == "rerun" and "Again" or "Hub"
            if not fireRunEndVerb(verb) then
                return false
            end
            if mode == "rerun" then
                watchRerunStart()
            end
            return true
        end

        if isRunEndVisible() then
            -- 2. Kalau controller tidak terbaca, tekan tombol Again/Hub
            -- bawaan game. Paling aman karena callback StartRun ikut jalan.
            if not hideSummary() and useRunEndVerb() then
                return
            end
        elseif endSessionRemote then
            -- Server membatasi EndSession. Kalau layar hasil belum terbuka,
            -- coba lagi beberapa kali sebelum menyerah.
            for _ = 1, 3 do
                pcall(function()
                    endSessionRemote:FireServer()
                end)
                local deadline = os.clock() + 3
                while S.alive and os.clock() < deadline and not isRunEndVisible() do
                    task.wait(0.25)
                end
                if isRunEndVisible() then
                    break
                end
                task.wait(1)
            end
            if isRunEndVisible() then
                if not hideSummary() and useRunEndVerb() then
                    return
                end
            end
        end

        if not usedHide then
            pcall(function()
                leaveRunRemote:FireServer(mode)
            end)
        end

        if mode ~= "rerun" then
            return
        end

        -- Kalau Hide sudah dipanggil dengan callback, callback itu yang
        -- menjalankan StartRun. Jangan kirim StartSession kedua.
        if usedHide then
            if mode == "rerun" then
                watchRerunStart()
            end
            return
        end

        local id = rerunWorldId()
        if not id then
            return
        end

        startWorldRun(id, oldPlate, S.rerunOldSession)
    end)

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
    if S.connIdled then
        pcall(function()
            S.connIdled:Disconnect()
        end)
        S.connIdled = nil
    end
    if S.connRerunGui then
        pcall(function()
            S.connRerunGui:Disconnect()
        end)
        S.connRerunGui = nil
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
    S.centerRow = nil
    S.mode = nil
    S.teleportedAt = 0
    S.mobsAt = 0
    S.rocksAt = 0
    S.chasing = false
    S.mob = nil
    S.pendingSwing = nil
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

    if CFG.focusMining then
        local session = delveSession()
        if session and session.worldId == "delve" then
            local kind = delveRoomKind(session)
            if delveNeedsCombat(session) then
                lines[#lines + 1] = "Fokus mining: lawan mob (room " .. (kind or "?") .. ")"
            else
                lines[#lines + 1] = "Fokus mining: mob dilewati (room " .. (kind or "?") .. ")"
            end
        else
            lines[#lines + 1] = "Fokus mining: menunggu run Delve"
        end
    else
        lines[#lines + 1] = "Fokus mining: nonaktif"
    end

    if centerMineActive() then
        lines[#lines + 1] = "Mode tengah: baris "
            .. (S.centerRow and tostring(S.centerRow) or "-")
    end

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
    if CFG.antiAfk then
        if S.antiAfkCount > 0 then
            lines[#lines + 1] = string.format(
                "Anti AFK: aktif (%d klik, terakhir %.0f detik lalu)",
                S.antiAfkCount,
                math.max(os.clock() - S.antiAfkLast, 0)
            )
        else
            lines[#lines + 1] = "Anti AFK: aktif (menunggu Idled)"
        end
    else
        lines[#lines + 1] = "Anti AFK: mati"
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

    if CFG.swingDive then
        lines[#lines + 1] = "Swing: dive (paksa)"
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

local function runStatusText()
    local lines = {}
    lines[#lines + 1] = "Auto: " .. (CFG.autoLeave and "aktif" or "mati")
    lines[#lines + 1] = "Tujuan: " .. (LEAVE_LABELS[CFG.leaveMode] or "Rerun")
    if isRunEndVisible() then
        lines[#lines + 1] = "Layar hasil: terbuka"
    else
        lines[#lines + 1] = "Layar hasil: tertutup"
    end
    local depth = liveDepthMetres()
    lines[#lines + 1] = "Kedalaman: " .. (depth and (tostring(depth) .. " m") or "-")
    lines[#lines + 1] = "Batas kedalaman: "
        .. (CFG.depthLeave and (tostring(CFG.depthLeaveAt) .. " m") or "mati")
    lines[#lines + 1] = "Posisi: " .. (isInRun() and "di dalam run" or "di hub")
    if S.lastLeaveAt > 0 then
        local ago = os.clock() - S.lastLeaveAt
        if ago < 60 then
            lines[#lines + 1] = string.format("Keluar terakhir: %.0f detik lalu", ago)
        end
    end
    return table.concat(lines, "\n")
end

local function depthStatusText()
    local lines = {}
    local depth = liveDepthMetres()
    lines[#lines + 1] = "Kedalaman sekarang: " .. (depth and (tostring(depth) .. " m") or "-")
    lines[#lines + 1] = "Target: " .. tostring(CFG.depthLeaveAt) .. " m"
    lines[#lines + 1] = "Auto: " .. (CFG.depthLeave and "aktif" or "mati")
    lines[#lines + 1] = "Tujuan: " .. (LEAVE_LABELS[CFG.leaveMode] or "Rerun")
    if CFG.depthLeave and depth and depth >= CFG.depthLeaveAt then
        lines[#lines + 1] = "Status: target tercapai, menunggu keluar"
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
local RunTab = Window:CreateTab({ Name = "Run", Icon = "rotate-ccw" })
local RelicTab = Window:CreateTab({ Name = "Relic", Icon = "sparkles" })

-- ------------------------------------------------------------
-- Tab Farm
-- ------------------------------------------------------------

local MainSection = FarmTab:CreateSection("Auto Farm")

local farmToggle

farmToggle = MainSection:AddToggle({
    Name = "Auto Farm",
    Description = "Finds rocks, teleports, aims, and fights mobs automatically.",
    Flag = "DelveFarmOn",
    Default = false,
    Callback = function(on)
        if on then
            api.Start()
        else
            api.Stop()
        end
    end,
})

S.toggle = farmToggle

MainSection:AddToggle({
    Name = "Auto Mining",
    Description = "Turn off if you only want mob combat mode.",
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
    Name = "Auto Fight Mobs",
    Description = "Switches to the weapon and swings automatically when a mob is within range.",
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

S.focusToggle = MainSection:AddToggle({
    Name = "Focus Mining (Delve)",
    Description = "In Delve, mobs in normal mining rooms are skipped. The hub only attacks when the current room is a gate/boss that must be cleared to open the next area. Locked chests are still cleared by Auto Collect Chest.",
    Flag = "DelveFocusMining",
    Default = CFG.focusMining,
    Callback = function(on)
        api.SetFocusMining(on)
    end,
})

MainSection:AddToggle({
    Name = "Auto Equip",
    Description = "Sends PickaxeOut / WeaponDrawn based on the current mode.",
    Flag = "DelveFarmEquip",
    Default = true,
    Callback = function(on)
        CFG.autoEquip = on
    end,
})

S.behindToggle = MainSection:AddToggle({
    Name = "Prioritize Rocks Behind",
    Description = "In Delve, rocks whose depth cell is lower than the player's cell (toward the shaft entrance) are mined before rocks ahead.",
    Flag = "DelveBehindFirst",
    Default = CFG.behindFirst,
    Callback = function(on)
        api.SetBehindFirst(on)
    end,
})

S.centerToggle = MainSection:AddToggle({
    Name = "Center Mining (Delve)",
    Description = "In Delve, stands in the middle lane of the shaft and aims at the middle of the row. Rocks on both sides are covered by the pickaxe Mining Range, so there is no teleport to every cell. Use when Mining Range is already wide.",
    Flag = "DelveCenterMine",
    Default = CFG.centerMine,
    Callback = function(on)
        api.SetCenterMine(on)
    end,
})

local FarmFlySection = FarmTab:CreateSection("Fly")

S.flyToggle = FarmFlySection:AddToggle({
    Name = "Enable Fly",
    Description = "WASD to move, Space to ascend, LeftCtrl to descend. While Auto Farm is running, hover takes over automatically.",
    Flag = "DelveFlyOn",
    Default = false,
    Callback = function(on)
        api.SetFly(on)
    end,
})

FarmFlySection:AddSlider({
    Name = "Hover Height",
    Description = "Body height above the target. If Swing misses, lower it toward weapon range.",
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

local EquipmentSection = FarmTab:CreateSection("Equipment Set")

S.loadoutToggle = EquipmentSection:AddToggle({
    Name = "Auto Switch Equipment Set",
    Description = "Automatically switches loadout based on the sword and pickaxe.",
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
    Name = "Set When Sword Equipped",
    Description = "Loadout used while the sword is drawn.",
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
    Name = "Set While Mining",
    Description = "Loadout used while the pickaxe is out.",
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
    Name = "Set When Idle",
    Description = "Used when neither sword nor pickaxe is held. Choose Off to leave it unchanged.",
    Options = { "Off", "Set 1", "Set 2", "Set 3" },
    Default = loadoutSetLabel(CFG.loadoutIdle, true),
    Flag = "DelveLoadoutIdle",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        CFG.loadoutIdle = loadoutSetFromLabel(label)
        S.loadoutWant = nil
    end,
})

local AntiAfkSection = FarmTab:CreateSection("Anti AFK")

S.antiAfkToggle = AntiAfkSection:AddToggle({
    Name = "Enable Anti AFK",
    Description = "A virtual click is only sent when Roblox fires Idled, so there are no periodic clicks. Still runs even when Auto Farm is off.",
    Flag = "DelveAntiAfk",
    Default = CFG.antiAfk,
    Callback = function(on)
        api.SetAntiAfk(on)
    end,
})

local ChestSection = FarmTab:CreateSection("Chest")

ChestSection:AddToggle({
    Name = "Auto Collect Chest",
    Description = "While Auto Farm is running, spawned chests are teleported to immediately. If still locked, mob waves are cleared first, then the chest is opened and its reward collected. After that it goes straight back to mining without waiting for the chest to despawn.",
    Flag = "DelveFarmChest",
    Default = true,
    Callback = function(on)
        CFG.chest = on
        if not on then
            chestAbort()
        end
    end,
})

-- ------------------------------------------------------------
-- Tab Run
-- ------------------------------------------------------------

local AutoLeaveSection = RunTab:CreateSection("Automatic")

S.leaveToggle = AutoLeaveSection:AddToggle({
    Name = "Auto Leave When Run Ends",
    Description = "When the results screen (RunEnd) appears, the hub sends the destination below without waiting for a button press.",
    Default = CFG.autoLeave,
    Flag = "DelveAutoLeave",
    Callback = function(on)
        api.SetAutoLeave(on)
    end,
})

S.leaveDropdown = AutoLeaveSection:AddDropdown({
    Name = "Auto Destination",
    Description = "Used by the toggle above when the run ends.",
    Options = { LEAVE_LABELS.rerun, LEAVE_LABELS.hub },
    Default = LEAVE_LABELS[CFG.leaveMode] or "Rerun",
    Flag = "DelveLeaveMode",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        local key = LEAVE_KEYS[label]
        if key then
            CFG.leaveMode = key
        end
    end,
})

local DepthLeaveSection = RunTab:CreateSection("Depth Auto Leave")

S.depthToggle = DepthLeaveSection:AddToggle({
    Name = "Auto Leave at Depth",
    Description = "Ends the run mid-way once the DEPTH value in the HUD reaches the target. "
        .. "The exit destination follows the dropdown in Automatic.",
    Default = CFG.depthLeave,
    Flag = "DelveDepthLeave",
    Callback = function(on)
        api.SetDepthLeave(on)
    end,
})

S.depthInput = DepthLeaveSection:AddInput({
    Name = "Target Depth",
    Description = "Type a meter value and press Enter. This value is compared with the meter shown in the HUD.",
    Default = tostring(CFG.depthLeaveAt),
    Placeholder = "e.g. 500",
    Numeric = true,
    Width = 90,
    Flag = "DelveDepthLeaveAt",
    Callback = function(text)
        api.SetDepthTarget(text)
    end,
})

-- ------------------------------------------------------------
-- Tab Relic
-- ------------------------------------------------------------

local RelicAutoSection = RelicTab:CreateSection("Auto Pick")

RelicAutoSection:AddToggle({
    Name = "Auto Pick Relic",
    Description = "When a relic draft appears, the choice is sent automatically according to priority.",
    Flag = "DelveRelicAuto",
    Default = CFG.autoRelic,
    Callback = function(on)
        CFG.autoRelic = on
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

RelicAutoSection:AddToggle({
    Name = "Highest Rarity Fallback",
    Description = "If no priority relic is in the draft, pick the highest rarity.",
    Flag = "DelveRelicFallback",
    Default = CFG.relicFallback,
    Callback = function(on)
        CFG.relicFallback = on
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

RelicAutoSection:AddSlider({
    Name = "Delay Before Picking",
    Description = "Give the cards a moment to appear before picking.",
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

local AscendSection = RelicTab:CreateSection("Auto Ascend")

S.ascendToggle = AscendSection:AddToggle({
    Name = "Auto Ascend",
    Description = "When the Heart opens a Rift branch, the hub picks The Hollow or The Heavens according to the dropdown.",
    Flag = "DelveAscendAuto",
    Default = CFG.autoAscend,
    Callback = function(on)
        CFG.autoAscend = on and true or false
        saveRelicPrefs()
        refreshRelicStatus()
    end,
})

S.ascendDropdown = AscendSection:AddDropdown({
    Name = "Ascend To",
    Description = "Realm chosen when a Rift branch draft appears.",
    Options = { ASCEND_LABELS.hollow, ASCEND_LABELS.farside },
    Default = ASCEND_LABELS[CFG.ascendTo],
    Flag = "DelveAscendTo",
    Callback = function(value)
        local label = type(value) == "table" and value[1] or value
        local key = ASCEND_LABEL_TO_KEY[label]
        if key then
            CFG.ascendTo = key
            saveRelicPrefs()
            refreshRelicStatus()
        end
    end,
})

AscendSection:AddSlider({
    Name = "Delay Before Ascend",
    Description = "Give the cards a moment to appear before picking.",
    Min = 0,
    Max = 2,
    Default = CFG.ascendDelay,
    Increment = 0.05,
    Suffix = "s",
    Flag = "DelveAscendDelay",
    Callback = function(v)
        CFG.ascendDelay = v
        saveRelicPrefs()
    end,
})

local RelicPickSection = RelicTab:CreateSection("Relic Priority")

if #relicOptions > 0 then
    S.relicDropdown = RelicPickSection:AddDropdown({
        Name = "Priority Relics",
        Description = "Pick one or more relics. There is a filter box in the list for quick search.",
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
        Title = "Relic Data",
        Content = "Strata.Defs.Relics could not be read; the priority feature is unavailable.",
    })
end

RelicPickSection:AddButton({
    Name = "Clear Priority",
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
    Name = "Path Choice",
    Description = "When a gate branches, the hub picks SAFE PATH or CURSED PATH according to this.",
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
    Description = "Set which trader items are bought automatically. Manual = buy nothing.",
    Options = { TRADER_LABELS.manual, TRADER_LABELS.priority, TRADER_LABELS.relic, TRADER_LABELS.cheapest },
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
    Name = "Trader Price Limit",
    Description = "0 = no limit. Items more expensive than this value are not bought.",
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

-- Keluar otomatis. Hanya dipicu sekali per layar hasil: flag autoLeaveArmed
-- baru dilepas lagi setelah layar hasil tertutup, supaya tidak spam remote.
S.leaveThread = task.spawn(function()
    while S.alive do
        if CFG.autoLeave then
            local visible = isRunEndVisible()
            if visible and not S.autoLeaveArmed then
                S.autoLeaveArmed = true
                local mode = CFG.leaveMode
                task.delay(CFG.autoLeaveDelay, function()
                    if not S.alive or not CFG.autoLeave then
                        return
                    end
                    if not isRunEndVisible() then
                        return
                    end
                    api.LeaveRun(mode)
                end)
            elseif not visible then
                S.autoLeaveArmed = false
            end
        else
            S.autoLeaveArmed = false
        end
        task.wait(0.25)
    end
end)

-- Auto leave kedalaman. Dipicu sekali per run: setelah target tercapai,
-- LeaveRun dikirim; flag baru dilepas lagi ketika karakter keluar dari run
-- atau kedalaman sudah turun di bawah target (run baru), jadi rerun berikutnya
-- bisa memicu lagi dari awal.
S.depthThread = task.spawn(function()
    while S.alive do
        if CFG.depthLeave then
            local depth = liveDepthMetres()
            S.depthNow = depth
            if depth and not S.depthLeaveArmed and depth >= CFG.depthLeaveAt then
                S.depthLeaveArmed = true
                local mode = CFG.leaveMode
                task.delay(CFG.depthLeaveDelay, function()
                    if not S.alive or not CFG.depthLeave then
                        S.depthLeaveArmed = false
                        return
                    end
                    local nowDepth = liveDepthMetres()
                    if not nowDepth or nowDepth < CFG.depthLeaveAt then
                        S.depthLeaveArmed = false
                        return
                    end
                    if not api.LeaveRun(mode) then
                        S.depthLeaveArmed = false
                    end
                end)
            elseif not depth or depth < CFG.depthLeaveAt then
                S.depthLeaveArmed = false
            end
        else
            S.depthNow = nil
            S.depthLeaveArmed = false
        end
        task.wait(0.25)
    end
end)

-- Penjaga rerun: jangan biarkan layar hasil lama muncul lagi selama
-- menunggu sesi baru. Flag dilepas setelah sesi baru aktif ~2 detik, atau
-- setelah 30 detik kalau server tetap menolak.
S.rerunThread = task.spawn(function()
    while S.alive do
        if S.rerunPending then
            local now = os.clock()
            -- Guard GUI hanya aktif setelah SummaryController:Hide berhasil.
            -- Sebelum Hide, RunEnd harus dibiarkan terbuka agar Hide bisa jalan.
            if S.rerunGuard then
                local pg = plr:FindFirstChildOfClass("PlayerGui")
                local gui = pg and pg:FindFirstChild("RunEnd")
                if gui and gui:IsA("ScreenGui") and gui.Enabled then
                    pcall(function()
                        gui.Enabled = false
                    end)
                end
            end

            local app = getApp()
            local session = delveSession()
            local plate = workspace:FindFirstChild("StrataPlate")
            local newRun = false
            if app then
                newRun = session ~= nil
                    and session ~= S.rerunOldSession
                    and session.active ~= false
                    and plate ~= nil
                    and plate ~= S.rerunOldPlate
            else
                newRun = plate ~= nil and plate ~= S.rerunOldPlate
            end
            if newRun then
                if S.rerunSeenAt == 0 then
                    S.rerunSeenAt = now
                elseif now - S.rerunSeenAt > 2 then
                    S.rerunPending = false
                    S.rerunGuard = false
                    if S.connRerunGui then
                        pcall(function()
                            S.connRerunGui:Disconnect()
                        end)
                        S.connRerunGui = nil
                    end
                end
            else
                S.rerunSeenAt = 0
                if now - S.rerunAt > 30 then
                    S.rerunPending = false
                    S.rerunGuard = false
                    if S.connRerunGui then
                        pcall(function()
                            S.connRerunGui:Disconnect()
                        end)
                        S.connRerunGui = nil
                    end
                    -- Biarkan auto leave kedalaman mencoba lagi kalau tadi
                    -- gagal dan pemain ternyata masih di dalam run.
                    S.depthLeaveArmed = false
                end
            end
        end
        task.wait(0.05)
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

-- Anti AFK memakai jalur standar: hanya bereaksi saat Roblox memicu Idled,
-- beberapa saat sebelum kick 20 menit. Tidak ada timer berkala, jadi tidak ada
-- klik yang tidak perlu saat pemain masih aktif.
S.connIdled = plr.Idled:Connect(function()
    if not CFG.antiAfk then
        return
    end
    antiAfkPulse("idled")
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

print("[DelveFarm] ready. Turn on Auto Farm in the Farm tab. RightShift = hide window.")
