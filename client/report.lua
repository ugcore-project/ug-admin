--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The report window every player has: open a report, chat with staff, cancel it, rate the help. The page shows the
-- latest staff answer even while the window is closed. The server decides everything; this passes requests along.

---@class UgAdmin.Internal.Report
local Report = {}
UgAdmin.Internal.Report = Report

local Nui = UgAdmin.Internal.Nui
local NuiAction = UgAdmin.Enums.NuiAction
local NuiCallback = UgAdmin.Enums.NuiCallback
local Callbacks = UgAdmin.Enums.Callbacks
local ClientEvents = UgAdmin.Enums.ClientEvents
local NotifyType = UgLib.Enums.NotifyType

local RESOURCE = GetCurrentResourceName()

local open = false

---@return boolean
function Report.IsOpen()
    return open
end

---Opens the window with focus. Ignored while the staff panel is open.
function Report.Show()
    if open or UgAdmin.Internal.Panel.IsOpen() then
        return
    end

    open = true
    SetNuiFocus(true, true)
    Nui.Send(NuiAction.ReportWindow, {
        open = true,
    })
end

---Closes the window and releases focus.
function Report.Hide()
    if not open then
        return
    end

    open = false
    SetNuiFocus(false, false)
    Nui.Send(NuiAction.ReportWindow, {
        open = false,
    })
end

---Asks the server and shows a refusal. MUST run in a thread.
---@param callback UgAdminCallback
---@param ... any
---@return boolean ok
local function ask(callback, ...)
    local ok, result, errorCode = UgCore.Callback.Await(RESOURCE .. ':' .. callback, ...)

    if ok and type(result) == 'table' and result.ok == true then
        return true
    end

    -- The server already said why, more precisely than an error code.
    if ok and type(result) == 'table' and result.told == true then
        return false
    end

    local code = ok and type(result) == 'table' and result.error or errorCode

    UgAdmin.Internal.Notify.Show('error.' .. tostring(code or UgCore.Enums.Errors.InternalError), nil, NotifyType.Error)

    return false
end

---@param callback UgAdminCallback
---@param ... any
local function request(callback, ...)
    local args = table.pack(...)

    CreateThread(function()
        ask(callback, table.unpack(args, 1, args.n))
    end)
end

Nui.On(NuiCallback.ReportOpen, function(body)
    request(Callbacks.Report, body.message, body.category, body.accused)
end)

Nui.On(NuiCallback.ReportReply, function(text)
    request(Callbacks.ReportReply, text)
end)

Nui.On(NuiCallback.ReportCancel, function()
    request(Callbacks.ReportCancel)
end)

Nui.On(NuiCallback.ReportRate, function(rating)
    request(Callbacks.ReportRate, rating)
end)

Nui.On(NuiCallback.ReportHide, Report.Hide)

-- The page reads the report field by field, like every message.
UgCore.Network.Register(ClientEvents.MyReport, function(report)
    Nui.Send(NuiAction.MyReport, type(report) == 'table' and report or nil)
end)

UgCore.Network.Register(ClientEvents.ReportWindow, Report.Show)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE and open then
        SetNuiFocus(false, false)
    end
end)
