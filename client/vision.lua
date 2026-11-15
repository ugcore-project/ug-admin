--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Staff vision: every player on the map from the server's radar, and id, name and health over nearby heads.
-- Colors: staff purple, downed orange, dead red.

---@class UgAdmin.Internal.Vision
local Vision = {}
UgAdmin.Internal.Vision = Vision

local Schema = UgCore.Schema
local DeathState = UgCore.Enums.DeathState

local TAG_DISTANCE = 120.0
local TAG_HEIGHT = 1.15
local MAX_PLAYERS = 2048
-- Blip sprites and colors from the Cfx blip reference.
local SPRITE_PLAYER, SPRITE_VEHICLE = 1, 225
local COLOR = {
    player = 0,
    staff = 27,
    downed = 47,
    dead = 1,
}
local TEXT = {
    player = { 255, 255, 255, 230 },
    staff = { 180, 150, 255, 230 },
    downed = { 255, 170, 60, 230 },
    dead = { 255, 80, 80, 230 },
}

local RADAR = Schema.Array(Schema.Object({
    id = Schema.Integer({
        min = 1,
        max = 65535,
    }),
    name = Schema.String({
        max = 64,
    }),
    coords = Schema.Vector3({
        maxComponent = 20000,
    }),
    heading = Schema.Number({
        min = -720,
        max = 720,
    }),
    state = Schema.String({
        max = 16,
    }),
    staff = Schema.Boolean(),
    vehicle = Schema.Boolean(),
}), {
    max = MAX_PLAYERS,
})

local enabled = false
---@type table<integer, integer> server id -> blip
local blips = {}
---@type table<integer, table> server id -> last radar entry
local known = {}

---@param entry table
---@return string
local function tone(entry)
    if entry.state == DeathState.Dead then
        return 'dead'
    end

    if entry.state == DeathState.Downed then
        return 'downed'
    end

    return entry.staff and 'staff' or 'player'
end

local function clear()
    for id, blip in pairs(blips) do
        RemoveBlip(blip)
        blips[id] = nil
    end

    known = {}
end

---@param list table[]
function Vision.Update(list)
    if not enabled then
        return
    end

    local self = GetPlayerServerId(PlayerId())
    local seen = {}

    for _, entry in ipairs(list) do
        if entry.id ~= self then
            seen[entry.id] = true
            known[entry.id] = entry

            local blip = blips[entry.id]

            if not blip then
                blip = AddBlipForCoord(entry.coords.x, entry.coords.y, entry.coords.z)
                SetBlipCategory(blip, 7)
                SetBlipAsShortRange(blip, false)
                blips[entry.id] = blip
            end

            SetBlipCoords(blip, entry.coords.x, entry.coords.y, entry.coords.z)
            SetBlipSprite(blip, entry.vehicle and SPRITE_VEHICLE or SPRITE_PLAYER)
            SetBlipRotation(blip, math.floor(entry.heading))
            SetBlipColour(blip, COLOR[tone(entry)])
            ShowHeadingIndicatorOnBlip(blip, not entry.vehicle)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('[%d] %s'):format(entry.id, entry.name))
            EndTextCommandSetBlipName(blip)
        end
    end

    for id, blip in pairs(blips) do
        if not seen[id] then
            RemoveBlip(blip)
            blips[id] = nil
            known[id] = nil
        end
    end
end

---@param on boolean
function Vision.SetEnabled(on)
    enabled = on

    if not on then
        clear()
    end
end

---@return boolean
function Vision.IsEnabled()
    return enabled
end

---Number of players on the map. For tests and the panel.
---@return integer
function Vision.Count()
    local count = 0

    for _ in pairs(blips) do
        count = count + 1
    end

    return count
end

local function tags()
    local origin = GetEntityCoords(PlayerPedId())
    local self = PlayerId()

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)

        if player ~= self and ped ~= 0 then
            local at = GetEntityCoords(ped)

            if #(at - origin) <= TAG_DISTANCE then
                local id = GetPlayerServerId(player)
                local entry = known[id] or {
                    state = DeathState.Alive,
                    staff = false,
                }
                local health = math.max(GetEntityHealth(ped) - 100, 0)

                UgLib.Draw.Text3D(at + vector3(0.0, 0.0, TAG_HEIGHT), ('[%d] %s  %d'):format(id, GetPlayerName(player), health), {
                    scale = 0.32,
                    color = TEXT[tone(entry)],
                    maxDistance = TAG_DISTANCE,
                    outline = true,
                })
            end
        end
    end
end

UgCore.Network.Register(UgAdmin.Enums.ClientEvents.Radar, function(list)
    local ok, checked = Schema.Check(RADAR, list)

    if ok then
        Vision.Update(checked)
    end
end)

CreateThread(function()
    while true do
        if enabled then
            tags()
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clear()
    end
end)
