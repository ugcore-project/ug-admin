--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Test helpers: a tiny runner, CfxLua mocks, and the real ug-core and ug-lib shared code this resource relies on.
-- ug-core and ug-lib are read from the UG_CORE and UG_LIB paths, siblings of this repository by default.
-- Mock only what the resource uses. Add a mock here when new code calls a new native or UgCore function.

---@class TestHelpers
local H = {}

H.Resource = 'ug-admin'
H.CorePath = os.getenv('UG_CORE') or '../ug-core'
H.LibPath = os.getenv('UG_LIB') or '../ug-lib'

local passed, failed = 0, 0
local rawType = type
local vectorKinds = setmetatable({}, {
    __mode = 'k',
})

---The CfxLua `type` names vectors.
---@param value any
---@return string
type = function(value)
    return rawType(value) == 'table' and vectorKinds[value] or rawType(value)
end

local vectorMeta = {}

---@param kind string
---@param components table
---@return table
local function newVector(kind, components)
    vectorKinds[components] = kind

    return setmetatable(components, vectorMeta[kind])
end

local AXES = {
    vector2 = { 'x', 'y' },
    vector3 = { 'x', 'y', 'z' },
    vector4 = { 'x', 'y', 'z', 'w' },
}

for kind, axes in pairs(AXES) do
    local meta = {}

    ---@param a any
    ---@param b any
    ---@param op fun(x: number, y: number): number
    local function combine(a, b, op)
        local out = {}

        for _, axis in ipairs(axes) do
            local x = rawType(a) == 'number' and a or a[axis]
            local y = rawType(b) == 'number' and b or b[axis]

            out[axis] = op(x, y)
        end

        return newVector(kind, out)
    end

    meta.__add = function(a, b) return combine(a, b, function(x, y) return x + y end) end
    meta.__sub = function(a, b) return combine(a, b, function(x, y) return x - y end) end
    meta.__mul = function(a, b) return combine(a, b, function(x, y) return x * y end) end
    meta.__div = function(a, b) return combine(a, b, function(x, y) return x / y end) end
    meta.__unm = function(a) return combine(a, 0, function(x) return -x end) end
    meta.__len = function(a)
        local sum = 0

        for _, axis in ipairs(axes) do
            sum = sum + a[axis] * a[axis]
        end

        return math.sqrt(sum)
    end
    meta.__eq = function(a, b)
        for _, axis in ipairs(axes) do
            if a[axis] ~= b[axis] then
                return false
            end
        end

        return true
    end

    vectorMeta[kind] = meta
end

function vector2(x, y) return newVector('vector2', { x = x, y = y }) end

function vector3(x, y, z) return newVector('vector3', { x = x, y = y, z = z }) end

function vector4(x, y, z, w) return newVector('vector4', { x = x, y = y, z = z, w = w }) end

---@type table<string, string|false> file contents by path; false reads as missing
H.Files = {}
---@type table<string, string> files written by SaveResourceFile
H.Saved = {}
---@type table<string, function[]> FiveM event handlers
H.Handlers = {}
---@type table<string, function> exports of this resource
H.Exports = {}
H.Now = 0
H.CoreReady = true
---@type table<string, boolean> enabled ug-core modules
H.Modules = {}

-- Server side.

---@type table<string, { options: table, handler: function }> callbacks registered, by short name
H.Callbacks = {}
---@type table<string, { options: table, handler: function }> chat commands registered through ug-core
H.Commands = {}
---@type { source: integer, violation: string, detail: string? }[]
H.Flags = {}
---@type table<integer, { identifier: string, characterId: integer?, group: string?, state: string? }> players by source
H.Players = {}
---@type table<integer, vector3> server-side ped positions by source
H.PedCoords = {}
---@type table<integer, table<string, integer>> balances by source and account
H.Balances = {}
---@type { target: integer, account: string, amount: integer, reason: string? }[]
H.Ledger = {}
---@type { name: string, args: any[] }[] events emitted through UgCore.Events
H.Emitted = {}
---@type table<string, function[]> UgCore.Events handlers by name
H.EventHandlers = {}
---@type { source: integer, name: string, args: any[] }[] net events sent to clients, -1 for everyone
H.Sent = {}
---@type table<string, fun(source: integer, ...): any> what clients answer to server-to-client callbacks
H.ClientAnswers = {}
---@type table<integer, table> player statebags by source
H.State = {}
---@type { fn: string, args: any[] }[] calls of mutating ug-core functions
H.CoreCalls = {}
---@type table[] rows of ug_admin_log
H.Rows = {}
---@type table[] rows of ug_admin_notes
H.Notes = {}
H.NoteId = 0
---@type table<string, table> rows of ug_admin_sanctions by `identifier/kind`
H.Sanctions = {}
H.DbReady = true
---@type table<integer, integer> routing bucket by source
H.Bucket = {}

-- Groups like ug-core's defaults: founder > admin > moderator.
H.Groups = {
    moderator = {
        label = 'Moderator',
        weight = 10,
    },
    admin = {
        label = 'Admin',
        weight = 50,
        inherits = 'moderator',
    },
    founder = {
        label = 'Founder',
        weight = 100,
        inherits = 'admin',
    },
}

-- Client side.

---@type table<string, fun(...): any> what the server answers, by callback short name
H.Respond = {}
---@type { name: string, args: any[] }[] callbacks the client called
H.Requests = {}
---@type table<string, fun(body: any, cb: fun(reply: any))>
H.NuiCallbacks = {}
---@type table[] ug-lib keybinds registered
H.Keybinds = {}
---@type table[] notifications shown
H.Notifications = {}
---@type table<string, function> net event handlers, by short name
H.NetHandlers = {}
---@type { key?: string, bag?: string, handler: function }[] state bag change handlers, like AddStateBagChangeHandler
H.BagHandlers = {}
---@type table<string, function> client callbacks, by short name
H.ClientCallbacks = {}
---@type table client LocalPlayer.state
H.LocalState = {}
H.Locale = 'en'

function GetCurrentResourceName()
    return H.Resource
end

---@param _ string
---@param path string
---@return string?
function LoadResourceFile(_, path)
    if H.Files[path] ~= nil then
        return H.Files[path] or nil
    end

    local handle = io.open(path, 'rb')

    if not handle then
        return nil
    end

    local content = handle:read('a')

    handle:close()

    return content
end

function SaveResourceFile(_, path, content)
    H.Saved[path] = content
    H.Files[path] = content

    return true
end

function GetResourceMetadata(_, key)
    return key == 'version' and '1.0.0' or nil
end

---@type { thread: thread, wakeAt: integer }[] threads waiting in Wait
local sleeping = {}

---@param thread thread
local function resume(thread)
    local ok, result = coroutine.resume(thread)

    if not ok then
        error(debug.traceback(thread, tostring(result)), 0)
    end

    if coroutine.status(thread) == 'suspended' then
        sleeping[#sleeping + 1] = {
            thread = thread,
            wakeAt = H.Now + math.max(result or 0, 1),
        }
    end
end

---Like FiveM: the thread runs at once until its first Wait.
function CreateThread(fn)
    resume(coroutine.create(fn))
end

---Yields until H.Advance reaches the time. Outside a thread it only moves the clock.
---@param ms? integer
function Wait(ms)
    if coroutine.isyieldable() then
        coroutine.yield(ms or 0)
    else
        H.Now = H.Now + (ms or 0)
    end
end

---Runs frames of 16 ms until `ms` passed, waking threads whose time came.
---@param ms integer
function H.Advance(ms)
    local target = H.Now + ms

    repeat
        H.Now = math.min(H.Now + 16, target)

        local ready = {}

        for index = #sleeping, 1, -1 do
            if sleeping[index].wakeAt <= H.Now then
                ready[#ready + 1] = table.remove(sleeping, index)
            end
        end

        for index = #ready, 1, -1 do
            resume(ready[index].thread)
        end
    until H.Now >= target
end

---Calls of auto-mocked natives, in order: `{ name, args }`.
---@type { name: string, args: any[] }[]
H.Natives = {}

---@param name string
---@return { name: string, args: any[] }[]
function H.CallsOf(name)
    local list = {}

    for _, call in ipairs(H.Natives) do
        if call.name == name then
            list[#list + 1] = call
        end
    end

    return list
end

---@type table<string, any> answers of auto-mocked natives
H.NativeReturns = {}

-- Any other PascalCase global is a native: recorded, answering H.NativeReturns[name] or nil.
setmetatable(_G, {
    __index = function(_, name)
        if rawType(name) == 'string' and name:find('^%u') then
            return function(...)
                H.Natives[#H.Natives + 1] = {
                    name = name,
                    args = { ... },
                }

                local value = H.NativeReturns[name]

                if rawType(value) == 'function' then
                    return value(...)
                end

                return value
            end
        end

        return nil
    end,
})

function GetGameTimer()
    return H.Now
end

function AddEventHandler(name, handler)
    H.Handlers[name] = H.Handlers[name] or {}
    table.insert(H.Handlers[name], handler)
end

exports = setmetatable({}, {
    __call = function(_, name, fn)
        H.Exports[name] = fn
    end,
})

function RegisterNUICallback(name, handler)
    H.NuiCallbacks[name] = handler
end

---Posts to a NUI callback like the page does. Returns the reply.
---@param name string
---@param body any
---@return any
function H.PostNui(name, body)
    local reply = nil

    assert(H.NuiCallbacks[name], 'NUI callback not registered: ' .. name)(body, function(value)
        reply = value
    end)

    return reply
end

---Messages sent to the page, in order.
---@return { action: string, payload: any }[]
function H.PageMessages()
    local list = {}

    for _, call in ipairs(H.CallsOf('SendNUIMessage')) do
        list[#list + 1] = call.args[1]
    end

    return list
end

---The payload of the last page message with this action, or false when it was sent without one.
---@param action string
---@return any
function H.LastPage(action)
    local found = nil

    for _, message in ipairs(H.PageMessages()) do
        if message.action == action then
            found = message
        end
    end

    return found and (found.payload or false)
end

---Stand-in for CfxLua's joaat: stable and different per name.
function joaat(name)
    local hash = 0

    for index = 1, #name do
        hash = (hash * 31 + name:byte(index)) % 4294967296
    end

    return hash
end

---Loads a Lua file into the global environment.
---@param path string
local function run(path)
    assert(loadfile(path, 't'))()
end

---@param bag table
---@param name? string bag name for change handlers, such as `global`
---@return table
local function stateBag(bag, name)
    return setmetatable(bag, {
        __index = {
            set = function(self, key, value)
                rawset(self, key, value)

                for _, entry in ipairs(name and H.BagHandlers or {}) do
                    if (entry.key == nil or entry.key == key) and (entry.bag == nil or entry.bag == name) then
                        entry.handler(name, key, value, 0, true)
                    end
                end
            end,
        },
    })
end

---Like the Cfx native: the handler runs when a matching bag key is set.
---@param key? string
---@param bag? string
---@param handler function
---@return integer
function AddStateBagChangeHandler(key, bag, handler)
    H.BagHandlers[#H.BagHandlers + 1] = {
        key = key,
        bag = bag,
        handler = handler,
    }

    return #H.BagHandlers
end

---Translations like ug-lib, as the key and its variables, so tests read what was asked for.
---@return fun(key: string, vars?: table): string
local function translator()
    return function(key, vars)
        local parts = {}

        for name, value in pairs(vars or {}) do
            parts[#parts + 1] = name .. '=' .. tostring(value)
        end

        table.sort(parts)

        return #parts > 0 and (key .. '(' .. table.concat(parts, ',') .. ')') or key
    end
end

local function loadCore()
    for _, file in ipairs({
        'core/shared/init.lua',
        'core/shared/utils/init.lua',
        'core/shared/utils/table.lua',
        'core/shared/utils/string.lua',
        'core/shared/enums/init.lua',
        'core/shared/enums/lifecycle.lua',
        'core/shared/enums/violations.lua',
        'core/shared/enums/errors.lua',
        'core/shared/logger.lua',
        'core/shared/schema.lua',
        'core/shared/enums/events.lua',
        'core/shared/enums/hooks.lua',
        'core/shared/enums/statebags.lua',
        'modules/players/shared/enums.lua',
        'modules/permissions/shared/enums.lua',
        'modules/commands/shared/enums.lua',
    }) do
        run(H.CorePath .. '/' .. file)
    end

    UgCore.Logger.Debug = function() end
    UgCore.Logger.Info = function() end
    UgCore.Lifecycle = {
        Await = function()
            return H.CoreReady
        end,
    }
    UgCore.Modules = {
        IsEnabled = function(name)
            return H.Modules[name] == true
        end,
    }
    UgCore.Events = {
        Emit = function(name, ...)
            H.Emitted[#H.Emitted + 1] = {
                name = name,
                args = { ... },
            }
        end,
        On = function(name, handler)
            H.EventHandlers[name] = H.EventHandlers[name] or {}
            table.insert(H.EventHandlers[name], handler)
        end,
    }
end

---@param fn string
---@param ... any
local function record(fn, ...)
    H.CoreCalls[#H.CoreCalls + 1] = {
        fn = fn,
        args = { ... },
    }
end

---The group and every group it inherits.
---@param group string?
---@return table<string, boolean>
local function chain(group)
    local seen = {}

    while group and H.Groups[group] do
        seen[group] = true
        group = H.Groups[group].inherits
    end

    return seen
end

---@param source integer|string
---@return number
local function weightOf(source)
    if source == 0 then
        return math.huge
    end

    local player = H.Players[source]
    local group = player and player.group

    return group and H.Groups[group] and H.Groups[group].weight or 0
end

local function installServer()
    local Errors = UgCore.Enums.Errors
    local DeathState = UgCore.Enums.DeathState

    UgCore.Callback = {
        Register = function(name, options, handler)
            H.Callbacks[name] = {
                options = options,
                handler = handler,
            }
        end,
        Await = function(source, name, options, ...)
            local answer = H.ClientAnswers[name:match(':(.+)$')]

            if not answer then
                return false, nil, Errors.Timeout
            end

            local ok, value = UgCore.Schema.Check(options.schema, answer(source, ...))

            return ok, ok and value or nil, not ok and Errors.InvalidArgs or nil
        end,
    }
    UgCore.Network = {
        TriggerClient = function(source, name, ...)
            H.Sent[#H.Sent + 1] = {
                source = source,
                name = name:match(':(.+)$'),
                args = { ... },
            }
        end,
        TriggerClients = function(name, ...)
            H.Sent[#H.Sent + 1] = {
                source = -1,
                name = name:match(':(.+)$'),
                args = { ... },
            }
        end,
    }
    UgCore.Commands = {
        Register = function(name, options, handler)
            H.Commands[name] = {
                options = options,
                handler = handler,
            }
        end,
    }
    UgCore.Guard = {
        Flag = function(target, violation, detail)
            H.Flags[#H.Flags + 1] = {
                source = target,
                violation = violation,
                detail = detail,
            }
        end,
        GetScore = function()
            return 0
        end,
        IsNear = function(target, coords, maxDistance)
            local at = H.PedCoords[target]

            return at ~= nil and #(at - coords) <= maxDistance
        end,
    }
    UgCore.Config = {
        Get = function(name, key)
            if name == 'permissions' and key == 'groups' then
                return H.Groups
            end

            if name == 'accounts' and key == 'accounts' then
                return {
                    cash = {
                        label = 'Cash',
                    },
                    debt = {
                        label = 'Debt',
                        allowNegative = true,
                    },
                }
            end

            if name == 'needs' and key == 'needs' then
                return {
                    hunger = {
                        label = 'Hunger',
                    },
                    thirst = {
                        label = 'Thirst',
                    },
                }
            end

            return {}
        end,
    }
    UgCore.Identity = {
        GetPrimary = function(source)
            return H.Players[source] and H.Players[source].identifier or nil
        end,
        GetIdentifiers = function(source)
            return H.Players[source] and { H.Players[source].identifier, 'ip:127.0.0.1' } or {}
        end,
        Ban = function(target, options)
            record('Ban', target, options)

            return true, 1, nil
        end,
        Unban = function(identifier)
            record('Unban', identifier)

            return true, identifier == 'license:banned' and 1 or 0, nil
        end,
    }
    UgCore.Permissions = {
        IsInGroup = function(source, group)
            local player = H.Players[source]

            return player ~= nil and chain(player.group)[group] == true
        end,
        CanTarget = function(actor, target)
            return weightOf(actor) > weightOf(target)
        end,
        GetWeight = weightOf,
        GetGroupDefinition = function(group)
            return H.Groups[group]
        end,
        GetGroups = function(source)
            local player = H.Players[source]

            return player and player.group and { player.group } or {}
        end,
        AddGroup = function(target, group, by)
            record('AddGroup', target, group, by)
            H.Players[target].group = group

            return true, nil
        end,
        RemoveGroup = function(target, group)
            record('RemoveGroup', target, group)

            if H.Players[target].group ~= group then
                return true, false, nil
            end

            H.Players[target].group = nil

            return true, true, nil
        end,
    }
    UgCore.Players = {
        Get = function(target)
            local player = H.Players[target]

            return player and {
                source = target,
                identifier = player.identifier,
                characterId = player.characterId,
            } or nil
        end,
        GetAll = function()
            local list = {}

            for source, player in pairs(H.Players) do
                list[#list + 1] = {
                    source = source,
                    identifier = player.identifier,
                    characterId = player.characterId,
                }
            end

            table.sort(list, function(a, b) return a.source < b.source end)

            return list
        end,
        GetDeathState = function(target)
            return H.Players[target] and H.Players[target].state or DeathState.Alive
        end,
        Revive = function(target, options)
            record('Revive', target, options)
            H.Players[target].state = DeathState.Alive

            return true, nil
        end,
        ClearInjuries = function(target)
            record('ClearInjuries', target)

            return true, nil
        end,
        Kill = function(target)
            record('Kill', target)

            return true, nil
        end,
        Kick = function(target, reason)
            record('Kick', target, reason)

            return true, nil
        end,
    }
    UgCore.Characters = {
        GetActive = function(target)
            local player = H.Players[target]

            return player and player.characterId and {
                id = player.characterId,
                name = 'Character ' .. player.characterId,
            } or nil
        end,
    }
    UgCore.Accounts = {
        GetAll = function(target)
            return H.Balances[target]
        end,
        Add = function(target, account, amount, reason)
            local balances = H.Balances[target]

            balances[account] = (balances[account] or 0) + amount
            H.Ledger[#H.Ledger + 1] = {
                target = target,
                account = account,
                amount = amount,
                reason = reason,
            }

            return true, balances[account], nil
        end,
        Remove = function(target, account, amount, reason)
            local balances = H.Balances[target]

            if (balances[account] or 0) < amount then
                return false, nil, Errors.InsufficientFunds
            end

            balances[account] = balances[account] - amount
            H.Ledger[#H.Ledger + 1] = {
                target = target,
                account = account,
                amount = -amount,
                reason = reason,
            }

            return true, balances[account], nil
        end,
        Set = function(target, account, balance, reason)
            local balances = H.Balances[target]

            H.Ledger[#H.Ledger + 1] = {
                target = target,
                account = account,
                amount = balance - (balances[account] or 0),
                reason = reason,
            }
            balances[account] = balance

            return true, balance, nil
        end,
    }
    UgCore.Jobs = {
        Exists = function(name, grade)
            return name == 'police' and grade <= 3
        end,
        Set = function(target, name, grade)
            record('SetJob', target, name, grade)

            return true, nil
        end,
    }
    UgCore.Items = {
        Exists = function(name)
            return name == 'water'
        end,
        GetAll = function()
            return {
                water = {
                    name = 'water',
                    label = 'Water',
                },
            }
        end,
    }
    UgCore.Inventory = {
        AddItem = function(target, name, count, metadata, reason)
            record('AddItem', target, name, count, metadata, reason)

            return true, nil
        end,
        GetItems = function()
            return {
                {
                    name = 'water',
                    count = 2,
                    slot = 1,
                    metadata = {
                        secret = true,
                    },
                },
            }
        end,
        Clear = function(target, reason)
            record('Clear', target, reason)

            return true, nil
        end,
        Open = function(source, inventoryId)
            record('OpenInventory', source, inventoryId)

            return true, nil
        end,
        RemoveFromSlot = function(target, slot, count, reason)
            record('RemoveFromSlot', target, slot, count, reason)

            return true, nil
        end,
    }
    UgCore.Needs = {
        Reset = function(target)
            record('ResetNeeds', target)

            return true, nil
        end,
        Set = function(target, name, value)
            record('SetNeed', target, name, value)

            return true, value, nil
        end,
        GetAll = function()
            return {
                hunger = 80,
                thirst = 60,
            }
        end,
    }

    -- Each table is a Lua table: H.Rows the audit log, H.Notes and H.Sanctions keyed `identifier/kind`.
    MySQL = {
        query = {
            await = function(sql, params)
                if not H.DbReady then
                    error('database down')
                end

                if sql:find('^%s*CREATE') then
                    return {}
                end

                local rows = {}

                if sql:find('ug_admin_sanctions', 1, true) then
                    local key = params[1] .. '/' .. tostring(params[2])

                    if sql:find('^INSERT') then
                        H.Sanctions[key] = {
                            identifier = params[1],
                            kind = params[2],
                            remaining = params[3],
                            reason = params[4],
                            by = params[5],
                        }
                    elseif sql:find('^DELETE') then
                        H.Sanctions[key] = nil
                    else
                        for _, kind in ipairs({ 'jail', 'mute' }) do
                            rows[#rows + 1] = H.Sanctions[params[1] .. '/' .. kind]
                        end
                    end

                    return rows
                end

                if sql:find('ug_admin_notes', 1, true) then
                    for index = #H.Notes, 1, -1 do
                        if H.Notes[index].target == params[1] then
                            rows[#rows + 1] = H.Notes[index]
                        end
                    end

                    return rows
                end

                local target = sql:find('`target` = ?', 1, true) and params[1] or nil

                for index = #H.Rows, 1, -1 do
                    if not target or H.Rows[index].target == target then
                        rows[#rows + 1] = H.Rows[index]
                    end
                end

                return rows
            end,
        },
        update = {
            await = function(sql, params)
                if not H.DbReady then
                    error('database down')
                end

                assert(sql:find('^DELETE FROM `ug_admin_notes`'), 'unexpected update: ' .. sql)

                for index, note in ipairs(H.Notes) do
                    if note.id == params[1] then
                        table.remove(H.Notes, index)

                        return 1
                    end
                end

                return 0
            end,
        },
        insert = {
            await = function(sql, params)
                if not H.DbReady then
                    error('database down')
                end

                if sql:find('ug_admin_notes', 1, true) then
                    H.NoteId = H.NoteId + 1
                    H.Notes[#H.Notes + 1] = {
                        id = H.NoteId, target = params[1], author = params[2], author_name = params[3], text = params[4], created_at = params[5],
                    }

                    return H.NoteId
                end

                H.Rows[#H.Rows + 1] = {
                    id = #H.Rows + 1, actor = params[1], actor_name = params[2], action = params[3],
                    target = params[4] ~= '' and params[4] or nil, target_name = params[5] ~= '' and params[5] or nil,
                    detail = params[6], created_at = params[7],
                }

                return #H.Rows
            end,
        },
    }

    function Player(source)
        H.State[source] = H.State[source] or stateBag({})

        return {
            state = H.State[source],
        }
    end

    -- Peds are 100 + source. Positions come from H.PedCoords.
    H.NativeReturns.GetPlayerPed = function(source)
        local id = math.tointeger(tonumber(source))

        return id and H.Players[id] and 100 + id or 0
    end
    H.NativeReturns.GetEntityCoords = function(entity)
        return H.PedCoords[entity - 100] or vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.DoesEntityExist = function(entity)
        return entity ~= nil and entity ~= 0
    end
    H.NativeReturns.GetPlayerName = function(source)
        return 'Player' .. tostring(source)
    end
    H.NativeReturns.GetVehiclePedIsIn = 0
    H.NativeReturns.GetEntityHeading = 90.0
    H.NativeReturns.GetPlayerPing = 30
    H.NativeReturns.GetEntityHealth = 200
    H.NativeReturns.GetPlayerRoutingBucket = function(source)
        return H.Bucket[math.tointeger(tonumber(source))] or 0
    end
    H.NativeReturns.SetPlayerRoutingBucket = function(source, bucket)
        H.Bucket[math.tointeger(tonumber(source))] = bucket
    end
    H.NativeReturns.GetPlayers = function()
        local list = {}

        for source in pairs(H.Players) do
            list[#list + 1] = tostring(source)
        end

        return list
    end
    H.NativeReturns.GetAllVehicles = {}

    H.NativeReturns.GetConvar = function(_, fallback)
        return fallback
    end
end

local function installClient()
    UgCore.Callback = {
        Await = function(name, ...)
            local short = name:match('^' .. H.Resource:gsub('%-', '%%-') .. ':(.+)$') or name

            H.Requests[#H.Requests + 1] = {
                name = short,
                args = { ... },
            }

            local respond = H.Respond[short]

            if not respond then
                return false, nil, UgCore.Enums.Errors.Timeout
            end

            return true, respond(...), nil
        end,
        Register = function(name, handler)
            H.ClientCallbacks[name] = handler
        end,
    }
    UgCore.Network = {
        Register = function(name, handler)
            H.NetHandlers[name] = handler
        end,
    }
    UgLib.Notify = {
        Show = function(options)
            H.Notifications[#H.Notifications + 1] = options
        end,
    }
    UgLib.Keybind = {
        Register = function(options)
            H.Keybinds[#H.Keybinds + 1] = options

            return ('+%s-%s'):format(H.Resource, options.name)
        end,
    }
    UgLib.Raycast = {
        FromCoords = function()
            return {
                hit = false,
            }
        end,
    }
    UgLib.Draw = {
        Text2D = function() end,
        Text3D = function() end,
    }
    UgLib.Clipboard = {
        Copy = function() return true end,
    }
    UgLib.Streaming = {
        ScaleformMovie = function()
            return true, 1
        end,
    }

    LocalPlayer = {
        state = H.LocalState,
    }

    function Player()
        return {
            state = {},
        }
    end

    H.Kvp = {}
    H.NativeReturns.GetResourceKvpString = function(key)
        return H.Kvp[key]
    end
    H.NativeReturns.SetResourceKvp = function(key, value)
        H.Kvp[key] = value
    end
    H.NativeReturns.PlayerPedId = 1
    H.NativeReturns.PlayerId = 0
    H.NativeReturns.GetPlayerServerId = 1
    H.NativeReturns.GetVehiclePedIsIn = 0
    H.NativeReturns.GetEntityCoords = function()
        return vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetGameplayCamCoord = function()
        return vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetGameplayCamRot = function()
        return vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetGameplayCamFov = 50.0
    H.NativeReturns.GetEntityHeading = 0.0
    H.NativeReturns.GetGroundZFor_3dCoord = function()
        return true, 30.0
    end
    H.NativeReturns.HasCollisionLoadedAroundEntity = true
    H.NativeReturns.GetActivePlayers = {}
    H.NativeReturns.GetDisabledControlNormal = 0.0
    H.NativeReturns.GetEntityHealth = 200
    H.NativeReturns.GetPedArmour = 0
    H.NativeReturns.GetEntitySpeed = 0.0
    H.NativeReturns.CreateCamWithParams = 9
    H.NativeReturns.GetHashKey = 0x1234
end

local function loadLib()
    for _, file in ipairs({
        'shared/init.lua',
        'shared/utils.lua',
        'shared/string.lua',
        'shared/table.lua',
        'shared/enums/init.lua',
        'shared/enums/ui.lua',
    }) do
        run(H.LibPath .. '/' .. file)
    end

    UgLib.Locale = {
        Create = translator,
        GetCode = function()
            return H.Locale
        end,
    }
    UgLib.Format = {
        Money = function(amount)
            return '$' .. tostring(amount)
        end,
    }
    UgLib.Enums.GlobalState = UgLib.Enums.GlobalState or {
        Config = 'ug-lib:Config',
    }
end

---Reads script lists from fxmanifest.lua.
---@return table<string, string[]>
local function readManifest()
    local lists = {
        shared = {},
        server = {},
        client = {},
    }
    local groups = {
        shared_script = 'shared', shared_scripts = 'shared',
        server_script = 'server', server_scripts = 'server',
        client_script = 'client', client_scripts = 'client',
    }
    local env = setmetatable({}, {
        __index = function(_, directive)
            return function(value)
                local group = groups[directive]

                if group then
                    for _, entry in ipairs(rawType(value) == 'table' and value or { value }) do
                        table.insert(lists[group], entry)
                    end
                end
            end
        end,
    })

    assert(loadfile('fxmanifest.lua', 't', env))()

    return lists
end

---Fresh mocks. Tests change them before H.Load. `config.lua` starts missing, whatever is on disk.
---Player 1 is a founder, 2 a moderator, 3 an admin, 4 a player. All have characters.
function H.Reset()
    H.Files, H.Saved = {
        ['config.lua'] = false,
    }, {}
    H.Handlers, H.Exports = {}, {}
    H.Now, H.CoreReady = 1000, true
    H.Modules = {
        accounts = true,
        characters = true,
        commands = true,
        jobs = true,
        items = true,
        inventory = true,
        needs = true,
    }
    H.Natives, H.NativeReturns = {}, {}
    H.Callbacks, H.Commands, H.Flags, H.Emitted, H.Ledger = {}, {}, {}, {}, {}
    H.EventHandlers, H.Sent, H.ClientAnswers, H.State, H.CoreCalls, H.Rows = {}, {}, {}, {}, {}, {}
    H.DbReady, H.Bucket = true, {}
    H.Notes, H.NoteId, H.Sanctions = {}, 0, {}
    H.Players = {
        [1] = {
            identifier = 'license:1',
            characterId = 10,
            group = 'founder',
        },
        [2] = {
            identifier = 'license:2',
            characterId = 20,
            group = 'moderator',
        },
        [3] = {
            identifier = 'license:3',
            characterId = 30,
            group = 'admin',
        },
        [4] = {
            identifier = 'license:4',
            characterId = 40,
        },
    }
    H.PedCoords = {
        [1] = vector3(100.0, 100.0, 30.0),
        [2] = vector3(200.0, 200.0, 30.0),
        [3] = vector3(300.0, 300.0, 30.0),
        [4] = vector3(400.0, 400.0, 30.0),
    }
    H.Balances = {
        [1] = {
            cash = 0,
        },
        [2] = {
            cash = 0,
        },
        [3] = {
            cash = 0,
        },
        [4] = {
            cash = 100,
        },
    }
    H.Respond, H.Requests, H.NuiCallbacks = {}, {}, {}
    H.Keybinds, H.Notifications, H.NetHandlers, H.ClientCallbacks, H.LocalState, H.Locale = {}, {}, {}, {}, {}, 'en'
    H.BagHandlers = {}
    GlobalState = stateBag({}, 'global')
    MySQL, LocalPlayer, Player = nil, nil, nil
    sleeping = {}
    UgCore, UgLib, UgAdmin = nil, nil, nil
end

---Loads ug-core and ug-lib, then this resource's shared and side scripts in manifest order.
---@param side 'server'|'client'
---@return string[] printed lines
function H.Load(side)
    return H.Capture(function()
        loadCore()
        loadLib()

        if side == 'server' then
            installServer()
        else
            installClient()
        end

        local manifest = readManifest()

        for _, group in ipairs({ 'shared', side }) do
            for _, path in ipairs(manifest[group]) do
                if path:sub(1, 1) ~= '@' then
                    run(path)
                end
            end
        end
    end)
end

---The defaults, read from server/config.default.lua like the server reads them.
---@return table
function H.Defaults()
    local content = assert(LoadResourceFile('ug-admin', 'server/config.default.lua'))
    local env = setmetatable({}, {
        __index = _G,
    })

    return assert(load(content, '@server/config.default.lua', 't', env))()
end

---Loads the client with the server's config replicated, and opens the page.
---@param overrides? table config values that replace the defaults
---@return string[] printed lines
function H.LoadClient(overrides)
    local values = H.Defaults()

    for key, value in pairs(overrides or {}) do
        values[key] = value
    end

    GlobalState['ug-admin:Config'] = values

    local lines = H.Load('client')

    H.PostNui('ready', {})

    return lines
end

---Calls a registered server callback like ug-core does: the schema first, then the handler.
---@param name string short name, such as `Run`
---@param target integer
---@param ... any
---@return any result
---@return string? errorCode when ug-core rejects before the handler
function H.Call(name, target, ...)
    local entry = assert(H.Callbacks[name], 'callback not registered: ' .. name)
    local ok, args = UgCore.Schema.Validate(entry.options.schema, ...)

    if not ok or not args then
        return nil, UgCore.Enums.Errors.InvalidArgs
    end

    return entry.handler(target, table.unpack(args, 1, args.n))
end

---Runs a chat command like ug-core: the player MUST be in one of its groups, then the handler gets parsed args.
---@param name string
---@param source integer
---@param parsed table<string, any>
---@return boolean ran false when the group check refused
function H.Command(name, source, parsed)
    local entry = assert(H.Commands[name], 'command not registered: ' .. name)

    if source ~= 0 and entry.options.groups then
        local allowed = false

        for _, group in ipairs(entry.options.groups) do
            allowed = allowed or UgCore.Permissions.IsInGroup(source, group)
        end

        if not allowed then
            return false
        end
    end

    entry.handler(source, parsed)

    return true
end

---Net events sent with this short name, in order.
---@param name string
---@return { source: integer, name: string, args: any[] }[]
function H.SentOf(name)
    local list = {}

    for _, sent in ipairs(H.Sent) do
        if sent.name == name then
            list[#list + 1] = sent
        end
    end

    return list
end

---Calls of a mocked ug-core function, in order.
---@param fn string
---@return any[][]
function H.CoreCallsOf(fn)
    local list = {}

    for _, call in ipairs(H.CoreCalls) do
        if call.fn == fn then
            list[#list + 1] = call.args
        end
    end

    return list
end

---Runs every UgCore.Events handler of an event.
---@param name string
---@param ... any
function H.EmitCore(name, ...)
    for _, handler in ipairs(H.EventHandlers[name] or {}) do
        handler(...)
    end
end

---Runs every handler of a FiveM event, like the runtime.
---@param name string
function H.TriggerEvent(name, ...)
    for _, handler in ipairs(H.Handlers[name] or {}) do
        handler(...)
    end
end

---Runs `fn` and returns every printed line, without color codes.
---@param fn fun()
---@return string[]
function H.Capture(fn)
    local lines = {}
    local original = print

    print = function(...)
        local parts = {}

        for index = 1, select('#', ...) do
            parts[#parts + 1] = tostring((select(index, ...)))
        end

        lines[#lines + 1] = (table.concat(parts, ' '):gsub('%^%d', ''))
    end

    local ok, err = pcall(fn)

    print = original

    if not ok then
        error(err, 0)
    end

    return lines
end

---@param a any
---@param b any
---@return boolean
local function same(a, b)
    if rawType(a) ~= 'table' or rawType(b) ~= 'table' then
        return a == b
    end

    if vectorKinds[a] ~= vectorKinds[b] then
        return false
    end

    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

---@param value any
---@param depth? integer
---@return string
local function show(value, depth)
    depth = depth or 0

    if rawType(value) ~= 'table' then
        return rawType(value) == 'string' and ('%q'):format(value) or tostring(value)
    end

    if depth > 3 then
        return '{...}'
    end

    local parts = {}

    for key, item in pairs(value) do
        parts[#parts + 1] = ('%s = %s'):format(tostring(key), show(item, depth + 1))
    end

    table.sort(parts)

    return (vectorKinds[value] or '') .. '{ ' .. table.concat(parts, ', ') .. ' }'
end

function H.Equal(actual, expected, message)
    if not same(actual, expected) then
        error(('%s\n  expected: %s\n  actual:   %s'):format(message or 'not equal', show(expected), show(actual)), 2)
    end
end

function H.Assert(condition, message)
    if not condition then
        error(message or 'assertion failed', 2)
    end
end

---Runs `fn` and expects it to raise an error containing `text`.
---@param fn fun()
---@param text string
function H.Raises(fn, text)
    local ok, err = pcall(fn)

    if ok then
        error(('expected an error containing "%s"'):format(text), 2)
    end

    if not tostring(err):find(text, 1, true) then
        error(('expected an error containing "%s", got: %s'):format(text, tostring(err)), 2)
    end
end

---@param lines string[]
---@param text string
function H.ExpectLine(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return
        end
    end

    error(('no line contains "%s":\n  %s'):format(text, table.concat(lines, '\n  ')), 2)
end

---Wrong-type values for tests. LuaLS ignores casts on literals.
---@param value any
---@return any
function H.Any(value)
    return value
end

---@param name string
---@param fn fun()
function H.Test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)

    if ok then
        passed = passed + 1
        print('  ok    ' .. name)
    else
        failed = failed + 1
        print('  FAIL  ' .. name .. '\n        ' .. tostring(err):gsub('\n', '\n        '))
    end
end

function H.Done()
    print(('\n%d passed, %d failed'):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

---Minimal json like the CfxLua one: objects, arrays, strings, numbers, booleans.
json = {}

---@param text string
---@return any
function json.decode(text)
    local position = 1

    local function skip()
        position = text:find('[^%s]', position) or #text + 1
    end

    local parse

    local function parseString()
        local result = {}

        position = position + 1

        while true do
            local char = text:sub(position, position)

            if char == '' then
                error('unterminated string')
            end

            if char == '"' then
                position = position + 1

                return table.concat(result)
            end

            if char == '\\' then
                local escape = text:sub(position + 1, position + 1)

                if escape == 'u' then
                    result[#result + 1] = utf8.char(tonumber(text:sub(position + 2, position + 5), 16))
                    position = position + 6
                else
                    result[#result + 1] = ({
                        n = '\n',
                        t = '\t',
                        r = '\r',
                    })[escape] or escape
                    position = position + 2
                end
            else
                result[#result + 1] = char
                position = position + 1
            end
        end
    end

    ---@param close string
    ---@param item fun(result: table)
    ---@return table
    local function collection(close, item)
        local result = {}

        position = position + 1
        skip()

        if text:sub(position, position) == close then
            position = position + 1

            return result
        end

        while true do
            item(result)
            skip()

            local separator = text:sub(position, position)

            position = position + 1

            if separator == close then
                return result
            end

            if separator ~= ',' then
                error('expected , or ' .. close)
            end
        end
    end

    parse = function()
        skip()

        local char = text:sub(position, position)

        if char == '{' then
            return collection('}', function(result)
                skip()

                local key = parseString()

                skip()
                position = position + 1
                result[key] = parse()
            end)
        end

        if char == '[' then
            return collection(']', function(result)
                result[#result + 1] = parse()
            end)
        end

        if char == '"' then
            return parseString()
        end

        for literal, value in pairs({
            ['true'] = true,
            ['false'] = false,
        }) do
            if text:sub(position, position + #literal - 1) == literal then
                position = position + #literal

                return value
            end
        end

        if text:sub(position, position + 3) == 'null' then
            position = position + 4

            return nil
        end

        local number = text:match('^-?%d+%.?%d*[eE]?[-+]?%d*', position)

        if not number or number == '' then
            error('unexpected character at ' .. position)
        end

        position = position + #number

        return math.tointeger(tonumber(number)) or tonumber(number)
    end

    return parse()
end

---Encodes like the CfxLua json: tables with keys 1..n are arrays, other tables objects, an empty table an array.
---@param value any
---@return string
function json.encode(value)
    local kind = type(value)

    if kind == 'string' then
        local escaped = value:gsub('[%c"\\]', function(char)
            return ('\\u%04x'):format(char:byte())
        end)

        return '"' .. escaped .. '"'
    end

    if kind == 'number' or kind == 'boolean' then
        return tostring(value)
    end

    if kind ~= 'table' then
        return 'null'
    end

    local parts = {}

    if next(value) == nil or #value > 0 then
        for _, item in ipairs(value) do
            parts[#parts + 1] = json.encode(item)
        end

        return '[' .. table.concat(parts, ',') .. ']'
    end

    local keys = {}

    for key in pairs(value) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(keys) do
        parts[#parts + 1] = json.encode(tostring(key)) .. ':' .. json.encode(value[key])
    end

    return '{' .. table.concat(parts, ',') .. '}'
end

return H
