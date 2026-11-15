--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Last client script: waits for the server config and ug-core, starts the mode watcher, and registers staff keys
-- once the server says this player is staff.

local Action = UgAdmin.Enums.Action
local StateBags = UgAdmin.Enums.StateBags

local STATE_KEY = UgAdmin.Enums.GlobalState.Config
local READY_TIMEOUT = 60000
local ACCESS_POLL = 1000

---@param action UgAdminAction
local function request(action)
    if UgAdmin.Internal.Allowed(action) then
        CreateThread(function()
            UgAdmin.Internal.Request(action)
        end)
    end
end

---Registers the staff keys. Players without access never get them in their key bindings.
---@param keys { noclip: string, panel: string, vision: string }
local function registerKeys(keys)
    local Notify = UgAdmin.Internal.Notify

    UgLib.Keybind.Register({
        name = 'noclip',
        label = Notify.Text('keybind.noclip'),
        defaultKey = keys.noclip ~= '' and keys.noclip or nil,
        disableWhileUi = true,
        onPressed = function()
            request(Action.Noclip)
        end,
    })

    UgLib.Keybind.Register({
        name = 'panel',
        label = Notify.Text('keybind.panel'),
        defaultKey = keys.panel ~= '' and keys.panel or nil,
        disableWhileUi = true,
        onPressed = function()
            CreateThread(UgAdmin.Internal.Panel.Open)
        end,
    })

    UgLib.Keybind.Register({
        name = 'vision',
        label = Notify.Text('keybind.vision'),
        defaultKey = keys.vision ~= '' and keys.vision or nil,
        disableWhileUi = true,
        onPressed = function()
            request(Action.Vision)
        end,
    })
end

CreateThread(function()
    local deadline = GetGameTimer() + READY_TIMEOUT

    while type(GlobalState[STATE_KEY]) ~= 'table' do
        if GetGameTimer() >= deadline then
            print('^1[ug-admin] No config from the server. Check the server console.^7')

            return
        end

        Wait(250)
    end

    if not UgCore.Lifecycle.Await(UgCore.Enums.Lifecycle.Ready, READY_TIMEOUT) then
        print('^1[ug-admin] ug-core did not become ready.^7')

        return
    end

    local settings = GlobalState[STATE_KEY] --[[@as table]]

    UgAdmin.Internal.Modes.Start(settings)
    print('[ug-admin] Ready.')

    -- Access arrives when the character loads, or later when staff promote the player.
    while type(LocalPlayer.state[StateBags.Access]) ~= 'table' do
        Wait(ACCESS_POLL)
    end

    registerKeys(settings.keys)
    print(('[ug-admin] Staff: %d action(s).'):format(#LocalPlayer.state[StateBags.Access]))
end)
