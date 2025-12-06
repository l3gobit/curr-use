function missing(t, f, fallback)
    if type(f) == t then return f end
    return fallback
end

local queueteleport = missing("function", queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport))
local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer and game.Players.LocalPlayer.Character

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local PlaceId, JobId = game.PlaceId, game.JobId

-- =====================
-- SETTINGS
-- =====================
local Settings = {
    autoFarmEnabled = true,
    teleportHeight = 30,
    noMobTimeout = 70,  -- Thời gian chờ (giây) trước khi server hop
}

local curr_mob, curr_mobDist = nil, nil
local lastMobFoundTime = tick()

-- =====================
-- SERVER HOP FUNCTIONS
-- =====================
local Api = "https://games.roblox.com/v1/games/"

local function fetchServersData(limit, cursor, sort, placeId)
    local format = string.format("%s%d/servers/Public?sortOrder=%s&limit=%d&excludeFullGames=true", Api, placeId, sort, limit)
    local url = string.format("%s%s", format, (cursor and string.format("&cursor=%s", cursor)) or "")

    local success, response = pcall(function()
        if httprequest then
            local req = httprequest({Url = url})
            return HttpService:JSONDecode(req.Body)
        else
            return HttpService:JSONDecode(game:HttpGet(url))
        end
    end)

    if response and response.data then
        return response.data, response.nextPageCursor
    end

    return nil, nil
end

local function serversGet(serverLimit, getTimes, sort, onlyGetJobId, delay)
    getTimes = getTimes or 1
    serverLimit = (serverLimit <= 100 and serverLimit) or 100

    local serversTable = {}
    local nextPage
    repeat
        local servers
        local retryWait = 0
        repeat
            servers, nextPage = fetchServersData(serverLimit, nextPage, sort, PlaceId)
            if not servers then
                task.wait(math.random(175, 300)/100 + retryWait)
                retryWait = retryWait + 1
            elseif delay then
                task.wait(delay)
            end
        until servers

        for _, server in ipairs(servers) do
            if type(server) == "table" and server.playing > 0 and server.maxPlayers > server.playing and server.id ~= JobId then
                local insertPos = tostring(sort) == "Asc" and 1 or #serversTable + 1
                table.insert(serversTable, insertPos, (onlyGetJobId and server.id) or server)
            end
        end

        getTimes = getTimes - 1
    until not nextPage or getTimes <= 0

    return serversTable
end

local function sHop(sAmmount, sAmmountMultipliedTime, sortByLowPlayers, onlyGetJobId, sGetDelay, sHopDelay)
    if sHopDelay then task.wait(sHopDelay) end
    local sort = sortByLowPlayers and "Asc" or "Desc"
    local serversTable = serversGet(sAmmount, sAmmountMultipliedTime, sort, onlyGetJobId, sGetDelay)

    if #serversTable == 0 then return end

    local teleporting = false
    local connection
    connection = TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
        if player == LocalPlayer then
            teleporting = false
        end
    end)

    while #serversTable > 0 do
        if not teleporting then
            local serverIndex = sortByLowPlayers and 1 or math.random(1, #serversTable)
            local serverId = onlyGetJobId and serversTable[serverIndex] or serversTable[serverIndex].id

            table.remove(serversTable, serverIndex)

            local success, _ = pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceId, serverId, LocalPlayer)
            end)

            if success then
                teleporting = true
            end
        end
        task.wait(0.3)
    end

    connection:Disconnect()
end

-- =====================
-- MOB FUNCTIONS
-- =====================
local function getNearestMob()
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil, nil end

    local aliensFolder = workspace:FindFirstChild("Aliens")
    if not aliensFolder then return nil, nil end

    local nearestMob = nil
    local nearestDist = math.huge

    for _, mob in pairs(aliensFolder:GetChildren()) do
        if mob.Name ~= "Gem Alien" then continue end

        local humanoid = mob:FindFirstChild("Humanoid")
        local head = mob:FindFirstChild("Head")
        local hrp = mob:FindFirstChild("HumanoidRootPart")

        if humanoid and humanoid.Health > 0 and head and hrp then
            local dist = (head.Position - myHRP.Position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearestMob = mob
            end
        end
    end

    return nearestMob, nearestDist
end

local function checkGemAlienExists()
    local aliensFolder = workspace:FindFirstChild("Aliens")
    if not aliensFolder then return false end

    for _, mob in pairs(aliensFolder:GetChildren()) do
        if mob.Name == "Gem Alien" then
            local humanoid = mob:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return true
            end
        end
    end
    return false
end

-- =====================
-- HOOK SIMULATE PROJECTILE
-- =====================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProjectileHandler = require(Modules:WaitForChild("ProjectileHandler"))
local originalSimulate = ProjectileHandler.SimulateProjectile

ProjectileHandler.SimulateProjectile = function(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    if Settings.autoFarmEnabled then
        local curr_mobhead = curr_mob and curr_mob:FindFirstChild("Head")
        if curr_mobhead and arg4 and arg4[1] and arg5 then
            local origin = arg5.WorldPosition
            local direction = (curr_mobhead.Position - origin).Unit

            arg4[1][1] = direction

            if arg7 and arg7.MousePosition then
                arg7.MousePosition = curr_mobhead.Position
            end
        end
    end

    return originalSimulate(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
end

-- =====================
-- FARM FUNCTIONS
-- =====================
local function equipGun()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local gun = backpack and backpack:FindFirstChild("Meltdown")
    local myCharc = LocalPlayer.Character
    local humanoid = myCharc and myCharc:FindFirstChild("Humanoid")
    if gun and humanoid then
        humanoid:EquipTool(gun)
    end
    return myCharc and myCharc:FindFirstChild("Meltdown")
end

local function teleportToMob()
    local aliensFolder = workspace:FindFirstChild("Aliens")
    if not aliensFolder then return false end

    curr_mob, curr_mobDist = getNearestMob()
    if not curr_mob then return false end

    local mobHRP = curr_mob:FindFirstChild("HumanoidRootPart")
    local myHRP = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if myHRP and mobHRP then
        myHRP.CFrame = CFrame.new(mobHRP.Position + Vector3.new(0, Settings.teleportHeight, 0))
        myHRP.Anchored = true
        return true
    end
    return false
end

-- =====================
-- MAIN LOOPS
-- =====================

-- Auto Shoot Loop
task.spawn(function()
    while true do
        if Settings.autoFarmEnabled then
            if equipGun() and curr_mob and curr_mob:FindFirstChild("Humanoid") and curr_mob.Humanoid.Health > 0 then
                VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
            end
        end
        task.wait()
    end
end)

-- Auto Farm Loop
task.spawn(function()
    while true do
        if Settings.autoFarmEnabled then
            if equipGun() then
                teleportToMob()
            end
        end
        task.wait()
    end
end)

-- Auto sell gems
task.spawn(function()
    while true do
        pcall(function()
            if LocalPlayer.realstats.Gems.Value > 99 then
                ReplicatedStorage.BlackMarket.Events.ClientServer.RequestOpen:InvokeServer()
            end
        end)
        task.wait(1)
    end
end)

-- Server Hop Check Loop (kiểm tra mỗi giây)
task.spawn(function()
    while true do
        if Settings.autoFarmEnabled then
            if checkGemAlienExists() then
                lastMobFoundTime = tick()
            else
                local timeSinceLastMob = tick() - lastMobFoundTime
                if timeSinceLastMob >= Settings.noMobTimeout then
                    print("=== Không tìm thấy Gem Alien trong " .. Settings.noMobTimeout .. "s, đang chuyển server... ===")
                    
                    -- Unanchor trước khi hop
                    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if myHRP then
                        myHRP.Anchored = false
                    end
                    
                    sHop(100, 1, false, true, 0, 0)
                    break
                end
            end
        end
        task.wait(1)
    end
end)

-- =====================
-- TOGGLE & KEYBIND
-- =====================
local function toggleAutoFarm()
    Settings.autoFarmEnabled = not Settings.autoFarmEnabled

    if Settings.autoFarmEnabled then
        lastMobFoundTime = tick()  -- Reset timer khi bật lại
        print("=== Auto Farm: ON ===")
    else
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if myHRP then
            myHRP.Anchored = false
        end
        print("=== Auto Farm: OFF ===")
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.K then
        toggleAutoFarm()
    end
end)

-- =====================
-- QUEUE TELEPORT
-- =====================
if queueteleport then
    queueteleport([[loadstring(game:HttpGet("https://raw.githubusercontent.com/l3gobit/curr-use/refs/heads/main/auto_farm_with_serverhop.lua"))()]])
end

print("=== Auto Farm + Server Hop Ready ===")
print("Nhấn K để bật/tắt Auto Farm")
print("Tự động chuyển server nếu không có Gem Alien trong " .. Settings.noMobTimeout .. " giây")
