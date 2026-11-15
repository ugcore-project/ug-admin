--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Server callbacks of the panel and of the client features. Each one has a schema and a rate limit, and checks
-- access again: the `ug-admin:Access` statebag only decides what the client shows.

---@class UgAdmin.Internal.Panel
local Panel = {}
UgAdmin.Internal.Panel = Panel

local Actions = UgAdmin.Internal.Actions
local Audit = UgAdmin.Internal.Audit
local Staff = UgAdmin.Internal.Staff
local Config = UgAdmin.Internal.Config
local Reports = UgAdmin.Internal.Reports
local Spectate = UgAdmin.Internal.Spectate
local Sanctions = UgAdmin.Internal.Sanctions
local Notes = UgAdmin.Internal.Notes
local Sanction = UgAdmin.Enums.Sanction
local Callbacks = UgAdmin.Enums.Callbacks
local Action = UgAdmin.Enums.Action
local StateBags = UgAdmin.Enums.StateBags
local Schema = UgCore.Schema

local MAX_SOURCE = 65535
local TARGET = Schema.Integer({
    min = 1,
    max = MAX_SOURCE,
})
local MESSAGE = Schema.String({
    min = 1,
    max = 256,
})

---@param source integer
---@param key string statebag holding a job or gang
---@return table?
local function jobOf(source, key)
    local value = Player(source).state[key]

    if type(value) ~= 'table' then
        return nil
    end

    return {
        name = value.name,
        label = value.label,
        grade = value.grade,
        gradeLabel = value.gradeLabel,
    }
end

---Name of the character a player plays, when the characters module runs.
---@param source integer
---@return string?
local function characterOf(source)
    if not UgCore.Modules.IsEnabled('characters') then
        return nil
    end

    local character = UgCore.Characters.GetActive(source)

    return character and character.name or nil
end

---Rows of the player list.
---@return table[]
function Panel.Players()
    local list = {}
    local Bags = UgCore.Enums.StateBags

    for _, player in ipairs(UgCore.Players.GetAll()) do
        local source = player.source
        local ped = GetPlayerPed(tostring(source))
        local groups = UgCore.Permissions.GetGroups(source)

        list[#list + 1] = {
            id = source,
            name = UgAdmin.Internal.NameOf(source),
            characterId = player.characterId,
            job = jobOf(source, Bags.Job),
            ping = GetPlayerPing(tostring(source)),
            health = ped ~= 0 and GetEntityHealth(ped) or 0,
            state = UgCore.Players.GetDeathState(source),
            group = groups[1],
            frozen = Player(source).state[StateBags.Frozen] == true,
            score = UgCore.Guard.GetScore(source),
            jailed = Sanctions.Remaining(source, Sanction.Jail),
            muted = Sanctions.Remaining(source, Sanction.Mute),
            duty = Staff.HasMode(source, UgAdmin.Enums.Mode.Duty) or nil,
            staff = Staff.Can(source, Action.Reports) or nil,
            character = characterOf(source),
        }
    end

    return list
end

---Choices for the panel forms: accounts, jobs, gangs, items and groups that exist on this server.
---@return table
function Panel.Catalog()
    local catalog = {
        accounts = {}, jobs = {}, gangs = {}, items = {}, groups = {}, needs = {}, locations = {},
        banDurations = Config.Get().banDurations,
    }

    for name, place in pairs(Config.Get().locations) do
        catalog.locations[#catalog.locations + 1] = {
            name = name,
            label = place.label,
        }
    end

    if UgCore.Modules.IsEnabled('needs') then
        local needs = UgCore.Config.Get('needs', 'needs')

        for name, need in pairs(type(needs) == 'table' and needs or {}) do
            catalog.needs[#catalog.needs + 1] = {
                name = name,
                label = need.label or name,
            }
        end
    end

    if UgCore.Modules.IsEnabled('accounts') then
        local accounts = UgCore.Config.Get('accounts', 'accounts')

        for name, account in pairs(type(accounts) == 'table' and accounts or {}) do
            catalog.accounts[#catalog.accounts + 1] = {
                name = name,
                label = account.label or name,
            }
        end
    end

    for _, kind in ipairs({ 'jobs', 'gangs' }) do
        if UgCore.Modules.IsEnabled(kind) then
            for name, definition in pairs(UgCore.Config.Get(kind)) do
                local grades = {}

                for grade, entry in ipairs(definition.grades or {}) do
                    grades[grade] = {
                        grade = grade,
                        label = entry.label or tostring(grade),
                    }
                end

                catalog[kind][#catalog[kind] + 1] = {
                    name = name,
                    label = definition.label or name,
                    grades = grades,
                }
            end
        end
    end

    if UgCore.Modules.IsEnabled('items') then
        for name, item in pairs(UgCore.Items.GetAll()) do
            catalog.items[#catalog.items + 1] = {
                name = name,
                label = item.label,
            }
        end
    end

    for name, definition in pairs(UgCore.Config.Get('permissions', 'groups')) do
        catalog.groups[#catalog.groups + 1] = {
            name = name,
            label = definition.label,
            weight = definition.weight,
        }
    end

    for _, list in pairs(catalog) do
        if type(list) == 'table' and type(list[1]) == 'table' and list[1].name then
            table.sort(list, function(a, b)
                return a.name < b.name
            end)
        end
    end

    return catalog
end

---Everything the panel shows about one player.
---@param target integer
---@return table?
function Panel.Inspect(target)
    local player = UgCore.Players.Get(target)

    if not player then
        return nil
    end

    local details = {
        id = target,
        name = UgAdmin.Internal.NameOf(target),
        characterId = player.characterId,
        identifiers = {},
        groups = UgCore.Permissions.GetGroups(target),
        state = UgCore.Players.GetDeathState(target),
        score = UgCore.Guard.GetScore(target),
        back = UgAdmin.Internal.World.GetBack(target) ~= nil,
        armor = 0,
        jail = Sanctions.Remaining(target, Sanction.Jail),
        mute = Sanctions.Remaining(target, Sanction.Mute),
    }

    local ped = GetPlayerPed(tostring(target))

    if ped and ped ~= 0 then
        details.armor = GetPedArmour(ped) or 0
    end

    local identifier = UgAdmin.Internal.IdentifierOf(target)

    details.history = Audit.ForTarget(identifier)
    details.notes = Notes.For(identifier)

    -- IP addresses never leave the server.
    for _, identifier in ipairs(UgCore.Identity.GetIdentifiers(target)) do
        if not identifier:find('^ip:') then
            details.identifiers[#details.identifiers + 1] = identifier
        end
    end

    if player.characterId then
        if UgCore.Modules.IsEnabled('accounts') then
            details.accounts = UgCore.Accounts.GetAll(target)
        end

        if UgCore.Modules.IsEnabled('inventory') then
            local items = {}

            for _, slot in ipairs(UgCore.Inventory.GetItems(target)) do
                items[#items + 1] = {
                    name = slot.name,
                    count = slot.count,
                    slot = slot.slot,
                }
            end

            details.items = items
        end

        if UgCore.Modules.IsEnabled('needs') then
            details.needs = UgCore.Needs.GetAll(target)
        end

        details.job = jobOf(target, UgCore.Enums.StateBags.Job)
        details.gang = jobOf(target, UgCore.Enums.StateBags.Gang)
    end

    return details
end

---@param source integer
---@return boolean
local function canPanel(source)
    return Staff.Can(source, Action.Panel)
end

---Registers the callbacks. Runs once after a clean boot.
function Panel.Register()
    UgCore.Callback.Register(Callbacks.Run, {
        schema = Schema.Define({ Actions.ActionRule, Schema.Optional(TARGET), Schema.Optional(Actions.ArgsRule) }),
        rate = {
            max = 6,
            per = 3000,
        },
        requirePlayer = true,
    }, function(source, action, target, args)
        local ok, errorCode = Actions.Run(source, action, target, args)

        return {
            ok = ok,
            error = errorCode,
        }
    end)

    UgCore.Callback.Register(Callbacks.Snapshot, {
        schema = Schema.Define({}),
        rate = {
            max = 4,
            per = 4000,
        },
        requirePlayer = true,
    }, function(source)
        if not canPanel(source) then
            return nil
        end

        local reports = Staff.Can(source, Action.Reports) and Reports.List() or {}

        return {
            players = Panel.Players(),
            reports = reports,
            catalog = Panel.Catalog(),
            self = source,
        }
    end)

    UgCore.Callback.Register(Callbacks.Inspect, {
        schema = Schema.Define({ TARGET }),
        rate = {
            max = 6,
            per = 3000,
        },
        requirePlayer = true,
    }, function(source, target)
        return canPanel(source) and Panel.Inspect(target) or nil
    end)

    UgCore.Callback.Register(Callbacks.Logs, {
        schema = Schema.Define({
            Schema.Optional(Schema.String({
                max = 64,
            })),
        }),
        rate = {
            max = 3,
            per = 3000,
        },
        requirePlayer = true,
    }, function(source, search)
        return canPanel(source) and Audit.Find(search) or nil
    end)

    UgCore.Callback.Register(Callbacks.SpectateStep, {
        schema = Schema.Define({ Schema.Enum({ -1, 1 }) }),
        rate = {
            max = 4,
            per = 2000,
        },
        requirePlayer = true,
    }, function(source, direction)
        local ok, errorCode = Spectate.Step(source, direction)

        return {
            ok = ok,
            error = errorCode,
        }
    end)

    UgCore.Callback.Register(Callbacks.StopSpectate, {
        schema = Schema.Define({}),
        rate = {
            max = 2,
            per = 2000,
        },
        requirePlayer = true,
    }, function(source)
        return {
            ok = Spectate.Stop(source),
        }
    end)

    UgCore.Callback.Register(Callbacks.Report, {
        schema = Schema.Define({
            MESSAGE,
            Schema.Optional(Schema.Enum(UgAdmin.Rules.Sorted(UgAdmin.Enums.ReportCategory))),
            Schema.Optional(TARGET),
        }),
        rate = {
            max = 1,
            per = 5000,
        },
        requirePlayer = true,
    }, function(source, message, category, accused)
        local ok, errorCode, told = Reports.Open(source, message, category, accused)

        return {
            ok = ok,
            error = errorCode,
            told = told,
        }
    end)

    UgCore.Callback.Register(Callbacks.ReportReply, {
        schema = Schema.Define({ MESSAGE }),
        rate = {
            max = 4,
            per = 6000,
        },
        requirePlayer = true,
    }, function(source, text)
        local ok, errorCode = Reports.Reply(source, text)

        return {
            ok = ok,
            error = errorCode,
        }
    end)

    UgCore.Callback.Register(Callbacks.ReportCancel, {
        schema = Schema.Define({}),
        rate = {
            max = 1,
            per = 3000,
        },
        requirePlayer = true,
    }, function(source)
        local ok, errorCode = Reports.Cancel(source)

        return {
            ok = ok,
            error = errorCode,
        }
    end)

    UgCore.Callback.Register(Callbacks.ReportRate, {
        schema = Schema.Define({
            Schema.Integer({
                min = 1,
                max = 5,
            }),
        }),
        rate = {
            max = 1,
            per = 3000,
        },
        requirePlayer = true,
    }, function(source, rating)
        local ok, errorCode = Reports.Rate(source, rating)

        return {
            ok = ok,
            error = errorCode,
        }
    end)
end
