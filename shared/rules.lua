--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Schemas both sides use: the server for callbacks, the client for what the page posts.

---@class UgAdmin.Rules
UgAdmin.Rules = {}

local Schema = UgCore.Schema

local MAX_INT = 2147483647

---Values of an enum, sorted, for Schema.Enum.
---@param values table<string, string>
---@return string[]
local function sorted(values)
    local list = {}

    for _, value in pairs(values) do
        list[#list + 1] = value
    end

    table.sort(list)

    return list
end

---Rule for the arguments of an action. The panel sends them as one object, commands build the same object.
UgAdmin.Rules.Args = Schema.Object({
    reason = Schema.Optional(Schema.String({
        min = 1,
        max = 200,
    })),
    duration = Schema.Optional(Schema.String({
        min = 1,
        max = 8,
        pattern = '^%w+$',
    })),
    account = Schema.Optional(Schema.String({
        min = 1,
        max = 32,
        pattern = '^%l[%w_]*$',
    })),
    amount = Schema.Optional(Schema.Integer({
        min = -100000000,
        max = 100000000,
    })),
    job = Schema.Optional(Schema.String({
        min = 1,
        max = 32,
        pattern = '^[%w_]+$',
    })),
    grade = Schema.Optional(Schema.Integer({
        min = 0,
        max = 100,
    })),
    item = Schema.Optional(Schema.String({
        min = 1,
        max = 64,
        pattern = '^[%w_%-]+$',
    })),
    count = Schema.Optional(Schema.Integer({
        min = 1,
        max = 1000000,
    })),
    group = Schema.Optional(Schema.String({
        min = 1,
        max = 32,
        pattern = '^%l[%l%d_]*$',
    })),
    text = Schema.Optional(Schema.String({
        min = 1,
        max = 256,
    })),
    model = Schema.Optional(Schema.String({
        min = 1,
        max = 32,
        pattern = '^[%w_]+$',
    })),
    radius = Schema.Optional(Schema.Number({
        min = 1,
        max = 500,
    })),
    identifier = Schema.Optional(Schema.String({
        min = 3,
        max = 64,
        pattern = '^%l+:[%w%.%-_]+$',
    })),
    coords = Schema.Optional(Schema.Vector3({
        maxComponent = 20000,
    })),
    report = Schema.Optional(Schema.Integer({
        min = 1,
        max = MAX_INT,
    })),
    op = Schema.Optional(Schema.Enum(sorted(UgAdmin.Enums.ReportOp))),
    staff = Schema.Optional(Schema.Integer({
        min = 1,
        max = MAX_INT,
    })),
    netId = Schema.Optional(Schema.Integer({
        min = 1,
        max = MAX_INT,
    })),
    -- Model hash of a map prop. Natives return it signed or unsigned.
    hash = Schema.Optional(Schema.Integer({
        min = -2147483648,
        max = 4294967295,
    })),
    -- 100 is dead for a GTA ped, 200 is full.
    health = Schema.Optional(Schema.Integer({
        min = 101,
        max = 200,
    })),
    armor = Schema.Optional(Schema.Integer({
        min = 0,
        max = 100,
    })),
    need = Schema.Optional(Schema.String({
        min = 1,
        max = 32,
        pattern = '^%l[%w]*$',
    })),
    value = Schema.Optional(Schema.Number({
        min = 0,
        max = 100,
    })),
    minutes = Schema.Optional(Schema.Integer({
        min = 1,
        max = 43200,
    })),
    slot = Schema.Optional(Schema.Integer({
        min = 1,
        max = 1000,
    })),
    location = Schema.Optional(Schema.String({
        min = 1,
        max = 32,
        pattern = '^%l[%w_]*$',
    })),
    note = Schema.Optional(Schema.Integer({
        min = 1,
        max = MAX_INT,
    })),
})

UgAdmin.Rules.Sorted = sorted

---Rule for an action name.
UgAdmin.Rules.Action = Schema.Enum(sorted(UgAdmin.Enums.Action))

---Panel settings of one staff member. Every field is optional, so settings saved by an older version still load.
UgAdmin.Rules.Settings = Schema.Object({
    -- Quick bar actions in the order the staff member wants. Actions left out keep their default place, after these.
    order = Schema.Optional(Schema.Array(UgAdmin.Rules.Action, {
        max = 64,
    })),
    -- Quick bar actions the staff member hid.
    hidden = Schema.Optional(Schema.Array(UgAdmin.Rules.Action, {
        max = 64,
    })),
    -- Show the actions on everyone.
    everyone = Schema.Optional(Schema.Boolean()),
    tab = Schema.Optional(Schema.Enum(sorted(UgAdmin.Enums.PanelTab))),
    -- Ask a second click before risky actions.
    confirm = Schema.Optional(Schema.Boolean()),
    -- Own quick replies of the report chat, in place of the built-in ones.
    replies = Schema.Optional(Schema.Array(Schema.String({
        min = 1,
        max = 100,
    }), {
        max = 8,
    })),
})
