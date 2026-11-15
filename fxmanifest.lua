--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@diagnostic disable: undefined-global

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ug-admin'
author 'UgCore Framework & Contributors'
version '1.0.0' -- x-release-please-version
description 'Staff tools for UgCore: commands, cinematic noclip, spectate, vision, reports, audit log and a panel'
repository 'https://github.com/ugcore-project/ug-admin'

ugcore_version '1.0.0'
uglib_version '1.0.0'

dependencies {
    '/onesync',
    'oxmysql',
    'ug-core',
    'ug-lib',
}

shared_scripts {
    '@ug-core/import.lua',
    '@ug-lib/import.lua',
    'shared/init.lua',
    'shared/enums.lua',
    'shared/rules.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/util.lua',
    'server/config.lua',
    'server/staff.lua',
    'server/notify.lua',
    'server/audit.lua',
    'server/world.lua',
    'server/sanctions.lua',
    'server/notes.lua',
    'server/spectate.lua',
    'server/reports.lua',
    'server/actions.lua',
    'server/manage.lua',
    'server/radar.lua',
    'server/commands.lua',
    'server/panel.lua',
    'server/boot.lua',
}

client_scripts {
    'client/nui.lua',
    'client/request.lua',
    'client/notify.lua',
    'client/camera.lua',
    'client/modes.lua',
    'client/noclip.lua',
    'client/props.lua',
    'client/spectate.lua',
    'client/vision.lua',
    'client/events.lua',
    'client/faces.lua',
    'client/settings.lua',
    'client/panel.lua',
    'client/report.lua',
    'client/boot.lua',
}

ui_page 'web/dist/index.html'

files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
}
