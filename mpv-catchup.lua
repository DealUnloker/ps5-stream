-- Keeps the player at the live edge. After a stall (a display reconnecting, the Mac waking up,
-- a network hiccup) mpv resumes where it stopped and would stay that far behind for the rest of
-- the stream. This plays the buffered backlog faster until it is gone.

local START = 0.5   -- seconds of backlog that start catching up
local STOP = 0.05   -- seconds of backlog at which normal speed returns
local MAX_SPEED = 2

local catching_up = false
local ticks_behind = 0

mp.add_periodic_timer(0.1, function()
    local backlog = mp.get_property_number("demuxer-cache-duration", 0)
    if catching_up then
        catching_up = backlog > STOP
    else
        -- Three readings in a row, so a single late batch of packets does not change the speed.
        ticks_behind = backlog > START and ticks_behind + 1 or 0
        catching_up = ticks_behind >= 3
    end
    local speed = catching_up and math.min(1 + 2 * backlog, MAX_SPEED) or 1
    if speed ~= mp.get_property_number("speed") then
        mp.set_property_number("speed", speed)
    end
end)
