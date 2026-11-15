--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Jail and mute. A sanction lasts a number of minutes that count down while the player is online, so logging out
-- never serves it. What is left is saved in `ug_admin_sanctions` on drop and every minute, and restored when the
-- player loads again. A jailed player who leaves the jail radius is brought back.

---@class UgAdmin.Internal.Sanctions
local Sanctions = {}
UgAdmin.Internal.Sanctions = Sanctions

---@class UgAdminSanctionEntry
---@field identifier string
---@field endsAt integer Unix seconds
---@field reason string
---@field by string identifier of the staff member

local Config = UgAdmin.Internal.Config
local Notify = UgAdmin.Internal.Notify
local World = UgAdmin.Internal.World
local Kind = UgAdmin.Enums.Sanction
local Logger = UgCore.Logger
local NotifyType = UgLib.Enums.NotifyType

local TICK_MS = 1000
-- Ticks between two saves of every running sanction.
local SAVE_TICKS = 60
local MAX_REASON = 200

local CREATE = [[
CREATE TABLE IF NOT EXISTS `ug_admin_sanctions` (
    `identifier` VARCHAR(64) NOT NULL,
    `kind` VARCHAR(8) NOT NULL,
    `remaining` INT UNSIGNED NOT NULL,
    `reason` VARCHAR(200) NOT NULL,
    `by` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`identifier`, `kind`)
)]]

local UPSERT = 'INSERT INTO `ug_admin_sanctions` (`identifier`, `kind`, `remaining`, `reason`, `by`) VALUES (?, ?, ?, ?, ?) '
    .. 'ON DUPLICATE KEY UPDATE `remaining` = VALUES(`remaining`), `reason` = VALUES(`reason`), `by` = VALUES(`by`)'
local DELETE = 'DELETE FROM `ug_admin_sanctions` WHERE `identifier` = ? AND `kind` = ?'
local SELECT = 'SELECT `kind`, `remaining`, `reason`, `by` FROM `ug_admin_sanctions` WHERE `identifier` = ?'

---@type table<integer, table<UgAdminSanction, UgAdminSanctionEntry>>
local active = {}
local ready = false
local ticks = 0

local KINDS = {}

for _, kind in pairs(Kind) do
    KINDS[kind] = true
end

---@param entry UgAdminSanctionEntry
---@return integer seconds
local function remainingOf(entry)
    return math.max(0, entry.endsAt - os.time())
end

---@param seconds integer
---@return integer
local function minutesOf(seconds)
    return math.max(1, math.ceil(seconds / 60))
end

---@param what string
---@param sql string
---@param params any[]
local function write(what, sql, params)
    if not ready then
        return
    end

    CreateThread(function()
        UgAdmin.Internal.Try('sanctions ' .. what, function()
            return MySQL.query.await(sql, params)
        end)
    end)
end

---@param kind UgAdminSanction
---@param entry UgAdminSanctionEntry
local function save(kind, entry)
    write('save', UPSERT, { entry.identifier, kind, remainingOf(entry), entry.reason, entry.by })
end

---Creates the table. MUST run in a thread, after ug-core is ready.
---@return boolean ok
function Sanctions.Init()
    ready = UgAdmin.Internal.Try('sanctions create table', function()
        return MySQL.query.await(CREATE)
    end)

    return ready
end

---Seconds left of a sanction. nil when the player is not under it.
---@param source integer
---@param kind UgAdminSanction
---@return integer?
function Sanctions.Remaining(source, kind)
    local entry = active[source] and active[source][kind]

    return entry and remainingOf(entry) or nil
end

---@param source integer
local function toJail(source)
    World.Teleport(source, Config.Get().jail.coords, true)
end

---Puts a player under a sanction, or sets a new length for the one they serve.
---@param actor integer
---@param target integer
---@param kind UgAdminSanction
---@param minutes integer
---@param reason? string
function Sanctions.Apply(actor, target, kind, minutes, reason)
    ---@type UgAdminSanctionEntry
    local entry = {
        identifier = UgAdmin.Internal.IdentifierOf(target),
        endsAt = os.time() + minutes * 60,
        reason = (reason or ''):sub(1, MAX_REASON),
        by = UgAdmin.Internal.IdentifierOf(actor),
    }

    active[target] = active[target] or {}
    active[target][kind] = entry
    save(kind, entry)

    if kind == Kind.Jail then
        toJail(target)
    end

    Notify.Send(target, kind .. '.start', {
        minutes = minutes,
        reason = entry.reason ~= '' and entry.reason or '—',
    }, NotifyType.Warning)
end

---Ends a sanction early or on time. A released prisoner is taken out of the jail.
---@param target integer
---@param kind UgAdminSanction
---@return boolean lifted false when the player was not under it
function Sanctions.Lift(target, kind)
    local entry = active[target] and active[target][kind]

    if not entry then
        return false
    end

    active[target][kind] = nil

    if not next(active[target]) then
        active[target] = nil
    end

    write('delete', DELETE, { entry.identifier, kind })

    if kind == Kind.Jail then
        World.Teleport(target, Config.Get().jail.release, true)
    end

    Notify.Send(target, kind .. '.end', nil, NotifyType.Success)

    return true
end

---Restores the sanctions a player left with. MUST run in a thread.
---@param source integer
function Sanctions.Load(source)
    if not ready then
        return
    end

    local identifier = UgAdmin.Internal.IdentifierOf(source)
    local ok, rows = UgAdmin.Internal.Try('sanctions load', function()
        return MySQL.query.await(SELECT, { identifier })
    end)

    if not ok or type(rows) ~= 'table' then
        return
    end

    for _, row in ipairs(rows) do
        local kind, remaining = row.kind, math.tointeger(row.remaining)

        -- A sanction already running, such as after a character switch, keeps its own clock.
        local running = active[source] and active[source][kind]

        if KINDS[kind] and remaining and remaining > 0 and not running then
            active[source] = active[source] or {}
            active[source][kind] = {
                identifier = identifier,
                endsAt = os.time() + remaining,
                reason = tostring(row.reason or ''),
                by = tostring(row.by or ''),
            }

            if kind == Kind.Jail then
                toJail(source)
            end

            Notify.Send(source, kind .. '.start', {
                minutes = minutesOf(remaining),
                reason = row.reason ~= '' and tostring(row.reason) or '—',
            }, NotifyType.Warning)
        end
    end
end

---Players under any sanction, sorted.
---@return integer[]
local function sources()
    local list = {}

    for source in pairs(active) do
        list[#list + 1] = source
    end

    table.sort(list)

    return list
end

---Ends sanctions that ran out and brings escaped prisoners back. Saves everything every minute.
function Sanctions.Tick()
    local jail = Config.Get().jail

    ticks = ticks + 1

    for _, source in ipairs(sources()) do
        for _, kind in ipairs({ Kind.Jail, Kind.Mute }) do
            local entry = active[source] and active[source][kind]

            if entry and remainingOf(entry) == 0 then
                Sanctions.Lift(source, kind)
            elseif entry and kind == Kind.Jail then
                local coords = World.CoordsOf(source)

                if coords and #(coords - jail.coords) > jail.radius then
                    toJail(source)
                    Notify.Send(source, 'jail.escape', {
                        minutes = minutesOf(remainingOf(entry)),
                    }, NotifyType.Error)
                end
            end

            if entry and active[source] and active[source][kind] and ticks % SAVE_TICKS == 0 then
                save(kind, entry)
            end
        end
    end
end

---Loads the sanctions of everyone online and starts the clock. Runs once after a clean boot.
function Sanctions.Start()
    for _, player in ipairs(UgCore.Players.GetAll()) do
        Sanctions.Load(player.source)
    end

    CreateThread(function()
        while true do
            Wait(TICK_MS)

            local ok, message = pcall(Sanctions.Tick)

            if not ok then
                Logger.Error('Sanctions: tick failed: %s', tostring(message))
            end
        end
    end)
end

AddEventHandler('playerDropped', function()
    local dropped = math.tointeger(tonumber(source))
    local entries = dropped and active[dropped]

    if not dropped or not entries then
        return
    end

    for kind, entry in pairs(entries) do
        save(kind, entry)
    end

    active[dropped] = nil
end)

-- The cfx chat resource raises chatMessage for every message. A muted player's message is cancelled.
AddEventHandler('chatMessage', function(author)
    local muted = math.tointeger(tonumber(author))
    local remaining = muted and Sanctions.Remaining(muted, Kind.Mute)

    if remaining then
        CancelEvent()
        Notify.Send(muted --[[@as integer]], 'mute.active', {
            minutes = minutesOf(remaining),
        }, NotifyType.Error)
    end
end)
