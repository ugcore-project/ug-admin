--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Chat commands through ug-core's commands module: typed arguments, groups and rate limits. Each one builds the same
-- arguments the panel sends and calls Actions.Run.

---@class UgAdmin.Internal.Commands
local Commands = {}
UgAdmin.Internal.Commands = Commands

local Actions = UgAdmin.Internal.Actions
local Config = UgAdmin.Internal.Config
local Notify = UgAdmin.Internal.Notify
local Spectate = UgAdmin.Internal.Spectate
local Reports = UgAdmin.Internal.Reports
local Action = UgAdmin.Enums.Action
local Errors = UgCore.Enums.Errors
local Schema = UgCore.Schema
local Logger = UgCore.Logger
local NotifyType = UgLib.Enums.NotifyType

local REPORT = 'report'
local STAFF_RATE = {
    max = 5,
    per = 2000,
}
local REPORT_RATE = {
    max = 1,
    per = 5000,
}

---@param name string
---@param kind UgCommandArgumentType
---@param optional? boolean
---@param max? integer
---@return UgCommandArgument
local function arg(name, kind, optional, max)
    return {
        name = name,
        type = kind,
        optional = optional,
        max = max,
    }
end

---Copies arguments with their chat hint from `arg.<name>` in the locale.
---@param args UgCommandArgument[]
---@return UgCommandArgument[]
local function withHelp(args)
    local copy = {}

    for index, argument in ipairs(args) do
        copy[index] = {
            name = argument.name,
            type = argument.type,
            optional = argument.optional,
            max = argument.max,
            help = Notify.Text('arg.' .. argument.name),
        }
    end

    return copy
end

local TARGET = arg('target', 'player')
local OPTIONAL_TARGET = arg('target', 'player', true)

-- Arguments per command. Names match UgAdminArgs, plus `target`, and `x`, `y`, `z` for /tp.
---@type table<UgAdminAction, UgCommandArgument[]>
local ARGUMENTS = {
    [Action.Panel] = {},
    [Action.Noclip] = {},
    [Action.Vision] = {},
    [Action.God] = {},
    [Action.Invisible] = {},
    [Action.Waypoint] = {},
    [Action.Coords] = { arg('x', 'number'), arg('y', 'number'), arg('z', 'number', true) },
    [Action.Back] = { OPTIONAL_TARGET },
    [Action.Goto] = { TARGET },
    [Action.Bring] = { TARGET },
    [Action.Spectate] = { OPTIONAL_TARGET },
    [Action.Revive] = { OPTIONAL_TARGET },
    [Action.Heal] = { OPTIONAL_TARGET },
    [Action.Kill] = { TARGET },
    [Action.Freeze] = { TARGET },
    [Action.Warn] = { TARGET, arg('reason', 'text', false, 200) },
    [Action.Kick] = { TARGET, arg('reason', 'text', true, 200) },
    [Action.Ban] = { TARGET, arg('duration', 'string', false, 8), arg('reason', 'text', false, 200) },
    [Action.Unban] = { arg('identifier', 'string', false, 64) },
    [Action.Message] = { TARGET, arg('text', 'text', false, 256) },
    [Action.SendTo] = { TARGET, arg('location', 'string', false, 32) },
    [Action.Jail] = { TARGET, arg('minutes', 'integer'), arg('reason', 'text', true, 200) },
    [Action.Unjail] = { TARGET },
    [Action.Mute] = { TARGET, arg('minutes', 'integer'), arg('reason', 'text', true, 200) },
    [Action.Unmute] = { TARGET },
    [Action.Note] = { TARGET, arg('text', 'text', false, 256) },
    [Action.DeleteNote] = { arg('note', 'integer') },
    [Action.SetStats] = { TARGET, arg('health', 'integer', true), arg('armor', 'integer', true) },
    [Action.SetNeed] = { TARGET, arg('need', 'string', false, 32), arg('value', 'number') },
    [Action.SetMoney] = { TARGET, arg('account', 'string', false, 32), arg('amount', 'integer') },
    [Action.RemoveItem] = { TARGET, arg('slot', 'integer'), arg('count', 'integer', true) },
    [Action.ReviveAll] = {},
    [Action.BringAll] = { arg('radius', 'number', true) },
    [Action.FreezeAll] = {},
    [Action.GiveMoney] = { TARGET, arg('account', 'string', false, 32), arg('amount', 'integer') },
    [Action.SetJob] = { TARGET, arg('job', 'string', false, 32), arg('grade', 'integer', true) },
    [Action.SetGang] = { TARGET, arg('job', 'string', false, 32), arg('grade', 'integer', true) },
    [Action.GiveItem] = { TARGET, arg('item', 'string', false, 64), arg('count', 'integer', true) },
    [Action.ClearInventory] = { TARGET },
    [Action.OpenInventory] = { TARGET },
    [Action.SetGroup] = { TARGET, arg('group', 'string', false, 32) },
    [Action.RemoveGroup] = { TARGET, arg('group', 'string', false, 32) },
    [Action.Car] = { arg('model', 'string', false, 32) },
    [Action.DeleteVehicle] = { arg('radius', 'number', true) },
    [Action.Fix] = { OPTIONAL_TARGET },
    [Action.DeleteEntity] = { arg('netId', 'integer') },
    [Action.Announce] = { arg('text', 'text', false, 256) },
    [Action.Duty] = {},
    [Action.Reports] = { arg('report', 'integer'), arg('op', 'string', false, 8), arg('text', 'text', true, 256) },
}

---@type table<string, boolean> names of every command this resource registered
local registered = {}

---Turns parsed command arguments into a target and validated action arguments.
---@param parsed table<string, any>
---@return boolean ok
---@return integer? target
---@return UgAdminArgs? args
function Commands.Build(parsed)
    local target = parsed.target
    local values = {}

    for key, value in pairs(parsed) do
        if key ~= 'target' and key ~= 'x' and key ~= 'y' and key ~= 'z' then
            values[key] = value
        end
    end

    if parsed.x then
        -- Without z the client finds the ground.
        values.coords = vector3(parsed.x + 0.0, parsed.y + 0.0, (parsed.z or 0) + 0.0)
    end

    local ok, args = Schema.Check(Actions.ArgsRule, values)

    return ok, target, ok and args or nil
end

---@param action UgAdminAction
---@param source integer
---@param parsed table<string, any>
local function run(action, source, parsed)
    -- /spectate without a target while spectating stops.
    if action == Action.Spectate and not parsed.target and source ~= 0 and Spectate.TargetOf(source) then
        Spectate.Stop(source)

        return
    end

    local ok, target, args = Commands.Build(parsed)

    if not ok then
        Notify.Error(source, Errors.InvalidArgs)

        return
    end

    CreateThread(function()
        Actions.Run(source, action, target, args)
    end)
end

---Registers every staff command and /report. Runs once after a clean boot.
---@return integer count registered
function Commands.Register()
    if not UgCore.Modules.IsEnabled('commands') then
        Logger.Warn('The commands module is off: chat commands are unavailable. The panel and keys still work.')

        return 0
    end

    local access = Config.Get().access
    local names = {}

    for action in pairs(ARGUMENTS) do
        names[#names + 1] = action
    end

    table.sort(names)

    for _, action in ipairs(names) do
        UgCore.Commands.Register(action, {
            help = Notify.Text('help.' .. action),
            args = withHelp(ARGUMENTS[action]),
            groups = { access[action] },
            rate = STAFF_RATE,
        }, function(source, parsed)
            run(action, source, parsed)
        end)

        registered[action] = true
    end

    UgCore.Commands.Register(REPORT, {
        help = Notify.Text('help.report'),
        args = withHelp({ arg('message', 'text', true, 256) }),
        rate = REPORT_RATE,
        requirePlayer = true,
        console = false,
    }, function(source, parsed)
        local muted = UgAdmin.Internal.Sanctions.Remaining(source, UgAdmin.Enums.Sanction.Mute)

        if muted then
            Notify.Send(source, 'mute.active', {
                minutes = math.max(1, math.ceil(muted / 60)),
            }, NotifyType.Error)

            return
        end

        -- Without a message, the report window opens: categories, a player to report and the chat.
        if not parsed.message then
            Reports.ShowWindow(source)

            return
        end

        local ok, errorCode = Reports.Open(source, parsed.message)

        if ok then
            Notify.Send(source, 'report.sent', nil, NotifyType.Success)
        else
            Notify.Error(source, errorCode --[[@as UgErrorCode]])
        end
    end)

    registered[REPORT] = true

    -- ug-core reports bad arguments and missing groups as an event. Answer players of this resource's commands.
    UgCore.Events.On(UgCore.Enums.Events.Commands.Failed, function(source, name, errorCode)
        if registered[name] then
            Notify.Error(source, errorCode)
        end
    end)

    return #names + 1
end
