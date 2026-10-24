-- Own Tile Indicator
-- Marks the tile under your character. It uses the position of the character
-- model, so the marker always matches what you see on screen. It only reads
-- your own position and draws on your own screen, nothing is sent anywhere.
local Settings = require("src/settings")
local Marker = require("src/marker")
local Fade = require("src/fade")
local SettingsUI = require("src/settings_ui")

local EVENT_ID = "own-tile-indicator"
local TILE = 512
local MAX_REPORTS = 20

Settings.load()

local marker = Marker.new()
local fade = Fade.new()
local style

-- the marker compares style tables to know when to rebuild, so this makes a
-- new one each time a setting changes
local function refreshStyle()
    local values = Settings.values
    style = {
        rgb = Settings.colourRGB(),
        fillAlpha = Settings.fillAlpha(),
        cornersOnly = values.cornersOnly,
        lineWidth = values.lineWidth,
        drawOnTop = values.drawOnTop,
    }
end
refreshStyle()

-- Draw runs every frame, so an error there is only printed once instead of
-- filling the console
local reported, reportCount = {}, 0
local function report(label, failure)
    local message = "[own-tile] error in " .. label .. ": " .. tostring(failure)
    if reported[message] or reportCount >= MAX_REPORTS then return end
    reported[message] = true
    reportCount = reportCount + 1
    print(message)
end

local function guarded(label, callback)
    return function(...)
        local ok, failure = pcall(callback, ...)
        if not ok then report(label, failure) end
    end
end

-- the same settings page is shown on the cog in Plugin Hub and in the Plugins
-- window, a change on one updates the other
local settingsPage, panelPage
local function settingsChanged()
    refreshStyle()
    fade:wake()
    settingsPage:sync()
    panelPage:sync()
end
settingsPage = SettingsUI.new(Settings, settingsChanged)
panelPage = SettingsUI.new(Settings, settingsChanged)

-- the Plugins window layer is filled on the next frame, once it has its size
local pendingPanel

local function onDraw(event)
    if pendingPanel ~= nil then
        local parent = pendingPanel
        pendingPanel = nil
        local ok, failure = pcall(panelPage.build, panelPage, parent)
        if not ok then report("Plugins window", failure) end
    end

    local player = Player.IsAvailable() and Player.GetEntity() or nil
    if player == nil or not player.isValid or not World.IsAvailable() then
        marker:hide()
        return
    end
    local position = player.position
    local plane = player.coordGrid.level
    local opacity = fade:update(event and event.timeDeltaSecs, position, plane,
        Settings.values.fadeWhenStill, Settings.values.fadeDelay)
    marker:show(plane, math.floor(position.x / TILE), math.floor(position.z / TILE), style, opacity)
end

-- the map was rebuilt, so cached ground heights may be wrong
local function mapChanged()
    marker:invalidate()
end

local EVENTS = {
    Draw = onDraw,
    WorldCreated = mapChanged,
    RegionCreated = mapChanged,
    RegionUpdated = mapChanged,
    SettingsLayerReady = function(event)
        settingsPage:build(event.component)
        fade:wake()
    end,
    ContentLayerReady = function(event)
        panelPage:clear()
        pendingPanel = event.component
        fade:wake()
    end,
    GameStateChanged = function(event)
        if event.newState ~= GameState.GAME then
            marker:hide()
            marker:invalidate()
        end
        fade:wake()
    end,
}

for name, callback in pairs(EVENTS) do
    Event[name].Subscribe(EVENT_ID, guarded(name, callback))
end

function PluginShutdown()
    for name in pairs(EVENTS) do
        pcall(function() Event[name].Unsubscribe(EVENT_ID) end)
    end
    pendingPanel = nil
    settingsPage:clear()
    panelPage:clear()
    marker:destroy()
    Settings.save()
end

print("[own-tile] loaded")
