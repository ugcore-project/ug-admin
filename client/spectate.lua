--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Spectate with an orbit camera. Starting fades out, hides the ped near the target so OneSync streams their area,
-- then swoops down from the sky into an orbit around them. Mouse orbits, wheel zooms, arrows switch players.
-- A live card shows health, armor, death state, vehicle and speed.

---@class UgAdmin.Internal.Spectate
local Spectate = {}
UgAdmin.Internal.Spectate = Spectate

local Camera = UgAdmin.Internal.Camera
local Callbacks = UgAdmin.Enums.Callbacks

local RESOURCE = GetCurrentResourceName()
local STEP = RESOURCE .. ':' .. Callbacks.SpectateStep
local STOP = RESOURCE .. ':' .. Callbacks.StopSpectate
local DEATH_STATE = UgCore.Enums.StateBags.DeathState
---The owner's `spectate` config, with the defaults before it replicates.
---@return { swoop: boolean, swoopHeight: number, swoopDuration: integer, fade: integer }
local function look()
    local config = GlobalState[UgAdmin.Enums.GlobalState.Config]
    local value = type(config) == 'table' and config.spectate

    return type(value) == 'table' and value or {
        swoop = true,
        swoopHeight = 90.0,
        swoopDuration = 1400,
        fade = 350,
    }
end
local PED_WAIT = 5000
local FOLLOW_EVERY = 400
-- The hidden ped stays below the target: close enough to stream, never in sight.
local HIDE_OFFSET = vector3(0.0, 0.0, -8.0)
local MIN_DISTANCE, MAX_DISTANCE, DEFAULT_DISTANCE = 2.0, 25.0, 6.0
local LOOK_SPEED = 6.0
local FOLLOW_SMOOTHING = 10.0
local FOV = 55.0
local SPEED_TO_KMH = 3.6

local C = {
    LookX = 1,
    LookY = 2,
    WheelUp = 241,
    WheelDown = 242,
    Prev = 174,
    Next = 175,
    Exit = 177,
    Chat = 245,
    PushToTalk = 249,
    Pause = 200,
}
local KEPT = { C.Chat, C.PushToTalk, C.Pause }

local active = false
---@type integer?
local cam = nil
---@type integer?
local targetId = nil
local targetName = ''
local yaw, pitch, distance = 0.0, -15.0, DEFAULT_DISTANCE
local focus = vector3(0.0, 0.0, 0.0)
local switching = false

---@return boolean
function Spectate.IsActive()
    return active
end

---@return integer?
local function targetPed()
    local player = targetId and GetPlayerFromServerId(targetId) or -1

    if player == -1 then
        return nil
    end

    local ped = GetPlayerPed(player)

    return ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

---@param hidden boolean
local function hide(hidden)
    local ped = PlayerPedId()

    SetEntityVisible(ped, not hidden, false)
    SetEntityCollision(ped, not hidden, not hidden)
    FreezeEntityPosition(ped, hidden)
    SetEntityInvincible(ped, hidden or UgAdmin.Internal.Modes.Has(UgAdmin.Enums.Mode.God))
end

---@param center vector3
---@return UgAdminShot
local function orbitShot(center)
    local rotation = vector3(pitch, 0.0, yaw)

    return {
        coords = center - Camera.Forward(rotation) * distance,
        rotation = rotation,
        fov = FOV,
    }
end

---@param ped integer
local function card(ped)
    local lines = {
        ('~p~[%d]~s~ %s'):format(targetId or 0, targetName),
        ('%s %d   %s %d'):format(UgAdmin.Internal.Notify.Text('spectate.health'), math.max(GetEntityHealth(ped) - 100, 0),
            UgAdmin.Internal.Notify.Text('spectate.armor'), GetPedArmour(ped)),
    }

    local state = targetId and Player(targetId).state[DEATH_STATE] or nil

    if state and state ~= UgCore.Enums.DeathState.Alive then
        lines[#lines + 1] = ('~r~%s'):format(state)
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 then
        lines[#lines + 1] = ('%s  %d km/h'):format(GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))),
            math.floor(GetEntitySpeed(vehicle) * SPEED_TO_KMH))
    end

    UgLib.Draw.Text2D(0.015, 0.3, table.concat(lines, '\n'), {
        scale = 0.36,
        outline = true,
    })

    Camera.Buttons({
        {
            control = C.Prev,
            label = UgAdmin.Internal.Notify.Text('spectate.previous'),
        },
        {
            control = C.Next,
            label = UgAdmin.Internal.Notify.Text('spectate.next'),
        },
        {
            control = C.WheelUp,
            label = UgAdmin.Internal.Notify.Text('spectate.zoom'),
        },
        {
            control = C.Exit,
            label = UgAdmin.Internal.Notify.Text('spectate.exit'),
        },
    })
end

---@param direction integer
local function step(direction)
    if switching then
        return
    end

    switching = true

    CreateThread(function()
        UgCore.Callback.Await(STEP, direction)
        switching = false
    end)
end

---@param dt number
local function frame(dt)
    DisableAllControlActions(0)

    for _, control in ipairs(KEPT) do
        EnableControlAction(0, control, true)
    end

    yaw = (yaw - GetDisabledControlNormal(0, C.LookX) * LOOK_SPEED) % 360
    pitch = math.max(-70.0, math.min(30.0, pitch - GetDisabledControlNormal(0, C.LookY) * LOOK_SPEED))

    if IsDisabledControlJustPressed(0, C.WheelUp) then distance = math.max(MIN_DISTANCE, distance - 1.0) end
    if IsDisabledControlJustPressed(0, C.WheelDown) then distance = math.min(MAX_DISTANCE, distance + 1.0) end
    if IsDisabledControlJustPressed(0, C.Prev) then step(-1) end
    if IsDisabledControlJustPressed(0, C.Next) then step(1) end

    if IsDisabledControlJustPressed(0, C.Exit) then
        CreateThread(function()
            UgCore.Callback.Await(STOP)
        end)
    end

    local ped = targetPed()

    if not ped then
        return
    end

    local center = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.6)

    focus = focus + (center - focus) * (1 - math.exp(-FOLLOW_SMOOTHING * dt))
    Camera.Set(cam --[[@as integer]], orbitShot(focus))
    card(ped)
end

---Keeps the hidden ped under the target, so their area keeps streaming.
local function shadow()
    while active do
        local ped = targetPed()

        if ped then
            local at = GetEntityCoords(ped) + HIDE_OFFSET

            SetEntityCoordsNoOffset(PlayerPedId(), at.x, at.y, at.z, false, false, false)
        end

        Wait(FOLLOW_EVERY)
    end
end

---Waits until the target's ped streams in.
---@return integer?
local function awaitPed()
    local deadline = GetGameTimer() + PED_WAIT

    while GetGameTimer() < deadline do
        local ped = targetPed()

        if ped then
            return ped
        end

        Wait(50)
    end

    return nil
end

---Starts watching a player, or switches to another.
---@param id integer server id
---@param coords vector3 where the server last saw them
---@param name string
function Spectate.Start(id, coords, name)
    local first = not active

    targetId, targetName = id, name

    if not first then
        local ped = awaitPed()

        focus = ped and GetEntityCoords(ped) or coords

        return
    end

    active = true
    yaw, pitch, distance = GetGameplayCamRot(2).z, -15.0, DEFAULT_DISTANCE

    CreateThread(function()
        local tuning = look()

        DoScreenFadeOut(tuning.fade)
        Wait(tuning.fade)

        hide(true)

        local at = coords + HIDE_OFFSET

        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        SetEntityCoordsNoOffset(PlayerPedId(), at.x, at.y, at.z, false, false, false)

        local ped = awaitPed()

        focus = (ped and GetEntityCoords(ped) or coords) + vector3(0.0, 0.0, 0.6)

        local landing = orbitShot(focus)

        local sky = {
            coords = focus + vector3(0.0, 0.0, tuning.swoopHeight),
            rotation = vector3(-89.0, 0.0, yaw),
            fov = 40.0,
        }

        cam = Camera.Create(tuning.swoop and sky or landing)
        DoScreenFadeIn(tuning.fade)

        -- Satellite swoop down into the orbit.
        if tuning.swoop then
            Camera.Fly(cam --[[@as integer]], sky, landing, tuning.swoopDuration, Camera.EaseInOutCubic)
        end

        CreateThread(shadow)

        local last = GetGameTimer()

        while active do
            local now = GetGameTimer()

            frame(math.min((now - last) / 1000, 0.1))
            last = now
            Wait(0)
        end
    end)
end

---Stops watching. The server teleports the staff member back.
function Spectate.Stop()
    if not active then
        return
    end

    active = false

    CreateThread(function()
        local fade = look().fade

        DoScreenFadeOut(fade)
        Wait(fade)

        if cam then
            Camera.Release(cam, 0)
            cam = nil
        end

        hide(false)
        targetId = nil
        -- The server's teleport fades back in once the ped is home.
    end)
end

UgCore.Network.Register(UgAdmin.Enums.ClientEvents.Spectate, function(id, coords, name)
    if id == nil then
        Spectate.Stop()

        return
    end

    if math.type(id) == 'integer' and type(coords) == 'vector3' and type(name) == 'string' then
        Spectate.Start(id, coords, name:sub(1, 64))
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE and active then
        if cam then
            Camera.Release(cam, 0)
        end

        hide(false)
        DoScreenFadeIn(0)
    end
end)
