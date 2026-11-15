--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Character faces for the panel avatars, taken with ped headshots. Only peds this client can see have one: players
-- out of scope keep their initials. The page shows a headshot through its texture name, never through pixels.

---@class UgAdmin.Internal.Faces
local Faces = {}
UgAdmin.Internal.Faces = Faces

-- Headshot slots are a shared game resource: other scripts need some too.
local MAX_FACES = 20
-- Milliseconds a headshot MAY take to render before it is dropped.
local READY_TIMEOUT = 2000

---@type table<integer, { handle: integer, ped: integer, txd: string }> server id -> headshot
local shots = {}
local collecting = false

---@param id integer
local function release(id)
    local shot = shots[id]

    if shot then
        UnregisterPedheadshot(shot.handle)
        shots[id] = nil
    end
end

---Frees every headshot, such as when the panel closes.
function Faces.Release()
    local ids = {}

    for id in pairs(shots) do
        ids[#ids + 1] = id
    end

    for _, id in ipairs(ids) do
        release(id)
    end
end

---@param ped integer
---@return { handle: integer, ped: integer, txd: string }?
local function take(ped)
    local handle = RegisterPedheadshot(ped)
    local deadline = GetGameTimer() + READY_TIMEOUT

    while not IsPedheadshotReady(handle) and GetGameTimer() < deadline do
        Wait(0)
    end

    local txd = IsPedheadshotReady(handle) and IsPedheadshotValid(handle) and GetPedheadshotTxdString(handle) or nil

    if type(txd) ~= 'string' or txd == '' then
        UnregisterPedheadshot(handle)

        return nil
    end

    return {
        handle = handle,
        ped = ped,
        txd = txd,
    }
end

---Headshots of the listed players this client can see, new ones taken, gone ones freed. MUST run in a thread.
---@param ids integer[] server ids, in the order they matter
---@return table<string, string>? faces server id -> texture name, nil while another collection runs
function Faces.Collect(ids)
    if collecting then
        return nil
    end

    collecting = true

    local wanted, faces, count = {}, {}, 0

    for _, id in ipairs(ids) do
        wanted[id] = true

        local player = GetPlayerFromServerId(id)
        local ped = player ~= -1 and GetPlayerPed(player) or 0

        -- A respawn or a model change makes a new ped: the old headshot shows someone else.
        if shots[id] and shots[id].ped ~= ped then
            release(id)
        end

        if not shots[id] and ped ~= 0 and DoesEntityExist(ped) and count < MAX_FACES then
            shots[id] = take(ped)
        end

        if shots[id] then
            faces[tostring(id)] = shots[id].txd
            count = count + 1
        end
    end

    local gone = {}

    for id in pairs(shots) do
        if not wanted[id] then
            gone[#gone + 1] = id
        end
    end

    for _, id in ipairs(gone) do
        release(id)
    end

    collecting = false

    return faces
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        Faces.Release()
    end
end)
