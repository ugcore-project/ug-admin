--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Owner config: config.lua, copied from server/config.default.lua on the first start and never overwritten.
-- Owner values replace the defaults key by key. Clients get every value through GlobalState: never put secrets here.

---@class UgAdmin.Internal.Config
local Config = {}
UgAdmin.Internal.Config = Config

local Schema = UgCore.Schema

local RESOURCE = GetCurrentResourceName()
local OWNER_FILE = 'config.lua'
local DEFAULT_FILE = 'server/config.default.lua'
local STATE_KEY = UgAdmin.Enums.GlobalState.Config
-- A location name that means the staff member's own waypoint.
local WAYPOINT = 'waypoint'

Config.StateKey = STATE_KEY
local ACTION_NAMES = {}

for _, action in pairs(UgAdmin.Enums.Action) do
    ACTION_NAMES[#ACTION_NAMES + 1] = action
end

table.sort(ACTION_NAMES)

---@param enum table<string, string>
---@return string[]
local function valuesOf(enum)
    local values = {}

    for _, value in pairs(enum) do
        values[#values + 1] = value
    end

    table.sort(values)

    return values
end

local GROUP = Schema.String({
    min = 1,
    max = 32,
    pattern = '^%l[%l%d_]*$',
})
local HSL = Schema.String({
    min = 5,
    max = 24,
    pattern = '^%d+%.?%d* %d+%.?%d*%% %d+%.?%d*%%$',
})
local GAME_NAME = Schema.String({
    min = 1,
    max = 64,
    pattern = '^[%w_%-]+$',
})
local BYTE = Schema.Integer({
    min = 0,
    max = 255,
})
local TABS = valuesOf(UgAdmin.Enums.Tab)

-- ug-lib's theme tokens, then the panel's section tones.
local THEME_TOKENS = {
    'background', 'foreground', 'card', 'cardForeground', 'popover', 'popoverForeground',
    'primary', 'primaryForeground', 'secondary', 'secondaryForeground', 'muted', 'mutedForeground',
    'accent', 'accentForeground', 'destructive', 'destructiveForeground', 'success', 'successForeground',
    'warning', 'warningForeground', 'border', 'input', 'ring',
}

for _, tone in ipairs(valuesOf(UgAdmin.Enums.Tone)) do
    THEME_TOKENS[#THEME_TOKENS + 1] = tone
end

---@param value string
---@return boolean ok
---@return string? message
local function size(value)
    if value:find('^%d*%.?%d+rem$') or value:find('^%d*%.?%d+px$') then
        return true, nil
    end

    return false, 'MUST be a size such as "0.75rem" or "12px"'
end
local KEY = Schema.String({
    max = 16,
    pattern = '^[%w_]*$',
})
local COORDS = Schema.Vector3({
    maxComponent = 20000,
})

---@param value string
---@return boolean ok
---@return string? message
local function checkDuration(value)
    if value == 'perm' or UgAdmin.Internal.ParseDuration(value) then
        return true
    end

    return false, 'MUST be a duration such as 30m, 12h, 7d or perm'
end

---@param value string
---@return boolean ok
---@return string? message
local function checkLocation(value)
    if value == WAYPOINT then
        return false, 'MUST NOT be waypoint, which means the staff member\'s own waypoint'
    end

    return true
end

-- One rule per key. Every string, array and map is bounded.
---@type { key: string, rule: UgSchemaRule }[]
local RULES = {
    {
        key = 'access',
        rule = Schema.Map(Schema.Enum(ACTION_NAMES), GROUP, {
            max = #ACTION_NAMES,
        }),
    },
    {
        key = 'keys',
        rule = Schema.Object({
            noclip = KEY,
            panel = KEY,
            vision = KEY,
        }),
    },
    {
        key = 'noclipSpeeds',
        rule = Schema.Array(Schema.Number({
            min = 0.1,
            max = 1000,
        }), {
            min = 1,
            max = 10,
        }),
    },
    {
        key = 'radarInterval',
        rule = Schema.Integer({
            min = 500,
            max = 60000,
        }),
    },
    {
        key = 'maxDeleteRadius',
        rule = Schema.Number({
            min = 1,
            max = 500,
        }),
    },
    {
        key = 'replaceSpawnedVehicle',
        rule = Schema.Boolean(),
    },
    {
        key = 'reportCooldown',
        rule = Schema.Integer({
            min = 0,
            max = 3600,
        }),
    },
    {
        key = 'maxReports',
        rule = Schema.Integer({
            min = 1,
            max = 1000,
        }),
    },
    {
        key = 'startOnDuty',
        rule = Schema.Boolean(),
    },
    {
        key = 'banDurations',
        rule = Schema.Array(Schema.String({
            min = 1,
            max = 8,
            validate = checkDuration,
        }), {
            min = 1,
            max = 12,
        }),
    },
    {
        key = 'jail',
        rule = Schema.Object({
            coords = COORDS,
            radius = Schema.Number({
                min = 5,
                max = 1000,
            }),
            release = COORDS,
        }),
    },
    {
        key = 'locations',
        rule = Schema.Map(
            Schema.String({
                min = 1,
                max = 32,
                pattern = '^%l[%w_]*$',
                validate = checkLocation,
            }),
            Schema.Object({
                label = Schema.String({
                    min = 1,
                    max = 32,
                }),
                coords = COORDS,
            }),
            {
                max = 32,
            }
        ),
    },
    {
        key = 'theme',
        rule = Schema.Object({
            mode = Schema.Optional(Schema.Enum({ 'dark', 'light' })),
            colors = Schema.Optional(Schema.Map(Schema.Enum(THEME_TOKENS), HSL, {
                max = #THEME_TOKENS,
            })),
            radius = Schema.Optional(Schema.String({
                min = 3,
                max = 16,
                validate = size,
            })),
            font = Schema.Optional(Schema.Enum({ 'Inter' })),
            scale = Schema.Optional(Schema.Number({
                min = 0.75,
                max = 1.5,
            })),
        }),
    },
    {
        key = 'layout',
        rule = Schema.Object({
            width = Schema.Number({
                min = 40,
                max = 160,
            }),
            height = Schema.Number({
                min = 25,
                max = 100,
            }),
            rail = Schema.Enum({ 'left', 'right' }),
            backdrop = Schema.Number({
                min = 0,
                max = 1,
            }),
            glow = Schema.Boolean(),
            logo = Schema.Boolean(),
            quickBar = Schema.Boolean(),
            toasts = Schema.Enum({ 'bottom', 'top' }),
            toastDuration = Schema.Integer({
                min = 500,
                max = 15000,
            }),
            animations = Schema.Boolean(),
            refreshInterval = Schema.Integer({
                min = 2000,
                max = 60000,
            }),
            noclipHud = Schema.Boolean(),
        }),
    },
    {
        key = 'tabs',
        rule = Schema.Array(Schema.Enum(TABS), {
            min = 1,
            max = #TABS,
        }),
    },
    {
        key = 'noclip',
        rule = Schema.Object({
            fov = Schema.Number({
                min = 30,
                max = 110,
            }),
            fovKick = Schema.Number({
                min = 0,
                max = 40,
            }),
            lookSpeed = Schema.Number({
                min = 0.5,
                max = 30,
            }),
            smoothing = Schema.Number({
                min = 1,
                max = 50,
            }),
            boost = Schema.Number({
                min = 1,
                max = 10,
            }),
            slow = Schema.Number({
                min = 0.05,
                max = 1,
            }),
            liftDuration = Schema.Integer({
                min = 0,
                max = 5000,
            }),
            diveDuration = Schema.Integer({
                min = 0,
                max = 5000,
            }),
            inspect = Schema.Boolean(),
            outline = Schema.Boolean(),
            outlineColor = Schema.Array(BYTE, {
                min = 4,
                max = 4,
            }),
            marker = Schema.Boolean(),
        }),
    },
    {
        key = 'spectate',
        rule = Schema.Object({
            swoop = Schema.Boolean(),
            swoopHeight = Schema.Number({
                min = 10,
                max = 500,
            }),
            swoopDuration = Schema.Integer({
                min = 100,
                max = 10000,
            }),
            fade = Schema.Integer({
                min = 0,
                max = 5000,
            }),
        }),
    },
    {
        key = 'shards',
        rule = Schema.Map(
            Schema.Enum(valuesOf(UgAdmin.Enums.Shard)),
            Schema.Object({
                duration = Schema.Integer({
                    min = 1000,
                    max = 30000,
                }),
                color = Schema.Enum(valuesOf(UgAdmin.Enums.ShardColor)),
                sound = Schema.Optional(Schema.Object({
                    name = GAME_NAME,
                    set = GAME_NAME,
                })),
            }),
            {
                max = 8,
            }
        ),
    },
    {
        key = 'invisibleAlpha',
        rule = Schema.Integer({
            min = 0,
            max = 255,
        }),
    },
}

-- Tables that merge onto the defaults field by field. access merges per action, so a config from an older version
-- gets new actions with their default.
local MERGED = {
    access = true,
    layout = true,
    noclip = true,
    spectate = true,
}

---Runs owner code in a sandbox with only what a config needs.
---@param content string
---@param name? string file name in errors, config.lua by default
---@return boolean ok
---@return table? values
---@return string? message
local function run(content, name)
    local env = {
        vector2 = vector2, vector3 = vector3, vector4 = vector4,
        vec2 = vec2, vec3 = vec3, vec4 = vec4,
        tonumber = tonumber, tostring = tostring, type = type, pairs = pairs, ipairs = ipairs,
        math = setmetatable({}, {
            __index = math,
        }),
        string = setmetatable({}, {
            __index = string,
        }),
        table = setmetatable({}, {
            __index = table,
        }),
    }

    local chunk, syntaxError = load(content, '@' .. (name or OWNER_FILE), 't', env)

    if not chunk then
        return false, nil, tostring(syntaxError)
    end

    local ok, result = pcall(chunk)

    if not ok then
        return false, nil, tostring(result)
    end

    if type(result) ~= 'table' then
        return false, nil, 'MUST return a table'
    end

    return true, result, nil
end

---A fresh copy of the defaults, read from server/config.default.lua: the only place they live.
---@return table
function UgAdmin.Internal.Defaults()
    local ok, values, message = run(LoadResourceFile(RESOURCE, DEFAULT_FILE) or '', DEFAULT_FILE)

    if not ok or not values then
        error(('[ug-admin] %s: %s'):format(DEFAULT_FILE, tostring(message)), 2)
    end

    return values
end

---Checks merged values. Returns clean copies of every valid key, and every error found.
---@param values table
---@return table clean
---@return string[] errors
function Config.Validate(values)
    local errors, clean, known, names = {}, {}, {}, {}

    for _, entry in ipairs(RULES) do
        known[entry.key] = true
        names[#names + 1] = entry.key

        local ok, checked, detail = Schema.Check(entry.rule, values[entry.key])

        if ok then
            clean[entry.key] = checked
        else
            local text = (detail or 'is invalid'):gsub('^value:? ?', '')

            errors[#errors + 1] = ('%s: %s'):format(entry.key, text)
        end
    end

    for key in pairs(values) do
        if not known[key] then
            local suggestion = type(key) == 'string' and UgLib.String.Suggest(key, names) or nil

            errors[#errors + 1] = ('unknown key "%s".%s'):format(tostring(key), suggestion and (' Did you mean "%s"?'):format(suggestion) or '')
        end
    end

    table.sort(errors)

    return clean, errors
end

---@type table?
local current = nil

---Reads, merges and checks config.lua, generating it from the example when missing. Publishes the values to clients.
---@return boolean ok
---@return string[] errors
function Config.Load()
    local content = LoadResourceFile(RESOURCE, OWNER_FILE)

    if content == nil then
        local example = LoadResourceFile(RESOURCE, DEFAULT_FILE)

        if example and SaveResourceFile(RESOURCE, OWNER_FILE, example, -1) then
            UgCore.Logger.Info('Generated %s.', OWNER_FILE)
        end

        content = example
    end

    local values = UgAdmin.Internal.Defaults()

    if content then
        local ok, owner, message = run(content)

        if not ok or not owner then
            current = nil

            return false, { ('%s: %s'):format(OWNER_FILE, tostring(message)) }
        end

        for key, value in pairs(owner) do
            if MERGED[key] and type(value) == 'table' and type(values[key]) == 'table' then
                for field, fieldValue in pairs(value) do
                    values[key][field] = fieldValue
                end
            else
                values[key] = value
            end
        end
    end

    local clean, errors = Config.Validate(values)

    for index, message in ipairs(errors) do
        errors[index] = ('%s: %s'):format(OWNER_FILE, message)
    end

    current = #errors == 0 and clean or nil

    if current then
        GlobalState:set(STATE_KEY, current, true)
    end

    return current ~= nil, errors
end

---The loaded config. Raises before a successful Load.
---@return table
function Config.Get()
    if not current then
        error('[ug-admin] Config.Get before a successful Config.Load', 2)
    end

    return current
end
