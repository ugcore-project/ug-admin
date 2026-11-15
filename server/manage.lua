--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Player management on top of the basics in actions.lua: live stats, exact balances, inventory slots, sanctions,
-- private messages, notes, preset places and actions on everyone at once. Same pipeline: Actions.Run checks them.

local Actions = UgAdmin.Internal.Actions
local Sanctions = UgAdmin.Internal.Sanctions
local Notes = UgAdmin.Internal.Notes
local Notify = UgAdmin.Internal.Notify
local World = UgAdmin.Internal.World
local Config = UgAdmin.Internal.Config
local Staff = UgAdmin.Internal.Staff
local Action = UgAdmin.Enums.Action
local Sanction = UgAdmin.Enums.Sanction
local StateBags = UgAdmin.Enums.StateBags
local ClientEvents = UgAdmin.Enums.ClientEvents
local Shard = UgAdmin.Enums.Shard
local Errors = UgCore.Enums.Errors
local DeathState = UgCore.Enums.DeathState

local RESOURCE = GetCurrentResourceName()
local CONSOLE = 0
local REQUIRED = 'required'
local SELF = 'self'
local SOURCE = 'ug-admin'
-- The location name that means the staff member's own waypoint.
local WAYPOINT = 'waypoint'
-- Players brought together stand on a ring this wide around the staff member.
local RING = 2.0

---@param name UgAdminClientEvent
---@return string
local function event(name)
    return RESOURCE .. ':' .. name
end

---@param source integer
---@return string
local function name(source)
    return UgAdmin.Internal.NameOf(source)
end

---Everyone online but the staff member, who they outrank, sorted by source.
---@param actor integer
---@return integer[]
local function others(actor)
    local list = {}

    for _, player in ipairs(UgCore.Players.GetAll()) do
        if player.source ~= actor and Staff.Outranks(actor, player.source) then
            list[#list + 1] = player.source
        end
    end

    return list
end

---@param module string
---@param config string
---@return table
local function definitions(module, config)
    if not UgCore.Modules.IsEnabled(module) then
        return {}
    end

    local values = UgCore.Config.Get(module, config)

    return type(values) == 'table' and values or {}
end

---@param kind UgAdminSanction
---@return UgAdminDefinition
local function sanction(kind)
    return {
        target = REQUIRED,
        outrank = true,
        args = { 'minutes' },
        run = function(ctx)
            local minutes, reason = ctx.args.minutes --[[@as integer]], ctx.args.reason

            if ctx.target == ctx.actor then
                return false, Errors.InvalidArgs
            end

            Sanctions.Apply(ctx.actor, ctx.target --[[@as integer]], kind, minutes, reason)

            return true, nil, ('%dm%s'):format(minutes, reason and (', ' .. reason) or ''), {
                target = name(ctx.target),
                minutes = minutes,
            }
        end,
    }
end

---@param kind UgAdminSanction
---@return UgAdminDefinition
local function release(kind)
    return {
        target = REQUIRED,
        run = function(ctx)
            if not Sanctions.Lift(ctx.target --[[@as integer]], kind) then
                return false, Errors.NotFound
            end

            return true, nil, nil, {
                target = name(ctx.target),
            }
        end,
    }
end

---@type table<UgAdminAction, UgAdminDefinition>
local DEFINITIONS = {
    [Action.Message] = {
        target = REQUIRED,
        args = { 'text' },
        run = function(ctx)
            UgCore.Network.TriggerClient(ctx.target, event(ClientEvents.Shard), Shard.Message, ctx.args.text)

            return true, nil, ctx.args.text, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.SendTo] = {
        target = REQUIRED,
        outrank = true,
        args = { 'location' },
        run = function(ctx)
            local location = ctx.args.location --[[@as string]]
            local coords, exact, label

            if location == WAYPOINT then
                coords = ctx.actor ~= CONSOLE and World.Waypoint(ctx.actor) or nil
                exact, label = false, Notify.Text('location.waypoint')
            else
                local place = Config.Get().locations[location]

                coords, exact, label = place and place.coords, true, place and place.label
            end

            if not coords then
                return false, Errors.NotFound
            end

            World.Teleport(ctx.target, coords, exact)

            return true, nil, location, {
                target = name(ctx.target),
                location = label,
            }
        end,
    },

    [Action.Jail] = sanction(Sanction.Jail),
    [Action.Unjail] = release(Sanction.Jail),
    [Action.Mute] = sanction(Sanction.Mute),
    [Action.Unmute] = release(Sanction.Mute),

    [Action.Note] = {
        target = REQUIRED,
        args = { 'text' },
        silent = true,
        run = function(ctx)
            local ok, errorCode = Notes.Add(ctx.actor, ctx.target --[[@as integer]], ctx.args.text --[[@as string]])

            return ok, errorCode, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.DeleteNote] = {
        args = { 'note' },
        silent = true,
        run = function(ctx)
            if not Notes.Delete(ctx.args.note --[[@as integer]]) then
                return false, Errors.NotFound
            end

            return true
        end,
    },

    [Action.SetStats] = {
        target = SELF,
        outrank = true,
        run = function(ctx)
            local health, armor = ctx.args.health, ctx.args.armor

            if not health and not armor then
                return false, Errors.InvalidArgs
            end

            -- A downed or dead player is brought back with revive, never with a health value.
            if health and UgCore.Players.GetDeathState(ctx.target) ~= DeathState.Alive then
                return false, Errors.InvalidArgs
            end

            UgCore.Network.TriggerClient(ctx.target, event(ClientEvents.Stats), health, armor)

            return true, nil, ('health %s, armor %s'):format(tostring(health or '-'), tostring(armor or '-')), {
                target = name(ctx.target),
            }
        end,
    },

    [Action.SetNeed] = {
        target = SELF,
        character = true,
        args = { 'need', 'value' },
        run = function(ctx)
            local need = ctx.args.need --[[@as string]]
            local definition = definitions('needs', 'needs')[need]

            if not definition then
                return false, Errors.NotFound
            end

            local ok, value, errorCode = UgCore.Needs.Set(ctx.target, need, ctx.args.value)

            return ok, errorCode, ('%s %s'):format(need, tostring(value)), {
                target = name(ctx.target),
                need = definition.label or need,
                value = math.floor((value or 0) + 0.5),
            }
        end,
    },

    [Action.SetMoney] = {
        target = REQUIRED,
        character = true,
        args = { 'account', 'amount' },
        run = function(ctx)
            local account, amount = ctx.args.account --[[@as string]], ctx.args.amount --[[@as integer]]
            local definition = definitions('accounts', 'accounts')[account]

            if not definition then
                return false, Errors.NotFound
            end

            if amount < 0 and not definition.allowNegative then
                return false, Errors.InvalidArgs
            end

            local ok, balance, errorCode = UgCore.Accounts.Set(ctx.target, account, amount, SOURCE)

            return ok, errorCode, ('%s = %s'):format(account, tostring(balance)), {
                target = name(ctx.target),
                account = definition.label or account,
                amount = UgLib.Format.Money(amount),
            }
        end,
    },

    [Action.RemoveItem] = {
        target = REQUIRED,
        outrank = true,
        character = true,
        args = { 'slot' },
        run = function(ctx)
            local slot, item = ctx.args.slot --[[@as integer]], nil

            for _, entry in ipairs(UgCore.Inventory.GetItems(ctx.target)) do
                if entry.slot == slot then
                    item = entry
                end
            end

            if not item then
                return false, Errors.NotFound
            end

            local count = math.min(ctx.args.count or item.count, item.count)
            local ok, errorCode = UgCore.Inventory.RemoveFromSlot(ctx.target, slot, count, SOURCE)

            return ok, errorCode, ('%dx %s from slot %d'):format(count, item.name, slot), {
                target = name(ctx.target),
                item = item.name,
                count = count,
            }
        end,
    },

    [Action.ReviveAll] = {
        run = function(ctx)
            local count = 0

            for _, player in ipairs(UgCore.Players.GetAll()) do
                if UgCore.Players.GetDeathState(player.source) ~= DeathState.Alive
                    and Actions.Restore({
                        actor = ctx.actor,
                        target = player.source,
                        args = {},
                    }) then
                    count = count + 1
                end
            end

            if count == 0 then
                return false, Errors.NotFound
            end

            return true, nil, ('%d player(s)'):format(count), {
                count = count,
            }
        end,
    },

    [Action.BringAll] = {
        ped = true,
        run = function(ctx)
            local origin = World.CoordsOf(ctx.actor)
            local radius = ctx.args.radius

            if not origin then
                return false, Errors.NotLoaded
            end

            local list = {}

            for _, source in ipairs(others(ctx.actor)) do
                local coords = World.CoordsOf(source)

                if coords and (not radius or #(coords - origin) <= radius) then
                    list[#list + 1] = source
                end
            end

            if #list == 0 then
                return false, Errors.NotFound
            end

            for index, source in ipairs(list) do
                local angle = (index - 1) * (2 * math.pi / #list)

                World.Teleport(source, vector3(origin.x + math.cos(angle) * RING, origin.y + math.sin(angle) * RING, origin.z), true)
            end

            return true, nil, ('%d player(s)'):format(#list), {
                count = #list,
            }
        end,
    },

    [Action.FreezeAll] = {
        run = function(ctx)
            local list = others(ctx.actor)

            if #list == 0 then
                return false, Errors.NotFound
            end

            -- Freezes everyone when anyone still moves, frees everyone otherwise.
            local frozen = false

            for _, source in ipairs(list) do
                frozen = frozen or Player(source).state[StateBags.Frozen] ~= true
            end

            for _, source in ipairs(list) do
                Actions.SetFrozen(source, frozen)
            end

            return true, nil, ('%d player(s) %s'):format(#list, frozen and 'on' or 'off'), {
                count = #list,
                state = Notify.Text(frozen and 'state.on' or 'state.off'),
            }
        end,
    },
}

for action, definition in pairs(DEFINITIONS) do
    Actions.Define(action, definition)
end
