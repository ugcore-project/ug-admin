--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The page bridge. The page is untrusted: any script in CEF can post to these callbacks, so every body is
-- read through a schema here before a handler sees it, and the page MAY post only so often.

---@class UgAdmin.Internal.Nui
local Nui = {}
UgAdmin.Internal.Nui = Nui

local Enums = UgAdmin.Enums
local Action = Enums.NuiAction
local Callback = Enums.NuiCallback
local Schema = UgCore.Schema

local RESOURCE = GetCurrentResourceName()
-- Callbacks per second the page MAY send. Raise it for pages with sliders or drag, and throttle in the page too.
local EVENTS_PER_SECOND = 10
local FALLBACK_LOCALE = 'en'
local RUN = Schema.Object({
    action = UgAdmin.Rules.Action,
    target = Schema.Optional(Schema.Integer({
        min = 1,
        max = 65535,
    })),
    args = Schema.Optional(UgAdmin.Rules.Args),
})
local REPORT_TEXT = Schema.String({
    min = 1,
    max = 256,
})
local REPORT_OPEN = Schema.Object({
    message = REPORT_TEXT,
    category = Schema.Optional(Schema.Enum(UgAdmin.Rules.Sorted(Enums.ReportCategory))),
    accused = Schema.Optional(Schema.Integer({
        min = 1,
        max = 65535,
    })),
})

local ready = false
---@type table[] messages sent before the page was ready
local queue = {}
local budget = {
    second = -1,
    count = 0,
}
---@type table<UgAdminNuiCallback, fun(value: any)>
local handlers = {}

---Sends a message, or queues it until the page is ready.
---@param action UgAdminNuiAction
---@param payload? table
function Nui.Send(action, payload)
    local message = {
        action = action,
        payload = payload,
    }

    if ready then
        SendNUIMessage(message)
    else
        queue[#queue + 1] = message
    end
end

---@return boolean
function Nui.IsReady()
    return ready
end

---The `page` group of locales/<code>.json, or of English when that file is missing or broken.
---@return table
function Nui.Labels()
    for _, code in ipairs({ UgLib.Locale.GetCode(), FALLBACK_LOCALE }) do
        local content = LoadResourceFile(RESOURCE, ('locales/%s.json'):format(code))

        if content then
            local ok, decoded = pcall(json.decode, content)

            if ok and type(decoded) == 'table' and type(decoded.page) == 'table' then
                return decoded.page
            end
        end
    end

    return {}
end

---ug-lib's theme with the owner's ug-admin overrides on top. Colors merge token by token.
---@param base table? ug-lib's theme
---@param own table? the ug-admin theme
---@return table
function Nui.Theme(base, own)
    base = type(base) == 'table' and base or {}
    own = type(own) == 'table' and own or {}

    local colors = {}

    -- Not ipairs over both: it stops at a missing ug-lib table and drops the owner colors.
    for index = 1, 2 do
        local source = index == 1 and base.colors or own.colors

        if type(source) == 'table' then
            for token, color in pairs(source) do
                colors[token] = color
            end
        end
    end

    return {
        mode = own.mode or base.mode,
        colors = colors,
        radius = own.radius or base.radius,
        font = own.font or base.font,
        scale = own.scale or base.scale,
    }
end

---What the page gets first: the theme, the labels, the owner's layout and tabs.
---@return table
local function config()
    local libConfig = GlobalState[UgLib.Enums.GlobalState.Config]
    local replicated = GlobalState[UgAdmin.Enums.GlobalState.Config]
    local owner = type(replicated) == 'table' and replicated or {}

    return {
        theme = Nui.Theme(type(libConfig) == 'table' and libConfig.theme or nil, owner.theme),
        labels = Nui.Labels(),
        locale = UgLib.Locale.GetCode(),
        layout = owner.layout,
        tabs = owner.tabs,
    }
end

---Sets who receives a page callback. The handler gets the validated value.
---@param callback UgAdminNuiCallback
---@param handler fun(value: any)
function Nui.On(callback, handler)
    handlers[callback] = handler
end

---@return boolean
local function withinBudget()
    local second = GetGameTimer() // 1000

    if budget.second ~= second then
        budget.second, budget.count = second, 0
    end

    budget.count = budget.count + 1

    return budget.count <= EVENTS_PER_SECOND
end

---A reader that checks one field of the body with a rule.
---@param field string
---@param rule UgSchemaRule
---@return fun(body: any): any
local function fieldOf(field, rule)
    return function(body)
        if type(body) ~= 'table' then
            return nil
        end

        local ok, value = Schema.Check(rule, body[field])

        return ok and value or nil
    end
end

-- One reader per callback. A reader returns the checked value, or nil to reject the body.
---@type table<UgAdminNuiCallback, fun(body: any): any>
local READERS = {
    [Callback.Refresh] = function()
        return true
    end,
    [Callback.Inspect] = fieldOf('id', Schema.Integer({
        min = 1,
        max = 65535,
    })),
    [Callback.Run] = function(body)
        local ok, value = Schema.Check(RUN, body)

        return ok and value or nil
    end,
    [Callback.Logs] = function(body)
        local search = fieldOf('search', Schema.String({
            max = 64,
        }))(body)

        return {
            search = search or '',
        }
    end,
    [Callback.Close] = function()
        return true
    end,
    [Callback.ReportOpen] = function(body)
        local ok, value = Schema.Check(REPORT_OPEN, body)

        return ok and value or nil
    end,
    [Callback.ReportReply] = fieldOf('text', REPORT_TEXT),
    [Callback.ReportCancel] = function()
        return true
    end,
    [Callback.ReportRate] = fieldOf('rating', Schema.Integer({
        min = 1,
        max = 5,
    })),
    [Callback.ReportHide] = function()
        return true
    end,
    [Callback.Settings] = function(body)
        local ok, value = Schema.Check(UgAdmin.Rules.Settings, body)

        return ok and value or nil
    end,
}

for name, read in pairs(READERS) do
    RegisterNUICallback(name, function(body, cb)
        local value = nil

        if withinBudget() then
            value = read(body)
        end

        if value ~= nil and handlers[name] then
            handlers[name](value)
        end

        cb({
            ok = value ~= nil,
        })
    end)
end

-- The page posts ready once it listens. It reloads after a crash: config is sent again each time.
RegisterNUICallback(Callback.Ready, function(_, cb)
    ready = true
    SendNUIMessage({
        action = Action.Config,
        payload = config(),
    })

    for _, message in ipairs(queue) do
        SendNUIMessage(message)
    end

    queue = {}
    cb({
        ok = true,
    })
end)
