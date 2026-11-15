--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Who may do what. Access comes from ug-core groups only: `access` in config.lua names the lowest group per action,
-- and ug-core's inheritance decides who is in it. The `ug-admin:Access` statebag mirrors it for the client, which uses
-- it for keybinds and panel buttons only. The server checks again on every request.

---@class UgAdmin.Internal.Staff
local Staff = {}
UgAdmin.Internal.Staff = Staff

local Config = UgAdmin.Internal.Config
local Action = UgAdmin.Enums.Action
local StateBags = UgAdmin.Enums.StateBags

local CONSOLE = 0

---@param source integer
---@param action UgAdminAction
---@return boolean
function Staff.Can(source, action)
    if source == CONSOLE then
        return true
    end

    local group = Config.Get().access[action]

    return group ~= nil and UgCore.Permissions.IsInGroup(source, group)
end

---True when the actor may act on the target: themselves, or someone they outrank. The console outranks everyone.
---@param actor integer
---@param target integer
---@return boolean
function Staff.Outranks(actor, target)
    return actor == target or UgCore.Permissions.CanTarget(actor, target)
end

---Actions the player may use, sorted.
---@param source integer
---@return UgAdminAction[]
function Staff.ActionsOf(source)
    local list = {}

    for _, action in pairs(Action) do
        if Staff.Can(source, action) then
            list[#list + 1] = action
        end
    end

    table.sort(list)

    return list
end

---True for anyone with at least one action.
---@param source integer
---@return boolean
function Staff.IsStaff(source)
    for _, action in pairs(Action) do
        if Staff.Can(source, action) then
            return true
        end
    end

    return false
end

---Staff that may use the action, sorted by source.
---@param action UgAdminAction
---@return integer[]
function Staff.With(action)
    local list = {}

    for _, player in ipairs(UgCore.Players.GetAll()) do
        if Staff.Can(player.source, action) then
            list[#list + 1] = player.source
        end
    end

    return list
end

---Publishes the player's actions. Turns off modes they lost.
---@param source integer
function Staff.Sync(source)
    local actions = Staff.ActionsOf(source)
    local state = Player(source).state

    state:set(StateBags.Access, #actions > 0 and actions or nil, true)

    local modes = state[StateBags.Mode]

    if type(modes) == 'table' then
        local kept, changed = {}, false

        for mode in pairs(modes) do
            if Staff.Can(source, mode) then
                kept[mode] = true
            else
                changed = true
            end
        end

        if changed then
            state:set(StateBags.Mode, next(kept) and kept or nil, true)
        end
    end
end

---Every connected player.
function Staff.SyncAll()
    for _, player in ipairs(UgCore.Players.GetAll()) do
        Staff.Sync(player.source)
    end
end

---@param source integer
---@param mode UgAdminMode
---@return boolean
function Staff.HasMode(source, mode)
    local modes = Player(source).state[StateBags.Mode]

    return type(modes) == 'table' and modes[mode] == true
end

---Turns a mode on or off. Mode names are their action names.
---@param source integer
---@param mode UgAdminMode
---@param enabled boolean
function Staff.SetMode(source, mode, enabled)
    local state = Player(source).state
    local modes = type(state[StateBags.Mode]) == 'table' and state[StateBags.Mode] or {}

    modes[mode] = enabled or nil
    state:set(StateBags.Mode, next(modes) and modes or nil, true)
end
