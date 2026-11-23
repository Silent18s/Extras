-- SnowX Extras / AvatarBridge
-- Shared contract only: this file does not download, compile, or execute Skins or Accessories.
-- Execute with an optional existing bridge table to join an already running SnowX session.

local sharedEnvironment = _G
if type(getgenv) == "function" then
    local environmentOk, environment = pcall(getgenv)
    if environmentOk and type(environment) == "table" then
        sharedEnvironment = environment
    end
end

local bridge = ...
if type(bridge) ~= "table" then
    bridge = type(sharedEnvironment.__SnowXAvatarBridge) == "table"
        and sharedEnvironment.__SnowXAvatarBridge or {}
end
bridge.version = 2
bridge.skin = type(bridge.skin) == "table" and bridge.skin or {}
bridge.accessory = type(bridge.accessory) == "table" and bridge.accessory or {}
bridge.skin.revision = tonumber(bridge.skin.revision) or 0
bridge.accessory.revision = tonumber(bridge.accessory.revision) or 0
bridge.uiPanels = type(bridge.uiPanels) == "table" and bridge.uiPanels or {}
sharedEnvironment.__SnowXAvatarBridge = bridge
_G.__SnowXAvatarBridge = bridge

local registry = sharedEnvironment.__SnowXExtrasApis
if type(registry) ~= "table" then registry = {} end
sharedEnvironment.__SnowXExtrasApis = registry
_G.__SnowXExtrasApis = registry

local function register(name, api)
    if name ~= "skins" and name ~= "accessories" then
        return false, "Módulo desconocido"
    end
    if type(api) ~= "table" then return false, "API inválida" end
    registry[name] = api
    return true
end

local function get(name)
    if name ~= "skins" and name ~= "accessories" then return nil end
    return registry[name]
end

local function openSkins()
    local api = registry.skins
    if type(api) ~= "table" or type(api.open) ~= "function" or not api.gui then
        registry.skins = nil
        return false, "Skins todavía no está ejecutándose"
    end
    local guiOk, guiParent = pcall(function() return api.gui.Parent end)
    if not guiOk or guiParent == nil then
        registry.skins = nil
        return false, "Skins todavía no está ejecutándose"
    end
    local ok, result = pcall(api.open)
    if not ok then return false, tostring(result) end
    return result ~= false, result
end

local function openAccessories()
    local api = registry.accessories
    if type(api) ~= "table" or type(api.Open) ~= "function" or not api.gui then
        registry.accessories = nil
        return false, "Accessories todavía no está ejecutándose"
    end
    local guiOk, guiParent = pcall(function() return api.gui.Parent end)
    if not guiOk or guiParent == nil then
        registry.accessories = nil
        return false, "Accessories todavía no está ejecutándose"
    end
    local ok, result = pcall(api.Open)
    if not ok then return false, tostring(result) end
    return result ~= false, result
end

local connection = {
    bridge = bridge,
    apis = registry,
    register = register,
    get = get,
    openSkins = openSkins,
    openAccessories = openAccessories,
}
sharedEnvironment.__SnowXExtrasConnection = connection
_G.__SnowXExtrasConnection = connection

return connection
