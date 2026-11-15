--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- What the server asks this client to do: teleport, heal, repair, show a big message, and the two questions only
-- a client can answer (a vehicle model's type, the waypoint).

---@class UgAdmin.Internal.Events
local Events = {}
UgAdmin.Internal.Events = Events

local ClientEvents = UgAdmin.Enums.ClientEvents
local ClientCallbacks = UgAdmin.Enums.ClientCallbacks
local Shard = UgAdmin.Enums.Shard
local Schema = UgCore.Schema

local FADE_MS = 300
local COLLISION_TIMEOUT = 3000
local GROUND_STEPS = { 1000.0, 800.0, 600.0, 400.0, 300.0, 200.0, 150.0, 100.0, 50.0, 25.0, 0.0 }
local SHARD_MOVIE = 'MP_BIG_MESSAGE_FREEMODE'
local ShardColor = UgAdmin.Enums.ShardColor
local KINDS = {}

for _, kind in pairs(Shard) do
    KINDS[kind] = true
end

-- Text color codes of the game's scaleform strings.
local COLOR_CODES = {
    [ShardColor.Purple] = '~p~', [ShardColor.Red] = '~r~', [ShardColor.Blue] = '~b~', [ShardColor.Green] = '~g~',
    [ShardColor.Yellow] = '~y~', [ShardColor.Orange] = '~o~', [ShardColor.White] = '~w~', [ShardColor.Grey] = '~c~',
}

---The owner's look for a shard kind, or nil when the owner left it out.
---@param kind UgAdminShard
---@return { duration: integer, color: UgAdminShardColor, sound?: { name: string, set: string } }?
local function shardLook(kind)
    local config = GlobalState[UgAdmin.Enums.GlobalState.Config]
    local shards = type(config) == 'table' and config.shards

    return type(shards) == 'table' and shards[kind] or nil
end
local HEALTH = Schema.Integer({
    min = 101,
    max = 200,
})
local ARMOR = Schema.Integer({
    min = 0,
    max = 100,
})
local SHARD_TEXT = Schema.String({
    min = 1,
    max = 256,
})
local MODEL = Schema.String({
    min = 1,
    max = 32,
    pattern = '^[%w_]+$',
})
local ORIGIN = vector3(0.0, 0.0, 0.0)
local SUBMARINES = {
    submersible = true,
    submersible2 = true,
    avisa = true,
    kosatka = true,
}
local TRAIN_CLASS = 21

---@type table[] open reports, for the panel
local reports = {}

---@return table[]
function Events.GetReports()
    return reports
end

---Ground at x, y, probing from the sky down while collision streams in.
---@param x number
---@param y number
---@return number? z
local function findGround(x, y)
    for _, height in ipairs(GROUND_STEPS) do
        RequestCollisionAtCoord(x, y, height)

        local found, z = GetGroundZFor_3dCoord(x, y, height, false)

        if found then
            return z
        end

        Wait(0)
    end

    return nil
end

---Moves the player, with their vehicle when they drive it, behind a short fade.
---@param coords vector3
---@param exact boolean false to find the ground under coords
function Events.Teleport(coords, exact)
    if UgAdmin.Internal.Noclip.IsActive() and UgAdmin.Internal.Noclip.MoveTo(coords) then
        return
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped

    DoScreenFadeOut(FADE_MS)
    Wait(FADE_MS)

    FreezeEntityPosition(entity, true)
    SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, false)

    local deadline = GetGameTimer() + COLLISION_TIMEOUT

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do
        Wait(0)
    end

    local z = coords.z

    if not exact then
        z = findGround(coords.x, coords.y) or coords.z
    end

    SetEntityCoords(entity, coords.x, coords.y, z, false, false, false, false)
    FreezeEntityPosition(entity, UgAdmin.Internal.Modes.IsFrozen())
    DoScreenFadeIn(FADE_MS)
end

---Plays a big full-screen message, like GTA's mission results.
---@param kind UgAdminShard
---@param text string
function Events.Shard(kind, text)
    local look = shardLook(kind)
    local ok, movie = false, nil

    if look then
        ok, movie = UgLib.Streaming.ScaleformMovie(SHARD_MOVIE, 3000)
    end

    if not look or not ok or not movie then
        UgAdmin.Internal.Notify.Show('shard.' .. kind .. '.text', {
            text = text,
        })

        return
    end

    local title = UgAdmin.Internal.Notify.Text('shard.' .. kind .. '.title')

    BeginScaleformMovieMethod(movie, 'SHOW_SHARD_WASTED_MP_MESSAGE')
    ScaleformMovieMethodAddParamPlayerNameString((COLOR_CODES[look.color] or '') .. title)
    ScaleformMovieMethodAddParamPlayerNameString(text)
    ScaleformMovieMethodAddParamInt(5)
    EndScaleformMovieMethod()

    if look.sound then
        PlaySoundFrontend(-1, look.sound.name, look.sound.set, true)
    end

    local untilAt = GetGameTimer() + look.duration

    while GetGameTimer() < untilAt do
        DrawScaleformMovieFullscreen(movie, 255, 255, 255, 255, 0)
        Wait(0)
    end

    SetScaleformMovieAsNoLongerNeeded(movie)
end

---Type of a vehicle model for the server's CreateVehicleServerSetter. '' for unknown models.
---@param model string
---@return string
function Events.VehicleType(model)
    if not Schema.Check(MODEL, model) then
        return ''
    end

    local hash = joaat(model)

    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return ''
    end

    if SUBMARINES[model:lower()] then return 'submarine' end
    if IsThisModelAHeli(hash) then return 'heli' end
    if IsThisModelAPlane(hash) then return 'plane' end
    if IsThisModelABoat(hash) or IsThisModelAJetski(hash) then return 'boat' end
    if IsThisModelABike(hash) or IsThisModelABicycle(hash) or IsThisModelAQuadbike(hash) then return 'bike' end
    if GetVehicleClassFromName(hash) == TRAIN_CLASS then return 'train' end

    return 'automobile'
end

---The waypoint, with z 0 so the teleport finds the ground. The origin without a waypoint.
---@return vector3
function Events.Waypoint()
    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then
        return ORIGIN
    end

    local at = GetBlipInfoIdCoord(blip)

    return vector3(at.x, at.y, 0.0)
end

UgCore.Network.Register(ClientEvents.Teleport, function(coords, exact)
    if type(coords) == 'vector3' then
        CreateThread(function()
            Events.Teleport(coords, exact == true)
        end)
    end
end)

-- Sent by the server after /heal or /revive. A ped can be dead here while the server still counts the player alive,
-- when the death report never got through: it is brought back in place, since staff asked for it.
UgCore.Network.Register(ClientEvents.Heal, function()
    local ped = PlayerPedId()

    if IsPedFatallyInjured(ped) then
        local coords = GetEntityCoords(ped)

        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), 0, false)
        ped = PlayerPedId()
    end

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasks(ped)
end)

-- Sent by the server after /setstats. A fatally injured ped is left alone: only revive brings it back.
UgCore.Network.Register(ClientEvents.Stats, function(health, armor)
    local ped = PlayerPedId()

    if health ~= nil and Schema.Check(HEALTH, health) and not IsPedFatallyInjured(ped) then
        SetEntityHealth(ped, health)
    end

    if armor ~= nil and Schema.Check(ARMOR, armor) then
        SetPedArmour(ped, armor)
    end
end)

UgCore.Network.Register(ClientEvents.Fix, function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

    if vehicle == 0 then
        return
    end

    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineOn(vehicle, true, true, false)
end)

UgCore.Network.Register(ClientEvents.Shard, function(kind, text)
    if KINDS[kind] and Schema.Check(SHARD_TEXT, text) then
        CreateThread(function()
            Events.Shard(kind, text)
        end)
    end
end)

UgCore.Network.Register(ClientEvents.Reports, function(list)
    reports = type(list) == 'table' and list or {}
    UgAdmin.Internal.Panel.SetReports(reports)
end)

UgCore.Callback.Register(ClientCallbacks.VehicleType, Events.VehicleType)
UgCore.Callback.Register(ClientCallbacks.Waypoint, Events.Waypoint)
