if _G.sa_on and type(_G.sa_off) == "function" then
    pcall(_G.sa_off)
end
_G.sa_on = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Workspace = workspace
local lp = Players.LocalPlayer
_G.__SnowXAvatarBridge = type(_G.__SnowXAvatarBridge) == "table" and _G.__SnowXAvatarBridge or {}
_G.__SnowXAvatarBridge.version = 2
_G.__SnowXAvatarBridge.skin = type(_G.__SnowXAvatarBridge.skin) == "table" and _G.__SnowXAvatarBridge.skin or {}
_G.__SnowXAvatarBridge.accessory = type(_G.__SnowXAvatarBridge.accessory) == "table" and _G.__SnowXAvatarBridge.accessory or {}
_G.__SnowXAvatarBridge.skin.revision = tonumber(_G.__SnowXAvatarBridge.skin.revision) or 0
_G.__SnowXAvatarBridge.accessory.revision = tonumber(_G.__SnowXAvatarBridge.accessory.revision) or 0
_G.__SnowXAvatarBridge.uiPanels = type(_G.__SnowXAvatarBridge.uiPanels) == "table" and _G.__SnowXAvatarBridge.uiPanels or {}

local wallcheck = true
local teamcheck = true 
local silentAimSettings = {
    Enabled = false,
    Mode = "Fov",
    Fov = 250,
    ShowFov = false,
    TargetPart = "Cabeza",
}
local visualSettings = {
    ESP = false,
    Glow = true,
    Name = false,
    Distance = false,
    Tracers = false,
    Color = Color3.fromRGB(255, 0, 0),
}

local tgt, tgtPart, lastScan = nil, nil, 0
local library, window
local runtimeConnections = {}
local shuttingDown = false

local fpsBoost = { Enabled = false, SavedProperties = {}, Connections = {} }
local FPS_EFFECT_CLASSES = { ParticleEmitter = true, Beam = true, Trail = true, Smoke = true, Fire = true, Sparkles = true }
local FPS_LIGHT_CLASSES = { PointLight = true, SpotLight = true, SurfaceLight = true }

local function fpsSaveAndSet(instance, property, value)
    if not instance then return false end
    local readOk, original = pcall(function() return instance[property] end)
    if not readOk or original == nil then return false end
    local saved = fpsBoost.SavedProperties[instance]
    if not saved then saved = {}; fpsBoost.SavedProperties[instance] = saved end
    if saved[property] == nil then saved[property] = original end
    return pcall(function() instance[property] = value end)
end

local function isCharacterObject(instance)
    local current = instance
    while current and current ~= Workspace do
        if current:IsA("Model") then
            local hasHumanoid = false
            pcall(function() hasHumanoid = current:FindFirstChildOfClass("Humanoid") ~= nil end)
            if hasHumanoid then return true end
            local playerCharacter = false
            pcall(function() playerCharacter = Players:GetPlayerFromCharacter(current) ~= nil end)
            if playerCharacter then return true end
        end
        current = current.Parent
    end
    return false
end

local function optimizeFpsInstance(instance, isLightingObject)
    if not instance then return end
    pcall(function()
        if isLightingObject then
            if instance:IsA("PostEffect") then fpsSaveAndSet(instance, "Enabled", false)
            elseif instance:IsA("Atmosphere") then
                fpsSaveAndSet(instance, "Density", 0); fpsSaveAndSet(instance, "Haze", 0); fpsSaveAndSet(instance, "Glare", 0)
            end
            return
        end
        if isCharacterObject(instance) then return end
        local className = instance.ClassName
        if FPS_EFFECT_CLASSES[className] then fpsSaveAndSet(instance, "Enabled", false)
        elseif FPS_LIGHT_CLASSES[className] then fpsSaveAndSet(instance, "Enabled", false)
        elseif instance:IsA("BasePart") then fpsSaveAndSet(instance, "CastShadow", false) end
    end)
end

local function disconnectFpsListeners()
    for i = #fpsBoost.Connections, 1, -1 do
        local connection = fpsBoost.Connections[i]
        fpsBoost.Connections[i] = nil
        pcall(function() if connection and connection.Connected then connection:Disconnect() end end)
    end
end

local function restoreFpsBoost()
    fpsBoost.Enabled = false
    disconnectFpsListeners()
    for instance, properties in pairs(fpsBoost.SavedProperties) do
        for property, original in pairs(properties) do
            pcall(function() instance[property] = original end)
        end
    end
    fpsBoost.SavedProperties = {}
end

local function enableFpsBoost()
    if fpsBoost.Enabled then return end
    fpsBoost.Enabled = true
    pcall(function()
        for _, instance in ipairs(Lighting:GetDescendants()) do optimizeFpsInstance(instance, true) end
        fpsSaveAndSet(Lighting, "GlobalShadows", false)
    end)
    pcall(function()
        for _, instance in ipairs(Workspace:GetDescendants()) do optimizeFpsInstance(instance, false) end
    end)
    local lightingOk, lightingConnection = pcall(function()
        return Lighting.DescendantAdded:Connect(function(instance)
            if fpsBoost.Enabled then optimizeFpsInstance(instance, true) end
        end)
    end)
    if lightingOk and lightingConnection then fpsBoost.Connections[#fpsBoost.Connections + 1] = lightingConnection end
    local workspaceOk, workspaceConnection = pcall(function()
        return Workspace.DescendantAdded:Connect(function(instance)
            if fpsBoost.Enabled then optimizeFpsInstance(instance, false) end
        end)
    end)
    if workspaceOk and workspaceConnection then fpsBoost.Connections[#fpsBoost.Connections + 1] = workspaceConnection end
end

local function trackConnection(connection)
    if connection then runtimeConnections[#runtimeConnections + 1] = connection end
    return connection
end

local function disconnectAll()
    for i = #runtimeConnections, 1, -1 do
        local connection = runtimeConnections[i]
        runtimeConnections[i] = nil
        pcall(function() if connection and connection.Connected then connection:Disconnect() end end)
    end
end

local function untrackConnection(connection)
    if not connection then return end
    for i = #runtimeConnections, 1, -1 do
        if runtimeConnections[i] == connection then
            table.remove(runtimeConnections, i)
            break
        end
    end
    pcall(function() if connection.Connected then connection:Disconnect() end end)
end

local function playerStatsOf(player)
    return player and player:FindFirstChild("PlayerStats") or nil
end

local function matchIdOf(player)
    if not player then return nil end
    local attrId
    local attrOk, attrValue = pcall(function() return player:GetAttribute("Game") end)
    if attrOk and type(attrValue) == "string" and attrValue ~= "" then
        attrId = attrValue
    end

    local stats = playerStatsOf(player)
    local uuidValue = stats and stats:FindFirstChild("Match_UUID")
    local statsId
    if uuidValue and uuidValue:IsA("StringValue") and uuidValue.Value ~= "" then
        statsId = uuidValue.Value
    end

    if attrId and statsId and attrId ~= statsId then
        return nil
    end
    return attrId or statsId
end

local function hasActiveMatchFlag(player)
    local stats = playerStatsOf(player)
    local inMatch = stats and stats:FindFirstChild("InMatch")
    if inMatch and inMatch:IsA("BoolValue") then
        return inMatch.Value == true
    end

    return matchIdOf(player) ~= nil
end

local function scoreboardTeamOf(player)
    local playerGui = lp:FindFirstChild("PlayerGui")
    local newMatchUi = playerGui and playerGui:FindFirstChild("NewMatchUI")
    local mainFrame = newMatchUi and newMatchUi:FindFirstChild("MainGameFrame")
    local score = mainFrame and mainFrame:FindFirstChild("IngameScore")
    if not score or not player then return nil end

    local identifiers = {
        string.lower(player.Name or ""),
        string.lower(player.DisplayName or ""),
    }
    for _, teamName in ipairs({ "TeamRed", "TeamBlue" }) do
        local teamFrame = score:FindFirstChild(teamName)
        if teamFrame then
            for _, entry in ipairs(teamFrame:GetChildren()) do
                local entryName = string.lower(entry.Name or "")
                local label = entry:FindFirstChildWhichIsA("TextLabel", true)
                local labelText = label and string.lower(label.Text or "") or ""
                for _, identifier in ipairs(identifiers) do
                    if identifier ~= "" and (entryName == identifier or labelText == identifier) then
                        return teamName == "TeamRed" and "Red" or "Blue"
                    end
                end
            end
        end
    end
    return nil
end

local function teamOf(player)
    local ok, value = pcall(function() return player:GetAttribute("VendraMatchTeam") end)
    if ok and type(value) == "string" and value ~= "" then return value end
    return scoreboardTeamOf(player)
end

local function getMatchContext(player)
    player = player or lp
    local matchId = matchIdOf(player)
    local team = teamOf(player)
    if not matchId or not team or not hasActiveMatchFlag(player) then
        return nil, nil
    end

    local deadOk, isDead = pcall(function() return player:GetAttribute("IsDead") end)
    if deadOk and isDead == true then return nil, nil end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil, nil end

    return matchId, team
end

local function isLocalInMatch()
    local matchId = getMatchContext(lp)
    return matchId ~= nil
end

local function alive(player)
    if not player or player == lp or not hasActiveMatchFlag(player) then return false end
    local deadOk, isDead = pcall(function() return player:GetAttribute("IsDead") end)
    if deadOk and isDead == true then return false end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function isEnemy(player, localMatchId, localTeam)
    if player == lp or not alive(player) then return false end
    if not localMatchId or not localTeam then
        localMatchId, localTeam = getMatchContext(lp)
    end
    if not localMatchId or not localTeam then return false end
    if matchIdOf(player) ~= localMatchId then return false end
    if teamcheck then
        local targetTeam = teamOf(player)
        if not targetTeam or targetTeam == localTeam then return false end
    end
    return true
end

local function isVisualEnemy(player, localMatchId, localTeam)
    if player == lp or not alive(player) or not localMatchId then return false end
    if matchIdOf(player) ~= localMatchId then return false end
    if teamcheck then
        if not localTeam then return false end
        local targetTeam = teamOf(player)
        if not targetTeam or targetTeam == localTeam then return false end
    end
    return true
end

local function isAimEnemy(player)
    local localMatchId, localTeam = getMatchContext(lp)
    return isEnemy(player, localMatchId, localTeam)
end

local function getLocalPosition()
    local character = lp.Character
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if root and root:IsA("BasePart") then return root.Position end
    local camera = Workspace.CurrentCamera
    return camera and camera.CFrame.Position or Vector3.zero
end

local TARGET_PART_NAMES = {
    Cabeza = { "Head" },
    Torso = { "UpperTorso", "Torso", "LowerTorso" },
    Completo = {
        "Head", "UpperTorso", "Torso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
        "RightUpperLeg", "RightLowerLeg", "RightFoot",
        "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    },
}

local function getAimParts(character, targetPartMode)
    if not character then return {} end
    local names = TARGET_PART_NAMES[targetPartMode or silentAimSettings.TargetPart] or TARGET_PART_NAMES.Cabeza
    local parts, seen = {}, {}
    for _, name in ipairs(names) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") and not seen[part] then
            seen[part] = true
            parts[#parts + 1] = part
        end
    end
    if #parts == 0 and (targetPartMode or silentAimSettings.TargetPart) ~= "Cabeza" then
        local root = character:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then parts[1] = root end
    end
    return parts
end

local sharedRaycastParams = RaycastParams.new()
sharedRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
local sharedRaycastFilter = { nil, nil }

local function clearShot(part)
    if not wallcheck then return true end
    local camera = Workspace.CurrentCamera
    if not camera or not part or not part.Parent then return false end
    sharedRaycastFilter[1] = lp.Character
    sharedRaycastFilter[2] = part.Parent
    sharedRaycastParams.FilterDescendantsInstances = sharedRaycastFilter
    local hit = Workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, sharedRaycastParams)
    if not hit then return true end
    local instance = hit.Instance
    while instance do
        if instance == part or instance == part.Parent then return true end
        instance = instance.Parent
    end
    return false
end

local function findBestAimTarget()
    if not isLocalInMatch() then return nil, nil end
    local camera = Workspace.CurrentCamera
    if not camera then return nil, nil end
    local mode = silentAimSettings.Mode
    if mode ~= "Fov" and mode ~= "Screen" and mode ~= "360" then return nil, nil end

    local viewport = camera.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local bestMetric, bestPlayer, bestPart = math.huge, nil, nil
    for _, player in ipairs(Players:GetPlayers()) do
        if isAimEnemy(player) then
            for _, part in ipairs(getAimParts(player.Character)) do
                if clearShot(part) then
                    local metric, candidate = nil, false
                    if mode == "360" then
                        metric = (part.Position - camera.CFrame.Position).Magnitude
                        candidate = true
                    else
                        local screenPoint, onScreen = camera:WorldToViewportPoint(part.Position)
                        if onScreen and screenPoint.Z > 0 then
                            local screenDistance = (Vector2.new(screenPoint.X, screenPoint.Y) - center).Magnitude
                            if mode == "Screen" then
                                metric = screenDistance
                                candidate = true
                            elseif mode == "Fov" and screenDistance <= silentAimSettings.Fov then
                                metric = screenDistance
                                candidate = true
                            end
                        end
                    end
                    if candidate and metric < bestMetric then
                        bestMetric, bestPlayer, bestPart = metric, player, part
                    end
                end
            end
        end
    end
    return bestPlayer, bestPart
end

local function scan()
    if not silentAimSettings.Enabled then
        tgt, tgtPart = nil, nil
        lastScan = os.clock()
        return
    end
    tgt, tgtPart = findBestAimTarget()
    lastScan = os.clock()
end

local function getSilentAimTarget()
    if not silentAimSettings.Enabled then return nil, nil end
    if not tgt or not tgtPart or os.clock() - lastScan > 0.5 then
        local scanOk = pcall(scan)
        if not scanOk then return nil, nil end
    end
    if tgt and tgtPart and tgtPart:IsA("BasePart") then
        local character = tgt.Character
        if character and tgtPart:IsDescendantOf(character) then
            return tgt, tgtPart
        end
    end
    return nil, nil
end

local movementSettings = {
    SpeedEnabled = false, Speed = 0,
    FlyEnabled = false, FlySpeed = 60,
    TelaEnabled = false, TelaTurnSpeed = 45,
    SuperJumpEnabled = false, JumpPower = 95,
    InfiniteLeap = false, WallClimb = false,
    FovEnabled = false, Fov = 70,
}
local movementSaved = { PlatformStand = nil, AutoRotate = nil, FieldOfView = nil }
local movementCurrentHumanoid = nil
local rainbowSettings = { Enabled = false, Hue = 0 }
local rainbowOriginals = setmetatable({}, { __mode = "k" })
local rainbowTool = nil
local hitboxSettings = { Enabled = false, Size = 3.5, Color = Color3.fromRGB(255, 70, 70), Invisible = true }
local hitboxAdornments = {}
local hitboxAccumulator = 0
local customSoundSettings = {
    KillEnabled = false, ShotEnabled = false, ReloadEnabled = false,
    KillId = "114361503583259", ShotId = "680140087", ReloadId = "138084889",
}
local customSoundOriginals = setmetatable({}, { __mode = "k" })
local customSoundWatchers = {}

local function getCurrentTool()
    local character = lp.Character
    return character and character:FindFirstChildOfClass("Tool") or nil
end

local function restoreMovementState()
    local character = lp.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if movementSaved.PlatformStand ~= nil then
            pcall(function() humanoid.PlatformStand = movementSaved.PlatformStand end)
        end
        if movementSaved.AutoRotate ~= nil then
            pcall(function() humanoid.AutoRotate = movementSaved.AutoRotate end)
        end
    end
    local camera = Workspace.CurrentCamera
    if camera and movementSaved.FieldOfView ~= nil then
        pcall(function() camera.FieldOfView = movementSaved.FieldOfView end)
    end
    movementSaved.PlatformStand = nil
    movementSaved.AutoRotate = nil
    movementSaved.FieldOfView = nil
    movementCurrentHumanoid = nil
end

local function applyRainbowToTool(tool)
    if rainbowTool ~= tool then
        for instance, original in pairs(rainbowOriginals) do
            if instance and instance.Parent then
                pcall(function()
                    if instance:IsA("BasePart") then instance.Color = original.Color end
                    if instance:IsA("SpecialMesh") then instance.VertexColor = original.VertexColor end
                end)
            end
            rainbowOriginals[instance] = nil
        end
        rainbowTool = tool
        if tool then
            for _, instance in ipairs(tool:GetDescendants()) do
                if instance:IsA("BasePart") and not rainbowOriginals[instance] then
                    rainbowOriginals[instance] = { Color = instance.Color }
                elseif instance:IsA("SpecialMesh") and not rainbowOriginals[instance] then
                    rainbowOriginals[instance] = { VertexColor = instance.VertexColor }
                end
            end
        end
    end
end

local function updateRainbow(deltaTime)
    if not rainbowSettings.Enabled then
        if rainbowTool then applyRainbowToTool(nil) end
        return
    end
    local tool = getCurrentTool()
    if not tool then
        if rainbowTool then applyRainbowToTool(nil) end
        return
    end
    applyRainbowToTool(tool)
    rainbowSettings.Hue = (rainbowSettings.Hue + deltaTime * 0.35) % 1
    local color = Color3.fromHSV(rainbowSettings.Hue, 1, 1)
    for instance, original in pairs(rainbowOriginals) do
        if not instance or not instance.Parent then
            rainbowOriginals[instance] = nil
        else
            pcall(function()
                if instance:IsA("BasePart") then instance.Color = color end
                if instance:IsA("SpecialMesh") then instance.VertexColor = Vector3.new(color.R, color.G, color.B) end
            end)
        end
    end
end

local function clearHitboxAdornment(player)
    local hitbox = hitboxAdornments[player]
    hitboxAdornments[player] = nil
    if hitbox and hitbox.Parent then pcall(function() hitbox:Destroy() end) end
end

local function clearAllHitboxAdornments()
    for player in pairs(hitboxAdornments) do clearHitboxAdornment(player) end
end

local function updateHitboxAdornments()
    if not hitboxSettings.Enabled then
        clearAllHitboxAdornments()
        return
    end
    local localMatchId, localTeam = getMatchContext(lp)
    if not localMatchId or not localTeam then
        clearAllHitboxAdornments()
        return
    end

    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player, localMatchId, localTeam) and count < 6 then
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                count = count + 1
                local hitbox = hitboxAdornments[player]
                if hitbox and (not hitbox:IsA("BasePart") or hitbox.Parent ~= character
                    or hitbox:GetAttribute("SilentHubOwned") ~= true) then
                    clearHitboxAdornment(player)
                    hitbox = nil
                end
                if not hitbox then
                    hitbox = Instance.new("Part")
                    hitbox.Name = "GhostHitbox"
                    hitbox:SetAttribute("SilentHubOwned", true)

                    hitbox.Anchored = true
                    hitbox.CanCollide = false
                    hitbox.CanTouch = false
                    hitbox.CanQuery = true
                    hitbox.Massless = true
                    hitbox.CastShadow = false
                    hitbox.Material = Enum.Material.Neon
                    hitbox.Parent = character
                    hitboxAdornments[player] = hitbox
                end
                hitbox.CFrame = root.CFrame
                local size = math.clamp(tonumber(hitboxSettings.Size) or 3.5, 3, 15)
                hitbox.Size = Vector3.new(size, size, size)
                hitbox.Color = hitboxSettings.Color
                hitbox.Transparency = hitboxSettings.Invisible and 1 or 0.92
            else
                clearHitboxAdornment(player)
            end
        else
            clearHitboxAdornment(player)
        end
    end
    for player in pairs(hitboxAdornments) do
        if player.Parent ~= Players then clearHitboxAdornment(player) end
    end
end

local function customSoundAsset(raw)
    local id = tostring(raw or ""):gsub("%D", "")
    if id == "" then return nil end
    return "rbxassetid://" .. id
end

local function localToolSound(sound)
    if not sound or not sound:IsA("Sound") then return false end
    local character = lp.Character
    local backpack = lp:FindFirstChildOfClass("Backpack")
    return (character and sound:IsDescendantOf(character)) or (backpack and sound:IsDescendantOf(backpack)) or false
end

local function customSoundRule(sound)
    local name = sound.Name:lower()
    if name == "gunkill" or name == "killsound" or name == "kill sound" then
        return "KillEnabled", "KillId"
    elseif name == "beam" or name == "gunshot" then
        return "ShotEnabled", "ShotId"
    elseif name == "reload" then
        return "ReloadEnabled", "ReloadId"
    end
    return nil, nil
end

local customKillSound = Instance.new("Sound")
customKillSound.Name = "KillSound"
customKillSound.Volume = 1
customKillSound.Looped = false
customKillSound.Parent = SoundService

local function playCustomKillSound()
    if not customSoundSettings.KillEnabled then return end
    local asset = customSoundAsset(customSoundSettings.KillId)
    if not asset then return end
    pcall(function()
        customKillSound:Stop()
        customKillSound.SoundId = asset
        customKillSound.TimePosition = 0
        customKillSound:Play()
    end)
end

local function applyCustomSound(sound)
    if not localToolSound(sound) then return end
    local enabledKey, idKey = customSoundRule(sound)
    if not enabledKey then return end
    if not customSoundOriginals[sound] then
        customSoundOriginals[sound] = {
            SoundId = sound.SoundId,
            Volume = sound.Volume,
        }
    end
    local original = customSoundOriginals[sound]
    local asset = customSoundAsset(customSoundSettings[idKey])
    if enabledKey == "KillEnabled" then
        if customSoundSettings.KillEnabled and asset then
            pcall(function() sound.Volume = 0 end)
        else
            pcall(function()
                sound.SoundId = original.SoundId
                sound.Volume = original.Volume
            end)
        end
    elseif customSoundSettings[enabledKey] and asset then
        pcall(function() sound.SoundId = asset end)
    else
        pcall(function() sound.SoundId = original.SoundId end)
    end
end

local function refreshCustomSounds()
    local character = lp.Character
    local backpack = lp:FindFirstChildOfClass("Backpack")
    for sound in pairs(customSoundOriginals) do
        if not sound.Parent then customSoundOriginals[sound] = nil end
    end
    if character then
        for _, item in ipairs(character:GetDescendants()) do
            if item:IsA("Sound") then applyCustomSound(item) end
        end
    end
    if backpack then
        for _, item in ipairs(backpack:GetDescendants()) do
            if item:IsA("Sound") then applyCustomSound(item) end
        end
    end
end

local function restoreCustomSounds()
    for sound, original in pairs(customSoundOriginals) do
        if sound and sound.Parent then
            pcall(function()
                sound.SoundId = original.SoundId
                sound.Volume = original.Volume
            end)
        end
        customSoundOriginals[sound] = nil
    end
end

local function bindCustomSoundWatchers()
    for _, connection in ipairs(customSoundWatchers) do pcall(function() connection:Disconnect() end) end
    table.clear(customSoundWatchers)
    local function watch(container)
        if not container then return end
        customSoundWatchers[#customSoundWatchers + 1] = container.DescendantAdded:Connect(function(instance)
            if instance:IsA("Sound") then task.defer(applyCustomSound, instance) end
        end)
    end
    watch(lp.Character)
    watch(lp:FindFirstChildOfClass("Backpack"))
end

trackConnection(lp.CharacterAdded:Connect(function()
    task.defer(function()
        bindCustomSoundWatchers()
        refreshCustomSounds()
    end)
end))
trackConnection(lp.ChildAdded:Connect(function(child)
    if child:IsA("Backpack") then
        task.defer(function()
            bindCustomSoundWatchers()
            refreshCustomSounds()
        end)
    end
end))

trackConnection(RunService.RenderStepped:Connect(function(deltaTime)
    local character = lp.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local camera = Workspace.CurrentCamera

    if humanoid and humanoid ~= movementCurrentHumanoid then
        movementCurrentHumanoid = humanoid
        movementSaved.PlatformStand = humanoid.PlatformStand
        movementSaved.AutoRotate = humanoid.AutoRotate
    end

    if root and humanoid and humanoid.Health > 0 then
        if movementSettings.SpeedEnabled and movementSettings.Speed > 0 and humanoid.MoveDirection.Magnitude > 0 then
            root.CFrame = root.CFrame + humanoid.MoveDirection * movementSettings.Speed * deltaTime
        end
        if movementSettings.WallClimb and humanoid.MoveDirection.Magnitude > 0 then
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, 25, velocity.Z)
        end
        if movementSettings.FlyEnabled then
            local move = humanoid.MoveDirection
            local vertical = 0
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vertical = vertical + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then vertical = vertical - 1 end
            local flyVector = move + Vector3.new(0, vertical, 0)
            if flyVector.Magnitude > 0 then
                root.CFrame = root.CFrame + flyVector.Unit * movementSettings.FlySpeed * deltaTime
            end
            root.AssemblyLinearVelocity = Vector3.zero
        end
        if movementSettings.TelaEnabled and camera then
            local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
            if right.Magnitude > 0.001 then
                right = right.Unit
                local side = humanoid.MoveDirection:Dot(right)
                if math.abs(side) >= 0.35 then
                    if movementSaved.AutoRotate == nil then movementSaved.AutoRotate = humanoid.AutoRotate end
                    humanoid.AutoRotate = false
                    local target = CFrame.lookAt(root.Position, root.Position + (side > 0 and right or -right))
                    root.CFrame = root.CFrame:Lerp(target, 1 - math.exp(-movementSettings.TelaTurnSpeed * deltaTime))
                end
            end
        elseif movementSettings.TelaEnabled == false and movementSaved.AutoRotate ~= nil then
            humanoid.AutoRotate = movementSaved.AutoRotate
        end
        if movementSettings.FlyEnabled then
            if movementSaved.PlatformStand == nil then movementSaved.PlatformStand = humanoid.PlatformStand end
            humanoid.PlatformStand = false
        end
    end

    if movementSettings.FovEnabled and camera then
        if movementSaved.FieldOfView == nil then movementSaved.FieldOfView = camera.FieldOfView end
        camera.FieldOfView = movementSettings.Fov
    end

    updateRainbow(deltaTime)
    hitboxAccumulator = hitboxAccumulator + deltaTime
    if hitboxAccumulator >= (1 / 30) then
        hitboxAccumulator = 0
        pcall(updateHitboxAdornments)
    end
end))

trackConnection(UserInputService.JumpRequest:Connect(function()
    local character = lp.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 then return end
    if movementSettings.SuperJumpEnabled and root and humanoid.FloorMaterial ~= Enum.Material.Air then
        local velocity = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, movementSettings.JumpPower, velocity.Z)
    elseif movementSettings.InfiniteLeap then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

bindCustomSoundWatchers()

local visualEntries = {}
local visualConnections = {}
local visualAccumulator = 0
local MAX_ESP_TARGETS = 5
local overlayGui
local overlayParent

local function resolveOverlayParent()
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then return result end
    end

    local serviceOk, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if serviceOk and coreGui then
        local parentOk = pcall(function()
            local probe = Instance.new("Folder")
            probe.Name = "OverlayProbe"
            probe.Parent = coreGui
            probe:Destroy()
        end)
        if parentOk then return coreGui end
    end

    return lp:WaitForChild("PlayerGui")
end

overlayParent = resolveOverlayParent()
local overlayOk, overlayInstance = pcall(function()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Visuals"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Parent = overlayParent
    return gui
end)
if overlayOk then
    overlayGui = overlayInstance
else
    overlayParent = lp:WaitForChild("PlayerGui")
end

local fovDrawing
local fovScreenGui
local fovGuiCircle

local function hideFovIndicator()
    if fovDrawing then
        pcall(function() fovDrawing.Visible = false end)
    end
    if fovGuiCircle then
        pcall(function() fovGuiCircle.Visible = false end)
    end
end

local function destroyFovIndicator()
    if fovDrawing then
        pcall(function() fovDrawing.Visible = false end)
        pcall(function() fovDrawing:Remove() end)
        fovDrawing = nil
    end
    if fovScreenGui then
        pcall(function() fovScreenGui:Destroy() end)
        fovScreenGui = nil
        fovGuiCircle = nil
    end
end

local function createFovGuiCircle()
    local parent = overlayParent or lp:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FovIndicator"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 1000
    screenGui.Parent = parent

    local circle = Instance.new("Frame")
    circle.Name = "FovCircle"
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.Visible = false
    circle.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = circle

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 1.5
    stroke.Transparency = 0
    stroke.Parent = circle

    fovScreenGui = screenGui
    fovGuiCircle = circle
end

local function ensureFovIndicator()
    if fovDrawing or fovGuiCircle then return end

    local drawingApi
    pcall(function() drawingApi = Drawing end)
    if drawingApi and type(drawingApi.new) == "function" then
        local ok, circle = pcall(function()
            local object = drawingApi.new("Circle")
            object.Filled = false
            object.NumSides = 64
            object.Thickness = 1.5
            object.Transparency = 1
            object.Color = Color3.fromRGB(255, 255, 255)
            object.Visible = false
            return object
        end)
        if ok and circle then
            fovDrawing = circle
            return
        end
    end

    pcall(createFovGuiCircle)
end

local function updateFovIndicator()
    if not isLocalInMatch()
        or not silentAimSettings.ShowFov
        or silentAimSettings.Mode ~= "Fov" then
        hideFovIndicator()
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        hideFovIndicator()
        return
    end

    ensureFovIndicator()
    local viewport = camera.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local radius = silentAimSettings.Fov

    if fovDrawing then
        pcall(function()
            fovDrawing.Position = center
            fovDrawing.Radius = radius
            fovDrawing.Visible = true
        end)
    elseif fovGuiCircle then
        pcall(function()
            fovGuiCircle.Position = UDim2.fromOffset(center.X, center.Y)
            fovGuiCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
            fovGuiCircle.Visible = true
        end)
    end
end

local function colorToHex(color)
    return string.format("#%02X%02X%02X",
        math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
        math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
        math.clamp(math.floor(color.B * 255 + 0.5), 0, 255))
end

local function destroyTracer(entry)
    local tracer = entry and entry.Tracer
    if not tracer then return end
    entry.Tracer = nil
    if tracer.Kind == "Drawing" then
        pcall(function() tracer.Object.Visible = false end)
        pcall(function() tracer.Object:Remove() end)
    elseif tracer.Object then
        pcall(function() tracer.Object:Destroy() end)
    end
end

local function destroyVisualEntry(player)
    local entry = visualEntries[player]
    if not entry then return end
    visualEntries[player] = nil
    destroyTracer(entry)
    if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
    if entry.Billboard then pcall(function() entry.Billboard:Destroy() end) end
end

local function clearVisuals()
    local playersToClear = {}
    for player in pairs(visualEntries) do
        playersToClear[#playersToClear + 1] = player
    end
    for _, player in ipairs(playersToClear) do
        destroyVisualEntry(player)
    end
end

local function makeTracer()
    local drawingApi
    pcall(function() drawingApi = Drawing end)
    if drawingApi and type(drawingApi.new) == "function" then
        local ok, line = pcall(function()
            local object = drawingApi.new("Line")
            object.Thickness = 1.5
            object.Transparency = 1
            object.Visible = false
            return object
        end)
        if ok and line then
            return { Kind = "Drawing", Object = line }
        end
    end

    if not overlayGui or not overlayGui.Parent then return nil end
    local ok, line = pcall(function()
        local object = Instance.new("Frame")
        object.Name = "Tracer"
        object.BorderSizePixel = 0
        object.AnchorPoint = Vector2.new(0, 0.5)
        object.Size = UDim2.fromOffset(0, 2)
        object.Visible = false
        object.Parent = overlayGui
        return object
    end)
    if ok and line then
        return { Kind = "Gui", Object = line }
    end
    return nil
end

local function updateTracer(entry, camera)
    if not visualSettings.Tracers then
        destroyTracer(entry)
        return
    end
    local root = entry.Root
    if not root or not root.Parent then
        destroyTracer(entry)
        return
    end

    local point, onScreen = camera:WorldToViewportPoint(root.Position)
    local viewport = camera.ViewportSize
    local offscreen = not onScreen or point.Z <= 0
        or point.X < 0 or point.Y < 0
        or point.X > viewport.X or point.Y > viewport.Y
    if offscreen then
        if entry.Tracer then
            if entry.Tracer.Kind == "Drawing" then
                pcall(function() entry.Tracer.Object.Visible = false end)
            else
                pcall(function() entry.Tracer.Object.Visible = false end)
            end
        end
        return
    end

    if not entry.Tracer then
        entry.Tracer = makeTracer()
    end
    if not entry.Tracer then return end

    local origin = Vector2.new(viewport.X * 0.5, 0)
    local destination = Vector2.new(point.X, point.Y)
    local tracer = entry.Tracer
    if tracer.Kind == "Drawing" then
        pcall(function()
            tracer.Object.From = origin
            tracer.Object.To = destination
            tracer.Object.Color = visualSettings.Color
            tracer.Object.Visible = true
        end)
    else
        local delta = destination - origin
        pcall(function()
            tracer.Object.Position = UDim2.fromOffset(origin.X, origin.Y)
            tracer.Object.Size = UDim2.fromOffset(delta.Magnitude, 2)
            tracer.Object.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            tracer.Object.BackgroundColor3 = visualSettings.Color
            tracer.Object.Visible = true
        end)
    end
end

local function createVisualEntry(player, character, root)
    local highlight, billboard
    local ok, entry = pcall(function()
        highlight = Instance.new("Highlight")
        highlight.Name = "ESPHighlight"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 1
        highlight.OutlineTransparency = 0
        highlight.OutlineColor = visualSettings.Color
        highlight.Adornee = character
        highlight.Enabled = visualSettings.Glow
        highlight.Parent = Workspace

        billboard = Instance.new("BillboardGui")
        billboard.Name = "ESPInfo"
        billboard.Size = UDim2.new(0, 200, 0, 75)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Adornee = root
        billboard.Parent = overlayParent

        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextStrokeTransparency = 1
        label.RichText = true
        label.Font = Enum.Font.SourceSansBold
        label.TextSize = 14
        label.TextYAlignment = Enum.TextYAlignment.Bottom
        label.Text = ""
        label.Parent = billboard

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1.2
        stroke.Parent = label

        return {
            Character = character,
            Root = root,
            Highlight = highlight,
            Billboard = billboard,
            Label = label,
            LastDistance = -1,
            Player = player,
        }
    end)

    if not ok then
        if highlight then pcall(function() highlight:Destroy() end) end
        if billboard then pcall(function() billboard:Destroy() end) end
        return nil
    end
    return entry
end

local function updateVisuals()
    if not _G.sa_on or not visualSettings.ESP then
        clearVisuals()
        return
    end

    local visualMatchId = matchIdOf(lp)
    local visualTeam = teamOf(lp)
    if not visualMatchId then
        clearVisuals()
        return
    end

    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= lp and isVisualEnemy(player, visualMatchId, visualTeam) then
            local character = player.Character
            local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
            if character and root and root:IsA("BasePart") and count < MAX_ESP_TARGETS then
                count = count + 1
                local entry = visualEntries[player]
                if entry and (entry.Character ~= character or not entry.Root or not entry.Root.Parent) then
                    destroyVisualEntry(player)
                    entry = nil
                end
                if not entry then
                    entry = createVisualEntry(player, character, root)
                    if entry then
                        visualEntries[player] = entry
                    end
                end

                if entry then
                    entry.Root = root
                    entry.Highlight.Adornee = character
                    entry.Highlight.OutlineColor = visualSettings.Color
                    entry.Highlight.Enabled = visualSettings.Glow
                    entry.Billboard.Adornee = root

                    local textParts = {}
                    if visualSettings.Name then
                        textParts[#textParts + 1] = string.format('<font color="%s">%s</font>', colorToHex(visualSettings.Color), player.Name)
                    end
                    if visualSettings.Distance then
                        local distance = (getLocalPosition() - root.Position).Magnitude
                        textParts[#textParts + 1] = string.format('<font size="11" color="#BDC3C7">%dm</font>', math.floor(distance + 0.5))
                    end
                    entry.Label.Text = table.concat(textParts, "\n")
                    entry.Billboard.Enabled = #textParts > 0
                end
            else
                destroyVisualEntry(player)
            end
        else
            destroyVisualEntry(player)
        end
    end

    local removedPlayers = {}
    for player in pairs(visualEntries) do
        if player.Parent ~= Players then
            removedPlayers[#removedPlayers + 1] = player
        end
    end
    for _, player in ipairs(removedPlayers) do
        destroyVisualEntry(player)
    end
end

local function updateTracerVisuals()
    if not _G.sa_on or not visualSettings.ESP or not visualSettings.Tracers then
        for _, entry in pairs(visualEntries) do destroyTracer(entry) end
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    for _, entry in pairs(visualEntries) do
        if entry.Root and entry.Root.Parent then
            updateTracer(entry, camera)
        else
            destroyTracer(entry)
        end
    end
end

trackConnection(RunService.Heartbeat:Connect(function(deltaTime)
    visualAccumulator = visualAccumulator + deltaTime
    if visualAccumulator >= (1 / 15) then
        visualAccumulator = 0
        pcall(updateVisuals)
    end
end))
local renderAccumulator = 0
trackConnection(RunService.RenderStepped:Connect(function(deltaTime)
    renderAccumulator = renderAccumulator + deltaTime
    if renderAccumulator < (1 / 30) then return end
    renderAccumulator = 0
    if visualSettings.ESP and visualSettings.Tracers then pcall(updateTracerVisuals) end
    if silentAimSettings.ShowFov and silentAimSettings.Mode == "Fov" then pcall(updateFovIndicator) end
end))
trackConnection(Players.PlayerRemoving:Connect(function(player)
    destroyVisualEntry(player)
    local connection = visualConnections[player]
    visualConnections[player] = nil
    if connection then untrackConnection(connection) end
end))
trackConnection(Players.PlayerAdded:Connect(function(player)
    local connection = player.CharacterAdded:Connect(function()
        destroyVisualEntry(player)
    end)
    visualConnections[player] = connection
    trackConnection(connection)
end))
for _, player in ipairs(Players:GetPlayers()) do
    visualConnections[player] = trackConnection(player.CharacterAdded:Connect(function()
        destroyVisualEntry(player)
    end))
end

local skyboxData = {
    ["Twilight"] = {"264908339", "264907909", "264909420", "264909758", "264908886", "264907379"},
    ["Nebula"] = {"159454299", "159454296", "159454293", "159454286", "159454300", "159454288"},
    ["Vaporwave"] = {"1417494030", "1417494146", "1417494253", "1417494402", "1417494499", "1417494643"},
    ["Redshift"] = {"401664839", "401664862", "401664960", "401664881", "401664901", "401664936"},
    ["Blue Stars"] = {"149397684", "149397686", "149397688", "149397692", "149397697", "149397702"},
    ["Sakura Pink Sky"] = {"271042516", "271077243", "271042556", "271042310", "271042467", "271077958"},
    ["Desert"] = {"1013852", "1013853", "1013850", "1013851", "1013849", "1013854"},
    ["DaBaby"] = {"7245418472", "7245418472", "7245418472", "7245418472", "7245418472", "7245418472"},
    ["Minecraft"] = {"1876545003", "1876544331", "1876542941", "1876543392", "1876543764", "1876544642"},
    ["SpongeBob"] = {"7633178166", "7633178166", "7633178166", "7633178166", "7633178166", "7633178166"},
    ["Skibidi"] = {"14952256113", "14952256113", "14952256113", "14952256113", "14952256113", "14952256113"},
    ["Blaze"] = {"150939022", "150939038", "150939047", "150939056", "150939063", "150939082"},
    ["Pussy Cat"] = {"11154422902", "11154422902", "11154422902", "11154422902", "11154422902", "11154422902"},
    ["Among Us"] = {"5752463190", "5752463190", "5752463190", "5752463190", "5752463190", "5752463190"},
    ["Space Wave"] = {"16262356578", "16262358026", "16262360469", "16262362003", "16262363873", "16262366016"},
    ["Space Wave 2"] = {"1233158420", "1233158838", "1233157105", "1233157640", "1233157995", "1233159158"},
    ["Turquoise Wave"] = {"47974894", "47974690", "47974821", "47974776", "47974859", "47974909"},
    ["Dark Night"] = {"6285719338", "6285721078", "6285722964", "6285724682", "6285726335", "6285730635"},
    ["White Galaxy"] = {"5540798456", "5540799894", "5540801779", "5540801192", "5540799108", "5540800635"},
}
local skyboxFaceUrlMaps = {
    ["Hakari Hananozo"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NjEzMTVf/SkyBk.tex", SkyboxDn="https://od.lk/d/NjNfOTg0NjEzMTZf/Skydn.tex", SkyboxFt="https://od.lk/s/NjNfOTg0NjEzMTdf/SkyFt.tex", SkyboxLf="https://od.lk/s/NjNfOTg0NjEzMThf/SkyIf.tex", SkyboxRt="https://od.lk/d/NjNfOTg0NjEzMTlf/SkyRt.tex", SkyboxUp="https://od.lk/d/NjNfOTg0NjEzMjBf/SkyUp.tex" },
    ["ItsukiNakano"] = { SkyboxBk="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano/ItsukiNakano_Bk.png", SkyboxDn="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano/ItsukiNakano_Dn.png", SkyboxFt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano/ItsukiNakano_Ft.png", SkyboxLf="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano/ItsukiNakano_Lf.png", SkyboxRt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano/ItsukiNakano_Rt.png", SkyboxUp="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano/ItsukiNakano_Up.png" },
    ["ItsukiNakano2"] = { SkyboxBk="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano2/ItsukiNakano2_Bk.png", SkyboxDn="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano2/ItsukiNakano2_Dn.png", SkyboxFt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano2/ItsukiNakano2_Ft.png", SkyboxLf="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano2/ItsukiNakano2_Lf.png", SkyboxRt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano2/ItsukiNakano2_Rt.png", SkyboxUp="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/ItsukiNakano2/ItsukiNakano2_Up.png" },
    ["MaiSakurajima"] = { SkyboxBk="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MaiSakurajima/back.png", SkyboxDn="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MaiSakurajima/down.png", SkyboxFt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MaiSakurajima/front.png", SkyboxLf="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MaiSakurajima/left.png", SkyboxRt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MaiSakurajima/right.png", SkyboxUp="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MaiSakurajima/top.png" },
    ["MikuNakano"] = { SkyboxBk="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MikuNakano/MikuNakano_Bk.png", SkyboxDn="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MikuNakano/MikuNakano_Dn.png", SkyboxFt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MikuNakano/MikuNakano_Ft.png", SkyboxLf="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MikuNakano/MikuNakano_Lf.png", SkyboxRt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MikuNakano/MikuNakano_Rt.png", SkyboxUp="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/MikuNakano/MikuNakano_Up.png" },
    ["Nino Nakano"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NjQyODJf/left1.png", SkyboxDn="https://od.lk/d/NjNfOTg0NjQyNzlf/down.png", SkyboxFt="https://od.lk/d/NjNfOTg0NjQyODBf/front.png", SkyboxLf="https://od.lk/d/NjNfOTg0NjQyNzhf/back.png", SkyboxRt="https://od.lk/d/NjNfOTg0NjQyODNf/right1.png", SkyboxUp="https://od.lk/d/NjNfOTg0NjQyODFf/up.png" },
    ["Nino Nakano 2"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NjQyNTNf/if.png", SkyboxDn="https://od.lk/d/NjNfOTg0NjQyNTVf/dn.png", SkyboxFt="https://od.lk/d/NjNfOTg0NjQyNTZf/bk.png", SkyboxLf="https://od.lk/d/NjNfOTg0NjQyNTRf/ft.png", SkyboxRt="https://od.lk/d/NjNfOTg0NjQyNTJf/rt.png", SkyboxUp="https://od.lk/d/NjNfOTg0NjQyNTBf/up.png" },
    ["Rias Gremory"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NzkyOTNf/leftRias.png", SkyboxDn="https://od.lk/d/NjNfOTg0NzkyOThf/downRias.png", SkyboxFt="https://od.lk/d/NjNfOTg0NzkyOTVf/front%20Rias.png", SkyboxLf="https://od.lk/d/NjNfOTg0NzkyOTRf/BackRias.png", SkyboxRt="https://od.lk/d/NjNfOTg0NzkyOTFf/RightRias.png", SkyboxUp="https://od.lk/d/NjNfOTg0NzkyOTJf/UpRias.png" },
    ["Saki Saki"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NjQyNjZf/back1.png", SkyboxDn="https://od.lk/d/NjNfOTg0NjQyNjdf/down1.png", SkyboxFt="https://od.lk/d/NjNfOTg0NjQyNjhf/front1.png", SkyboxLf="https://od.lk/d/NjNfOTg0NjQyNzBf/left.png", SkyboxRt="https://od.lk/d/NjNfOTg0NjQyNzNf/right.png", SkyboxUp="https://od.lk/d/NjNfOTg0NjQyNjlf/Up1.png" },
    ["Waguri"] = { SkyboxBk="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/Waguri/waguri_ft.png", SkyboxDn="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/Waguri/waguri_dn.png", SkyboxFt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/Waguri/waguri_bk.png", SkyboxLf="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/Waguri/waguri_rt.png", SkyboxRt="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/Waguri/waguri_lf.png", SkyboxUp="https://raw.githubusercontent.com/StyearX/Custom-skybox/main/Waguri/waguri_up.png" },
    ["Xenovia Quarta"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NjM0ODlf/ft.png", SkyboxDn="https://od.lk/d/NjNfOTg0NjM0OTBf/dn.png", SkyboxFt="https://od.lk/d/NjNfOTg0NjM0OTFf/bk.png", SkyboxLf="https://od.lk/d/NjNfOTg0NjM0ODhf/if.png", SkyboxRt="https://od.lk/d/NjNfOTg0NjM0ODdf/rt.png", SkyboxUp="https://od.lk/d/NjNfOTg0NjM0ODZf/up.png" },
    ["Yotsuba Nakano"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NzkzMzFf/YotsubaBk.png", SkyboxDn="https://od.lk/d/NjNfOTg0NzkzMzNf/YotsubaDn.png", SkyboxFt="https://od.lk/d/NjNfOTg0NzkzMzRf/YotsubaFt.png", SkyboxLf="https://od.lk/d/NjNfOTg0NzkzMzZf/YotsubaLeft.png", SkyboxRt="https://od.lk/d/NjNfOTg0NzkzMzdf/YotsubaRt.png", SkyboxUp="https://od.lk/d/NjNfOTg0NzkzMzhf/YotsubaUp.png" },
    ["Alya"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NzkzMTFf/bk.png", SkyboxDn="https://od.lk/d/NjNfOTg0NzkzMTJf/dn.png", SkyboxFt="https://od.lk/d/NjNfOTg0NzkzMTNf/ft.png", SkyboxLf="https://od.lk/d/NjNfOTg0NzkzMTRf/if.png", SkyboxRt="https://od.lk/d/NjNfOTg0NzkzMTZf/Rt.png", SkyboxUp="https://od.lk/d/NjNfOTg0NzkzMTVf/Up.png" },
    ["Alya 2"] = { SkyboxBk="https://od.lk/d/NjNfOTg0NzkzMjBf/AlyaBk.png", SkyboxDn="https://od.lk/d/NjNfOTg0NzkzMjFf/alyaDn.png", SkyboxFt="https://od.lk/d/NjNfOTg0NzkzMjJf/AlyaFt.png", SkyboxLf="https://od.lk/d/NjNfOTg0NzkzMjNf/AlyaLf.png", SkyboxRt="https://od.lk/d/NjNfOTg0NzkzMjRf/AlyaRt.png", SkyboxUp="https://od.lk/d/NjNfOTg0NzkzMjVf/AlyaUp.png" },
}
local SKYBOX_FACE_ORDER = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
local skyboxNames = { "Original" }
for name in pairs(skyboxData) do skyboxNames[#skyboxNames + 1] = name end
for name in pairs(skyboxFaceUrlMaps) do skyboxNames[#skyboxNames + 1] = name end
table.sort(skyboxNames, function(a, b)
    if a == "Original" then return true end
    if b == "Original" then return false end
    return a < b
end)

local function executorHttpGetText(url)
    if type(url) ~= "string" or not string.match(url, "^https?://") or #url > 2048 then
        return nil, "URL inválida"
    end

    local candidates = {}
    local function addCandidate(fn, label)
        if type(fn) ~= "function" then return end
        for _, item in ipairs(candidates) do
            if item.fn == fn then return end
        end
        candidates[#candidates + 1] = { fn = fn, label = label }
    end
    addCandidate(request, "request")
    addCandidate(http_request, "http_request")
    if type(syn) == "table" then addCandidate(syn.request, "syn.request") end
    if type(http) == "table" then addCandidate(http.request, "http.request") end

    for _, candidate in ipairs(candidates) do
        local ok, response = pcall(function()
            return candidate.fn({ Url = url, URL = url, Method = "GET" })
        end)
        if ok and type(response) == "table" then
            local body = response.Body or response.body or response.ResponseBody or response.responseBody
            local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status)
            if type(body) == "string" and body ~= "" and (not status or (status >= 200 and status < 300)) then
                return body
            end
        end
    end

    local nativeOk, body = pcall(function() return game:HttpGet(url, true) end)
    if nativeOk and type(body) == "string" and body ~= "" then
        return body
    end
    return nil, "No hay un método HTTP compatible"
end

local AVATAR_EXTRAS_BASE_URL = "https://raw.githubusercontent.com/api-Silent/Extras/main/"
local AVATAR_BRIDGE_URL = AVATAR_EXTRAS_BASE_URL .. "Extras/AvatarBridge.lua"
local AVATAR_SKINS_URL = AVATAR_EXTRAS_BASE_URL .. "SnowX-Skins.lua"
local AVATAR_ACCESSORIES_URL = AVATAR_EXTRAS_BASE_URL .. "SnowX-Accessories.lua"

local function getAvatarExtrasConnection()
    local current = _G.__SnowXExtrasConnection
    if type(current) == "table" and type(current.register) == "function" then
        return current
    end

    local source, fetchError = executorHttpGetText(AVATAR_BRIDGE_URL)
    if not source then return nil, "No se pudo obtener AvatarBridge: " .. tostring(fetchError) end
    if type(loadstring) ~= "function" then return nil, "loadstring no está disponible" end

    local chunk, compileError = loadstring(source)
    if type(chunk) ~= "function" then return nil, "Error compilando AvatarBridge: " .. tostring(compileError) end
    local ok, connection = pcall(chunk, _G.__SnowXAvatarBridge)
    if not ok or type(connection) ~= "table" then
        return nil, "Error inicializando AvatarBridge: " .. tostring(connection)
    end
    _G.__SnowXExtrasConnection = connection
    return connection
end

local function openAvatarSystem(systemName)
    if systemName ~= "skins" and systemName ~= "accessories" then return end

    local connection, connectionError = getAvatarExtrasConnection()
    if not connection then
        warn("[SnowX Extras] " .. tostring(connectionError))
        return
    end

    if type(connection.get) ~= "function" or type(connection.register) ~= "function" then
        warn("[SnowX Extras] AvatarBridge no expone la API de conexión esperada.")
        return
    end
    local openMethod = systemName == "skins" and connection.openSkins or connection.openAccessories
    local existingApi = connection.get(systemName)
    if type(existingApi) == "table" and type(openMethod) == "function" then
        local opened, openError = openMethod()
        if opened then return end
        if openError ~= "Skins todavía no está ejecutándose"
            and openError ~= "Accessories todavía no está ejecutándose" then
            warn("[SnowX Extras] " .. tostring(openError))
            return
        end
    end

    local moduleUrl = systemName == "skins" and AVATAR_SKINS_URL or AVATAR_ACCESSORIES_URL
    local source, fetchError = executorHttpGetText(moduleUrl)
    if not source then
        warn("[SnowX Extras] " .. systemName .. ": " .. tostring(fetchError))
        return
    end
    if type(loadstring) ~= "function" then
        warn("[SnowX Extras] loadstring no está disponible")
        return
    end

    local chunk, compileError = loadstring(source)
    if type(chunk) ~= "function" then
        warn("[SnowX Extras] Error compilando " .. systemName .. ": " .. tostring(compileError))
        return
    end

    local runOk, api = pcall(chunk, connection.bridge)
    if not runOk or type(api) ~= "table" then
        warn("[SnowX Extras] Error ejecutando " .. systemName .. ": " .. tostring(api))
        return
    end
    connection.register(systemName, api)

    local opened, openError
    if systemName == "skins" then
        opened, openError = connection.openSkins()
    else
        opened, openError = connection.openAccessories()
    end
    if not opened then
        warn("[SnowX Extras] No se pudo abrir " .. systemName .. ": " .. tostring(openError))
    end
end

local function openSkinsExtra()
    openAvatarSystem("skins")
end

local function openAccessoriesExtra()
    openAvatarSystem("accessories")
end

local function ensureSkyboxFolder(path)
    if type(makefolder) ~= "function" then return false end
    if type(isfolder) == "function" then
        local ok, exists = pcall(isfolder, path)
        if ok and exists then return true end
    end
    local ok, result = pcall(makefolder, path)
    if ok and result ~= false then return true end
    if type(isfolder) == "function" then
        local checkOk, exists = pcall(isfolder, path)
        return checkOk and exists == true
    end
    if not ok and type(result) == "string" then
        local message = string.lower(result)
        if string.find(message, "exist", 1, true) then return true end
    end
    return false
end

local SKYBOX_CACHE_ROOT = "SnowX"
local SKYBOX_CACHE_DIR = SKYBOX_CACHE_ROOT .. "/Skybox"
local skyboxSequence = 0

local function deleteSkyboxFiles(paths)
    local failed = {}
    if type(paths) ~= "table" then return failed end
    local remover = type(delfile) == "function" and delfile or (type(removefile) == "function" and removefile or nil)
    if not remover then
        for _, path in ipairs(paths) do failed[#failed + 1] = path end
        return failed
    end
    for _, path in ipairs(paths) do
        local ok, result = pcall(remover, path)
        if not ok or result == false then
            failed[#failed + 1] = path
        end
    end
    return failed
end

local function appendUniquePaths(destination, paths)
    if type(paths) ~= "table" then return end
    for _, path in ipairs(paths) do
        local found = false
        for _, existing in ipairs(destination) do
            if existing == path then
                found = true
                break
            end
        end
        if not found then destination[#destination + 1] = path end
    end
end

local function resolveCustomAssetLoader()
    if type(getcustomasset) == "function" then return getcustomasset end
    if type(getsynasset) == "function" then return getsynasset end
    if type(get_custom_asset) == "function" then return get_custom_asset end
    if type(syn) == "table" then
        if type(syn.getcustomasset) == "function" then return syn.getcustomasset end
        if type(syn.getsynasset) == "function" then return syn.getsynasset end
    end
    return nil
end

local SkyboxEngine = {
    OriginalSkies = {},
    SuspendedSkies = {},
    OwnedSky = nil,
    RequestId = 0,
    ActiveTempFiles = {},
    CurrentName = "Original",
    PendingName = nil,
    WorkerRunning = false,
}

for _, object in ipairs(Lighting:GetChildren()) do
    if object:IsA("Sky") then
        SkyboxEngine.OriginalSkies[#SkyboxEngine.OriginalSkies + 1] = object
        SkyboxEngine.SuspendedSkies[#SkyboxEngine.SuspendedSkies + 1] = object
    end
end

local function skyboxRemember(sky)
    if not sky or not sky:IsA("Sky") then return end
    for _, current in ipairs(SkyboxEngine.SuspendedSkies) do
        if current == sky then return end
    end
    SkyboxEngine.SuspendedSkies[#SkyboxEngine.SuspendedSkies + 1] = sky
end

trackConnection(Lighting.ChildAdded:Connect(function(object)
    if not object:IsA("Sky") or not SkyboxEngine.OwnedSky or object == SkyboxEngine.OwnedSky then
        return
    end
    skyboxRemember(object)
    task.defer(function()
        if SkyboxEngine.OwnedSky and object.Parent == Lighting then
            pcall(function() object.Parent = nil end)
        end
    end)
end))

function SkyboxEngine:Restore()
    self.RequestId = self.RequestId + 1
    self.PendingName = nil
    self.CurrentName = "Original"
    local owned = self.OwnedSky
    self.OwnedSky = nil
    if owned then pcall(function() owned:Destroy() end) end
    self.ActiveTempFiles = deleteSkyboxFiles(self.ActiveTempFiles)

    local restored = {}
    for _, sky in ipairs(self.SuspendedSkies) do
        if sky then
            local readable, parent = pcall(function() return sky.Parent end)
            if readable then
                if parent == nil then pcall(function() sky.Parent = Lighting end) end
                local checkOk, currentParent = pcall(function() return sky.Parent end)
                if checkOk and currentParent == Lighting then
                    restored[#restored + 1] = sky
                end
            end
        end
    end
    self.SuspendedSkies = restored
end

function SkyboxEngine:_Build(name, requestId)
    if requestId ~= self.RequestId then return nil, "Solicitud cancelada", {} end
    local ids = skyboxData[name]
    local remoteFaces = skyboxFaceUrlMaps[name]
    if not ids and not remoteFaces then return nil, "Skybox desconocido: " .. tostring(name), {} end

    local sky = Instance.new("Sky")
    sky.Name = "CustomSky"
    sky.CelestialBodiesShown = false
    sky.StarCount = 0
    local temporaryFiles = {}

    local function fail(message)
        pcall(function() sky:Destroy() end)
        local failedFiles = deleteSkyboxFiles(temporaryFiles)
        return nil, message, failedFiles
    end

    if ids then
        for index, propertyName in ipairs(SKYBOX_FACE_ORDER) do
            local assetId = ids[index]
            if type(assetId) ~= "string" or not string.match(assetId, "^%d+$") then
                return fail("ID inválido para " .. propertyName)
            end
            sky[propertyName] = "rbxassetid://" .. assetId
        end
    else
        if type(writefile) ~= "function" then
            return fail("El executor no proporciona writefile para este skybox")
        end
        local assetLoader = resolveCustomAssetLoader()
        if not assetLoader then
            return fail("El executor no proporciona getcustomasset/getsynasset para este skybox")
        end
        if type(delfile) ~= "function" and type(removefile) ~= "function" then
            return fail("El executor no proporciona delfile/removefile para limpiar las texturas temporales")
        end
        local rootOk = ensureSkyboxFolder(SKYBOX_CACHE_ROOT)
        local dirOk = rootOk and ensureSkyboxFolder(SKYBOX_CACHE_DIR)
        if not dirOk then
            return fail("No se pudo crear la carpeta de caché del skybox")
        end

        for _, propertyName in ipairs(SKYBOX_FACE_ORDER) do
            if requestId ~= self.RequestId then
                return fail("Solicitud de skybox cancelada")
            end
            local url = remoteFaces[propertyName]
            local body, fetchError = executorHttpGetText(url)
            if type(body) ~= "string" or #body < 32 then
                return fail("No se pudo descargar " .. propertyName .. ": " .. tostring(fetchError))
            end

            skyboxSequence = skyboxSequence + 1
            local safeName = tostring(name):gsub("[^%w%-_]+", "_"):gsub("_+", "_")
            local path = SKYBOX_CACHE_DIR .. "/sky_" .. tostring(skyboxSequence) .. "_" .. safeName .. "_" .. propertyName .. ".png"
            local writeOk, writeResult = pcall(writefile, path, body)
            if not writeOk or writeResult == false then
                return fail("No se pudo escribir la textura " .. propertyName)
            end
            temporaryFiles[#temporaryFiles + 1] = path

            local assetOk, assetId = pcall(assetLoader, path)
            if not assetOk or type(assetId) ~= "string" or assetId == "" then
                return fail("No se pudo registrar la textura " .. propertyName)
            end
            sky[propertyName] = assetId
        end
    end

    if requestId ~= self.RequestId then
        return fail("Solicitud de skybox cancelada")
    end
    return sky, nil, temporaryFiles
end

function SkyboxEngine:Request(name)
    name = tostring(name or "Original")
    if name == "Original" then
        self.PendingName = nil
        self.CurrentName = "Original"
        self.RequestId = self.RequestId + 1
        self:Restore()
        return
    end

    if self.CurrentName == name and self.OwnedSky and self.OwnedSky.Parent == Lighting then return end
    if self.PendingName == name then return end

    self.PendingName = name
    self.RequestId = self.RequestId + 1
    if self.WorkerRunning then return end
    self.WorkerRunning = true

    task.spawn(function()
        while _G.sa_on and self.PendingName do
            local requestName = self.PendingName
            local requestId = self.RequestId
            self.PendingName = nil

            local callOk, sky, err, temporaryFiles = pcall(function()
                return self:_Build(requestName, requestId)
            end)
            if not callOk then
                err, sky, temporaryFiles = tostring(sky), nil, {}
            end

            if requestId ~= self.RequestId then
                if sky then pcall(function() sky:Destroy() end) end
                appendUniquePaths(self.ActiveTempFiles, deleteSkyboxFiles(temporaryFiles))
            elseif not sky then
                appendUniquePaths(self.ActiveTempFiles, temporaryFiles)
                warn("Skybox failed")
            else
                local previousFiles = self.ActiveTempFiles
                local previousOwned = self.OwnedSky
                local applyOk = pcall(function()
                    for _, object in ipairs(Lighting:GetChildren()) do
                        if object:IsA("Sky") then
                            if object == previousOwned then
                                object.Parent = nil
                            else
                                skyboxRemember(object)
                                object.Parent = nil
                            end
                        end
                    end
                    self.OwnedSky = sky
                    sky.Parent = Lighting
                    if sky.Parent ~= Lighting then error("Sky apply failed") end
                end)

                if not applyOk then
                    self.OwnedSky = previousOwned
                    pcall(function() sky:Destroy() end)
                    if previousOwned and previousOwned.Parent == nil then pcall(function() previousOwned.Parent = Lighting end) end
                    for _, suspended in ipairs(self.SuspendedSkies) do
                        if suspended and suspended.Parent == nil then pcall(function() suspended.Parent = Lighting end) end
                    end
                    appendUniquePaths(self.ActiveTempFiles, deleteSkyboxFiles(temporaryFiles))
                    warn("Skybox apply failed")
                else
                    self.CurrentName = requestName
                    if previousOwned and previousOwned ~= sky then pcall(function() previousOwned:Destroy() end) end
                    self.ActiveTempFiles = temporaryFiles or {}
                    appendUniquePaths(self.ActiveTempFiles, deleteSkyboxFiles(previousFiles))
                end
            end
        end
        self.WorkerRunning = false
        if self.PendingName and _G.sa_on then self:Request(self.PendingName) end
    end)
end

local uiLoaded, uiError = pcall(function()
    local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xDTaraZz/Roblox-Scripts/refs/heads/main/ui.lua"))()
    library = Library

    local Window = Library:CreateWindow({
        Title = "SnowX",
        SubTitle = "By Fabnx1",
        Theme = "Overworld",
        Language = "EN",
        Intro = true,
        Watermark = true,
        WatermarkTitle = "SnowX",
    })
    window = Window

    Window:AddTabSection("PLAYER")
    local PlayerTab = Window:AddTab("Player", "user-round", "Movement settings")
    local PlayerLeft = PlayerTab:AddLeftGroupbox("Movement", "move")
    local PlayerRight = PlayerTab:AddRightGroupbox("Jump / Camera", "gauge")

    PlayerLeft:AddToggle("SpeedEnabled", {
        Text = "Speed",
        Default = movementSettings.SpeedEnabled,
        Callback = function(value) movementSettings.SpeedEnabled = value == true end,
    })
    PlayerLeft:AddSlider("SpeedValue", {
        Text = "Speed value",
        Min = 0, Max = 100, Step = 1, Default = movementSettings.Speed,
        Callback = function(value) movementSettings.Speed = math.clamp(tonumber(value) or 0, 0, 100) end,
    })
    PlayerLeft:AddToggle("FlyEnabled", {
        Text = "Fly",
        Default = movementSettings.FlyEnabled,
        Callback = function(value) movementSettings.FlyEnabled = value == true end,
    })
    PlayerLeft:AddSlider("FlySpeed", {
        Text = "Fly speed",
        Min = 10, Max = 150, Step = 5, Default = movementSettings.FlySpeed,
        Callback = function(value) movementSettings.FlySpeed = math.clamp(tonumber(value) or 60, 10, 150) end,
    })
    PlayerLeft:AddToggle("TelaMovement", {
        Text = "Movimiento Tela",
        Default = movementSettings.TelaEnabled,
        Callback = function(value)
            movementSettings.TelaEnabled = value == true
            if not movementSettings.TelaEnabled and lp.Character then
                local humanoid = lp.Character:FindFirstChildOfClass("Humanoid")
                if humanoid and movementSaved.AutoRotate ~= nil then humanoid.AutoRotate = movementSaved.AutoRotate end
            end
        end,
    })
    PlayerLeft:AddSlider("TelaTurnSpeed", {
        Text = "Velocidad de giro Tela",
        Min = 10, Max = 100, Step = 5, Default = movementSettings.TelaTurnSpeed,
        Callback = function(value) movementSettings.TelaTurnSpeed = math.clamp(tonumber(value) or 45, 10, 100) end,
    })
    PlayerRight:AddToggle("SuperJump", {
        Text = "Super Jump",
        Default = movementSettings.SuperJumpEnabled,
        Callback = function(value) movementSettings.SuperJumpEnabled = value == true end,
    })
    PlayerRight:AddSlider("JumpPower", {
        Text = "Fuerza de impulso",
        Min = 50, Max = 200, Step = 5, Default = movementSettings.JumpPower,
        Callback = function(value) movementSettings.JumpPower = math.clamp(tonumber(value) or 95, 50, 200) end,
    })
    PlayerRight:AddToggle("InfiniteLeap", {
        Text = "Infinite Leap",
        Default = movementSettings.InfiniteLeap,
        Callback = function(value) movementSettings.InfiniteLeap = value == true end,
    })
    PlayerRight:AddToggle("WallClimb", {
        Text = "Wall Climb",
        Default = movementSettings.WallClimb,
        Callback = function(value) movementSettings.WallClimb = value == true end,
    })
    PlayerRight:AddToggle("FovEnabled", {
        Text = "FOV",
        Default = movementSettings.FovEnabled,
        Callback = function(value)
            movementSettings.FovEnabled = value == true
            if not movementSettings.FovEnabled then
                local camera = Workspace.CurrentCamera
                if camera and movementSaved.FieldOfView ~= nil then camera.FieldOfView = movementSaved.FieldOfView end
                movementSaved.FieldOfView = nil
            end
        end,
    })
    PlayerRight:AddSlider("FovValue", {
        Text = "Valor FOV",
        Min = 70, Max = 120, Step = 1, Default = movementSettings.Fov,
        Callback = function(value) movementSettings.Fov = math.clamp(tonumber(value) or 70, 70, 120) end,
    })
    PlayerRight:AddLabel("")

    Window:AddTabSection("AIM")
    local Aim = Window:AddTab("Aim", "crosshair", "Aim settings")
    local AimLeft = Aim:AddLeftGroupbox("SilentAim", "crosshair")
    local AimRight = Aim:AddRightGroupbox("FOV", "target")

    AimLeft:AddToggle("SilentAimEnabled", {
        Text = "SilentAim",
        Default = silentAimSettings.Enabled,
        Callback = function(value)
            silentAimSettings.Enabled = value == true
            if not silentAimSettings.Enabled then
                tgt, tgtPart = nil, nil
            end
        end,
    })
    AimLeft:AddDropdown("TargetPart", {
        Text = "TargetPart",
        Values = { "Cabeza", "Torso", "Completo" },
        Default = silentAimSettings.TargetPart,
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            if TARGET_PART_NAMES[value] then
                silentAimSettings.TargetPart = value
                tgt, tgtPart = nil, nil
                pcall(scan)
            end
        end,
    })
    
    AimRight:AddDropdown("SilentAimMode", {
        Text = "SilentAim Mode",
        Values = { "Screen", "Fov", "360" },
        Default = silentAimSettings.Mode,
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            if value == "Screen" or value == "Fov" or value == "360" then
                silentAimSettings.Mode = value
                tgt, tgtPart = nil, nil
            end
            pcall(updateFovIndicator)
        end,
    })
    AimRight:AddSlider("SilentAimFov", {
        Text = "FOV",
        Min = 10,
        Max = 1000,
        Step = 20,
        Default = silentAimSettings.Fov,
        Callback = function(value)
            local numeric = tonumber(value) or 250
            numeric = math.floor((numeric + 5) / 10) * 10
            silentAimSettings.Fov = math.clamp(numeric, 10, 1000)
            tgt, tgtPart = nil, nil
            pcall(updateFovIndicator)
        end,
    })
    AimRight:AddToggle("ShowFov", {
        Text = "Mostrar FOV",
        Default = silentAimSettings.ShowFov,
        Callback = function(value)
            silentAimSettings.ShowFov = value == true
            pcall(updateFovIndicator)
        end,
    })
    AimRight:AddLabel("")

    Window:AddTabSection("VISUALS")
    local Visuals = Window:AddTab("Visuals", "eye", "Visual settings")
    local VisualsLeft = Visuals:AddLeftGroupbox("ESP Settings", "eye")
    local VisualsRight = Visuals:AddRightGroupbox("Display", "monitor")

    VisualsLeft:AddToggle("ESPPlayers", {
        Text = "ESP Jugadores",
        Default = visualSettings.ESP,
        Callback = function(value)
            visualSettings.ESP = value == true
            if not visualSettings.ESP then clearVisuals() end
        end,
    })
    VisualsLeft:AddToggle("ESPGlow", {
        Text = "Mostrar Brillo",
        Default = visualSettings.Glow,
        Callback = function(value)
            visualSettings.Glow = value == true
        end,
    })
    VisualsLeft:AddToggle("ESPName", {
        Text = "Mostrar Nombre",
        Default = visualSettings.Name,
        Callback = function(value)
            visualSettings.Name = value == true
        end,
    })
    VisualsLeft:AddToggle("ESPDistance", {
        Text = "Mostrar Distancia",
        Default = visualSettings.Distance,
        Callback = function(value)
            visualSettings.Distance = value == true
        end,
    })
    VisualsLeft:AddToggle("ESPTracers", {
        Text = "Tracers / Líneas",
        Default = visualSettings.Tracers,
        Callback = function(value)
            visualSettings.Tracers = value == true
            if not visualSettings.Tracers then
                for _, entry in pairs(visualEntries) do destroyTracer(entry) end
            end
        end,
    })
    VisualsRight:AddColorPicker("ESPColor", {
        Text = "Color de ESP",
        Default = visualSettings.Color,
        Callback = function(value)
            if typeof(value) == "Color3" then
                visualSettings.Color = value
            end
        end,
    })
    VisualsRight:AddLabel("Los elementos ESP se muestran sobre los enemigos")

    Window:AddTabSection("OTHERS")
    local Extras = Window:AddTab("Extras", "sparkles", "Extra settings")
    local ExtrasLeft = Extras:AddLeftGroupbox("Performance", "gauge")
    local ExtrasSky = Extras:AddLeftGroupbox("Skybox / Cielos", "cloud")

    ExtrasLeft:AddToggle("BoostFps", {
        Text = "BoostFps",
        Default = false,
        Callback = function(value)
            if value == true then
                local ok, err = pcall(enableFpsBoost)
                if not ok then
                    pcall(restoreFpsBoost)
                    warn("[SnowX] Feature Error")
                end
            else
                pcall(restoreFpsBoost)
            end
        end,
    })
    ExtrasLeft:AddLabel("Reduce efectos visuales del mapa y restaura los valores al desactivar")

    ExtrasLeft:AddToggle("RainbowWeapon", {
        Text = "Rainbow Weapon",
        Default = rainbowSettings.Enabled,
        Callback = function(value)
            rainbowSettings.Enabled = value == true
            if not rainbowSettings.Enabled then applyRainbowToTool(nil) end
        end,
    })
    ExtrasLeft:AddToggle("HitboxPreview", {
        Text = "HitboxExpander",
        Default = hitboxSettings.Enabled,
        Callback = function(value)
            hitboxSettings.Enabled = value == true
            if not hitboxSettings.Enabled then clearAllHitboxAdornments() end
        end,
    })
    ExtrasLeft:AddSlider("HitboxSize", {
        Text = "Hitbox Size",
        Min = 1, Max = 15, Step = 1, Default = hitboxSettings.Size,
        Callback = function(value) hitboxSettings.Size = math.clamp(tonumber(value) or 3.5, 3, 15) end,
    })
    ExtrasLeft:AddColorPicker("HitboxColor", {
        Text = "Color Hitbox",
        Default = hitboxSettings.Color,
        Callback = function(value) if typeof(value) == "Color3" then hitboxSettings.Color = value end end,
    })
    ExtrasLeft:AddToggle("HitboxInvisible", {
        Text = "Hitbox Invisible",
        Default = hitboxSettings.Invisible,
        Callback = function(value) hitboxSettings.Invisible = value == true end,
    })
    ExtrasLeft:AddLabel("Hitbox")

    local SoundsGroup = Extras:AddRightGroupbox("Sound Changer", "volume-2")
    local AvatarSystemsGroup = Extras:AddRightGroupbox("Avatar Systems", "user-round")
    AvatarSystemsGroup:AddButton({
        Text = "Abrir Skins",
        Func = openSkinsExtra,
    })
    AvatarSystemsGroup:AddButton({
        Text = "Abrir Accessories",
        Func = openAccessoriesExtra,
    })
    AvatarSystemsGroup:AddLabel("Módulos separados; conexión compartida mediante AvatarBridge.")
    local KillSounds = {
        { Name = "Onichaaan", Id = "114361503583259" },
        { Name = "Omagaaa", Id = "4496966777" },
        { Name = "korummm", Id = "119896940405402" },
        { Name = "FAAAH XD", Id = "92076037937225" },
        { Name = "Nuevo KillSound", Id = "109302722677792" },
        { Name = "Sword Hit", Id = "140462043853173" },
        { Name = "TF2", Id = "2866718318" },
        { Name = "SpongeBob Laugh", Id = "271580013" },
        { Name = "Monster Kill", Id = "74959901252990" },
        { Name = "Insta Kill", Id = "131961137" },
        { Name = "Fortnite Death", Id = "70982573243341" },
        { Name = "Ez", Id = "8922169253" },
        { Name = "Among Us", Id = "130456049552264" },
        { Name = "SONICXD", Id = "132307272475720" },
    }
    local ShotSounds = {
        { Name = "Revolver", Id = "680140087" },
        { Name = "Magia de Anime", Id = "109296938403067" },
        { Name = "Láser", Id = "4400449399" },
    }
    local ReloadSounds = {
        { Name = "Revolver", Id = "138084889" },
        { Name = "Magia de Anime", Id = "109296938403067" },
        { Name = "Láser", Id = "129456040607483" },
    }
    local function soundNames(items)
        local names = {}
        for _, item in ipairs(items) do names[#names + 1] = item.Name end
        return names
    end
    SoundsGroup:AddToggle("KillSoundEnabled", {
        Text = "Activar Killsound",
        Default = customSoundSettings.KillEnabled,
        Callback = function(value)
            customSoundSettings.KillEnabled = value == true
            refreshCustomSounds()
        end,
    })
    SoundsGroup:AddDropdown("KillSoundPreset", {
        Text = "Seleccionar Killsound",
        Values = soundNames(KillSounds),
        Default = KillSounds[1].Name,
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            for _, item in ipairs(KillSounds) do
                if item.Name == value then customSoundSettings.KillId = item.Id; refreshCustomSounds(); break end
            end
        end,
    })
    SoundsGroup:AddInput("KillSoundCustom", {
        Text = "Custom Killsound ID", Placeholder = "Roblox asset ID", Default = "", Numeric = true,
        Callback = function(value)
            if customSoundAsset(value) then customSoundSettings.KillId = tostring(value); refreshCustomSounds() end
        end,
    })
    SoundsGroup:AddToggle("ShotSoundEnabled", {
        Text = "Activar Sonido Disparo",
        Default = customSoundSettings.ShotEnabled,
        Callback = function(value)
            customSoundSettings.ShotEnabled = value == true
            refreshCustomSounds()
        end,
    })
    SoundsGroup:AddDropdown("ShotSoundPreset", {
        Text = "Seleccionar Disparo", Values = soundNames(ShotSounds), Default = ShotSounds[1].Name,
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            for _, item in ipairs(ShotSounds) do
                if item.Name == value then customSoundSettings.ShotId = item.Id; refreshCustomSounds(); break end
            end
        end,
    })
    SoundsGroup:AddInput("ShotSoundCustom", {
        Text = "Custom Disparo ID", Placeholder = "Roblox asset ID", Default = "", Numeric = true,
        Callback = function(value)
            if customSoundAsset(value) then customSoundSettings.ShotId = tostring(value); refreshCustomSounds() end
        end,
    })
    SoundsGroup:AddToggle("ReloadSoundEnabled", {
        Text = "Activar Sonido Recarga",
        Default = customSoundSettings.ReloadEnabled,
        Callback = function(value)
            customSoundSettings.ReloadEnabled = value == true
            refreshCustomSounds()
        end,
    })
    SoundsGroup:AddDropdown("ReloadSoundPreset", {
        Text = "Seleccionar Recarga", Values = soundNames(ReloadSounds), Default = ReloadSounds[1].Name,
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            for _, item in ipairs(ReloadSounds) do
                if item.Name == value then customSoundSettings.ReloadId = item.Id; refreshCustomSounds(); break end
            end
        end,
    })
    SoundsGroup:AddInput("ReloadSoundCustom", {
        Text = "Custom Recarga ID", Placeholder = "Roblox asset ID", Default = "", Numeric = true,
        Callback = function(value)
            if customSoundAsset(value) then customSoundSettings.ReloadId = tostring(value); refreshCustomSounds() end
        end,
    })
    SoundsGroup:AddLabel("")

    ExtrasSky:AddDropdown("Skybox", {
        Text = "Seleccionar cielo",
        Values = skyboxNames,
        Default = "Original",
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            SkyboxEngine:Request(value or "Original")
        end,
    })
    ExtrasSky:AddButton({
        Text = "Restaurar cielo original",
        Func = function()
            SkyboxEngine:Restore()
        end,
    })

    local Settings = Window:AddSettingsTab()
    if type(Library.OnUnload) == "function" then
        Library:OnUnload(function()
            if _G.sa_on and type(_G.sa_off) == "function" then
                _G.sa_off()
            end
        end)
    end
end)

if not uiLoaded then
    warn("[SnowX] UI Error")
end

task.spawn(function()
    while _G.sa_on do
        if silentAimSettings.Enabled then
            pcall(scan)
        else
            tgt, tgtPart = nil, nil
        end
        task.wait(0.1)
    end
end)

local function isValidAimPair(target, targetPart)
    local ok, valid = pcall(function()
        return target ~= nil and targetPart ~= nil
            and targetPart:IsA("BasePart")
            and target.Character ~= nil
            and targetPart:IsDescendantOf(target.Character)
    end)
    return ok and valid
end

local function resolveShotAim()
    local ok, target, targetPart = pcall(getSilentAimTarget)
    if ok and isValidAimPair(target, targetPart) then
        return target, targetPart, targetPart.Position
    end
    return nil, nil, nil
end

local vfxCreateBeamOriginal = nil
local vfxCreateBeamTable = nil
local vfxCreateBeamWrapper = nil
local gunVfxModule = ReplicatedStorage:FindFirstChild("Gun_VFX")
if gunVfxModule and gunVfxModule:IsA("ModuleScript") then
    local ok, result = pcall(require, gunVfxModule)
    if ok and type(result) == "table" and type(result.CreateBeam) == "function" then
        vfxCreateBeamTable = result
        vfxCreateBeamOriginal = result.CreateBeam
        vfxCreateBeamWrapper = function(from, to, isRainbowGun, is500KGun, ...)
            if _G.sa_on and silentAimSettings.Enabled and typeof(from) == "Vector3" and typeof(to) == "Vector3" then
                local target, targetPart = resolveShotAim()
                if target and targetPart then to = targetPart.Position end
            end
            return vfxCreateBeamOriginal(from, to, isRainbowGun, is500KGun, ...)
        end
        result.CreateBeam = vfxCreateBeamWrapper
    else
        warn("Feature unavailable")
    end
else
    warn("Feature unavailable")
end

local remote
local killConfirmRemote
pcall(function()
    local matchEvents = ReplicatedStorage:WaitForChild("MatchEvents", 10)
    if matchEvents then
        remote = matchEvents:WaitForChild("CombatRemote", 10)
        killConfirmRemote = matchEvents:WaitForChild("GunKillConfirm", 10)
    end
end)

if killConfirmRemote then
    trackConnection(killConfirmRemote.OnClientEvent:Connect(function(confirmed)
        if confirmed == true then
            playCustomKillSound()
        end
    end))
end

local orig = nil
if type(hookmetamethod) == "function" and type(checkcaller) == "function"
    and type(getnamecallmethod) == "function" and remote then
    local hookOk, previous = pcall(function()
        return hookmetamethod(game, "__namecall", function(self, ...)
            if not checkcaller() and _G.sa_on and getnamecallmethod() == "FireServer" and self == remote then
                local args = { ... }
                local data = args[1]
                if typeof(data) == "table" then
                    if silentAimSettings.Enabled then
                        if not tgt or not tgtPart or os.clock() - lastScan > 0.5 then
                            pcall(scan)
                        end
                    end
                    if silentAimSettings.Enabled and tgt and tgtPart then
                        pcall(function()
                            data.targetPos = tgtPart.Position
                            data.hitPosition = tgtPart.Position
                            data.victimUserId = tgt.UserId
                            data.hitPartName = tgtPart.Name
                        end)
                        args[1] = data
                    end
                end
                return orig(self, table.unpack(args))
            end
            return orig(self, ...)
        end)
    end)
    if hookOk and type(previous) == "function" then
        orig = previous
    else
        warn("Hook unavailable")
    end
else
    warn("Feature unavailable")
end

_G.sa_off = function()
    if shuttingDown then return end
    shuttingDown = true
    _G.sa_on = false

    if orig then
        pcall(function() hookmetamethod(game, "__namecall", orig) end)
        orig = nil
    end

    if vfxCreateBeamTable and vfxCreateBeamOriginal and vfxCreateBeamTable.CreateBeam == vfxCreateBeamWrapper then
        pcall(function() vfxCreateBeamTable.CreateBeam = vfxCreateBeamOriginal end)
    end
    movementSettings.SpeedEnabled = false
    movementSettings.FlyEnabled = false
    movementSettings.TelaEnabled = false
    movementSettings.SuperJumpEnabled = false
    movementSettings.InfiniteLeap = false
    movementSettings.WallClimb = false
    movementSettings.FovEnabled = false
    silentAimSettings.Enabled = false
    tgt, tgtPart = nil, nil
    restoreMovementState()
    rainbowSettings.Enabled = false
    applyRainbowToTool(nil)
    hitboxSettings.Enabled = false
    clearAllHitboxAdornments()
    restoreCustomSounds()
    pcall(function() customKillSound:Destroy() end)
    for _, connection in ipairs(customSoundWatchers) do pcall(function() connection:Disconnect() end) end
    table.clear(customSoundWatchers)

    clearVisuals()
    destroyFovIndicator()
    pcall(function() SkyboxEngine:Restore() end)
    disconnectAll()

    for player, connection in pairs(visualConnections) do
        pcall(function() connection:Disconnect() end)
        visualConnections[player] = nil
    end

    if overlayGui then
        pcall(function() overlayGui:Destroy() end)
        overlayGui = nil
    end

    if library and not library.Unloaded then
        pcall(function() library:Unload() end)
    end
    _G.sa_off = nil
end