--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Asks the server to run an action. The server decides and answers the staff member itself; this only reports
-- whether it went through.

local RESOURCE = GetCurrentResourceName()
local RUN = RESOURCE .. ':' .. UgAdmin.Enums.Callbacks.Run

---@param action UgAdminAction
---@param target? integer
---@param args? UgAdminArgs
---@return boolean ok
---@return UgErrorCode? errorCode
function UgAdmin.Internal.Request(action, target, args)
    local ok, result, errorCode = UgCore.Callback.Await(RUN, action, target, args)

    if not ok then
        UgAdmin.Internal.Notify.Show('error.' .. tostring(errorCode), nil, UgLib.Enums.NotifyType.Error)

        return false, errorCode
    end

    if type(result) ~= 'table' then
        return false, UgCore.Enums.Errors.InternalError
    end

    return result.ok == true, result.error
end

---True when the server allows this player the action. The server checks again on every request.
---@param action UgAdminAction
---@return boolean
function UgAdmin.Internal.Allowed(action)
    local access = LocalPlayer.state[UgAdmin.Enums.StateBags.Access]

    if type(access) ~= 'table' then
        return false
    end

    for _, name in ipairs(access) do
        if name == action then
            return true
        end
    end

    return false
end
