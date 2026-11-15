--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Applies what the server decided in this player's statebags: staff modes (noclip, vision, god, invisible) and
-- being frozen by staff. The statebags are written by the server only, so a client cannot turn these on itself
-- through ug-admin.

---@class UgAdmin.Internal.Modes
local Modes = {}
UgAdmin.Internal.Modes = Modes

local Mode = UgAdmin.Enums.Mode
local StateBags = UgAdmin.Enums.StateBags

local POLL = 200
-- Movement, attack and vehicle controls blocked while frozen, from the Cfx controls reference.
local FROZEN_CONTROLS = {
    21,
    22,
    23,
    24,
    25,
    30,
    31,
    32,
    33,
    34,
    35,
    44,
    47,
    58,
    59,
    60,
    63,
    64,
    71,
    72,
    75,
    140,
    141,
    142,
    143,
    257,
    263,
    264,
}

---@type table<UgAdminMode, boolean>
local current = {}
local frozen = false
---@type table
local settings = {}

---@param mode UgAdminMode
---@return boolean
function Modes.Has(mode)
    return current[mode] == true
end

---@return boolean
function Modes.IsFrozen()
    return frozen
end

---@param mode UgAdminMode
---@param enabled boolean
local function apply(mode, enabled)
    local ped = PlayerPedId()

    if mode == Mode.Noclip then
        if enabled then
            UgAdmin.Internal.Noclip.Start(settings)
        else
            UgAdmin.Internal.Noclip.Stop()
        end
    elseif mode == Mode.Vision then
        UgAdmin.Internal.Vision.SetEnabled(enabled)
    elseif mode == Mode.God then
        SetPlayerInvincible(PlayerId(), enabled)
        SetEntityInvincible(ped, enabled)
    elseif mode == Mode.Invisible then
        SetEntityVisible(ped, not enabled, false)

        if enabled then
            SetEntityAlpha(ped, settings.invisibleAlpha or 140, false)
        else
            ResetEntityAlpha(ped)
        end
    end
end

---Reads the statebags and applies changes. Exposed for tests.
function Modes.Poll()
    local modes = LocalPlayer.state[StateBags.Mode]

    modes = type(modes) == 'table' and modes or {}

    local changed = false

    for _, mode in pairs(Mode) do
        local enabled = modes[mode] == true

        if enabled ~= (current[mode] == true) then
            current[mode] = enabled or nil
            changed = true
            apply(mode, enabled)
        end
    end

    -- The panel lights up the modes that are on.
    if changed then
        local active = {}

        for mode in pairs(current) do
            active[#active + 1] = mode
        end

        table.sort(active)
        UgAdmin.Internal.Nui.Send(UgAdmin.Enums.NuiAction.Modes, active)
    end

    local nowFrozen = LocalPlayer.state[StateBags.Frozen] == true

    if nowFrozen ~= frozen then
        frozen = nowFrozen

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        FreezeEntityPosition(ped, frozen)

        if vehicle ~= 0 then
            FreezeEntityPosition(vehicle, frozen)
        end

        UgAdmin.Internal.Notify.Show(frozen and 'frozen.on' or 'frozen.off')
    end
end

---Starts watching. Runs once after the config arrived.
---@param replicated table
function Modes.Start(replicated)
    settings = replicated

    CreateThread(function()
        while true do
            Modes.Poll()
            Wait(POLL)
        end
    end)

    -- Per-frame upkeep: god mode and invisibility on a new ped, the local ghost, frozen controls.
    CreateThread(function()
        while true do
            local busy = false

            if current[Mode.God] then
                SetPlayerInvincible(PlayerId(), true)
                busy = true
            end

            if current[Mode.Invisible] and not current[Mode.Noclip] then
                SetEntityLocallyVisible(PlayerPedId())
                busy = true
            end

            if frozen then
                for _, control in ipairs(FROZEN_CONTROLS) do
                    DisableControlAction(0, control, true)
                end

                busy = true
            end

            Wait(busy and 0 or 500)
        end
    end)
end
