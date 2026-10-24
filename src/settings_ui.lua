-- Settings page. It's shown on the cog in Plugin Hub > Manage, and in the
-- Plugins window when you click the plugin's icon there. The Plugins window is
-- narrow, so the page uses smaller text and buttons when there's less room,
-- and scrolls if it still doesn't fit.
local SettingsUI = {}
SettingsUI.__index = SettingsUI

local NARROW_WIDTH = 300
local SCROLLBAR_WIDTH = 6
local SCROLLBAR_GAP = 4
local SCROLL_STEP = 30
local MIN_THUMB = 20

local WIDE = {
    font = id.Font.MUSEO_SANS_15PT_REGULAR,
    headingFont = id.Font.MUSEO_SANS_15PT_BOLD,
    charWidth = 7, -- rough text width if the font can't be measured
    padding = 12,
    row = 30,
    textOffset = 4,
    lineHeight = 22,
    button = 86,
    toggle = 86,
    small = 30,
    value = 40,
    swatch = 18,
    gap = 8,
    sectionGap = 10,
    hint = true,
}

local NARROW = {
    font = id.Font.MUSEO_SANS_11PT_REGULAR,
    headingFont = id.Font.MUSEO_SANS_13PT_BOLD,
    charWidth = 6,
    padding = 8,
    row = 26,
    textOffset = 4,
    lineHeight = 18,
    button = 62,
    toggle = 46,
    small = 22,
    value = 30,
    swatch = 14,
    gap = 6,
    sectionGap = 4,
    hint = false,
}

local TEXT_COLOUR = 0xE8E2D0FF
local HEADING_COLOUR = 0xF0C060FF
local DIM_COLOUR = 0x8A8478FF
local HINT_COLOUR = 0xA8A090FF
local DIVIDER_COLOUR = Vector4.new(0.55, 0.5, 0.4, 0.5)
local TRACK_COLOUR = Vector4.new(0.0, 0.0, 0.0, 0.35)
local THUMB_COLOUR = Vector4.new(0.62, 0.55, 0.42, 0.9)

local function rgbToVector(rgb)
    return Vector4.new(((rgb >> 16) & 0xFF) / 255, ((rgb >> 8) & 0xFF) / 255, (rgb & 0xFF) / 255, 1.0)
end

local function onOff(value)
    return value and "On" or "Off"
end

local function textWidth(layout, fontId, text)
    local ok, width = pcall(function()
        return config.Font.FromID(fontId):GetStringWidth(text, false)
    end)
    if ok and type(width) == "number" then return width end
    return #text * layout.charWidth
end

-- onChange is called after any setting changes, so the marker can redraw and
-- every open page can update its labels
function SettingsUI.new(settings, onChange)
    return setmetatable({ settings = settings, onChange = onChange, components = {}, syncs = {} }, SettingsUI)
end

function SettingsUI:_add(component)
    self.components[#self.components + 1] = component
    return component
end

function SettingsUI:_rectangle(parent, x, y, width, height, colour)
    local rectangle = self:_add(ui.Rectangle.new(parent))
    rectangle:SetPos(x, y)
    rectangle:SetSize(width, height)
    rectangle.fill = true
    rectangle.clickthrough = true
    rectangle.colour = colour
    return rectangle
end

function SettingsUI:_text(content, x, y, width, font, colour)
    local text = self:_add(ui.Text.new(self.content))
    text:SetPos(x, y)
    text:SetSize(width, self.layout.row)
    text.font = font or self.layout.font
    text.rgba = colour or TEXT_COLOUR
    text.clickthrough = true
    text:AlignTo(ui.AlignMode.TOPLEFT)
    text.content = content
    return text
end

function SettingsUI:_button(label, x, y, width, onPress)
    local button = self:_add(ui.Button.new(self.content))
    button:SetPos(x, y)
    button:SetSize(width, self.layout.row - 4)
    button.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    button.label = label
    button:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
        local ok, failure = pcall(onPress)
        if not ok then print("[own-tile] button error: " .. tostring(failure)) end
        self.onChange()
    end)
    -- so the wheel still scrolls when the mouse is over a button
    if self.onWheel then button:Subscribe(ui.Hook.ONSCROLLWHEEL, self.onWheel) end
    return button
end

-- keeps a control in step with the settings
function SettingsUI:_sync(update)
    self.syncs[#self.syncs + 1] = update
    update()
end

function SettingsUI:_heading(title)
    local layout = self.layout
    if self.y > layout.padding then self.y = self.y + layout.sectionGap end
    self:_text(title, layout.padding, self.y, self.width - layout.padding * 2, layout.headingFont, HEADING_COLOUR)
    self:_rectangle(self.content, layout.padding, self.y + layout.lineHeight, self.width - layout.padding * 2, 1,
        DIVIDER_COLOUR)
    self.y = self.y + layout.lineHeight + 4
end

-- label on the left and a control of the given width on the right. If the
-- label is too long to fit next to it, the control goes on the line below.
function SettingsUI:_row(label, controlWidth)
    local layout = self.layout
    local controlX = self.width - layout.padding - controlWidth
    local room = controlX - layout.padding - layout.gap
    local fits = textWidth(layout, layout.font, label) <= room
    local text = self:_text(label, layout.padding, self.y + layout.textOffset,
        fits and room or self.width - layout.padding * 2)
    if not fits then self.y = self.y + layout.lineHeight end
    local y = self.y
    self.y = self.y + layout.row
    return controlX, y, text
end

function SettingsUI:_toggle(label, key)
    local settings = self.settings
    local x, y = self:_row(label, self.layout.toggle)
    local button = self:_button(onOff(settings.values[key]), x, y, self.layout.toggle, function()
        settings.toggle(key)
    end)
    self:_sync(function() button.label = onOff(settings.values[key]) end)
end

-- label, then - value + on the right. isDimmed greys the row out when the
-- setting doesn't do anything right now
function SettingsUI:_stepper(label, show, adjust, isDimmed)
    local layout = self.layout
    local x, y, text = self:_row(label, layout.small * 2 + layout.value)
    -- same box as the buttons, so the value is centred between them
    local value = self:_text(show(), x + layout.small, y, layout.value)
    value:SetSize(layout.value, layout.row - 4)
    value:AlignTo(ui.AlignMode.CENTRE)
    self:_button("-", x, y, layout.small, function() adjust(-1) end)
    self:_button("+", x + layout.small + layout.value, y, layout.small, function() adjust(1) end)
    self:_sync(function()
        local colour = (isDimmed and isDimmed()) and DIM_COLOUR or TEXT_COLOUR
        value.content = show()
        value.rgba = colour
        text.rgba = colour
    end)
end

-- all the rows, laid out from the top of self.content
function SettingsUI:_rows()
    local settings = self.settings
    local layout = self.layout
    self.y = layout.padding

    self:_heading("Marker")

    -- colour row: swatch and a button that steps through the colours
    local x, y = self:_row("Colour", layout.swatch + layout.gap + layout.button)
    local swatch = self:_rectangle(self.content, x, y + (layout.row - 4 - layout.swatch) // 2,
        layout.swatch, layout.swatch, rgbToVector(settings.colourRGB()))
    local colourButton = self:_button(settings.values.colour, x + layout.swatch + layout.gap, y, layout.button,
        function() settings.cycleColour(1) end)
    self:_sync(function()
        colourButton.label = settings.values.colour
        swatch.colour = rgbToVector(settings.colourRGB())
    end)

    x, y = self:_row("Fill", layout.button)
    local fillButton = self:_button(settings.values.fill, x, y, layout.button, function() settings.cycleFill(1) end)
    self:_sync(function() fillButton.label = settings.values.fill end)

    self:_stepper("Line width", function() return tostring(settings.values.lineWidth) end, settings.adjustLineWidth)
    self:_toggle("Corners only", "cornersOnly")
    self:_toggle("Show through objects", "drawOnTop")

    self:_heading("Fade")
    self:_toggle("Fade when still", "fadeWhenStill")
    self:_stepper("Fade after", function() return settings.values.fadeDelay .. "s" end, settings.adjustFadeDelay,
        function() return not settings.values.fadeWhenStill end)

    self.y = self.y + layout.sectionGap
    local resetLabel = "Reset to defaults"
    local resetWidth = math.min(self.width - layout.padding * 2,
        math.ceil(textWidth(WIDE, WIDE.font, resetLabel)) + 32)
    self:_button(resetLabel, (self.width - resetWidth) // 2, self.y, resetWidth, settings.reset)
    self.y = self.y + layout.row

    if layout.hint then
        self:_text("Changes show on the marker straight away.", layout.padding, self.y + 4,
            self.width - layout.padding * 2, layout.font, HINT_COLOUR)
        self.y = self.y + layout.lineHeight + 4
    end
    self.y = self.y + layout.padding
end

-- the viewport is the visible part, content is everything and moves inside it
function SettingsUI:_layout(parent, width, height, scrolling)
    self.width = scrolling and width - SCROLLBAR_WIDTH - SCROLLBAR_GAP or width
    self.viewport = self:_add(ui.Layer.new(parent))
    self.viewport:SetPos(0, 0)
    self.viewport:SetSize(self.width, height > 0 and height or 1)
    self.content = self:_add(ui.Layer.new(self.viewport))
    self.content:SetPos(0, 0)
    self.onWheel = nil
    if scrolling then
        self.onWheel = function(_, delta)
            self:_scrollTo(self.scrollY + (tonumber(delta) or 0) * SCROLL_STEP)
            return false
        end
        self.viewport:Subscribe(ui.Hook.ONSCROLLWHEEL, self.onWheel)
        self.content:Subscribe(ui.Hook.ONSCROLLWHEEL, self.onWheel)
    end
    self:_rows()
    self.contentHeight = self.y
    self.content:SetSize(self.width, self.contentHeight)
    if not scrolling then
        self.viewport:SetSize(self.width, math.max(height, self.contentHeight))
    end
end

-- thin bar on the right. Click or drag anywhere on it to jump there
function SettingsUI:_scrollbar(parent, width, height)
    local track = self:_add(ui.Layer.new(parent))
    track:SetPos(width - SCROLLBAR_WIDTH, 0)
    track:SetSize(SCROLLBAR_WIDTH, height)
    self:_rectangle(track, 0, 0, SCROLLBAR_WIDTH, height, TRACK_COLOUR)
    self.thumbHeight = math.max(MIN_THUMB, math.floor(height * height / self.contentHeight))
    self.thumb = self:_rectangle(track, 0, 0, SCROLLBAR_WIDTH, self.thumbHeight, THUMB_COLOUR)

    local function jump(_, _, y)
        local travel = height - self.thumbHeight
        if travel > 0 then
            local maxScroll = self.contentHeight - height
            self:_scrollTo(((tonumber(y) or 0) - self.thumbHeight / 2) * maxScroll / travel)
        end
        return false
    end
    track:Subscribe(ui.Hook.ONCLICK, jump)
    track:Subscribe(ui.Hook.ONHOLD, jump)
    track:Subscribe(ui.Hook.ONSCROLLWHEEL, self.onWheel)
end

function SettingsUI:_scrollTo(position)
    if self.thumb == nil then return end
    local maxScroll = math.max(0, self.contentHeight - self.height)
    self.scrollY = math.max(0, math.min(maxScroll, math.floor(position)))
    self.viewport:SetScrollPos(0, self.scrollY)
    local travel = self.height - self.thumbHeight
    self.thumb:SetPos(0, maxScroll > 0 and math.floor(self.scrollY / maxScroll * travel) or 0)
end

function SettingsUI:build(parent)
    self:clear()
    local width = tonumber(parent.width) or 0
    local height = tonumber(parent.height) or 0
    self.layout = width < NARROW_WIDTH and NARROW or WIDE
    self.height = height
    self:_layout(parent, width, height, false)

    -- too tall for the window: lay it out again with room for a scrollbar
    if height > 0 and self.contentHeight > height then
        self:clear()
        self:_layout(parent, width, height, true)
        self.viewport:SetScrollSize(self.width, self.contentHeight)
        self:_scrollbar(parent, width, height)
        self:_scrollTo(0)
    end
end

-- refreshes labels after a change made here or on the other page
function SettingsUI:sync()
    for _, update in ipairs(self.syncs) do
        if not pcall(update) then
            -- the page was closed and its components are gone
            self:clear()
            return
        end
    end
end

function SettingsUI:clear()
    for index = #self.components, 1, -1 do
        local component = self.components[index]
        pcall(function() component:Destroy() end)
    end
    self.components = {}
    self.syncs = {}
    self.viewport, self.content, self.thumb, self.onWheel = nil, nil, nil, nil
    self.scrollY = 0
end

return SettingsUI
