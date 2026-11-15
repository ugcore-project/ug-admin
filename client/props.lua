--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Map props staff deleted in noclip. They are not networked, so the server lists them in GlobalState and every client
-- removes them itself: the model hide keeps the map from streaming the prop back, and the instance already streamed
-- in is deleted, collision included. Script objects are never touched: networked ones are deleted by the server.

---@class UgAdmin.Internal.Props
local Props = {}
UgAdmin.Internal.Props = Props

local KEY = UgAdmin.Enums.GlobalState.HiddenProps
local RADIUS = 1.0

---@alias UgAdminHiddenProp { x: number, y: number, z: number, hash: integer }

---@type table<string, UgAdminHiddenProp>
local applied = {}
local version = 0

---One signed form, like the server, so the same model always gives the same key.
---@param hash integer
---@return integer
local function signed(hash)
    return hash > 0x7FFFFFFF and hash - 0x100000000 or hash
end

---@param prop UgAdminHiddenProp
---@return string
local function keyOf(prop)
    return ('%d:%.1f:%.1f:%.1f'):format(signed(prop.hash), prop.x, prop.y, prop.z)
end

---Hides the model at the spot and deletes the instance this client streamed in.
---@param prop UgAdminHiddenProp
local function hide(prop)
    CreateModelHideExcludingScriptObjects(prop.x, prop.y, prop.z, RADIUS, prop.hash, true)

    local object = GetClosestObjectOfType(prop.x, prop.y, prop.z, RADIUS, prop.hash, false, false, false)

    if object and object ~= 0 and DoesEntityExist(object) and not NetworkGetEntityIsNetworked(object) then
        SetEntityAsMissionEntity(object, true, true)
        DeleteObject(object)
    end
end

---@param prop UgAdminHiddenProp
local function show(prop)
    RemoveModelHide(prop.x, prop.y, prop.z, RADIUS, prop.hash, false)
end

---Brings the hidden props in line with the list the server keeps.
---@param props table[]
local function sync(props)
    local wanted = {}

    for _, prop in ipairs(props) do
        if type(prop) == 'table' and math.type(prop.hash) == 'integer' and type(prop.x) == 'number'
            and type(prop.y) == 'number' and type(prop.z) == 'number' then
            wanted[keyOf(prop)] = prop
        end
    end

    for key, prop in pairs(applied) do
        if not wanted[key] then
            show(prop)
            applied[key] = nil
        end
    end

    for key, prop in pairs(wanted) do
        if not applied[key] then
            hide(prop)
            applied[key] = prop
        end
    end
end

---@param state any the GlobalState value
local function apply(state)
    if type(state) == 'table' and math.type(state.version) == 'integer' and state.version ~= version and type(state.props) == 'table' then
        version = state.version
        sync(state.props)
    end
end

---Removes a prop on this client at once, before the server answers. Undo it with Props.Restore when it refuses.
---@param prop UgAdminHiddenProp
function Props.HideNow(prop)
    local key = keyOf(prop)

    if not applied[key] then
        hide(prop)
        applied[key] = prop
    end
end

---Brings back a prop hidden by Props.HideNow. The deleted instance returns when the map streams it in again.
---@param prop UgAdminHiddenProp
function Props.Restore(prop)
    local key = keyOf(prop)

    if applied[key] then
        show(applied[key])
        applied[key] = nil
    end
end

AddStateBagChangeHandler(KEY, 'global', function(_, _, value)
    apply(value)
end)

-- The list as it was when this client joined.
CreateThread(function()
    apply(GlobalState[KEY])
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        sync({})
    end
end)
