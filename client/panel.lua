--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The staff panel. The page posts intent; this file asks the server and passes the answers back. Focus is released
-- on every way out: the close button, Escape, an action that moves the player, and a resource stop.

---@class UgAdmin.Internal.Panel
local Panel = {}
UgAdmin.Internal.Panel = Panel

local Nui = UgAdmin.Internal.Nui
local NuiAction = UgAdmin.Enums.NuiAction
local NuiCallback = UgAdmin.Enums.NuiCallback
local Callbacks = UgAdmin.Enums.Callbacks
local Action = UgAdmin.Enums.Action

local RESOURCE = GetCurrentResourceName()
local SNAPSHOT = RESOURCE .. ':' .. Callbacks.Snapshot
local INSPECT = RESOURCE .. ':' .. Callbacks.Inspect
local LOGS = RESOURCE .. ':' .. Callbacks.Logs

-- Actions that move or take over the staff member's view close the panel first.
local CLOSES = {
    [Action.Noclip] = true, [Action.Goto] = true, [Action.Spectate] = true, [Action.Waypoint] = true,
    [Action.Back] = true, [Action.Car] = true, [Action.OpenInventory] = true,
}

---@param body { action: UgAdminAction, target?: integer, args?: UgAdminArgs }
---@return boolean
local function closes(body)
    -- Report trips move the staff member: going to the reporter, and coming back.
    if body.action == Action.Reports then
        local op = body.args and body.args.op

        return op == UgAdmin.Enums.ReportOp.Goto or op == UgAdmin.Enums.ReportOp.Return
    end

    -- Acting on someone else stays in the panel: only moving yourself closes it.
    if body.action == Action.Back then
        return body.target == nil or body.target == GetPlayerServerId(PlayerId())
    end

    return CLOSES[body.action] == true
end

local open = false
local busy = false

---@return boolean
function Panel.IsOpen()
    return open
end

---@param name string full callback name
---@param ... any
---@return any value nil on failure
local function ask(name, ...)
    local ok, value = UgCore.Callback.Await(name, ...)

    return ok and value or nil
end

---Closes the page and releases focus.
function Panel.Close()
    if not open then
        return
    end

    open = false
    SetNuiFocus(false, false)
    Nui.Send(NuiAction.Close)
    UgAdmin.Internal.Faces.Release()
end

---Sends the faces of the listed players this client can see, in a thread of its own.
---@param players any rows from the server
local function sendFaces(players)
    if type(players) ~= 'table' then
        return
    end

    local ids = {}

    for _, row in ipairs(players) do
        if type(row) == 'table' and math.type(row.id) == 'integer' then
            ids[#ids + 1] = row.id
        end
    end

    CreateThread(function()
        local faces = UgAdmin.Internal.Faces.Collect(ids)

        if open and faces then
            Nui.Send(NuiAction.Faces, faces)
        end
    end)
end

---Opens the panel with fresh data. MUST run in a thread.
function Panel.Open()
    if open or busy or not UgAdmin.Internal.Allowed(Action.Panel) then
        return
    end

    -- One window holds focus at a time.
    UgAdmin.Internal.Report.Hide()

    busy = true

    local snapshot = ask(SNAPSHOT)

    busy = false

    if type(snapshot) ~= 'table' then
        return
    end

    open = true
    SetNuiFocus(true, true)
    Nui.Send(NuiAction.Open, {
        self = snapshot.self,
        access = LocalPlayer.state[UgAdmin.Enums.StateBags.Access] or {},
        players = snapshot.players,
        reports = snapshot.reports,
        catalog = snapshot.catalog,
        settings = UgAdmin.Internal.Settings.Get(),
    })
    sendFaces(snapshot.players)
end

---Open reports changed. Updates the page when it is open.
---@param reports table[]
function Panel.SetReports(reports)
    if open then
        Nui.Send(NuiAction.Reports, reports)
    end
end

local function refresh()
    local snapshot = ask(SNAPSHOT)

    if open and type(snapshot) == 'table' then
        Nui.Send(NuiAction.Players, snapshot.players)
        Nui.Send(NuiAction.Reports, snapshot.reports)
        sendFaces(snapshot.players)
    end
end

Nui.On(NuiCallback.Close, Panel.Close)

Nui.On(NuiCallback.Refresh, function()
    CreateThread(refresh)
end)

Nui.On(NuiCallback.Inspect, function(id)
    CreateThread(function()
        local details = ask(INSPECT, id)

        if open and type(details) == 'table' then
            Nui.Send(NuiAction.Player, details)
        end
    end)
end)

Nui.On(NuiCallback.Logs, function(body)
    CreateThread(function()
        local entries = ask(LOGS, body.search ~= '' and body.search or nil)

        if open and type(entries) == 'table' then
            Nui.Send(NuiAction.Logs, entries)
        end
    end)
end)

Nui.On(NuiCallback.Run, function(body)
    if closes(body) then
        Panel.Close()
    end

    CreateThread(function()
        local ok, errorCode = UgAdmin.Internal.Request(body.action, body.target, body.args)

        if open then
            Nui.Send(NuiAction.Result, {
                action = body.action,
                ok = ok,
                error = errorCode,
            })

            if ok then
                refresh()

                if body.target then
                    local details = ask(INSPECT, body.target)

                    if open and type(details) == 'table' then
                        Nui.Send(NuiAction.Player, details)
                    end
                end
            end
        end
    end)
end)

UgCore.Network.Register(UgAdmin.Enums.ClientEvents.Panel, function()
    CreateThread(Panel.Open)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE and open then
        SetNuiFocus(false, false)
    end
end)
