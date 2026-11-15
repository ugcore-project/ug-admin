--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Private staff notes about a player, kept by identifier in `ug_admin_notes`. Players never see them.

---@class UgAdmin.Internal.Notes
local Notes = {}
UgAdmin.Internal.Notes = Notes

---@class UgAdminNote
---@field id integer
---@field author string identifier
---@field authorName string
---@field text string
---@field at integer Unix seconds

local Errors = UgCore.Enums.Errors

-- Notes shown per player, newest first.
local PAGE = 30

local CREATE = [[
CREATE TABLE IF NOT EXISTS `ug_admin_notes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `target` VARCHAR(64) NOT NULL,
    `author` VARCHAR(64) NOT NULL,
    `author_name` VARCHAR(64) NOT NULL,
    `text` VARCHAR(256) NOT NULL,
    `created_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `ug_admin_notes_target` (`target`)
)]]

local INSERT = 'INSERT INTO `ug_admin_notes` (`target`, `author`, `author_name`, `text`, `created_at`) VALUES (?, ?, ?, ?, ?)'
local DELETE = 'DELETE FROM `ug_admin_notes` WHERE `id` = ?'
local SELECT = 'SELECT `id`, `author`, `author_name`, `text`, `created_at` FROM `ug_admin_notes` WHERE `target` = ? '
    .. ('ORDER BY `id` DESC LIMIT %d'):format(PAGE)

local ready = false

---Creates the table. MUST run in a thread, after ug-core is ready.
---@return boolean ok
function Notes.Init()
    ready = UgAdmin.Internal.Try('notes create table', function()
        return MySQL.query.await(CREATE)
    end)

    return ready
end

---Adds a note about a player. MUST run in a thread.
---@param actor integer
---@param target integer
---@param text string validated, 1 to 256 characters
---@return boolean ok
---@return UgErrorCode? errorCode
function Notes.Add(actor, target, text)
    if not ready then
        return false, Errors.InternalError
    end

    local ok, id = UgAdmin.Internal.Try('notes insert', function()
        return MySQL.insert.await(INSERT, {
            UgAdmin.Internal.IdentifierOf(target),
            UgAdmin.Internal.IdentifierOf(actor),
            UgAdmin.Internal.NameOf(actor),
            (text:gsub('%c', ' ')),
            os.time(),
        })
    end)

    if not ok or not id then
        return false, Errors.InternalError
    end

    return true, nil
end

---Deletes a note. MUST run in a thread.
---@param id integer
---@return boolean deleted false when no note has that id
function Notes.Delete(id)
    if not ready then
        return false
    end

    local ok, affected = UgAdmin.Internal.Try('notes delete', function()
        return MySQL.update.await(DELETE, { id })
    end)

    return ok and type(affected) == 'number' and affected > 0
end

---Newest notes about a player, at most 30. Empty when the database is unavailable. MUST run in a thread.
---@param identifier string
---@return UgAdminNote[]
function Notes.For(identifier)
    if not ready then
        return {}
    end

    local ok, rows = UgAdmin.Internal.Try('notes find', function()
        return MySQL.query.await(SELECT, { identifier })
    end)

    local list = {}

    for index, row in ipairs(ok and type(rows) == 'table' and rows or {}) do
        list[index] = {
            id = math.tointeger(row.id) or 0,
            author = tostring(row.author),
            authorName = tostring(row.author_name),
            text = tostring(row.text),
            at = math.tointeger(row.created_at) or 0,
        }
    end

    return list
end
