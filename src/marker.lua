-- Draws the marker on one tile and moves it when the tile changes.
local Marker = {}
Marker.__index = Marker

local TILE = 512
local LIFT = 30          -- keeps the shape just above the ground so it doesn't flicker
local OUTLINE_LIFT = 1   -- outline sits a hair above the fill
local CORNER_LENGTH = 0.25
local INSTANCE_NAME = "own-tile-indicator"

function Marker.new()
    return setmetatable({}, Marker)
end

local function groundHeight(level, x, z)
    local height, ok = World.GetGroundHeight(level, x, z)
    if not ok or height == nil or height < 0 then return nil end
    return height
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Ground heights for the tile, sampled once per tile. Corners are sampled
-- separately so the shape follows slopes.
-- Corner order: south-west, south-east, north-east, north-west.
local function measureTile(level, tileX, tileZ)
    local minX, minZ = tileX * TILE, tileZ * TILE
    local points = {}
    local offsets = { { 0, 0 }, { TILE, 0 }, { TILE, TILE }, { 0, TILE } }
    for index, offset in ipairs(offsets) do
        local x, z = minX + offset[1], minZ + offset[2]
        local height = groundHeight(level, x, z)
        if height == nil then return nil end
        points[index] = { x = x, y = height, z = z }
    end
    local centreX, centreZ = minX + TILE // 2, minZ + TILE // 2
    local centreY = groundHeight(level, centreX, centreZ) or points[1].y
    return { points = points, centre = { x = centreX, y = centreY, z = centreZ } }
end

-- Builds the shape relative to the tile centre, which becomes the translation.
-- It's always built at full strength, fading is done with the instance colour.
local function buildShape(tile, style)
    local points, centre = tile.points, tile.centre
    local positions, rgba, lines, tris = {}, {}, {}, {}

    local function add(point, lift, colour)
        positions[#positions + 1] = Vector3.new(point.x - centre.x, point.y + lift - centre.y, point.z - centre.z)
        rgba[#rgba + 1] = colour
        return #positions - 1
    end

    local outline = (style.rgb << 8) | 0xFF
    for side = 1, 4 do
        local from, to = points[side], points[side % 4 + 1]
        if style.cornersOnly then
            -- two short pieces at each end of the side
            local function at(t)
                return { x = lerp(from.x, to.x, t), y = lerp(from.y, to.y, t), z = lerp(from.z, to.z, t) }
            end
            local a = add(from, LIFT + OUTLINE_LIFT, outline)
            local b = add(at(CORNER_LENGTH), LIFT + OUTLINE_LIFT, outline)
            local c = add(at(1 - CORNER_LENGTH), LIFT + OUTLINE_LIFT, outline)
            local d = add(to, LIFT + OUTLINE_LIFT, outline)
            lines[#lines + 1], lines[#lines + 2] = a, b
            lines[#lines + 1], lines[#lines + 2] = c, d
        else
            local a = add(from, LIFT + OUTLINE_LIFT, outline)
            local b = add(to, LIFT + OUTLINE_LIFT, outline)
            lines[#lines + 1], lines[#lines + 2] = a, b
        end
    end

    if style.fillAlpha > 0 then
        local fill = (style.rgb << 8) | style.fillAlpha
        local first = #positions
        for _, point in ipairs(points) do add(point, LIFT, fill) end
        tris = { first, first + 1, first + 2, first, first + 2, first + 3 }
    end

    local shape = ShapeData.new()
    shape.positions = positions
    shape.rgba = rgba
    shape.lines = lines
    shape.tris = tris
    return shape
end

function Marker:_ensureInstance()
    if self.instance ~= nil and self.instance.isValid then return self.instance end
    self.instance = ShapeList.GetInstance(INSTANCE_NAME) or ShapeList.CreateInstance(INSTANCE_NAME)
    -- new instance, so none of the cached instance state applies any more
    self.builtStyle, self.colour, self.lineWidth, self.ignoreDepth, self.visible = nil, nil, nil, nil, nil
    return self.instance
end

function Marker:_setVisible(visible)
    if self.visible ~= visible then
        self.instance.visible = visible
        self.visible = visible
    end
end

-- style: { rgb, fillAlpha, cornersOnly, lineWidth, drawOnTop }, a new table
-- whenever a setting changes
-- opacity: 0 to 1, used for fading
function Marker:show(level, tileX, tileZ, style, opacity)
    local instance = self:_ensureInstance()
    if instance == nil then return false end

    local alpha = math.floor(math.max(0, math.min(1, opacity or 1)) * 255 + 0.5)
    if alpha == 0 then
        self:_setVisible(false)
        return true
    end

    if self.tile == nil or self.level ~= level or self.tileX ~= tileX or self.tileZ ~= tileZ then
        local tile = measureTile(level, tileX, tileZ)
        if tile == nil then
            -- ground isn't loaded yet, try again next frame
            self:_setVisible(false)
            return false
        end
        self.tile, self.level, self.tileX, self.tileZ = tile, level, tileX, tileZ
        self.builtStyle = nil
    end

    if self.builtStyle ~= style then
        if not instance:SetShapeData(buildShape(self.tile, style)) then
            self:_setVisible(false)
            return false
        end
        local centre = self.tile.centre
        instance.translation = Vector3.new(centre.x, centre.y, centre.z)
        self.builtStyle = style
    end

    -- the colour is multiplied with the shape, so this fades it without a rebuild.
    -- this runs every frame, so only touch the instance when something changed
    local colour = 0xFFFFFF00 | alpha
    if self.colour ~= colour then
        instance.colour = colour
        self.colour = colour
    end
    if self.lineWidth ~= style.lineWidth then
        instance.lineWidth = style.lineWidth
        self.lineWidth = style.lineWidth
    end
    if self.ignoreDepth ~= style.drawOnTop then
        instance.ignoreDepth = style.drawOnTop
        self.ignoreDepth = style.drawOnTop
    end
    self:_setVisible(true)
    return true
end

function Marker:hide()
    if self.instance ~= nil and self.instance.isValid then self:_setVisible(false) end
end

-- forget cached ground heights, e.g. after the map reloads
function Marker:invalidate()
    self.tile, self.builtStyle = nil, nil
end

function Marker:destroy()
    if self.instance ~= nil then
        local instance = self.instance
        pcall(function() ShapeList.DestroyInstance(instance) end)
    end
    self.instance = nil
    self:invalidate()
end

return Marker
