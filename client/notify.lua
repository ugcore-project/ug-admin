--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Messages from the server arrive as a locale key and variables. Shown through ug-lib, so they look like every
-- other UgCore notification.

---@class UgAdmin.Internal.Notify
local Notify = {}
UgAdmin.Internal.Notify = Notify

local NotifyType = UgLib.Enums.NotifyType
local Schema = UgCore.Schema

local KEY = Schema.String({
    min = 1,
    max = 64,
    pattern = '^[%w_%.]+$',
})
local VARS = Schema.Map(Schema.String({
    max = 32,
}), Schema.String({
    max = 256,
}), {
    max = 8,
})
local TYPES = {}

for _, kind in pairs(NotifyType) do
    TYPES[kind] = true
end

---@type fun(key: string, vars?: table): string
local translate

---@param key string
---@param vars? table
---@return string
function Notify.Text(key, vars)
    translate = translate or UgLib.Locale.Create()

    return translate(key, vars)
end

---@param key string
---@param vars? table
---@param kind? UgNotifyType
function Notify.Show(key, vars, kind)
    UgLib.Notify.Show({
        title = Notify.Text('title'),
        message = Notify.Text(key, vars),
        type = kind or NotifyType.Info,
    })
end

UgCore.Network.Register(UgAdmin.Enums.ClientEvents.Notify, function(key, vars, kind)
    -- Numbers become text, so the map schema holds.
    local strings = {}

    for name, value in pairs(type(vars) == 'table' and vars or {}) do
        strings[name] = tostring(value)
    end

    local okKey = Schema.Check(KEY, key)
    local okVars, checked = Schema.Check(VARS, strings)

    if okKey and okVars then
        Notify.Show(key, checked, TYPES[kind] and kind or NotifyType.Info)
    end
end)
