--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Every staff action, in one place. Chat commands and the panel both call Actions.Run, so access, rank, target and
-- argument checks, the audit log and the answer to the staff member are the same whichever way an action comes in.

---@class UgAdmin.Internal.Actions
local Actions = {}
UgAdmin.Internal.Actions = Actions

---@class UgAdminArgs
---@field reason? string
---@field duration? string
---@field account? string
---@field amount? integer
---@field job? string
---@field grade? integer
---@field item? string
---@field count? integer
---@field group? string
---@field text? string
---@field model? string
---@field radius? number
---@field identifier? string
---@field coords? vector3
---@field report? integer
---@field op? UgAdminReportOp
---@field staff? integer staff member an Assign hands the report to
---@field netId? integer
---@field hash? integer
---@field health? integer
---@field armor? integer
---@field need? string
---@field value? number
---@field minutes? integer
---@field slot? integer
---@field location? string
---@field note? integer

---@class UgAdminContext
---@field actor integer
---@field target? integer
---@field args UgAdminArgs

---@alias UgAdminTargetRule 'required'|'self'

---@class UgAdminDefinition
---@field target? UgAdminTargetRule `required` needs another player, `self` defaults to the staff member
---@field outrank? boolean the staff member MUST outrank a target that is not themselves
---@field character? boolean the target MUST have a character loaded
---@field ped? boolean the staff member MUST be a player, not the console
---@field args? string[] required argument names
---@field silent? boolean not written to the audit log
---@field quiet? boolean no success message to the staff member
---@field run fun(ctx: UgAdminContext): boolean, UgErrorCode?, string?, table?, boolean? ok, errorCode, log detail, message vars, and true when run already told the staff member why it failed

local Staff = UgAdmin.Internal.Staff
local Audit = UgAdmin.Internal.Audit
local Notify = UgAdmin.Internal.Notify
local World = UgAdmin.Internal.World
local Config = UgAdmin.Internal.Config
local Action = UgAdmin.Enums.Action
local Mode = UgAdmin.Enums.Mode
local StateBags = UgAdmin.Enums.StateBags
local ClientEvents = UgAdmin.Enums.ClientEvents
local Shard = UgAdmin.Enums.Shard
local Errors = UgCore.Enums.Errors
local Logger = UgCore.Logger
local NotifyType = UgLib.Enums.NotifyType

local RESOURCE = GetCurrentResourceName()
local CONSOLE = 0
local REQUIRED = 'required'
local SELF = 'self'
local SOURCE = 'ug-admin'
local PERMANENT = 'perm'

---@param name UgAdminClientEvent
---@return string
local function event(name)
    return RESOURCE .. ':' .. name
end

Actions.ArgsRule = UgAdmin.Rules.Args
Actions.ActionRule = UgAdmin.Rules.Action

---@param source integer
---@return string
local function name(source)
    return UgAdmin.Internal.NameOf(source)
end

---@param ctx UgAdminContext
---@param mode UgAdminMode
---@return boolean, UgErrorCode?, string?, table?
local function toggle(ctx, mode)
    local enabled = not Staff.HasMode(ctx.actor, mode)

    Staff.SetMode(ctx.actor, mode, enabled)

    return true, nil, enabled and 'on' or 'off', {
        state = Notify.Text(enabled and 'state.on' or 'state.off'),
    }
end

---Brings a player back to full shape in place: revives them when downed or dead, clears injuries, restores health
---and, with the needs module, sets every need back to its start value. /revive and /heal both use it, so neither
---leaves the staff member at a dead end: a heal on a dead player revives, a revive on a living one heals.
---@param ctx UgAdminContext
---@return boolean, UgErrorCode?, string?, table?
local function restore(ctx)
    local target = ctx.target --[[@as integer]]

    if UgCore.Players.GetDeathState(target) ~= UgCore.Enums.DeathState.Alive then
        local ok, errorCode = UgCore.Players.Revive(target, {
            by = ctx.actor ~= CONSOLE and ctx.actor or nil,
            reason = SOURCE,
            clearInjuries = true,
        })

        if not ok then
            return false, errorCode
        end
    else
        UgCore.Players.ClearInjuries(target)
    end

    local player = UgCore.Players.Get(target)

    if UgCore.Modules.IsEnabled('needs') and player and player.characterId then
        UgCore.Needs.Reset(target)
    end

    UgCore.Network.TriggerClient(target, event(ClientEvents.Heal))

    return true, nil, nil, {
        target = name(target),
    }
end

Actions.Restore = restore

---Freezes or frees a player: the statebag their client follows, and the ped on the server.
---@param target integer
---@param frozen boolean
function Actions.SetFrozen(target, frozen)
    Player(target).state:set(StateBags.Frozen, frozen or nil, true)
    FreezeEntityPosition(GetPlayerPed(tostring(target)), frozen)
end

---@param ctx UgAdminContext
---@param add boolean
---@return boolean, UgErrorCode?, string?, table?
local function changeGroup(ctx, add)
    local group = ctx.args.group --[[@as string]]
    local definition = UgCore.Permissions.GetGroupDefinition(group)

    if not definition then
        return false, Errors.NotFound
    end

    -- Nobody hands out or takes away a rank as high as their own.
    if ctx.actor ~= CONSOLE and definition.weight >= UgCore.Permissions.GetWeight(ctx.actor) then
        return false, Errors.NoPermission
    end

    local by = UgAdmin.Internal.IdentifierOf(ctx.actor)
    local ok, removed, errorCode

    if add then
        ok, errorCode = UgCore.Permissions.AddGroup(ctx.target, group, by)
    else
        ok, removed, errorCode = UgCore.Permissions.RemoveGroup(ctx.target, group)

        if ok and not removed then
            return false, Errors.NotFound
        end
    end

    if not ok then
        return false, errorCode
    end

    Staff.Sync(ctx.target)

    return true, nil, group, {
        target = name(ctx.target),
        group = definition.label,
    }
end

---@type table<UgAdminAction, UgAdminDefinition>
local DEFINITIONS = {
    [Action.Panel] = {
        ped = true,
        silent = true,
        quiet = true,
        run = function(ctx)
            UgCore.Network.TriggerClient(ctx.actor, event(ClientEvents.Panel))

            return true
        end,
    },

    [Action.Noclip] = {
        ped = true,
        run = function(ctx) return toggle(ctx, Mode.Noclip) end,
    },
    [Action.Vision] = {
        ped = true,
        run = function(ctx) return toggle(ctx, Mode.Vision) end,
    },
    [Action.God] = {
        ped = true,
        run = function(ctx) return toggle(ctx, Mode.God) end,
    },
    [Action.Invisible] = {
        ped = true,
        run = function(ctx) return toggle(ctx, Mode.Invisible) end,
    },

    [Action.Waypoint] = {
        ped = true,
        silent = true,
        run = function(ctx)
            -- Only the staff member moves, so their own client's answer is enough.
            local coords = World.Waypoint(ctx.actor)

            if not coords then
                return false, Errors.NotFound
            end

            World.Teleport(ctx.actor, coords, false)

            return true
        end,
    },

    [Action.Coords] = {
        ped = true,
        silent = true,
        args = { 'coords' },
        run = function(ctx)
            local coords = ctx.args.coords --[[@as vector3]]

            World.Teleport(ctx.actor, coords, coords.z ~= 0)

            return true, nil, nil, {
                coords = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z),
            }
        end,
    },

    [Action.Back] = {
        target = SELF,
        outrank = true,
        silent = true,
        run = function(ctx)
            if not World.Back(ctx.target) then
                return false, Errors.NotFound
            end

            return true, nil, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.Goto] = {
        target = REQUIRED,
        ped = true,
        run = function(ctx)
            local coords = World.CoordsOf(ctx.target)

            if ctx.target == ctx.actor or not coords then
                return false, Errors.InvalidArgs
            end

            World.Teleport(ctx.actor, coords, true)

            return true, nil, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.Bring] = {
        target = REQUIRED,
        outrank = true,
        ped = true,
        run = function(ctx)
            local coords = World.CoordsOf(ctx.actor)

            if ctx.target == ctx.actor or not coords then
                return false, Errors.InvalidArgs
            end

            World.Teleport(ctx.target, coords, true)

            return true, nil, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.Spectate] = {
        target = REQUIRED,
        outrank = true,
        ped = true,
        run = function(ctx)
            local ok, errorCode = UgAdmin.Internal.Spectate.Start(ctx.actor, ctx.target)

            return ok, errorCode, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.Revive] = {
        target = SELF,
        run = restore,
    },
    [Action.Heal] = {
        target = SELF,
        run = restore,
    },

    [Action.Kill] = {
        target = REQUIRED,
        outrank = true,
        run = function(ctx)
            local ok, errorCode = UgCore.Players.Kill(ctx.target)

            return ok, errorCode, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.Freeze] = {
        target = REQUIRED,
        outrank = true,
        run = function(ctx)
            local frozen = Player(ctx.target).state[StateBags.Frozen] ~= true

            Actions.SetFrozen(ctx.target, frozen)

            return true, nil, frozen and 'on' or 'off', {
                target = name(ctx.target),
                state = Notify.Text(frozen and 'state.on' or 'state.off'),
            }
        end,
    },

    [Action.Warn] = {
        target = REQUIRED,
        outrank = true,
        args = { 'reason' },
        run = function(ctx)
            UgCore.Network.TriggerClient(ctx.target, event(ClientEvents.Shard), Shard.Warn, ctx.args.reason)

            return true, nil, ctx.args.reason, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.Kick] = {
        target = REQUIRED,
        outrank = true,
        run = function(ctx)
            local reason = ctx.args.reason
            local targetName = name(ctx.target)
            local ok, errorCode = UgCore.Players.Kick(ctx.target, reason and Notify.Text('kicked', {
                reason = reason,
            }) or nil)

            return ok, errorCode, reason, {
                target = targetName,
            }
        end,
    },

    [Action.Ban] = {
        target = REQUIRED,
        outrank = true,
        args = { 'reason' },
        run = function(ctx)
            local duration = ctx.args.duration or PERMANENT
            local seconds = UgAdmin.Internal.ParseDuration(duration)

            if duration ~= PERMANENT and not seconds then
                return false, Errors.InvalidArgs
            end

            local targetName = name(ctx.target)
            local ok, _, errorCode = UgCore.Identity.Ban(ctx.target, {
                reason = ctx.args.reason,
                duration = seconds,
                by = UgAdmin.Internal.IdentifierOf(ctx.actor),
            })

            return ok, errorCode, ('%s, %s'):format(duration, ctx.args.reason), {
                target = targetName,
                duration = duration,
            }
        end,
    },

    [Action.Unban] = {
        args = { 'identifier' },
        run = function(ctx)
            local ok, count, errorCode = UgCore.Identity.Unban(ctx.args.identifier)

            if ok and count == 0 then
                return false, Errors.NotFound
            end

            return ok, errorCode, ctx.args.identifier, {
                identifier = ctx.args.identifier,
            }
        end,
    },

    [Action.GiveMoney] = {
        target = REQUIRED,
        character = true,
        args = { 'account', 'amount' },
        run = function(ctx)
            local account, amount = ctx.args.account --[[@as string]], ctx.args.amount --[[@as integer]]

            if amount == 0 then
                return false, Errors.InvalidArgs
            end

            local ok, balance, errorCode

            if amount > 0 then
                ok, balance, errorCode = UgCore.Accounts.Add(ctx.target, account, amount, SOURCE)
            else
                ok, balance, errorCode = UgCore.Accounts.Remove(ctx.target, account, -amount, SOURCE)
            end

            return ok, errorCode, ('%s %+d, balance %s'):format(account, amount, tostring(balance)), {
                target = name(ctx.target),
                account = account,
                amount = UgLib.Format.Money(amount),
            }
        end,
    },

    [Action.SetJob] = {
        target = REQUIRED,
        character = true,
        args = { 'job' },
        run = function(ctx)
            local job, grade = ctx.args.job --[[@as string]], ctx.args.grade or 1

            if not UgCore.Jobs.Exists(job, grade) then
                return false, Errors.NotFound
            end

            local ok, errorCode = UgCore.Jobs.Set(ctx.target, job, grade)

            return ok, errorCode, ('%s %d'):format(job, grade), {
                target = name(ctx.target),
                job = job,
                grade = grade,
            }
        end,
    },

    [Action.SetGang] = {
        target = REQUIRED,
        character = true,
        args = { 'job' },
        run = function(ctx)
            local gang, grade = ctx.args.job --[[@as string]], ctx.args.grade or 1

            if not UgCore.Gangs.Exists(gang, grade) then
                return false, Errors.NotFound
            end

            local ok, errorCode = UgCore.Gangs.Set(ctx.target, gang, grade)

            return ok, errorCode, ('%s %d'):format(gang, grade), {
                target = name(ctx.target),
                job = gang,
                grade = grade,
            }
        end,
    },

    [Action.GiveItem] = {
        target = REQUIRED,
        character = true,
        args = { 'item' },
        run = function(ctx)
            local item, count = ctx.args.item --[[@as string]], ctx.args.count or 1

            if not UgCore.Items.Exists(item) then
                return false, Errors.NotFound
            end

            local ok, errorCode = UgCore.Inventory.AddItem(ctx.target, item, count, nil, SOURCE)

            return ok, errorCode, ('%dx %s'):format(count, item), {
                target = name(ctx.target),
                item = item,
                count = count,
            }
        end,
    },

    [Action.ClearInventory] = {
        target = REQUIRED,
        outrank = true,
        character = true,
        run = function(ctx)
            local ok, errorCode = UgCore.Inventory.Clear(ctx.target, SOURCE)

            return ok, errorCode, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.OpenInventory] = {
        target = REQUIRED,
        outrank = true,
        character = true,
        ped = true,
        run = function(ctx)
            -- The staff member's own pockets are already on the left.
            if ctx.target == ctx.actor then
                return false, Errors.InvalidArgs
            end

            local characterId = UgCore.Players.Get(ctx.target).characterId
            local ok, errorCode = UgCore.Inventory.Open(ctx.actor, 'player:' .. characterId)

            return ok, errorCode, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.SetGroup] = {
        target = REQUIRED,
        outrank = true,
        args = { 'group' },
        run = function(ctx) return changeGroup(ctx, true) end,
    },

    [Action.RemoveGroup] = {
        target = REQUIRED,
        outrank = true,
        args = { 'group' },
        run = function(ctx) return changeGroup(ctx, false) end,
    },

    [Action.Car] = {
        ped = true,
        args = { 'model' },
        run = function(ctx)
            local model = ctx.args.model --[[@as string]]
            local ok, result = World.SpawnVehicle(ctx.actor, model, Config.Get().replaceSpawnedVehicle)

            if not ok then
                return false, result --[[@as UgErrorCode]]
            end

            return true, nil, model, {
                model = model,
            }
        end,
    },

    [Action.DeleteVehicle] = {
        ped = true,
        run = function(ctx)
            local radius = ctx.args.radius

            if radius and radius > Config.Get().maxDeleteRadius then
                return false, Errors.InvalidArgs
            end

            local count = World.DeleteVehicles(ctx.actor, radius)

            if count == 0 then
                return false, Errors.NotFound
            end

            return true, nil, ('%d vehicle(s)'):format(count), {
                count = count,
            }
        end,
    },

    [Action.Fix] = {
        target = SELF,
        silent = true,
        run = function(ctx)
            if GetVehiclePedIsIn(GetPlayerPed(tostring(ctx.target)), false) == 0 then
                return false, Errors.NotFound
            end

            UgCore.Network.TriggerClient(ctx.target, event(ClientEvents.Fix))

            return true, nil, nil, {
                target = name(ctx.target),
            }
        end,
    },

    [Action.DeleteEntity] = {
        ped = true,
        -- A networked entity by `netId`, or a map prop by `coords` and model `hash`.
        run = function(ctx)
            local args = ctx.args

            if args.netId then
                local ok, what = World.DeleteEntity(args.netId)

                if not ok then
                    return false, Errors.NotFound
                end

                return true, nil, what
            end

            if not (args.coords and args.hash) then
                return false, Errors.InvalidArgs
            end

            local ok, detail = World.HideProp(ctx.actor, args.coords, args.hash)

            if not ok then
                return false, detail --[[@as UgErrorCode]]
            end

            return true, nil, detail
        end,
    },

    [Action.Announce] = {
        args = { 'text' },
        run = function(ctx)
            UgCore.Network.TriggerClients(event(ClientEvents.Shard), Shard.Announce, ctx.args.text)

            return true, nil, ctx.args.text
        end,
    },

    [Action.Duty] = {
        ped = true,
        run = function(ctx)
            local ok, errorCode, detail = toggle(ctx, Mode.Duty)
            local onDuty = Staff.HasMode(ctx.actor, Mode.Duty)

            -- Off duty, nobody waits on this staff member.
            if not onDuty then
                UgAdmin.Internal.Reports.ReleaseAll(ctx.actor)
            end

            return ok, errorCode, detail, {
                state = Notify.Text(onDuty and 'duty.on' or 'duty.off'),
            }
        end,
    },

    [Action.Reports] = {
        args = { 'report', 'op' },
        -- Reports.Handle logs and confirms the ops that matter itself.
        silent = true,
        quiet = true,
        run = function(ctx)
            local args = ctx.args
            local staff = args.staff

            -- /reports <id> assign <staff id> passes the id as text.
            if not staff and args.op == UgAdmin.Enums.ReportOp.Assign and args.text then
                staff = math.tointeger(tonumber(args.text))
            end

            return UgAdmin.Internal.Reports.Handle(ctx.actor, args.report, args.op, args.text, staff)
        end,
    },
}

---Checks everything around an action. nil when it MAY run.
---@param definition UgAdminDefinition
---@param actor integer
---@param target? integer
---@param args UgAdminArgs
---@return UgErrorCode? errorCode
---@return integer? target the resolved target
local function admit(definition, actor, target, args)
    if definition.ped and actor == CONSOLE then
        return Errors.InvalidArgs
    end

    if definition.target == SELF then
        target = target or (actor ~= CONSOLE and actor or nil)
    end

    if definition.target and not target then
        return Errors.InvalidArgs
    end

    if not definition.target then
        target = nil
    end

    if target then
        local player = UgCore.Players.Get(target)

        if not player then
            return Errors.NotFound
        end

        if definition.character and not player.characterId then
            return Errors.NotLoaded
        end

        if definition.outrank and not Staff.Outranks(actor, target) then
            return Errors.NoPermission
        end
    end

    for _, field in ipairs(definition.args or {}) do
        if args[field] == nil then
            return Errors.InvalidArgs
        end
    end

    return nil, target
end

---Runs an action for a staff member, writes the audit log and answers them. MUST run in a thread.
---@param actor integer source, 0 for the console
---@param action UgAdminAction
---@param target? integer
---@param args? UgAdminArgs validated with Actions.ArgsRule
---@return boolean ok
---@return UgErrorCode? errorCode
function Actions.Run(actor, action, target, args)
    args = args or {}

    local definition = DEFINITIONS[action]

    if not definition or not Staff.Can(actor, action) then
        Notify.Error(actor, Errors.NoPermission)

        return false, Errors.NoPermission
    end

    local refused, resolved = admit(definition, actor, target, args)

    if refused then
        Notify.Error(actor, refused)

        return false, refused
    end

    local called, ok, errorCode, detail, vars, told = pcall(definition.run, {
        actor = actor,
        target = resolved,
        args = args,
    })

    if not called then
        Logger.Error('/%s failed: %s', action, tostring(ok))
        ok, errorCode = false, Errors.InternalError
    end

    if not ok then
        errorCode = errorCode or Errors.InternalError

        if told ~= true then
            Notify.Error(actor, errorCode)
        end

        return false, errorCode
    end

    if not definition.silent then
        Audit.Record(actor, action, resolved, detail)
    end

    if not definition.quiet then
        Notify.Send(actor, 'result.' .. action, vars, NotifyType.Success)
    end

    return true, nil
end

---Adds an action defined in another file. Raises on a duplicate.
---@param action UgAdminAction
---@param definition UgAdminDefinition
function Actions.Define(action, definition)
    if DEFINITIONS[action] then
        error(('[ug-admin] action %s is already defined'):format(action), 2)
    end

    DEFINITIONS[action] = definition
end

---True for known actions.
---@param action any
---@return boolean
function Actions.Exists(action)
    return DEFINITIONS[action] ~= nil
end
