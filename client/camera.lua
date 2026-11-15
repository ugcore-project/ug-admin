--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Scripted camera moves and GTA's instructional buttons, shared by noclip and spectate.

---@class UgAdmin.Internal.Camera
local Camera = {}
UgAdmin.Internal.Camera = Camera

---@class UgAdminShot
---@field coords vector3
---@field rotation vector3 degrees, rotation order 2
---@field fov number

local BUTTONS_MOVIE = 'INSTRUCTIONAL_BUTTONS'
local ROTATION_ORDER = 2

---@param t number 0 to 1
---@return number
function Camera.EaseOutCubic(t)
    local inverse = 1 - t

    return 1 - inverse * inverse * inverse
end

---@param t number 0 to 1
---@return number
function Camera.EaseInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    end

    local inverse = -2 * t + 2

    return 1 - inverse * inverse * inverse / 2
end

---Angle from a to b along the shortest way, in degrees.
---@param a number
---@param b number
---@param t number
---@return number
function Camera.LerpAngle(a, b, t)
    local delta = ((b - a + 180) % 360) - 180

    return a + delta * t
end

---Direction a camera rotation looks at.
---@param rotation vector3
---@return vector3
function Camera.Forward(rotation)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local horizontal = math.abs(math.cos(pitch))

    return vector3(-math.sin(yaw) * horizontal, math.cos(yaw) * horizontal, math.sin(pitch))
end

---Right of a camera rotation, flat.
---@param rotation vector3
---@return vector3
function Camera.Right(rotation)
    local yaw = math.rad(rotation.z)

    return vector3(math.cos(yaw), math.sin(yaw), 0.0)
end

---The current gameplay camera as a shot.
---@return UgAdminShot
function Camera.Gameplay()
    return {
        coords = GetGameplayCamCoord(),
        rotation = GetGameplayCamRot(ROTATION_ORDER),
        fov = GetGameplayCamFov(),
    }
end

---Creates an active scripted camera at a shot and renders it.
---@param shot UgAdminShot
---@return integer cam
function Camera.Create(shot)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', shot.coords.x, shot.coords.y, shot.coords.z,
        shot.rotation.x, shot.rotation.y, shot.rotation.z, shot.fov, false, ROTATION_ORDER)

    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    return cam
end

---@param cam integer
---@param shot UgAdminShot
function Camera.Set(cam, shot)
    SetCamCoord(cam, shot.coords.x, shot.coords.y, shot.coords.z)
    SetCamRot(cam, shot.rotation.x, shot.rotation.y, shot.rotation.z, ROTATION_ORDER)
    SetCamFov(cam, shot.fov)
end

---Moves the camera from one shot to another, one step per frame. Blocks the calling thread.
---`onFrame` runs every frame with the shot, so the ped can follow.
---@param cam integer
---@param from UgAdminShot
---@param to UgAdminShot
---@param duration integer ms
---@param ease fun(t: number): number
---@param onFrame? fun(shot: UgAdminShot)
function Camera.Fly(cam, from, to, duration, ease, onFrame)
    local started = GetGameTimer()

    while true do
        -- A zero duration cuts straight to the end, never dividing by zero.
        local t = duration > 0 and math.min((GetGameTimer() - started) / duration, 1.0) or 1.0
        local k = ease(t)
        local shot = {
            coords = from.coords + (to.coords - from.coords) * k,
            rotation = vector3(
                from.rotation.x + (to.rotation.x - from.rotation.x) * k,
                Camera.LerpAngle(from.rotation.y, to.rotation.y, k),
                Camera.LerpAngle(from.rotation.z, to.rotation.z, k)
            ),
            fov = from.fov + (to.fov - from.fov) * k,
        }

        Camera.Set(cam, shot)

        if onFrame then
            onFrame(shot)
        end

        if t >= 1.0 then
            return
        end

        Wait(0)
    end
end

---Hands back to the gameplay camera with a blend, then destroys the scripted one.
---@param cam integer
---@param blend integer ms
function Camera.Release(cam, blend)
    RenderScriptCams(false, blend > 0, blend, true, true)
    SetCamActive(cam, false)
    DestroyCam(cam, false)
end

---@class UgAdminButton
---@field control integer control index, for its key label
---@field label string

---@type integer?
local movie = nil
---@type string signature of the buttons on screen
local shown = ''

---Draws GTA's instructional buttons for this frame. Rebuilds the movie only when the list changes.
---@param buttons UgAdminButton[]
function Camera.Buttons(buttons)
    if not movie then
        local ok, handle = UgLib.Streaming.ScaleformMovie(BUTTONS_MOVIE, 2000)

        if not ok or not handle then
            return
        end

        movie = handle
    end

    local parts = {}

    for index, button in ipairs(buttons) do
        parts[index] = button.control .. button.label
    end

    local signature = table.concat(parts, '|')

    if signature ~= shown then
        shown = signature
        BeginScaleformMovieMethod(movie, 'CLEAR_ALL')
        EndScaleformMovieMethod()

        for index, button in ipairs(buttons) do
            BeginScaleformMovieMethod(movie, 'SET_DATA_SLOT')
            ScaleformMovieMethodAddParamInt(index - 1)
            ScaleformMovieMethodAddParamPlayerNameString(GetControlInstructionalButton(0, button.control, true))
            ScaleformMovieMethodAddParamTextureNameString(button.label)
            EndScaleformMovieMethod()
        end

        BeginScaleformMovieMethod(movie, 'DRAW_INSTRUCTIONAL_BUTTONS')
        EndScaleformMovieMethod()
    end

    DrawScaleformMovieFullscreen(movie, 255, 255, 255, 255, 0)
end
