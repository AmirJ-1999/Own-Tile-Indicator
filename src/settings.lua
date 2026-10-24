-- Settings, saved with PersistentDB.
local Settings = {}

local STORAGE_KEY = "settings"
local STORAGE_VERSION = 1

Settings.COLOURS = {
    { name = "Cyan", rgb = 0x00FFFF },
    { name = "White", rgb = 0xFFFFFF },
    { name = "Green", rgb = 0x40FF40 },
    { name = "Yellow", rgb = 0xFFEE33 },
    { name = "Orange", rgb = 0xFF8800 },
    { name = "Red", rgb = 0xFF3030 },
    { name = "Pink", rgb = 0xFF66CC },
    { name = "Purple", rgb = 0xB070FF },
}

Settings.FILLS = {
    { name = "Off", alpha = 0 },
    { name = "Light", alpha = 0x33 },
    { name = "Medium", alpha = 0x59 },
    { name = "Strong", alpha = 0x8C },
}

Settings.MIN_LINE_WIDTH = 1
Settings.MAX_LINE_WIDTH = 5
Settings.MIN_FADE_DELAY = 1
Settings.MAX_FADE_DELAY = 60

local DEFAULTS = {
    colour = "Cyan",
    fill = "Off",
    lineWidth = 2,
    cornersOnly = false,
    drawOnTop = true,
    fadeWhenStill = true,
    fadeDelay = 3,
}

Settings.values = {}

local function findIndex(list, name)
    for index, entry in ipairs(list) do
        if entry.name == name then return index end
    end
    return nil
end

-- whole number between min and max. Numbers from the db can come back as
-- floats, and anything odd (nan, inf, wrong type) falls back to the default
local function wholeNumber(value, min, max, default)
    if type(value) ~= "number" or value ~= value then return default end
    value = math.max(min, math.min(max, value))
    return math.tointeger(math.floor(value)) or default
end

local function defaults()
    local values = {}
    for key, value in pairs(DEFAULTS) do values[key] = value end
    return values
end

function Settings.load()
    local values = defaults()
    local ok, stored = pcall(function()
        return PersistentDB:GetStructuredData(STORAGE_KEY)
    end)
    if ok and type(stored) == "table" then
        -- only copy keys we know about, with the type we expect
        for key, default in pairs(DEFAULTS) do
            if type(stored[key]) == type(default) then values[key] = stored[key] end
        end
    end
    values.lineWidth = wholeNumber(values.lineWidth, Settings.MIN_LINE_WIDTH, Settings.MAX_LINE_WIDTH, DEFAULTS.lineWidth)
    values.fadeDelay = wholeNumber(values.fadeDelay, Settings.MIN_FADE_DELAY, Settings.MAX_FADE_DELAY, DEFAULTS.fadeDelay)
    if findIndex(Settings.COLOURS, values.colour) == nil then values.colour = DEFAULTS.colour end
    if findIndex(Settings.FILLS, values.fill) == nil then values.fill = DEFAULTS.fill end
    Settings.values = values
end

function Settings.save()
    local data = { version = STORAGE_VERSION }
    for key, value in pairs(Settings.values) do data[key] = value end
    local ok, failure = pcall(function()
        return PersistentDB:SetStructuredData(STORAGE_KEY, data)
    end)
    if not ok then print("[own-tile] failed to save settings: " .. tostring(failure)) end
end

function Settings.set(key, value)
    Settings.values[key] = value
    Settings.save()
end

function Settings.reset()
    Settings.values = defaults()
    Settings.save()
end

function Settings.toggle(key)
    Settings.set(key, not Settings.values[key])
end

-- steps to the next (or previous) entry and wraps around
local function cycle(list, key, direction)
    local index = findIndex(list, Settings.values[key]) or 1
    index = (index - 1 + direction) % #list + 1
    Settings.set(key, list[index].name)
end

function Settings.cycleColour(direction)
    cycle(Settings.COLOURS, "colour", direction or 1)
end

function Settings.cycleFill(direction)
    cycle(Settings.FILLS, "fill", direction or 1)
end

function Settings.adjustLineWidth(direction)
    local width = Settings.values.lineWidth + direction
    Settings.set("lineWidth", math.max(Settings.MIN_LINE_WIDTH, math.min(Settings.MAX_LINE_WIDTH, width)))
end

-- 1s steps up to 10s, then 5s steps up to a minute
function Settings.adjustFadeDelay(direction)
    local delay = Settings.values.fadeDelay
    local step = (delay > 10 or (delay == 10 and direction > 0)) and 5 or 1
    delay = math.max(Settings.MIN_FADE_DELAY, math.min(Settings.MAX_FADE_DELAY, delay + direction * step))
    Settings.set("fadeDelay", delay)
end

function Settings.colourRGB()
    return Settings.COLOURS[findIndex(Settings.COLOURS, Settings.values.colour)].rgb
end

function Settings.fillAlpha()
    return Settings.FILLS[findIndex(Settings.FILLS, Settings.values.fill)].alpha
end

return Settings
