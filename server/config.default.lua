--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- ug-admin config. Copied to config.lua in the resource folder on the first start: edit that file, never this one.
-- Updates never overwrite config.lua. A key you remove uses its default.
-- Clients receive these values: never put secrets here. The Discord webhook is the ug-admin:Webhook convar.

return {
    -- Lowest staff group (ug-core config/permissions.lua) allowed to use each action. Inheritance counts: with
    -- founder > admin > moderator, a founder MAY do everything a moderator may. Set a group nobody has to turn
    -- an action off. Staff MUST outrank a staff target (higher weight) for actions marked protected in the README.
    access = {
        -- Panel and movement
        admin = 'moderator',
        noclip = 'moderator',
        vision = 'moderator',
        tpm = 'moderator',
        tp = 'moderator',
        back = 'moderator',
        -- Players
        ['goto'] = 'moderator',
        bring = 'moderator',
        spectate = 'moderator',
        revive = 'moderator',
        heal = 'moderator',
        freeze = 'moderator',
        warn = 'moderator',
        kick = 'moderator',
        reports = 'moderator',
        duty = 'moderator',
        dm = 'moderator',
        sendto = 'moderator',
        jail = 'moderator',
        unjail = 'moderator',
        mute = 'moderator',
        unmute = 'moderator',
        note = 'moderator',
        delnote = 'admin',
        kill = 'admin',
        ban = 'admin',
        unban = 'admin',
        god = 'admin',
        invisible = 'admin',
        -- Characters
        givemoney = 'admin',
        setjob = 'admin',
        setgang = 'admin',
        giveitem = 'admin',
        clearinv = 'admin',
        inventory = 'admin',
        setgroup = 'founder',
        removegroup = 'founder',
        setstats = 'admin',
        setneed = 'admin',
        setmoney = 'admin',
        removeitem = 'admin',
        -- Everyone at once
        reviveall = 'admin',
        bringall = 'admin',
        freezeall = 'admin',
        -- World
        fix = 'moderator',
        dv = 'moderator',
        car = 'admin',
        delentity = 'admin',
        announce = 'admin',
    },

    -- Default keys. Staff MAY change them in the game's key bindings. '' leaves the action without a key.
    keys = {
        noclip = 'F2',
        panel = 'F10',
        vision = '',
    },

    -- Noclip speeds in meters per second. The slowest and fastest bound the mouse wheel, which changes speed by 20%
    -- per notch. Flights start at the second one. Shift doubles, Alt halves.
    noclipSpeeds = { 1.5, 15, 200 },

    -- How often staff with vision on receive every player's position, in milliseconds.
    radarInterval = 1500,

    -- Largest radius, in meters, /dv may clear.
    maxDeleteRadius = 50,

    -- Delete the last vehicle a staff member spawned with /car when they spawn another.
    replaceSpawnedVehicle = true,

    -- Seconds a player waits between two reports, and open reports kept at most.
    reportCooldown = 60,
    maxReports = 100,

    -- Staff with /duty start on duty when their character loads. Off duty, they get no report alerts and cannot
    -- take reports.
    startOnDuty = false,

    -- Ban durations staff pick from in the panel. /ban also takes any 30m, 12h, 7d or perm.
    banDurations = { '1h', '1d', '3d', '7d', '30d', 'perm' },

    -- /jail sends players to coords. One who goes farther than radius meters is brought back. Time counts down while
    -- they are online, and they walk out at release. The default is Bolingbroke Penitentiary.
    jail = {
        coords = vector3(1767.4, 2500.7, 45.7),
        radius = 150.0,
        release = vector3(1848.1, 2586.1, 45.7),
    },

    -- Places /sendto and the panel offer, by name. The name waypoint is taken: it sends to your own waypoint.
    locations = {
        hospital = {
            label = 'Pillbox Hospital',
            coords = vector3(298.6, -584.5, 43.3),
        },
        police = {
            label = 'Mission Row PD',
            coords = vector3(428.2, -981.3, 30.7),
        },
        legion = {
            label = 'Legion Square',
            coords = vector3(195.2, -933.8, 30.7),
        },
        airport = {
            label = 'Airport',
            coords = vector3(-1037.5, -2737.6, 20.2),
        },
        sandy = {
            label = 'Sandy Shores',
            coords = vector3(1853.2, 3686.6, 34.3),
        },
        paleto = {
            label = 'Paleto Bay',
            coords = vector3(-448.6, 6008.7, 31.7),
        },
    },

    -- ug-lib theme overrides for the panel only: mode, colors (HSL strings such as '262 83% 58%'), radius, font,
    -- scale. colors take ug-lib's tokens plus the section tones: violet, indigo, blue, sky, teal, emerald, amber, rose,
    -- fuchsia. A tone sets its lighter shades too.
    theme = {},

    -- The panel. width and height in rem (the window never passes 96% of the screen). rail: 'left' or 'right'.
    -- backdrop: how dark the game gets behind it, 0 to 1. glow: the ambient light. logo: the logo and title on the rail.
    -- quickBar: the row of quick actions. toasts: 'top' or 'bottom'. toastDuration in ms. animations: false keeps
    -- everything still. refreshInterval: ms between player list refreshes. noclipHud: crosshair, target card and keys
    -- while flying.
    layout = {
        width = 84,
        height = 50,
        rail = 'left',
        backdrop = 0.5,
        glow = true,
        logo = true,
        quickBar = true,
        toasts = 'bottom',
        toastDuration = 2600,
        animations = true,
        refreshInterval = 5000,
        noclipHud = true,
    },

    -- Panel tabs, in order: 'players', 'reports', 'logs', 'settings'. Leave one out to hide it. Reports also need the
    -- reports access.
    tabs = { 'players', 'reports', 'logs', 'settings' },

    -- The drone noclip. fov and fovKick (extra fov at speed) in degrees. lookSpeed: mouse sensitivity. smoothing: how
    -- quickly the drone reaches its speed, higher is snappier. boost and slow multiply speed with Shift and Alt.
    -- liftDuration and diveDuration: ms of the take-off and landing flights, 0 cuts. inspect: aim at things to land,
    -- board, delete or freeze them. outline and outlineColor { red, green, blue, alpha }: the aimed entity. marker: the
    -- ground marker where you would land.
    noclip = {
        fov = 60.0,
        fovKick = 8.0,
        lookSpeed = 7.5,
        smoothing = 10.0,
        boost = 2.0,
        slow = 0.5,
        liftDuration = 350,
        diveDuration = 400,
        inspect = true,
        outline = true,
        outlineColor = { 124, 92, 255, 255 },
        marker = true,
    },

    -- Spectate. swoop: the camera dives from the sky to the player. swoopHeight in meters, swoopDuration and fade in ms.
    spectate = {
        swoop = true,
        swoopHeight = 90.0,
        swoopDuration = 1400,
        fade = 350,
    },

    -- Full-screen messages for /announce, /warn and /dm. duration in ms. color: 'purple', 'red', 'blue', 'green',
    -- 'yellow', 'orange', 'white' or 'grey'. sound: { name, set } from the game's frontend sounds, or leave it out.
    -- Leave a kind out to show it as a notification instead.
    shards = {
        announce = {
            duration = 9000,
            color = 'purple',
            sound = {
                name = 'CHECKPOINT_PERFECT',
                set = 'HUD_MINI_GAME_SOUNDSET',
            },
        },
        warn = {
            duration = 7000,
            color = 'red',
            sound = {
                name = 'CHECKPOINT_MISSED',
                set = 'HUD_MINI_GAME_SOUNDSET',
            },
        },
        message = {
            duration = 9000,
            color = 'blue',
            sound = {
                name = 'CHECKPOINT_PERFECT',
                set = 'HUD_MINI_GAME_SOUNDSET',
            },
        },
    },

    -- How see-through invisible staff look to themselves, 0 to 255. Everyone else sees nothing.
    invisibleAlpha = 140,
}
