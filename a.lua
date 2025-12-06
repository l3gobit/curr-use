function missing(t, f, fallback)
    if type(f) == t then return f end
    return fallback
end

queueteleport =  missing("function", queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport))

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer and game.Players.LocalPlayer.Character

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Settings
local Settings = {
    autoFarmEnabled = true,
    teleportHeight = 30,
}

local curr_mob, curr_mobDist = nil, nil

-- Tìm mob gần nhất
local function getNearestMob()
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil, nil end
    
    local aliensFolder = workspace:FindFirstChild("Aliens")
    if not aliensFolder or not aliensFolder:FindFirstChild("Gem Alien") then return nil, nil end
    
    local nearestMob = nil
    local nearestDist = math.huge
    for _, mob in pairs(aliensFolder:GetChildren()) do
        if mob.Name ~= "Gem Alien" then continue end
        
        -- Validate mob parts
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


-- Hook SimulateProjectile
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

-- Equip gun
local function equipGun()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local gun = backpack and backpack:FindFirstChild("Meltdown")
    local myCharc = LocalPlayer.Character
    local humanoid = myCharc and myCharc:FindFirstChild("Humanoid")
    if gun then
        humanoid:EquipTool(gun)
    end
    return myCharc and myCharc:FindFirstChild("Meltdown")
end

-- Teleport tới mob gần nhất
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

-- Auto Shoot Loop
local VIM = game:GetService("VirtualInputManager")

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

-- Auto Farm Loop (teleport tới mob mới khi mob chết)
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

task.spawn(function()
    while true do
        if LocalPlayer.realstats.Gems.Value > 99 then
            ReplicatedStorage.BlackMarket.Events.ClientServer.RequestOpen:InvokeServer()
        end
        wait()
    end
end)

-- Toggle Function
local function toggleAutoFarm()
    Settings.autoFarmEnabled = not Settings.autoFarmEnabled
    
    if Settings.autoFarmEnabled then
        print("=== Auto Farm: ON ===")
    else
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if myHRP then
            myHRP.Anchored = false
        end
        print("=== Auto Farm: OFF ===")
    end
end

-- Keybind
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.K then
        toggleAutoFarm()
    end
end)

print("=== Auto Farm Mob Ready ===")
print("Nhấn K để bật/tắt Auto Farm")
print("(Silent Aim + Auto Shoot + Auto Teleport)")

queueteleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/l3gobit/curr-use/refs/heads/main/a.lua'))()")
