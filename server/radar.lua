--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Staff vision. OneSync only streams nearby players to a client, so the server sends every player's position to
-- staff with vision on. Nobody else ever receives it.

---@class UgAdmin.Internal.Radar
local Radar = {}
UgAdmin.Internal.Radar = Radar

---@class UgAdminBlip
---@field id integer
---@field name string
---@field coords vector3
---@field heading number
---@field state UgDeathState
---@field staff boolean
---@field vehicle boolean

local Config = UgAdmin.Internal.Config
local Staff = UgAdmin.Internal.Staff
local Mode = UgAdmin.Enums.Mode

local EVENT = GetCurrentResourceName() .. ':' .. UgAdmin.Enums.ClientEvents.Radar
local IDLE_WAIT = 1000

---Every player with a ped, sorted by source.
---@return UgAdminBlip[]
function Radar.Snapshot()
    local list = {}

    for _, player in ipairs(UgCore.Players.GetAll()) do
        local ped = GetPlayerPed(tostring(player.source))

        if ped and ped ~= 0 and DoesEntityExist(ped) then
            list[#list + 1] = {
                id = player.source,
                name = UgAdmin.Internal.NameOf(player.source),
                coords = GetEntityCoords(ped),
                heading = GetEntityHeading(ped),
                state = UgCore.Players.GetDeathState(player.source),
                staff = Player(player.source).state[UgAdmin.Enums.StateBags.Access] ~= nil,
                vehicle = GetVehiclePedIsIn(ped, false) ~= 0,
            }
        end
    end

    return list
end

---Sends one snapshot to every staff member with vision on. Returns how many received it.
---@return integer
function Radar.Tick()
    local watchers = {}

    for _, player in ipairs(UgCore.Players.GetAll()) do
        if Staff.HasMode(player.source, Mode.Vision) then
            watchers[#watchers + 1] = player.source
        end
    end

    if #watchers == 0 then
        return 0
    end

    local snapshot = Radar.Snapshot()

    for _, source in ipairs(watchers) do
        UgCore.Network.TriggerClient(source, EVENT, snapshot)
    end

    return #watchers
end

---Starts the loop. Runs once after a clean boot.
function Radar.Start()
    CreateThread(function()
        while true do
            local sent = Radar.Tick()

            Wait(sent > 0 and Config.Get().radarInterval or IDLE_WAIT)
        end
    end)
end
