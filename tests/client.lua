--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

local H = dofile('tests/helpers.lua')

local StateBags, Mode

---Loads the client. `access` makes the player staff.
---@param access? string[]
---@param overrides? table config values
---@return string[] lines
local function boot(access, overrides)
    H.Reset()
    H.LocalState[ 'ug-admin:Access' ] = access

    local lines = H.LoadClient(overrides)

    StateBags, Mode = UgAdmin.Enums.StateBags, UgAdmin.Enums.Mode

    return lines
end

---Arguments of the last call of a native.
---@param name string
---@return any[]?
local function last(name)
    local calls = H.CallsOf(name)

    return calls[#calls] and calls[#calls].args
end

---@param modes table?
local function setModes(modes)
    H.LocalState[StateBags.Mode] = modes
    UgAdmin.Internal.Modes.Poll()
end

print('client')

H.Test('keys are registered only once the server says the player is staff', function()
    local lines = boot()

    H.ExpectLine(lines, '[ug-admin] Ready.')
    H.Advance(2000)
    H.Equal(#H.Keybinds, 0)

    H.LocalState[StateBags.Access] = { 'admin', 'noclip' }
    H.Advance(1100)

    H.Equal(#H.Keybinds, 3)
    H.Equal(H.Keybinds[1].name, 'noclip')
    H.Equal(H.Keybinds[1].defaultKey, 'F2')
    H.Equal(H.Keybinds[3].defaultKey, nil)
end)

H.Test('a staff key asks the server, and only for actions the player has', function()
    boot({ 'noclip' })
    H.Advance(16)

    H.Keybinds[1].onPressed()
    H.Keybinds[3].onPressed()

    H.Equal(#H.Requests, 1)
    H.Equal(H.Requests[1].name, 'Run')
    H.Equal(H.Requests[1].args[1], 'noclip')
end)

H.Test('notifications from the server are checked before they show', function()
    boot()

    H.NetHandlers.Notify('result.kick', {
        target = 'Bob',
        amount = 5,
    }, 'success')
    H.NetHandlers.Notify('bad key!', {}, 'success')
    H.NetHandlers.Notify('result.kick', {}, 'rainbow')

    H.Equal(#H.Notifications, 2)
    H.Equal(H.Notifications[1].message, 'result.kick(amount=5,target=Bob)')
    H.Equal(H.Notifications[1].type, 'success')
    H.Equal(H.Notifications[2].type, 'info')
end)

H.Test('noclip lifts off when the server turns it on and lands when it turns it off', function()
    boot({ 'noclip' })

    setModes({
        noclip = true,
    })
    H.Assert(UgAdmin.Internal.Noclip.IsActive(), 'noclip did not start')
    H.Equal(last('SetEntityVisible'), { 1, false, false })
    H.Equal(#H.CallsOf('CreateCamWithParams'), 1)

    H.Advance(2000)
    setModes(nil)
    H.Advance(2000)

    H.Assert(not UgAdmin.Internal.Noclip.IsActive(), 'noclip did not stop')
    -- Lands on the ground under the camera, which rose straight up from the gameplay camera.
    H.Equal(last('SetEntityCoords'), { 1, 0.0, 0.0, 30.0, false, false, false, false })
    H.Equal(last('SetEntityVisible'), { 1, true, false })
    H.Equal(last('RenderScriptCams'), { false, true, 250, true, true })
    H.Equal(#H.CallsOf('DestroyCam'), 1)
end)

H.Test('noclip keeps looking where the gameplay camera looked', function()
    boot({ 'noclip' })

    H.NativeReturns.GetGameplayCamRot = function()
        return vector3(-5.0, 0.0, 120.0)
    end

    setModes({
        noclip = true,
    })
    H.Advance(2000)

    local rotation = assert(last('SetCamRot'))

    H.Equal({ rotation[2], rotation[3], rotation[4] }, { -5.0, 0.0, 120.0 })
end)

H.Test('noclip boards the targeted vehicle on landing', function()
    boot({ 'noclip' })

    local pressed = false

    -- The probe misses the vehicle: it is found in the pool, ahead of the camera on the view ray.
    UgLib.Raycast.FromCoords = function()
        return {
            hit = true,
            coords = vector3(0.0, 30.0, 1.2),
        }
    end
    H.NativeReturns.GetGamePool = function(pool)
        return pool == 'CVehicle' and { 50 } or {}
    end
    H.NativeReturns.GetEntityCoords = function(entity)
        return entity == 50 and vector3(0.5, 10.0, 1.0) or vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetModelDimensions = function()
        return vector3(-1.0, -2.0, -0.8), vector3(1.0, 2.0, 0.8)
    end
    H.NativeReturns.GetOffsetFromEntityInWorldCoords = function(entity, x, y, z)
        return (entity == 50 and vector3(0.5, 10.0, 1.0) or vector3(0.0, 0.0, 0.0)) + vector3(x, y, z)
    end
    H.NativeReturns.GetEntityType = 2
    H.NativeReturns.GetEntityModel = 7
    H.NativeReturns.GetVehicleModelNumberOfSeats = 4
    H.NativeReturns.IsVehicleSeatFree = true
    H.NativeReturns.DoesEntityExist = true
    H.NativeReturns.IsDisabledControlJustPressed = function(_, control)
        if control == 23 and not pressed then
            pressed = true

            return true
        end

        return false
    end

    setModes({
        noclip = true,
    })
    H.Advance(2000)
    H.Equal(H.Requests[#H.Requests].args[1], 'noclip')
    -- One glow outline on the target, set once, not every frame.
    H.Equal(#H.CallsOf('SetEntityDrawOutline'), 1)
    H.Equal(last('SetEntityDrawOutline'), { 50, true })
    H.Equal(last('SetEntityDrawOutlineShader'), { 0 })

    setModes(nil)
    H.Advance(2000)

    H.Equal(last('TaskWarpPedIntoVehicle'), { 1, 50, -1 })
    -- Landing clears it.
    H.Equal(last('SetEntityDrawOutline'), { 50, false })
    H.Equal(last('SetEntityDrawOutlineShader'), { 0 })
end)

H.Test('noclip picks the sign under a light pole arm, not the pole whose box covers it', function()
    boot({ 'noclip' })

    -- The probe misses both. The pole stands at y 8 with an arm reaching over y 12; the sign stands at y 12.
    UgLib.Raycast.FromCoords = function()
        return {
            hit = true,
            coords = vector3(0.0, 30.0, 1.2),
        }
    end
    H.NativeReturns.GetGamePool = function(pool)
        return pool == 'CObject' and { 80, 81 } or {}
    end

    local positions = {
        [80] = vector3(-1.0, 8.0, -0.5),
        [81] = vector3(0.0, 12.0, 0.0),
    }

    H.NativeReturns.GetEntityCoords = function(entity)
        return positions[entity] or vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetOffsetFromEntityInWorldCoords = function(entity, x, y, z)
        return (positions[entity] or vector3(0.0, 0.0, 0.0)) + vector3(x, y, z)
    end
    H.NativeReturns.GetEntityModel = function(entity)
        return entity
    end
    H.NativeReturns.GetModelDimensions = function(model)
        if model == 80 then
            return vector3(-0.3, -0.3, 0.0), vector3(1.5, 6.0, 9.0)
        end

        return vector3(-0.4, -0.05, -0.5), vector3(0.4, 0.05, 1.5)
    end
    H.NativeReturns.GetEntityType = 3
    H.NativeReturns.DoesEntityExist = true

    setModes({
        noclip = true,
    })
    H.Advance(2000)

    H.Equal(last('SetEntityDrawOutline'), { 81, true })

    setModes(nil)
    H.Advance(2000)
end)

H.Test('noclip never targets the weapon in the staff member hands', function()
    boot({ 'noclip' })

    -- Aiming when noclip starts: the weapon object sits on the view ray, and the probe hits it too.
    UgLib.Raycast.FromCoords = function()
        return {
            hit = true,
            coords = vector3(0.0, 1.0, 1.2),
            entity = 60,
        }
    end
    H.NativeReturns.GetGamePool = function(pool)
        return pool == 'CObject' and { 60 } or {}
    end
    H.NativeReturns.GetEntityCoords = function(entity)
        return entity == 60 and vector3(0.0, 1.0, 1.0) or vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetModelDimensions = function()
        return vector3(-0.3, -0.3, -0.3), vector3(0.3, 0.3, 0.3)
    end
    H.NativeReturns.GetEntityType = 3
    H.NativeReturns.DoesEntityExist = true
    H.NativeReturns.IsEntityAttached = function(entity)
        return entity == 60
    end
    H.NativeReturns.GetEntityAttachedTo = function(entity)
        return entity == 60 and 1 or 0
    end

    setModes({
        noclip = true,
    })
    H.Advance(2000)

    H.Equal(last('ClearPedTasksImmediately'), { 1 })
    H.Equal(#H.CallsOf('SetEntityDrawOutline'), 0)

    setModes(nil)
    H.Advance(2000)
end)

H.Test('noclip deletes a map prop by its spot and model, and every client hides it', function()
    boot({ 'noclip', 'delentity' })

    local pressed = false

    UgLib.Raycast.FromCoords = function()
        return {
            hit = true,
            coords = vector3(0.0, 10.0, 1.0),
            entity = 70,
        }
    end
    H.NativeReturns.GetGamePool = function(pool)
        return pool == 'CObject' and { 70 } or {}
    end
    H.NativeReturns.GetEntityCoords = function(entity)
        return entity == 70 and vector3(0.0, 10.0, 1.0) or vector3(0.0, 0.0, 0.0)
    end
    H.NativeReturns.GetModelDimensions = function()
        return vector3(-0.5, -0.5, -0.5), vector3(0.5, 0.5, 0.5)
    end
    H.NativeReturns.GetEntityType = 3
    H.NativeReturns.GetEntityModel = 1234
    H.NativeReturns.DoesEntityExist = true
    H.NativeReturns.NetworkGetEntityIsNetworked = false
    H.NativeReturns.GetClosestObjectOfType = 70
    H.NativeReturns.IsDisabledControlJustPressed = function(_, control)
        if control == 178 and not pressed and H.Now > 1000 then
            pressed = true

            return true
        end

        return false
    end
    H.Respond.Run = function()
        return {
            ok = true,
        }
    end

    setModes({
        noclip = true,
    })
    H.Advance(2000)

    local request = H.Requests[#H.Requests]

    H.Equal(request.args[1], 'delentity')
    H.Equal(request.args[3], {
        coords = vector3(0.0, 10.0, 1.0),
        hash = 1234,
    })

    -- Gone for the staff member before the server answers: the model is hidden and the instance deleted.
    H.Equal(last('CreateModelHideExcludingScriptObjects'), { 0.0, 10.0, 1.0, 1.0, 1234, true })
    H.Equal(last('DeleteObject'), { 70 })
    H.Equal(#H.CallsOf('RemoveModelHide'), 0)

    -- The server lists it at once for everyone; the staff member's client does not hide it twice.
    GlobalState:set(UgAdmin.Enums.GlobalState.HiddenProps, {
        version = 1,
        props = {
            {
                x = 0.0,
                y = 10.0,
                z = 1.0,
                hash = 1234,
            },
        },
    }, true)
    H.Equal(#H.CallsOf('CreateModelHideExcludingScriptObjects'), 1)

    GlobalState:set(UgAdmin.Enums.GlobalState.HiddenProps, {
        version = 2,
        props = {},
    }, true)
    H.Equal(last('RemoveModelHide'), { 0.0, 10.0, 1.0, 1.0, 1234, false })

    -- Another client hides it the moment the list changes, with no wait.
    GlobalState:set(UgAdmin.Enums.GlobalState.HiddenProps, {
        version = 3,
        props = {
            {
                x = 5.0,
                y = 5.0,
                z = 1.0,
                hash = 99,
            },
        },
    }, true)
    H.Equal(last('CreateModelHideExcludingScriptObjects'), { 5.0, 5.0, 1.0, 1.0, 99, true })

    setModes(nil)
    H.Advance(2000)
end)

H.Test('noclip sends its state to the page, and clears it on landing', function()
    boot({ 'noclip' })
    H.PostNui('ready', {})

    ---@return table[]
    local function flights()
        local list = {}

        for _, message in ipairs(H.PageMessages()) do
            if message.action == 'noclip' then
                list[#list + 1] = message.payload
            end
        end

        return list
    end

    UgLib.Raycast.FromCoords = function()
        return {
            hit = true,
            coords = vector3(0.0, 30.0, 1.2),
        }
    end

    setModes({
        noclip = true,
    })
    H.Advance(2000)

    local flying = flights()
    local state = flying[#flying]

    H.Assert(state and state.active, 'no flight state reached the page')
    H.Equal(state.speed, 15)
    H.Equal({ state.minSpeed, state.maxSpeed }, { 1.5, 200 })
    H.Equal(state.can, {
        land = true,
        delete = false,
        freeze = false,
        board = false,
    })
    H.Equal(state.target, nil)

    setModes(nil)
    H.Advance(2000)

    flying = flights()
    H.Equal(flying[#flying], {
        active = false,
    })
end)

H.Test('the panel learns which modes are on', function()
    boot({ 'god', 'invisible' })
    H.PostNui('ready', {})

    ---@return table?
    local function lastModes()
        local found = nil

        for _, message in ipairs(H.PageMessages()) do
            if message.action == 'modes' then
                found = message.payload
            end
        end

        return found
    end

    setModes({
        invisible = true,
        god = true,
    })
    H.Equal(lastModes(), { 'god', 'invisible' })

    local sent = #H.PageMessages()

    setModes({
        invisible = true,
        god = true,
    })
    H.Equal(#H.PageMessages(), sent)

    setModes(nil)
    H.Equal(lastModes(), {})
end)

H.Test('staff in invisible mode stay invisible after noclip', function()
    boot({ 'noclip', 'invisible' })

    setModes({
        invisible = true,
    })
    setModes({
        invisible = true,
        noclip = true,
    })
    H.Advance(2000)
    setModes({
        invisible = true,
    })
    H.Advance(2000)

    H.Equal(last('SetEntityVisible'), { 1, false, false })
end)

H.Test('noclip flies with the owner tuning, and a zero lift cuts straight to the flight', function()
    local noclip = H.Defaults().noclip

    noclip.fov, noclip.liftDuration = 90.0, 0
    boot({ 'noclip' }, {
        noclip = noclip,
    })

    setModes({
        noclip = true,
    })
    H.Advance(100)

    H.Equal(last('SetCamFov')[2], 90.0)
end)

H.Test('invisible staff see themselves at the owner alpha', function()
    boot({ 'invisible' }, {
        invisibleAlpha = 50,
    })

    setModes({
        invisible = true,
    })

    H.Equal(last('SetEntityAlpha'), { 1, 50, false })
end)

H.Test('big messages take the owner color, duration and sound, and a kind left out is a notification', function()
    boot(nil, {
        shards = {
            announce = {
                duration = 1000,
                color = 'green',
            },
        },
    })

    H.NetHandlers.Shard('announce', 'Restart in 5')
    H.Advance(10)

    H.Equal(H.CallsOf('ScaleformMovieMethodAddParamPlayerNameString')[1].args[1]:sub(1, 3), '~g~')
    H.Equal(#H.CallsOf('PlaySoundFrontend'), 0)

    H.NetHandlers.Shard('warn', 'Stop that')
    H.Advance(10)

    H.Equal(#H.CallsOf('BeginScaleformMovieMethod'), 1)
end)

H.Test('spectate without the swoop cuts to the orbit with the owner fade', function()
    local spectate = H.Defaults().spectate

    spectate.swoop, spectate.fade = false, 100
    boot({ 'spectate' }, {
        spectate = spectate,
    })

    H.NativeReturns.GetPlayerFromServerId = 3
    H.NativeReturns.GetPlayerPed = 77
    H.NativeReturns.DoesEntityExist = true

    H.NetHandlers.Spectate(4, vector3(50.0, 50.0, 30.0), 'Bob')
    H.Advance(1000)

    H.Assert(UgAdmin.Internal.Spectate.IsActive(), 'spectate did not start')
    H.Equal(last('DoScreenFadeOut'), { 100 })
end)

H.Test('the page gets the owner layout, tabs and theme, merged onto ug-lib', function()
    local layout = H.Defaults().layout

    layout.rail = 'right'
    boot(nil, {
        layout = layout,
        tabs = { 'logs' },
        theme = {
            colors = {
                violet = '10 80% 50%',
            },
        },
    })

    local config = H.LastPage('config')

    H.Equal(config.layout.rail, 'right')
    H.Equal(config.tabs, { 'logs' })
    H.Equal(config.theme.colors.violet, '10 80% 50%')
end)

H.Test('being frozen by staff freezes the ped and tells the player', function()
    boot()

    H.LocalState[StateBags.Frozen] = true
    UgAdmin.Internal.Modes.Poll()

    H.Equal(last('FreezeEntityPosition'), { 1, true })
    H.Equal(H.Notifications[1].message, 'frozen.on')

    H.LocalState[StateBags.Frozen] = nil
    UgAdmin.Internal.Modes.Poll()
    H.Equal(last('FreezeEntityPosition'), { 1, false })
end)

H.Test('a teleport without exact height lands on the ground', function()
    boot()

    H.NetHandlers.Teleport(vector3(10.0, 20.0, 0.0), false)
    H.Advance(1000)

    H.Equal(last('SetEntityCoords'), { 1, 10.0, 20.0, 30.0, false, false, false, false })
    H.Equal(last('DoScreenFadeIn'), { 300 })
end)

H.Test('a teleport while flying moves the camera instead', function()
    boot({ 'noclip' })

    setModes({
        noclip = true,
    })
    H.Advance(2000)

    local before = #H.CallsOf('DoScreenFadeOut')

    H.NetHandlers.Teleport(vector3(10.0, 20.0, 5.0), true)
    H.Equal(#H.CallsOf('DoScreenFadeOut'), before)
end)

H.Test('vehicle types come from the model, unknown models answer nothing', function()
    boot()

    local vehicleType = H.ClientCallbacks.VehicleType

    H.Equal(vehicleType('bad model!'), '')

    H.NativeReturns.IsModelInCdimage = false
    H.Equal(vehicleType('nothing'), '')

    H.NativeReturns.IsModelInCdimage = true
    H.NativeReturns.IsModelAVehicle = true
    H.NativeReturns.IsThisModelAHeli = true
    H.Equal(vehicleType('buzzard'), 'heli')
    H.Equal(vehicleType('Submersible'), 'submarine')

    H.NativeReturns.IsThisModelAHeli = false
    H.Equal(vehicleType('sultan'), 'automobile')
end)

H.Test('the waypoint answers the origin when there is none', function()
    boot()

    H.NativeReturns.DoesBlipExist = false
    H.Equal(H.ClientCallbacks.Waypoint(), vector3(0.0, 0.0, 0.0))

    H.NativeReturns.DoesBlipExist = true
    H.NativeReturns.GetBlipInfoIdCoord = function()
        return vector3(5.0, 6.0, 7.0)
    end
    H.Equal(H.ClientCallbacks.Waypoint(), vector3(5.0, 6.0, 0.0))
end)

H.Test('the panel opens for staff only and releases focus on every way out', function()
    boot()

    UgAdmin.Internal.Panel.Open()
    H.Equal(#H.Requests, 0)

    H.LocalState[StateBags.Access] = { 'admin', 'goto', 'kick' }
    H.Respond.Snapshot = function()
        return {
            players = {
                {
                    id = 4,
                    name = 'Bob',
                },
            },
            reports = {},
            catalog = {},
            self = 1,
        }
    end

    UgAdmin.Internal.Panel.Open()
    H.Equal(last('SetNuiFocus'), { true, true })
    H.Equal(H.LastPage('open').access, { 'admin', 'goto', 'kick' })

    H.Respond.Run = function()
        return {
            ok = true,
        }
    end

    H.Equal(H.PostNui('run', {
        action = 'kick',
        target = 4,
        args = {
            reason = 'afk',
        },
    }), {
        ok = true,
    })
    H.Assert(UgAdmin.Internal.Panel.IsOpen(), 'acting on someone else keeps the panel open')
    H.Equal(H.LastPage('result'), {
        action = 'kick',
        ok = true,
    })

    H.PostNui('run', {
        action = 'goto',
        target = 4,
    })
    H.Assert(not UgAdmin.Internal.Panel.IsOpen(), 'goto closes the panel')
    H.Equal(last('SetNuiFocus'), { false, false })
end)

H.Test('forged page bodies are refused before they reach the server', function()
    boot({ 'admin' })

    H.Equal(H.PostNui('run', {
        action = 'nuke',
        target = 4,
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('run', {
        action = 'kick',
        target = 4,
        args = {
            price = 1,
        },
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('run', {
        action = 'kick',
        target = -1,
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('inspect', {
        id = 'everyone',
    }), {
        ok = false,
    })
    H.Equal(#H.Requests, 0)
end)

H.Test('spectate swoops in, follows the target and comes back', function()
    boot({ 'spectate' })

    H.NativeReturns.GetPlayerFromServerId = 3
    H.NativeReturns.GetPlayerPed = 77
    H.NativeReturns.DoesEntityExist = true

    H.NetHandlers.Spectate(4, vector3(50.0, 50.0, 30.0), 'Bob')
    H.Advance(3000)

    H.Assert(UgAdmin.Internal.Spectate.IsActive(), 'spectate did not start')
    H.Equal(#H.CallsOf('CreateCamWithParams'), 1)
    H.Equal(last('SetEntityCollision'), { 1, false, false })

    H.NetHandlers.Spectate(nil)
    H.Advance(1000)

    H.Assert(not UgAdmin.Internal.Spectate.IsActive(), 'spectate did not stop')
    H.Equal(last('SetEntityVisible'), { 1, true, false })
    H.Equal(#H.CallsOf('DestroyCam'), 1)
end)

H.Test('vision puts every player from the radar on the map, and clears them when off', function()
    boot({ 'vision' })

    H.NetHandlers.Radar({
        {
            id = 4,
            name = 'Bob',
            coords = vector3(1.0, 2.0, 3.0),
            heading = 90.0,
            state = 'Alive',
            staff = false,
            vehicle = false,
        },
    })
    H.Equal(UgAdmin.Internal.Vision.Count(), 0)

    setModes({
        vision = true,
    })
    H.NativeReturns.AddBlipForCoord = 55
    H.NetHandlers.Radar({
        {
            id = 4,
            name = 'Bob',
            coords = vector3(1.0, 2.0, 3.0),
            heading = 90.0,
            state = 'Alive',
            staff = false,
            vehicle = false,
        },
        {
            id = 1,
            name = 'Me',
            coords = vector3(0.0, 0.0, 0.0),
            heading = 0.0,
            state = 'Alive',
            staff = true,
            vehicle = false,
        },
    })
    H.Equal(UgAdmin.Internal.Vision.Count(), 1)

    H.NetHandlers.Radar({
        {
            id = 'x',
        },
    })
    H.Equal(UgAdmin.Internal.Vision.Count(), 1)

    setModes(nil)
    H.Equal(UgAdmin.Internal.Vision.Count(), 0)
    H.Equal(last('RemoveBlip'), { 55 })
end)

H.Test('big messages show only known kinds with valid text', function()
    boot()

    H.NetHandlers.Shard('rainbow', 'hi')
    H.NetHandlers.Shard('announce', '')
    H.Equal(#H.CallsOf('BeginScaleformMovieMethod'), 0)

    H.NetHandlers.Shard('announce', 'Restart in 5')
    H.Equal(last('ScaleformMovieMethodAddParamPlayerNameString'), { 'Restart in 5' })
end)

H.Test('a heal tops up health, and brings back a ped the server never saw die', function()
    boot()

    H.NativeReturns.GetEntityMaxHealth = 200
    H.NativeReturns.IsPedFatallyInjured = false
    H.NetHandlers.Heal()

    H.Equal(#H.CallsOf('NetworkResurrectLocalPlayer'), 0)
    H.Equal(last('SetEntityHealth'), { 1, 200 })

    H.NativeReturns.IsPedFatallyInjured = true
    H.NetHandlers.Heal()

    H.Equal(#H.CallsOf('NetworkResurrectLocalPlayer'), 1)
    H.Equal(last('ClearPedTasks'), { 1 })
end)

H.Test('a prop hidden ahead of the server comes back when the server refuses, and the server list wins', function()
    boot()

    local prop = {
        x = 1.0,
        y = 2.0,
        z = 3.0,
        hash = 4294967295,
    }

    UgAdmin.Internal.Props.HideNow(prop)
    H.Equal(last('CreateModelHideExcludingScriptObjects'), { 1.0, 2.0, 3.0, 1.0, 4294967295, true })

    UgAdmin.Internal.Props.Restore(prop)
    H.Equal(last('RemoveModelHide'), { 1.0, 2.0, 3.0, 1.0, 4294967295, false })

    -- The server keeps hashes signed: the same prop, so it is hidden once and stays.
    UgAdmin.Internal.Props.HideNow(prop)
    GlobalState:set(UgAdmin.Enums.GlobalState.HiddenProps, {
        version = 1,
        props = {
            {
                x = 1.0,
                y = 2.0,
                z = 3.0,
                hash = -1,
            },
        },
    }, true)
    H.Equal(#H.CallsOf('CreateModelHideExcludingScriptObjects'), 2)
    H.Equal(#H.CallsOf('RemoveModelHide'), 1)
end)

H.Test('the report window takes focus, passes the chat along and refuses broken bodies', function()
    boot()

    H.NetHandlers.ReportWindow()
    H.Equal(last('SetNuiFocus'), { true, true })

    local messages = H.PageMessages()

    H.Equal(messages[#messages], {
        action = 'reportWindow',
        payload = {
            open = true,
        },
    })

    H.NetHandlers.MyReport({
        id = 1,
        message = 'help',
        messages = {},
    })
    messages = H.PageMessages()
    H.Equal(messages[#messages].payload.id, 1)

    H.Respond.Report = function()
        return {
            ok = true,
        }
    end
    H.Respond.ReportReply = function()
        return {
            ok = false,
            error = 'no_permission',
        }
    end

    H.Equal(H.PostNui('reportOpen', {
        message = 'help',
        category = 'player',
        accused = 3,
    }), {
        ok = true,
    })
    H.Equal(H.PostNui('reportOpen', {
        message = 'help',
        category = 'hacked',
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('reportOpen', {
        message = 'help',
        extra = true,
    }), {
        ok = false,
    })
    H.Advance(0)
    H.Equal(H.Requests[#H.Requests], {
        name = 'Report',
        args = { 'help', 'player', 3 },
    })

    H.Equal(H.PostNui('reportReply', {
        text = 'still stuck',
    }), {
        ok = true,
    })
    H.Advance(0)
    H.Equal(H.Requests[#H.Requests], {
        name = 'ReportReply',
        args = { 'still stuck' },
    })
    H.Equal(H.Notifications[#H.Notifications].message, 'error.no_permission')

    -- A refusal the server already explained shows nothing more.
    local shown = #H.Notifications

    H.Respond.Report = function()
        return {
            ok = false,
            error = 'not_found',
            told = true,
        }
    end
    H.PostNui('reportOpen', {
        message = 'help',
        category = 'player',
        accused = 99,
    })
    H.Advance(0)
    H.Equal(#H.Notifications, shown)

    H.Equal(H.PostNui('reportRate', {
        rating = 9,
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('reportHide', {}), {
        ok = true,
    })
    H.Equal(last('SetNuiFocus'), { false, false })
    H.Equal(UgAdmin.Internal.Report.IsOpen(), false)
end)

H.Test('panel settings are saved on this PC, checked on the way in and out, and sent with the panel', function()
    boot({ 'admin' })
    H.LocalState[StateBags.Access] = { 'admin' }

    H.Respond.Snapshot = function()
        return {
            self = 1,
            players = {},
            reports = {},
            catalog = {},
        }
    end

    -- Broken bodies never reach KVP.
    H.Equal(H.PostNui('settings', {
        order = { 'noclip', 'nope' },
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('settings', {
        replies = { string.rep('a', 101) },
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('settings', {
        theme = 'red',
    }), {
        ok = false,
    })
    H.Equal(H.Kvp['ug-admin:Settings'], nil)

    local settings = {
        order = { 'vision', 'noclip' },
        hidden = { 'god' },
        everyone = false,
        tab = 'reports',
        confirm = false,
        replies = { 'Hi!' },
    }

    H.Equal(H.PostNui('settings', settings), {
        ok = true,
    })
    H.Equal(UgAdmin.Internal.Settings.Get(), settings)

    UgAdmin.Internal.Panel.Open()

    H.Equal(H.LastPage('open').settings, settings)

    -- What KVP holds is checked too: a broken value loads as no settings.
    H.Kvp['ug-admin:Settings'] = json.encode({
        tab = 'nope',
    })
    H.Equal(UgAdmin.Internal.Settings.Get(), {})
    H.Kvp['ug-admin:Settings'] = '{broken'
    H.Equal(UgAdmin.Internal.Settings.Get(), {})
end)

H.Test('the panel shows faces of players in scope, retakes them for a new ped and frees them on close', function()
    boot()

    local peds = {
        [0] = 101,
        [7] = 107,
    }
    local nextHandle = 0

    H.NativeReturns.GetPlayerFromServerId = function(id)
        return ({
            [1] = 0,
            [4] = 7,
        })[id] or -1
    end
    H.NativeReturns.GetPlayerPed = function(player)
        return peds[player] or 0
    end
    H.NativeReturns.DoesEntityExist = true
    H.NativeReturns.RegisterPedheadshot = function()
        nextHandle = nextHandle + 1

        return nextHandle
    end
    H.NativeReturns.IsPedheadshotReady = true
    H.NativeReturns.IsPedheadshotValid = true
    H.NativeReturns.GetPedheadshotTxdString = function(handle)
        return 'PEDHEADSHOT_' .. handle
    end

    local Faces = UgAdmin.Internal.Faces

    -- Player 9 is out of scope: no face, initials stay.
    H.Equal(Faces.Collect({ 1, 4, 9 }), {
        ['1'] = 'PEDHEADSHOT_1',
        ['4'] = 'PEDHEADSHOT_2',
    })
    H.Equal(#H.CallsOf('RegisterPedheadshot'), 2)

    -- A refresh keeps headshots; a new ped gets a new one and frees the old.
    peds[7] = 207
    H.Equal(Faces.Collect({ 1, 4 }), {
        ['1'] = 'PEDHEADSHOT_1',
        ['4'] = 'PEDHEADSHOT_3',
    })
    H.Equal(last('UnregisterPedheadshot'), { 2 })

    -- A player who left is freed, and closing frees the rest.
    H.Equal(Faces.Collect({ 1 }), {
        ['1'] = 'PEDHEADSHOT_1',
    })
    H.Equal(last('UnregisterPedheadshot'), { 3 })
    Faces.Release()
    H.Equal(last('UnregisterPedheadshot'), { 1 })

    -- A headshot that never renders is dropped.
    H.NativeReturns.IsPedheadshotValid = false
    H.Equal(Faces.Collect({ 1 }), {})
    H.Equal(last('UnregisterPedheadshot'), { 4 })
end)

H.Done()
