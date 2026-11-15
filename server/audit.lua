--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Audit log: every staff action that succeeded, in `ug_admin_log`, the server console and an optional Discord
-- webhook. Nothing else calls MySQL. Writes never block an action: a failed write is logged and the action stands.

---@class UgAdmin.Internal.Audit
local Audit = {}
UgAdmin.Internal.Audit = Audit

---@class UgAdminLogEntry
---@field id? integer
---@field actor string identifier, `console` for the server console
---@field actorName string
---@field action UgAdminAction
---@field target? string identifier of the target player
---@field targetName? string
---@field detail string
---@field at integer Unix seconds

local Logger = UgCore.Logger

local MAX_DETAIL = 255
local MAX_SEARCH = 64
local PAGE = 100
-- Entries shown in the history of one player.
local HISTORY = 30
-- Recent entries kept in memory for the panel, newest last.
local RECENT = 200
local WEBHOOK_CONVAR = 'ug-admin:Webhook'
local WEBHOOK_PATTERN = '^https://discord%.com/api/webhooks/%d+/[%w_%-]+$'
local EMBED_COLOR = 0x7C5CFF

local CREATE = [[
CREATE TABLE IF NOT EXISTS `ug_admin_log` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `actor` VARCHAR(64) NOT NULL,
    `actor_name` VARCHAR(64) NOT NULL,
    `action` VARCHAR(32) NOT NULL,
    `target` VARCHAR(64) NULL,
    `target_name` VARCHAR(64) NULL,
    `detail` VARCHAR(255) NOT NULL,
    `created_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `ug_admin_log_created` (`created_at`),
    INDEX `ug_admin_log_target` (`target`)
)]]

local INSERT = 'INSERT INTO `ug_admin_log` (`actor`, `actor_name`, `action`, `target`, `target_name`, `detail`, `created_at`) '
    .. 'VALUES (?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'), ?, ?)'

local SELECT = 'SELECT `id`, `actor`, `actor_name`, `action`, `target`, `target_name`, `detail`, `created_at` FROM `ug_admin_log`'

---@type UgAdminLogEntry[]
local recent = {}
local ready = false

---@param fn fun(): any
---@param what string
---@return boolean ok
---@return any result
local function try(fn, what)
    return UgAdmin.Internal.Try('audit ' .. what, fn)
end

---Creates the table. MUST run in a thread, after ug-core is ready.
---@return boolean ok
function Audit.Init()
    ready = try(function()
        return MySQL.query.await(CREATE)
    end, 'create table')

    return ready
end

---@param entry UgAdminLogEntry
local function toDiscord(entry)
    local url = GetConvar(WEBHOOK_CONVAR, '')

    if url == '' then
        return
    end

    if not url:find(WEBHOOK_PATTERN) then
        Logger.Warn('Audit: %s is not a Discord webhook URL. Nothing is sent.', WEBHOOK_CONVAR)

        return
    end

    local fields = {
        {
            name = 'Staff',
            value = ('%s\n`%s`'):format(entry.actorName, entry.actor),
            inline = true,
        },
    }

    if entry.target then
        fields[#fields + 1] = {
            name = 'Target',
            value = ('%s\n`%s`'):format(entry.targetName or '?', entry.target),
            inline = true,
        }
    end

    local body = json.encode({
        -- Names are player input: never let them ping anyone.
        allowed_mentions = {
            parse = {},
        },
        embeds = {
            {
                title = '/' .. entry.action,
                description = entry.detail ~= '' and entry.detail or nil,
                color = EMBED_COLOR,
                fields = fields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', entry.at),
            },
        },
    })

    PerformHttpRequest(url, function(status)
        if status < 200 or status >= 300 then
            Logger.Warn('Audit: Discord answered %d.', status)
        end
    end, 'POST', body, {
        ['Content-Type'] = 'application/json',
    })
end

---Records a successful action. The detail is cut to 255 characters.
---@param actor integer source, 0 for the console
---@param action UgAdminAction
---@param target? integer
---@param detail? string
---@return UgAdminLogEntry
function Audit.Record(actor, action, target, detail)
    detail = tostring(detail or ''):gsub('%c', ' ')

    ---@type UgAdminLogEntry
    local entry = {
        actor = UgAdmin.Internal.IdentifierOf(actor),
        actorName = UgAdmin.Internal.NameOf(actor),
        action = action,
        target = target and UgAdmin.Internal.IdentifierOf(target) or nil,
        targetName = target and UgAdmin.Internal.NameOf(target) or nil,
        detail = #detail > MAX_DETAIL and detail:sub(1, MAX_DETAIL) or detail,
        at = os.time(),
    }

    recent[#recent + 1] = entry

    if #recent > RECENT then
        table.remove(recent, 1)
    end

    Logger.Info('%s /%s%s%s', entry.actorName, action, entry.targetName and (' -> ' .. entry.targetName) or '', entry.detail ~= '' and (': ' .. entry.detail) or '')

    if ready then
        CreateThread(function()
            try(function()
                return MySQL.insert.await(INSERT, {
                    entry.actor, entry.actorName, action, entry.target or '', entry.targetName or '', entry.detail, entry.at,
                })
            end, 'insert')
        end)
    end

    toDiscord(entry)
    UgCore.Events.Emit(UgAdmin.Enums.Events.Action, entry)

    return entry
end

---@param row table
---@return UgAdminLogEntry
local function fromRow(row)
    return {
        id = math.tointeger(row.id),
        actor = tostring(row.actor),
        actorName = tostring(row.actor_name),
        action = tostring(row.action),
        target = row.target and tostring(row.target) or nil,
        targetName = row.target_name and tostring(row.target_name) or nil,
        detail = tostring(row.detail),
        at = math.tointeger(row.created_at) or 0,
    }
end

---@param rows any
---@return UgAdminLogEntry[]?
local function fromRows(rows)
    if type(rows) ~= 'table' then
        return nil
    end

    local list = {}

    for index, row in ipairs(rows) do
        list[index] = fromRow(row)
    end

    return list
end

---Newest actions taken on one player, at most 30. Falls back to this session's entries when the database is
---unavailable. MUST run in a thread.
---@param identifier string
---@return UgAdminLogEntry[]
function Audit.ForTarget(identifier)
    if ready then
        local ok, rows = try(function()
            return MySQL.query.await(SELECT .. (' WHERE `target` = ? ORDER BY `id` DESC LIMIT %d'):format(HISTORY), {
                identifier,
            })
        end, 'history')
        local list = ok and fromRows(rows)

        if list then
            return list
        end
    end

    local list = {}

    for index = #recent, 1, -1 do
        if recent[index].target == identifier then
            list[#list + 1] = recent[index]

            if #list >= HISTORY then
                break
            end
        end
    end

    return list
end

---Newest entries first, at most 100. `search` matches staff, target names, identifiers and details.
---Falls back to this session's entries when the database is unavailable. MUST run in a thread.
---@param search? string
---@return UgAdminLogEntry[]
function Audit.Find(search)
    search = search and search:sub(1, MAX_SEARCH) or ''

    if ready then
        local sql, params = SELECT, {}

        if search ~= '' then
            local like = '%' .. search:gsub('[\\%%_]', '\\%0') .. '%'

            sql = sql .. ' WHERE `actor_name` LIKE ? OR `target_name` LIKE ? OR `actor` LIKE ? OR `target` LIKE ? OR `detail` LIKE ?'
            params = { like, like, like, like, like }
        end

        local ok, rows = try(function()
            return MySQL.query.await(sql .. (' ORDER BY `id` DESC LIMIT %d'):format(PAGE), params)
        end, 'find')

        local list = ok and fromRows(rows)

        if list then
            return list
        end
    end

    local needle, list = search:lower(), {}

    for index = #recent, 1, -1 do
        local entry = recent[index]
        local haystack = table.concat({
            entry.actorName,
            entry.targetName or '',
            entry.actor,
            entry.target or '',
            entry.detail,
        }, '\n'):lower()

        if needle == '' or haystack:find(needle, 1, true) then
            list[#list + 1] = entry

            if #list >= PAGE then
                break
            end
        end
    end

    return list
end
