--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Last server script: waits for ug-core, loads config, creates the log table, then registers everything.

local Config = UgAdmin.Internal.Config
local Staff = UgAdmin.Internal.Staff
local Logger = UgCore.Logger
local Events = UgCore.Enums.Events

local RESOURCE = GetCurrentResourceName()
local READY_TIMEOUT = 60000

---Warns about groups in `access` that ug-core does not know. Nobody matches them, so the action is off.
local function checkGroups()
    local names = {}

    for action in pairs(Config.Get().access) do
        names[#names + 1] = action
    end

    table.sort(names)

    for _, action in ipairs(names) do
        local group = Config.Get().access[action]

        if not UgCore.Permissions.GetGroupDefinition(group) then
            Logger.Warn('config.lua: access.%s names group "%s", which is not in ug-core config/permissions.lua. Nobody may use /%s.', action, group, action)
        end
    end
end

CreateThread(function()
    if not UgCore.Lifecycle.Await(UgCore.Enums.Lifecycle.Ready, READY_TIMEOUT) then
        Logger.Error('ug-core did not become ready. ug-admin stays off.')

        return
    end

    local ok, errors = Config.Load()

    if not ok then
        for _, message in ipairs(errors) do
            Logger.Error(message)
        end

        Logger.Error('Config invalid: %d error(s). ug-admin stays off.', #errors)

        return
    end

    checkGroups()

    if not UgAdmin.Internal.Audit.Init() then
        Logger.Warn('The audit log table could not be created. Staff actions are logged to the console only.')
    end

    if not UgAdmin.Internal.Notes.Init() or not UgAdmin.Internal.Sanctions.Init() then
        Logger.Warn('The notes or sanctions table could not be created. Notes are off, and jail and mute end on reconnect.')
    end

    UgAdmin.Internal.Panel.Register()

    local commands = UgAdmin.Internal.Commands.Register()

    UgAdmin.Internal.Radar.Start()
    UgAdmin.Internal.Sanctions.Start()

    UgCore.Events.On(Events.Players.Loaded, function(source)
        Staff.Sync(source)
        UgAdmin.Internal.Reports.StartDuty(source)
        CreateThread(function()
            UgAdmin.Internal.Sanctions.Load(source)
        end)
    end)

    UgCore.Events.On(Events.Permissions.GroupAdded, Staff.SyncAll)
    UgCore.Events.On(Events.Permissions.GroupRemoved, Staff.SyncAll)
    Staff.SyncAll()

    for _, player in ipairs(UgCore.Players.GetAll()) do
        UgAdmin.Internal.Reports.StartDuty(player.source)
    end

    local staff = 0

    for _, player in ipairs(UgCore.Players.GetAll()) do
        if Staff.IsStaff(player.source) then
            staff = staff + 1
        end
    end

    print(('[ug-admin] v%s ready. %d command(s), %d staff online.'):format(GetResourceMetadata(RESOURCE, 'version', 0) or '?', commands, staff))
end)
