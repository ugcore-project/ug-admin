--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Small helpers shared by the server scripts.

local MAX_NAME = 64
local CONSOLE = 0
local UNITS = {
    m = 60,
    h = 3600,
    d = 86400,
    w = 604800,
}
local MAX_DURATION = 3650 * 86400

---Seconds of a duration such as `30m`, `12h`, `7d` or `2w`. nil for anything else, `perm` included.
---@param value any
---@return integer?
function UgAdmin.Internal.ParseDuration(value)
    if type(value) ~= 'string' then
        return nil
    end

    local amount, unit = value:match('^(%d+)([mhdw])$')
    local count = math.tointeger(tonumber(amount))

    if not count or count < 1 then
        return nil
    end

    local seconds = count * UNITS[unit]

    return seconds <= MAX_DURATION and seconds or nil
end

---A player name safe for logs, the page and Discord: no control characters, at most 64 characters.
---@param source integer
---@return string
function UgAdmin.Internal.NameOf(source)
    if source == CONSOLE then
        return 'Console'
    end

    local name = GetPlayerName(tostring(source))

    if type(name) ~= 'string' or name == '' then
        return ('#%d'):format(source)
    end

    name = name:gsub('%c', ''):gsub('%^%d', '')

    return #name > MAX_NAME and name:sub(1, MAX_NAME) or name
end

---Primary identifier of a player, `console` for source 0.
---@param source integer
---@return string
function UgAdmin.Internal.IdentifierOf(source)
    if source == CONSOLE then
        return 'console'
    end

    return UgCore.Identity.GetPrimary(source) or ('source:%d'):format(source)
end

---Runs a database call. A failure is logged and never raises. MUST run in a thread.
---@param what string for the log
---@param fn fun(): any
---@return boolean ok
---@return any result
function UgAdmin.Internal.Try(what, fn)
    local ok, result = pcall(fn)

    if not ok then
        UgCore.Logger.Error('Database: %s failed: %s', what, tostring(result))

        return false, nil
    end

    return true, result
end
