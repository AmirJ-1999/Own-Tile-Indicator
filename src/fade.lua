-- Works out how visible the marker should be. It fades out after you've stood
-- still for a while and comes back quickly as soon as you move.
local Fade = {}
Fade.__index = Fade

local FADE_OUT_SECONDS = 0.5
local FADE_IN_SECONDS = 0.15
local MOVE_THRESHOLD = 1 -- fine units, anything smaller is just float noise
local MAX_STEP = 0.1     -- a long frame (alt-tab, loading) only moves the fade a little

function Fade.new()
    return setmetatable({ still = 0, level = 1 }, Fade)
end

-- shows the marker again, e.g. while changing settings so you can see the result
function Fade:wake()
    self.still = 0
end

-- returns opacity from 0 to 1
function Fade:update(dt, position, plane, enabled, delay)
    dt = tonumber(dt) or 0
    if dt ~= dt or dt < 0 then dt = 0 end
    dt = math.min(dt, MAX_STEP)

    local moved = self.lastX ~= nil and (
        math.abs(position.x - self.lastX) > MOVE_THRESHOLD
        or math.abs(position.z - self.lastZ) > MOVE_THRESHOLD
        or plane ~= self.lastPlane)
    if moved then
        self.still = 0
    else
        self.still = self.still + dt
    end
    self.lastX, self.lastZ, self.lastPlane = position.x, position.z, plane

    local target = (enabled and self.still >= delay) and 0 or 1
    if self.level < target then
        self.level = math.min(target, self.level + dt / FADE_IN_SECONDS)
    elseif self.level > target then
        self.level = math.max(target, self.level - dt / FADE_OUT_SECONDS)
    end

    -- smoothstep, so the fade eases in and out instead of moving at a flat rate
    local t = self.level
    return t * t * (3 - 2 * t)
end

return Fade
