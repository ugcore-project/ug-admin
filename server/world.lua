--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Positions, teleports and vehicles. Every position is read from the ped on the server (OneSync), never from a client.

---@class UgAdmin.Internal.World
local World = {}
UgAdmin.Internal.World = World

local ClientEvents = UgAdmin.Enums.ClientEvents
local Errors = UgCore.Enums.Errors

local RESOURCE = GetCurrentResourceName()
local TELEPORT_EVENT = RESOURCE .. ':' .. ClientEvents.Teleport
local VEHICLE_TYPE = RESOURCE .. ':' .. UgAdmin.Enums.ClientCallbacks.VehicleType
local VEHICLE_TYPES = {
    automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true, train = true,
}
local TYPE_RULE = UgCore.Schema.String({
    max = 16,
})
local SPAWN_TIMEOUT = 3000
local DRIVER_SEAT = -1
local PLATE = 'UG ADMIN'
local WAYPOINT = RESOURCE .. ':' .. UgAdmin.Enums.ClientCallbacks.Waypoint
local WAYPOINT_RULE = UgCore.Schema.Vector3({
    maxComponent = 20000,
})
local ORIGIN = vector3(0.0, 0.0, 0.0)

---@type table<integer, vector3> where each player was before ug-admin last moved them
local back = {}
---@type table<integer, integer> the last vehicle each staff member spawned
local spawned = {}

---@param source integer
---@return vector3?
function World.CoordsOf(source)
    local ped = GetPlayerPed(tostring(source))

    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    return GetEntityCoords(ped)
end

---Moves a player. Their current position becomes their way back.
---@param source integer
---@param coords vector3
---@param exact? boolean false to let the client find the ground under coords
---@return boolean ok
function World.Teleport(source, coords, exact)
    local from = World.CoordsOf(source)

    if not from then
        return false
    end

    back[source] = from
    UgCore.Network.TriggerClient(source, TELEPORT_EVENT, coords, exact ~= false)

    return true
end

---Sends the player back to where ug-admin last moved them from. That spot becomes the new way back.
---@param source integer
---@return boolean ok
function World.Back(source)
    local coords = back[source]

    return coords ~= nil and World.Teleport(source, coords, true)
end

---@param source integer
---@return vector3?
function World.GetBack(source)
    return back[source]
end

---The waypoint of a staff member, with z 0 so a teleport finds the ground. Only their own client knows it. MUST run
---in a thread.
---@param source integer
---@return vector3? coords nil without a waypoint or an answer
function World.Waypoint(source)
    local ok, coords = UgCore.Callback.Await(source, WAYPOINT, {
        schema = WAYPOINT_RULE,
        timeout = 5000,
    })

    if not ok or coords == ORIGIN then
        return nil
    end

    return coords
end

---Spawns a vehicle at the staff member and seats them as driver. MUST run in a thread.
---@param source integer
---@param model string
---@param replace boolean delete the last vehicle this staff member spawned
---@return boolean ok
---@return integer|UgErrorCode result the vehicle, or an error code
function World.SpawnVehicle(source, model, replace)
    local ped = GetPlayerPed(tostring(source))

    if not ped or ped == 0 then
        return false, Errors.NotLoaded
    end

    -- Only the client knows the model's type. Its answer is untrusted and checked against the known types.
    local ok, kind = UgCore.Callback.Await(source, VEHICLE_TYPE, {
        schema = TYPE_RULE,
        timeout = 5000,
    }, model)

    if not ok or not VEHICLE_TYPES[kind] then
        return false, Errors.NotFound
    end

    if replace and spawned[source] and DoesEntityExist(spawned[source]) then
        DeleteEntity(spawned[source])
    end

    local coords = GetEntityCoords(ped)
    local vehicle = CreateVehicleServerSetter(joaat(model), kind, coords.x, coords.y, coords.z, GetEntityHeading(ped))
    local deadline = GetGameTimer() + SPAWN_TIMEOUT

    while not DoesEntityExist(vehicle) do
        if GetGameTimer() >= deadline then
            return false, Errors.InternalError
        end

        Wait(0)
    end

    SetVehicleNumberPlateText(vehicle, PLATE)
    SetPedIntoVehicle(ped, vehicle, DRIVER_SEAT)
    spawned[source] = vehicle

    return true, vehicle
end

---Vehicles with a player in them.
---@return table<integer, boolean>
local function occupied()
    local list = {}

    for _, player in ipairs(GetPlayers()) do
        local vehicle = GetVehiclePedIsIn(GetPlayerPed(player), false)

        if vehicle ~= 0 then
            list[vehicle] = true
        end
    end

    return list
end

---Deletes the vehicle the staff member sits in, or every empty vehicle within radius.
---@param source integer
---@param radius? number
---@return integer count deleted
function World.DeleteVehicles(source, radius)
    local ped = GetPlayerPed(tostring(source))
    local current = GetVehiclePedIsIn(ped, false)

    if current ~= 0 and not radius then
        DeleteEntity(current)

        return 1
    end

    local origin = GetEntityCoords(ped)
    local skip, count = occupied(), 0

    for _, vehicle in ipairs(GetAllVehicles() --[[@as integer[] ]]) do
        if not skip[vehicle] and #(GetEntityCoords(vehicle) - origin) <= (radius or 5.0) then
            DeleteEntity(vehicle)
            count = count + 1
        end
    end

    return count
end

---Deletes a networked entity that is not a player.
---@param netId integer
---@return boolean ok
---@return string? what model hash, for the log
function World.DeleteEntity(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)

    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, nil
    end

    if GetEntityType(entity) == 1 and IsPedAPlayer(entity) then
        return false, nil
    end

    local model = GetEntityModel(entity)

    DeleteEntity(entity)

    return true, ('model %d'):format(model)
end

-- Map props are not networked, so the server cannot delete them. Every client hides the model at that spot instead,
-- until the server restarts. The oldest hidden prop comes back past the limit.
local MAX_HIDDEN = 256
local PROP_RANGE = 450.0
local SAME_SPOT = 1.0

---@type { x: number, y: number, z: number, hash: integer }[]
local hidden = {}
local hiddenVersion = 0

---Hides a map prop for everyone. The staff member MUST be near it: noclip carries the ped along with the camera.
---@param actor integer
---@param coords vector3
---@param hash integer
---@return boolean ok
---@return UgErrorCode|string detail error code, or the log detail
function World.HideProp(actor, coords, hash)
    if not UgCore.Guard.IsNear(actor, coords, PROP_RANGE) then
        return false, Errors.NotFound
    end

    -- One signed form, so the same model always compares equal.
    if hash > 0x7FFFFFFF then
        hash = hash - 0x100000000
    end

    for _, prop in ipairs(hidden) do
        if prop.hash == hash and #(vector3(prop.x, prop.y, prop.z) - coords) <= SAME_SPOT then
            return true, ('model %d'):format(hash)
        end
    end

    if #hidden >= MAX_HIDDEN then
        table.remove(hidden, 1)
    end

    hidden[#hidden + 1] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        hash = hash,
    }
    hiddenVersion = hiddenVersion + 1
    GlobalState:set(UgAdmin.Enums.GlobalState.HiddenProps, {
        version = hiddenVersion,
        props = hidden,
    }, true)

    return true, ('model %d at %.1f, %.1f, %.1f'):format(hash, coords.x, coords.y, coords.z)
end

AddEventHandler('playerDropped', function()
    local source = math.tointeger(tonumber(source))

    if source then
        back[source] = nil
        spawned[source] = nil
    end
end)
