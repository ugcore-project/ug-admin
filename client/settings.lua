--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Panel settings of this staff member: quick bar order and visibility, the tab the panel opens on, confirmations
-- and quick replies. They live in client KVP on the staff member's PC. The page is untrusted, and so is what KVP
-- holds: both go through the same schema.

---@class UgAdmin.Internal.Settings
local Settings = {}
UgAdmin.Internal.Settings = Settings

local KVP = 'ug-admin:Settings'

---The saved settings, or an empty table when none are saved or they no longer pass the schema.
---@return table
function Settings.Get()
    local raw = GetResourceKvpString(KVP)

    if type(raw) ~= 'string' or raw == '' then
        return {}
    end

    local decoded, value = pcall(json.decode, raw)

    if not decoded or type(value) ~= 'table' then
        return {}
    end

    local ok, checked = UgCore.Schema.Check(UgAdmin.Rules.Settings, value)

    return ok and checked or {}
end

---@param value table checked by `UgAdmin.Rules.Settings`
function Settings.Save(value)
    SetResourceKvp(KVP, json.encode(value))
end

UgAdmin.Internal.Nui.On(UgAdmin.Enums.NuiCallback.Settings, Settings.Save)
