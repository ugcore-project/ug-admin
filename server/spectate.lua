--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Spectating. The server moves the staff member into the target's routing bucket and remembers where they were.
-- Their client hides the ped and follows the target, so OneSync keeps streaming the target's area.

---@class UgAdmin.Internal.Spectate
local Spectate = {}
UgAdmin.Internal.Spectate = Spectate

---@class UgAdminSpectateSession
---@field target integer
---@field returnTo vector3
---@field bucket integer the staff member's bucket before spectating

local World = UgAdmin.Internal.World
local Staff = UgAdmin.Internal.Staff
local Errors = UgCore.Enums.Errors
local Action = UgAdmin.Enums.Action

local EVENT = GetCurrentResourceName() .. ':' .. UgAdmin.Enums.ClientEvents.Spectate

---@type table<integer, UgAdminSpectateSession>
local sessions = {}

---@param source integer
---@param target integer
local function show(source, target)
    UgCore.Network.TriggerClient(source, EVENT, target, World.CoordsOf(target), UgAdmin.Internal.NameOf(target))
end

---@param source integer
---@param target integer
---@return boolean ok
---@return UgErrorCode? errorCode
function Spectate.Start(source, target)
    if source == target then
        return false, Errors.InvalidArgs
    end

    local from = World.CoordsOf(source)

    if not from or not World.CoordsOf(target) then
        return false, Errors.NotFound
    end

    local session = sessions[source]

    if not session then
        session = {
            target = target,
            returnTo = from,
            bucket = GetPlayerRoutingBucket(tostring(source)),
        }
        sessions[source] = session
    end

    session.target = target
    SetPlayerRoutingBucket(tostring(source), GetPlayerRoutingBucket(tostring(target)))
    show(source, target)

    return true, nil
end

---Players sorted by source, without the staff member.
---@param source integer
---@return integer[]
local function others(source)
    local list = {}

    for _, player in ipairs(UgCore.Players.GetAll()) do
        if player.source ~= source then
            list[#list + 1] = player.source
        end
    end

    return list
end

---Switches to the next or previous player the staff member outranks.
---@param source integer
---@param direction integer 1 or -1
---@return boolean ok
---@return UgErrorCode? errorCode
function Spectate.Step(source, direction)
    local session = sessions[source]

    if not session or not Staff.Can(source, Action.Spectate) then
        return false, Errors.NotFound
    end

    local list = others(source)
    local count = #list
    local current = 0

    for index, player in ipairs(list) do
        if player == session.target then
            current = index
        end
    end

    for offset = 1, count do
        local candidate = list[((current - 1 + offset * direction) % count) + 1]

        if candidate and candidate ~= session.target and Staff.Outranks(source, candidate) then
            return Spectate.Start(source, candidate)
        end
    end

    return false, Errors.NotFound
end

---Ends spectating and sends the staff member back.
---@param source integer
---@return boolean ok
function Spectate.Stop(source)
    local session = sessions[source]

    if not session then
        return false
    end

    sessions[source] = nil
    SetPlayerRoutingBucket(tostring(source), session.bucket)
    UgCore.Network.TriggerClient(source, EVENT, nil)
    World.Teleport(source, session.returnTo, true)

    return true
end

---@param source integer
---@return integer? target
function Spectate.TargetOf(source)
    return sessions[source] and sessions[source].target
end

AddEventHandler('playerDropped', function()
    local dropped = math.tointeger(tonumber(source))

    if not dropped then
        return
    end

    sessions[dropped] = nil

    -- Whoever watched the player moves on to someone else, or comes back.
    for watcher, session in pairs(sessions) do
        if session.target == dropped and not Spectate.Step(watcher, 1) then
            Spectate.Stop(watcher)
        end
    end
end)
