--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Messages to staff. Players get a locale key and variables, and their client translates them. The console gets the
-- server's translation.

---@class UgAdmin.Internal.Notify
local Notify = {}
UgAdmin.Internal.Notify = Notify

local CONSOLE = 0
local EVENT = GetCurrentResourceName() .. ':' .. UgAdmin.Enums.ClientEvents.Notify
local NotifyType = UgLib.Enums.NotifyType

---@type fun(key: string, vars?: table): string
local translate

---@param key string
---@param vars? table
---@return string
function Notify.Text(key, vars)
    translate = translate or UgLib.Locale.Create()

    return translate(key, vars)
end

---@param source integer
---@param key string locale key
---@param vars? table<string, string|number>
---@param kind? UgNotifyType defaults to info
function Notify.Send(source, key, vars, kind)
    if source == CONSOLE then
        print(('[ug-admin] %s'):format(Notify.Text(key, vars)))

        return
    end

    UgCore.Network.TriggerClient(source, EVENT, key, vars or {}, kind or NotifyType.Info)
end

---@param source integer
---@param errorCode UgErrorCode
function Notify.Error(source, errorCode)
    Notify.Send(source, 'error.' .. errorCode, nil, NotifyType.Error)
end
