--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Drone noclip. The camera rises off the gameplay camera, keeping where the staff member looks, and flies free with
-- smoothed acceleration; the hidden ped (or the vehicle it drives) rides along, so the world keeps streaming around
-- the camera. The crosshair targets what it points at: model, network id, plate and owner, with keys to land there,
-- delete it, freeze a player or board a vehicle. Leaving dives the camera back down onto the ped at the landing spot.
-- The server owns the mode: this file only starts and stops when the `ug-admin:Mode` statebag says so.

---@class UgAdmin.Internal.Noclip
local Noclip = {}
UgAdmin.Internal.Noclip = Noclip

local Camera = UgAdmin.Internal.Camera
local Nui = UgAdmin.Internal.Nui
local Action = UgAdmin.Enums.Action
local NuiAction = UgAdmin.Enums.NuiAction
local TargetKind = UgAdmin.Enums.TargetKind

local BLEND_MS = 250
local LIFT_RISE = 1.2
local DIVE_BACK = 3.0
local DIVE_HEIGHT = 1.6
local DIVE_MIN_PITCH = -40.0
local DIVE_MAX_PITCH = 15.0
local KICK_SPEED = 80.0
local FOV_SMOOTHING = 6.0
local SPEED_STEP = 1.2
-- The owner's `noclip` config, read on each take-off. These are the defaults until then.
local tuning = {
    fov = 60.0, fovKick = 8.0, lookSpeed = 7.5, smoothing = 10.0, boost = 2.0, slow = 0.5, liftDuration = 350,
    diveDuration = 400, inspect = true, outline = true, outlineColor = { 124, 92, 255, 255 }, marker = true,
}
local INSPECT_RANGE = 400.0
local INSPECT_EVERY = 100
local INSPECT_FLAGS = 511
-- Entity pools searched along the view: the line-of-sight probe misses entities too often.
local POOLS = { 'CVehicle', 'CPed', 'CObject' }
-- Thin props such as poles and signs still get a box this thick, in meters.
local MIN_EXTENT = 0.2
-- No model reaches further than this from its origin, so entities beyond it skip the model lookup.
local MAX_REACH = 40.0
local SEND_EVERY = 100
local GROUND_PROBE = 1000.0

-- Control indices from the Cfx controls reference.
local C = {
    LookX = 1, LookY = 2, Sprint = 21, Jump = 22, Enter = 23, Attack = 24, Duck = 36, Forward = 32, Back = 33,
    Left = 34, Right = 35, Cover = 44, Context = 38, Detonate = 47, Walk = 19, WheelUp = 241, WheelDown = 242,
    Delete = 178, LookBehind = 26, Chat = 245, PushToTalk = 249, Pause = 200, Hud = 74,
}

-- Controls left on while flying: chat, voice and the pause menu.
local KEPT = { C.Chat, C.PushToTalk, C.Pause }

local active = false
local stopping = false
---@type integer?
local cam = nil
---@type integer the ped, or the vehicle it drives
local carried = 0
local coords = vector3(0.0, 0.0, 0.0)
local rotation = vector3(0.0, 0.0, 0.0)
local velocity = vector3(0.0, 0.0, 0.0)
local fov = tuning.fov
---@type number m/s, nil until the first flight reads the config
local speed = nil
local showHud = true
---@type vector3? where to land, chosen with the attack key
local landing = nil
---@type integer? vehicle to board on landing
local boarding = nil

---@class UgAdminInspection
---@field coords? vector3
---@field entity? integer
---@field kind? integer 1 ped, 2 vehicle, 3 object
---@field player? integer server id of a targeted player
---@field target? UgAdminNoclipTarget

---@class UgAdminNoclipTarget
---@field kind UgAdminTargetKind
---@field name? string
---@field plate? string
---@field model integer
---@field netId? integer
---@field owner? integer server id of the owner
---@field player? integer server id

---@type UgAdminInspection
local inspection = {}

---@return boolean
function Noclip.IsActive()
    return active
end

---@param value number
---@param low number
---@param high number
---@return number
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

---Slowest and fastest configured speeds bound the wheel. The second one is the starting speed.
---@param speeds number[]
---@return number low
---@return number high
---@return number start
local function speedRange(speeds)
    local low, high = math.huge, 0

    for _, value in ipairs(speeds) do
        low, high = math.min(low, value), math.max(high, value)
    end

    return low, high, speeds[2] or speeds[1]
end

---The entity that flies: the vehicle when the ped drives one, so stuck vehicles come along.
---@return integer
local function pickCarried()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        return vehicle
    end

    return ped
end

---@param entity integer
---@param hidden boolean
local function ghost(entity, hidden)
    local ped = PlayerPedId()
    -- Staff in invisible mode stay invisible after landing, and keep god mode.
    local pedVisible = not hidden and not UgAdmin.Internal.Modes.Has(UgAdmin.Enums.Mode.Invisible)

    local visible = not hidden

    if entity == ped then
        visible = pedVisible
    end

    SetEntityVisible(entity, visible, false)
    SetEntityCollision(entity, not hidden, not hidden)
    FreezeEntityPosition(entity, hidden or (entity == ped and UgAdmin.Internal.Modes.IsFrozen()))
    SetEntityInvincible(entity, hidden or UgAdmin.Internal.Modes.Has(UgAdmin.Enums.Mode.God))

    if entity ~= ped then
        SetEntityVisible(ped, pedVisible, false)
    end
end

---@param shot UgAdminShot
local function follow(shot)
    SetEntityCoordsNoOffset(carried, shot.coords.x, shot.coords.y, shot.coords.z, false, false, false)
    SetEntityHeading(carried, shot.rotation.z)
end

---Ground under a point, or the point itself over water or the void.
---@param point vector3
---@return vector3
local function groundUnder(point)
    RequestCollisionAtCoord(point.x, point.y, point.z)

    local found, z = GetGroundZFor_3dCoord(point.x, point.y, point.z + 2.0, false)

    if not found then
        found, z = GetGroundZFor_3dCoord(point.x, point.y, GROUND_PROBE, false)
    end

    return found and vector3(point.x, point.y, z) or point
end

---First free seat of a vehicle, driver first.
---@param vehicle integer
---@return integer? seat
local function freeSeat(vehicle)
    for seat = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
        if IsVehicleSeatFree(vehicle, seat) then
            return seat
        end
    end

    return nil
end

---@param entity integer
---@return UgAdminInspection
local function describe(entity)
    local kind = GetEntityType(entity)
    local model = GetEntityModel(entity)
    ---@type UgAdminNoclipTarget
    local target = {
        kind = TargetKind.Object,
        model = model,
    }
    local player = nil

    if kind == 2 then
        local display = GetDisplayNameFromVehicleModel(model)
        local label = GetLabelText(display)

        target.kind, target.name, target.plate = TargetKind.Vehicle, label ~= 'NULL' and label or display, GetVehicleNumberPlateText(entity)
    elseif kind == 1 then
        local index = NetworkGetPlayerIndexFromPed(entity)

        if index ~= -1 then
            player = GetPlayerServerId(index)
            target.kind, target.name, target.player = TargetKind.Player, GetPlayerName(index), player
        else
            target.kind = TargetKind.Ped
        end
    end

    if NetworkGetEntityIsNetworked(entity) then
        local owner = NetworkGetEntityOwner(entity)

        target.netId = NetworkGetNetworkIdFromEntity(entity)
        target.owner = owner ~= -1 and GetPlayerServerId(owner) or nil
    end

    return {
        entity = entity,
        kind = kind,
        player = player,
        target = target,
    }
end

---Whether the crosshair MAY pick an entity. Objects attached to something, such as the weapon in the staff member's
---hands while aiming, are skipped: outlining them crashes the game.
---@param entity? integer
---@return boolean
local function targetable(entity)
    if not entity or entity == 0 or entity == carried or not DoesEntityExist(entity) then
        return false
    end

    local ped = PlayerPedId()

    if entity == ped then
        return false
    end

    local kind = GetEntityType(entity)

    if kind == 0 or (kind == 3 and IsEntityAttached(entity)) then
        return false
    end

    local root = GetEntityAttachedTo(entity)

    return root ~= ped and root ~= carried
end

---Where a ray enters and leaves an entity's model box, in meters along the ray. The box turns with the entity.
---@param entity integer
---@param origin vector3
---@param direction vector3 unit
---@param low vector3
---@param high vector3
---@return number? enter
---@return number? leave
local function boxHit(entity, origin, direction, low, high)
    local position = GetEntityCoords(entity)
    local axes = {
        GetOffsetFromEntityInWorldCoords(entity, 1.0, 0.0, 0.0) - position,
        GetOffsetFromEntityInWorldCoords(entity, 0.0, 1.0, 0.0) - position,
        GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, 1.0) - position,
    }
    local mins, maxs = { low.x, low.y, low.z }, { high.x, high.y, high.z }
    local relative = origin - position
    local enter, leave = 0.0, math.huge

    for index = 1, 3 do
        local axis = axes[index]
        local from = relative.x * axis.x + relative.y * axis.y + relative.z * axis.z
        local step = direction.x * axis.x + direction.y * axis.y + direction.z * axis.z
        local min, max = mins[index], maxs[index]

        if max - min < MIN_EXTENT then
            local middle = (min + max) / 2

            min, max = middle - MIN_EXTENT / 2, middle + MIN_EXTENT / 2
        end

        if math.abs(step) < 1e-6 then
            if from < min or from > max then
                return nil, nil
            end
        else
            local near, far = (min - from) / step, (max - from) / step

            if near > far then
                near, far = far, near
            end

            enter, leave = math.max(enter, near), math.min(leave, far)

            if enter > leave then
                return nil, nil
            end
        end
    end

    return enter, leave
end

---The entity the view ray points at, closer than `limit`. Model boxes overlap: a light pole's box covers the sign
---under its arm. When the ray enters a smaller box before it leaves the nearest one, the smaller entity wins.
---@param origin vector3
---@param direction vector3 unit
---@param limit number meters along the ray
---@return integer? entity
local function entityOnRay(origin, direction, limit)
    local best, bestEnter, bestLeave, bestVolume = nil, limit, limit, math.huge
    local hits = {}

    for _, pool in ipairs(POOLS) do
        for _, entity in ipairs(GetGamePool(pool) or {}) do
            local offset = GetEntityCoords(entity) - origin
            local along = offset.x * direction.x + offset.y * direction.y + offset.z * direction.z

            if along > -MAX_REACH and along < limit + MAX_REACH and #(offset - direction * along) <= MAX_REACH then
                local low, high = GetModelDimensions(GetEntityModel(entity))
                local reach = #vector3(math.max(-low.x, high.x), math.max(-low.y, high.y), math.max(-low.z, high.z)) + MIN_EXTENT

                -- Sphere around the origin first, then the exact box.
                if #(offset - direction * along) <= reach and targetable(entity) then
                    local enter, leave = boxHit(entity, origin, direction, low, high)

                    if enter and enter < limit then
                        local size = high - low

                        hits[#hits + 1] = {
                            entity = entity,
                            enter = enter,
                            leave = leave,
                            volume = math.max(size.x, MIN_EXTENT) * math.max(size.y, MIN_EXTENT) * math.max(size.z, MIN_EXTENT),
                        }
                    end
                end
            end
        end
    end

    for _, hit in ipairs(hits) do
        if hit.enter < bestEnter then
            best, bestEnter, bestLeave, bestVolume = hit.entity, hit.enter, hit.leave, hit.volume
        end
    end

    for _, hit in ipairs(hits) do
        if hit.entity ~= best and hit.enter < bestLeave and hit.volume < bestVolume then
            best, bestLeave, bestVolume = hit.entity, hit.leave, hit.volume
        end
    end

    return best
end

---Updates what the crosshair points at. Runs in its own thread: shape tests take frames.
local function inspect()
    while active do
        local direction = Camera.Forward(rotation)
        local from = coords + direction * 0.5
        local result = UgLib.Raycast.FromCoords(from, coords + direction * INSPECT_RANGE, {
            flags = INSPECT_FLAGS,
            ignore = carried,
        })
        local entity = nil

        -- The probe hits what is really in front. The model boxes only fill in what it misses, such as peds.
        if targetable(result.entity) then
            entity = result.entity
        else
            entity = entityOnRay(coords, direction, result.hit and #(result.coords - coords) + 1.0 or INSPECT_RANGE)
        end

        local found = entity and targetable(entity) and describe(entity) or {}

        found.coords = result.hit and result.coords or nil
        inspection = found

        Wait(INSPECT_EVERY)
    end

    inspection = {}
end

-- Outline variant 0 from the Cfx docs: the default gauss glow. The variant is global, so it is set again for each
-- target in case another resource changed it.
local OUTLINE_GLOW = 0

---@type integer?
local outlined = nil

---Outlines one entity at a time. Called every frame; only a change of target touches the natives.
---@param entity? integer
local function outline(entity)
    -- A target deleted since the last inspection MUST NOT reach the outline natives.
    if entity and not DoesEntityExist(entity) then
        entity = nil
    end

    if outlined == entity then
        return
    end

    if outlined and DoesEntityExist(outlined) then
        SetEntityDrawOutline(outlined, false)
    end

    outlined = entity

    if entity then
        SetEntityDrawOutlineShader(OUTLINE_GLOW)
        local color = tuning.outlineColor

        SetEntityDrawOutlineColor(color[1], color[2], color[3], color[4])
        SetEntityDrawOutline(entity, true)
    end
end

---@return boolean
local function canBoard()
    return inspection.kind == 2 and carried == PlayerPedId() and freeSeat(inspection.entity --[[@as integer]]) ~= nil
end

---Key the staff member bound to noclip, read from the key mapping, or the configured default.
---@param fallback string
---@return string
local function exitKey(fallback)
    local hash = GetHashKey('+' .. GetCurrentResourceName() .. '-noclip') | 0x80000000
    local button = GetControlInstructionalButton(0, hash, true)

    if type(button) == 'string' and button:sub(1, 2) == 't_' then
        return button:sub(3)
    end

    return fallback ~= '' and fallback or '/noclip'
end

---@type string key that leaves noclip, read when a flight starts
local leaveKey = ''
local lastSent, lastKey = 0, ''

---Sends the flight state to the page, which draws the crosshair, the target card and the keys. Sends at once when
---something but the position changes, otherwise at most every SEND_EVERY ms.
---@param settings table
local function hud(settings)
    outline(tuning.outline and inspection.entity or nil)

    if tuning.marker and inspection.coords and not inspection.entity then
        local color = tuning.outlineColor

        DrawMarker(28, inspection.coords.x, inspection.coords.y, inspection.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.12, 0.12, 0.12, color[1], color[2], color[3], 120, false, false, 2, false, nil, nil, false)
    end

    if not Nui.IsReady() then
        return
    end

    local target = inspection.target
    local can = {
        land = inspection.coords ~= nil,
        -- Networked entities are deleted, map props hidden for everyone. Players never.
        delete = target ~= nil and not inspection.player and (target.netId ~= nil or inspection.kind == 3),
        freeze = inspection.player ~= nil,
        board = canBoard(),
    }
    local key = ('%s|%.2f|%d|%s|%s|%s|%s'):format(showHud, speed, inspection.entity or 0, can.land, can.delete, can.freeze, can.board)
    local now = GetGameTimer()

    if key == lastKey and now - lastSent < SEND_EVERY then
        return
    end

    local low, high = speedRange(settings.noclipSpeeds)

    lastKey, lastSent = key, now
    Nui.Send(NuiAction.Noclip, {
        active = true,
        hud = showHud,
        speed = speed,
        minSpeed = low,
        maxSpeed = high,
        leave = leaveKey,
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
        },
        heading = rotation.z,
        target = target,
        can = can,
    })
end

---@param dt number seconds
---@param settings table
local function fly(dt, settings)
    DisableAllControlActions(0)

    for _, control in ipairs(KEPT) do
        EnableControlAction(0, control, true)
    end

    local lookX, lookY = GetDisabledControlNormal(0, C.LookX), GetDisabledControlNormal(0, C.LookY)

    rotation = vector3(clamp(rotation.x - lookY * tuning.lookSpeed, -89.0, 89.0), 0.0, (rotation.z - lookX * tuning.lookSpeed) % 360)

    local low, high = speedRange(settings.noclipSpeeds)

    -- One wheel notch changes speed by 20%, so every speed is reachable without big jumps.
    if IsDisabledControlJustPressed(0, C.WheelUp) then
        speed = clamp(speed * SPEED_STEP, low, high)
    elseif IsDisabledControlJustPressed(0, C.WheelDown) then
        speed = clamp(speed / SPEED_STEP, low, high)
    end

    if IsDisabledControlJustPressed(0, C.Hud) then
        showHud = not showHud
    end

    local forward, right = Camera.Forward(rotation), Camera.Right(rotation)
    local direction = vector3(0.0, 0.0, 0.0)

    if IsDisabledControlPressed(0, C.Forward) then direction = direction + forward end
    if IsDisabledControlPressed(0, C.Back) then direction = direction - forward end
    if IsDisabledControlPressed(0, C.Right) then direction = direction + right end
    if IsDisabledControlPressed(0, C.Left) then direction = direction - right end
    if IsDisabledControlPressed(0, C.Jump) or IsDisabledControlPressed(0, C.Cover) then direction = direction + vector3(0.0, 0.0, 1.0) end
    if IsDisabledControlPressed(0, C.Duck) or IsDisabledControlPressed(0, C.Context) then direction = direction - vector3(0.0, 0.0, 1.0) end

    local wantedSpeed = speed

    if IsDisabledControlPressed(0, C.Sprint) then wantedSpeed = wantedSpeed * tuning.boost end
    if IsDisabledControlPressed(0, C.Walk) then wantedSpeed = wantedSpeed * tuning.slow end

    local length = #direction
    local wanted = length > 0 and direction / length * wantedSpeed or vector3(0.0, 0.0, 0.0)

    -- Exponential smoothing: frame-rate independent ease in and out.
    velocity = velocity + (wanted - velocity) * (1 - math.exp(-tuning.smoothing * dt))
    coords = coords + velocity * dt

    local wantedFov = tuning.fov + math.min(#velocity / KICK_SPEED, 1.0) * tuning.fovKick

    fov = fov + (wantedFov - fov) * (1 - math.exp(-FOV_SMOOTHING * dt))

    Camera.Set(cam --[[@as integer]], {
        coords = coords,
        rotation = rotation,
        fov = fov,
    })
    follow({
        coords = coords,
        rotation = rotation,
        fov = fov,
    })
end

---@param settings table
local function act(settings)
    if IsDisabledControlJustPressed(0, C.Attack) and inspection.coords then
        landing = inspection.coords
        UgAdmin.Internal.Request(Action.Noclip)
    end

    if IsDisabledControlJustPressed(0, C.Enter) and canBoard() then
        boarding = inspection.entity
        UgAdmin.Internal.Request(Action.Noclip)
    end

    local entity = inspection.entity

    if IsDisabledControlJustPressed(0, C.Delete) and entity and not inspection.player and DoesEntityExist(entity) then
        local args, prop = nil, nil

        if NetworkGetEntityIsNetworked(entity) then
            args = {
                netId = NetworkGetNetworkIdFromEntity(entity),
            }
        elseif inspection.kind == 3 then
            local at = GetEntityCoords(entity)

            args = {
                coords = at,
                hash = GetEntityModel(entity),
            }
            prop = {
                x = at.x,
                y = at.y,
                z = at.z,
                hash = args.hash,
            }
            -- Gone at once for the staff member. Everyone else follows when the server lists it.
            UgAdmin.Internal.Props.HideNow(prop)
        end

        if args then
            CreateThread(function()
                local ok = UgAdmin.Internal.Request(Action.DeleteEntity, nil, args)

                if not ok and prop then
                    UgAdmin.Internal.Props.Restore(prop)
                end
            end)
        end
    end

    if IsDisabledControlJustPressed(0, C.Detonate) and inspection.player then
        local target = inspection.player

        CreateThread(function()
            UgAdmin.Internal.Request(Action.Freeze, target)
        end)
    end

    if IsDisabledControlJustPressed(0, C.LookBehind) then
        local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, rotation.z)

        UgLib.Clipboard.Copy(text)
        UgAdmin.Internal.Notify.Show('noclip.copied', {
            coords = text,
        }, UgLib.Enums.NotifyType.Success)
    end

    hud(settings)
end

---Lifts off. Called when the server turns noclip on.
---@param settings table replicated config
function Noclip.Start(settings)
    if active then
        return
    end

    active, stopping, landing, boarding, velocity = true, false, nil, nil, vector3(0.0, 0.0, 0.0)
    tuning = type(settings.noclip) == 'table' and settings.noclip or tuning
    carried = pickCarried()

    leaveKey, lastKey = exitKey(settings.keys and settings.keys.noclip or ''), ''

    if not speed then
        local _, _, start = speedRange(settings.noclipSpeeds)

        speed = start
    end

    -- Rise straight up from the gameplay camera, still looking where the staff member looked.
    local from = Camera.Gameplay()
    local lifted = {
        coords = from.coords + vector3(0.0, 0.0, LIFT_RISE),
        rotation = vector3(clamp(from.rotation.x, -89.0, 89.0), 0.0, from.rotation.z),
        fov = tuning.fov,
    }

    -- Drop an aim or any other task first: a frozen, hidden ped kept aiming while it is moved every frame.
    if carried == PlayerPedId() then
        ClearPedTasksImmediately(carried)
    end

    cam = Camera.Create(from)
    ghost(carried, true)

    CreateThread(function()
        Camera.Fly(cam --[[@as integer]], from, lifted, tuning.liftDuration, Camera.EaseOutCubic)

        coords, rotation, fov = lifted.coords, lifted.rotation, tuning.fov

        if tuning.inspect then
            CreateThread(inspect)
        end

        local last = GetGameTimer()

        while active and not stopping do
            local now = GetGameTimer()

            fly(math.min((now - last) / 1000, 0.1), settings)
            act(settings)
            last = now
            Wait(0)
        end
    end)
end

---Lands. Called when the server turns noclip off. Boards the chosen vehicle, or lands where the staff member aimed,
---or under the camera.
function Noclip.Stop()
    if not active or stopping then
        return
    end

    stopping = true
    outline(nil)
    Nui.Send(NuiAction.Noclip, {
        active = false,
    })

    CreateThread(function()
        local vehicle = boarding and DoesEntityExist(boarding) and boarding or nil
        local spot = vehicle and GetEntityCoords(vehicle) or groundUnder(landing or coords)
        local heading = vehicle and GetEntityHeading(vehicle) or rotation.z
        local entity = carried

        -- Wait for the flight loop to let go of the camera.
        Wait(0)

        SetEntityCoords(entity, spot.x, spot.y, spot.z, false, false, false, false)
        SetEntityHeading(entity, heading)
        ghost(entity, false)

        local seat = vehicle and freeSeat(vehicle)

        if vehicle and seat then
            TaskWarpPedIntoVehicle(entity, vehicle, seat)
        end

        -- Dive: from wherever the camera is to just behind the ped, keeping a pitch close to the flight's.
        local pitch = clamp(rotation.x, DIVE_MIN_PITCH, DIVE_MAX_PITCH)
        local to = {
            coords = spot + Camera.Forward(vector3(0.0, 0.0, heading)) * -DIVE_BACK + vector3(0.0, 0.0, DIVE_HEIGHT),
            rotation = vector3(pitch, 0.0, heading),
            fov = GetGameplayCamFov(),
        }

        Camera.Fly(cam --[[@as integer]], {
            coords = coords,
            rotation = rotation,
            fov = fov,
        }, to, tuning.diveDuration, Camera.EaseInOutCubic)
        SetGameplayCamRelativeHeading(0.0)
        SetGameplayCamRelativePitch(pitch, 1.0)
        Camera.Release(cam --[[@as integer]], BLEND_MS)

        cam, active, stopping, landing, boarding, carried = nil, false, false, nil, nil, 0
        Nui.Send(NuiAction.Noclip, {
            active = false,
        })
    end)
end

---Moves the camera while flying, such as after /goto. Returns false when not flying.
---@param point vector3
---@return boolean
function Noclip.MoveTo(point)
    if not active or stopping then
        return false
    end

    coords, velocity = point + vector3(0.0, 0.0, 2.0), vector3(0.0, 0.0, 0.0)

    return true
end

-- Never leave a hidden, frozen ped behind.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then
        outline(nil)
        ghost(carried, false)

        if cam then
            Camera.Release(cam, 0)
        end
    end
end)

