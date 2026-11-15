--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Players: 1 founder, 2 moderator, 3 admin, 4 player. Founder > admin > moderator.

local H = dofile('tests/helpers.lua')

local Errors, Action, StateBags

local FOUNDER, MODERATOR, ADMIN, PLAYER = 1, 2, 3, 4

-- Staff start off duty by default. Report tests need them on.
local ON_DUTY = 'return { startOnDuty = true }'

---@param content string? config.lua content, nil for a first start
---@return string[] lines
local function boot(content)
    H.Reset()

    if content then
        H.Files['config.lua'] = content
    end

    local lines = H.Load('server')

    Errors, Action, StateBags = UgCore.Enums.Errors, UgAdmin.Enums.Action, UgAdmin.Enums.StateBags

    return lines
end

---@param actor integer
---@param action string
---@param target? integer
---@param args? table
---@return boolean ok
---@return string? errorCode
local function run(actor, action, target, args)
    local ok, checked = UgCore.Schema.Check(UgAdmin.Rules.Args, args or {})

    assert(ok, 'test args do not pass the schema')

    return UgAdmin.Internal.Actions.Run(actor, action, target, checked)
end

---Last notification a player received: key and kind.
---@param source integer
---@return string? key
---@return string? kind
local function lastNotice(source)
    local found = nil

    for _, sent in ipairs(H.SentOf('Notify')) do
        if sent.source == source then
            found = sent
        end
    end

    return found and found.args[1], found and found.args[3]
end

---Arguments of the last net event with this name sent to a player.
---@param name string
---@param target integer
---@return any
local function lastSent(name, target)
    local found = nil

    for _, sent in ipairs(H.SentOf(name)) do
        if sent.source == target then
            found = sent
        end
    end

    if not found then
        return nil
    end

    return #found.args > 1 and found.args or found.args[1]
end

print('server')

H.Test('first start generates config.lua, registers every command and prints the ready line', function()
    local lines = boot()

    H.Assert(H.Saved['config.lua'] ~= nil, 'config.lua not generated')
    H.ExpectLine(lines, '[ug-admin] v1.0.0 ready. 50 command(s), 3 staff online.')

    for _, action in pairs(Action) do
        H.Assert(H.Commands[action], 'no command /' .. action)
    end

    H.Assert(H.Commands.report and H.Commands.report.options.groups == nil, '/report is for everyone')
    H.Equal(H.Commands.ban.options.groups, { 'admin' })

    for _, name in pairs(UgAdmin.Enums.Callbacks) do
        H.Assert(H.Callbacks[name], 'no callback ' .. name)
    end
end)

H.Test('every command argument has a chat hint in the locale', function()
    boot()

    local english = json.decode(assert(LoadResourceFile('ug-admin', 'locales/en.json')))

    for name, command in pairs(H.Commands) do
        H.Assert(type(command.options.help) == 'string', 'no help for /' .. name)

        for _, argument in ipairs(command.options.args or {}) do
            H.Equal(argument.help, 'arg.' .. argument.name, '/' .. name)
            H.Assert(english.arg[argument.name], 'no arg.' .. argument.name .. ' in en.json')
        end
    end
end)

H.Test('an owner access table keeps defaults for actions it leaves out, and bad values stop boot', function()
    boot("return { access = { ban = 'founder' } }")

    local access = UgAdmin.Internal.Config.Get().access

    H.Equal(access.ban, 'founder')
    H.Equal(access.kick, 'moderator')

    local lines = boot("return { access = { bann = 'admin' }, banDurations = { '7x' } }")

    H.ExpectLine(lines, 'banDurations')
    H.ExpectLine(lines, 'Config invalid: 2 error(s). ug-admin stays off.')
    H.Equal(H.Commands.kick, nil)
end)

H.Test('access follows ug-core groups and inheritance', function()
    boot()

    local founder = H.State[FOUNDER][StateBags.Access]
    local moderator = H.State[MODERATOR][StateBags.Access]

    H.Equal(#founder, 49)
    H.Assert(not UgAdmin.Internal.Staff.Can(MODERATOR, Action.Ban), 'moderators do not ban')
    H.Assert(UgAdmin.Internal.Staff.Can(MODERATOR, Action.Kick), 'moderators kick')
    H.Assert(UgAdmin.Internal.Staff.Can(ADMIN, Action.Kick), 'admins inherit moderator actions')
    H.Assert(moderator[1] ~= nil, 'moderator has actions')
    H.Equal(H.State[PLAYER] and H.State[PLAYER][StateBags.Access], nil)
end)

H.Test('an action without access is refused and nothing happens', function()
    boot()

    H.Equal({
        run(MODERATOR, Action.Ban, PLAYER, {
            reason = 'x',
        }),
    }, { false, Errors.NoPermission })
    H.Equal({ run(PLAYER, Action.Noclip) }, { false, Errors.NoPermission })
    H.Equal(#H.CoreCallsOf('Ban'), 0)
    H.Equal(lastNotice(MODERATOR), 'error.no_permission')
end)

H.Test('staff only act on players they outrank', function()
    boot()

    H.Equal({ run(MODERATOR, Action.Kick, ADMIN) }, { false, Errors.NoPermission })
    H.Equal({ run(ADMIN, Action.Kick, FOUNDER) }, { false, Errors.NoPermission })
    H.Equal({
        run(ADMIN, Action.Kick, MODERATOR, {
            reason = 'afk',
        }),
    }, { true, nil })
    H.Equal({ run(0, Action.Kick, FOUNDER) }, { true, nil })
    H.Equal(#H.CoreCallsOf('Kick'), 2)
end)

H.Test('a successful action writes the audit log and answers the staff member', function()
    boot()

    run(ADMIN, Action.Kick, PLAYER, {
        reason = 'combat logging',
    })

    H.Equal(H.Rows[1].actor, 'license:3')
    H.Equal(H.Rows[1].action, 'kick')
    H.Equal(H.Rows[1].target, 'license:4')
    H.Equal(H.Rows[1].detail, 'combat logging')
    H.Equal({ lastNotice(ADMIN) }, { 'result.kick', 'success' })

    local emitted = H.Emitted[#H.Emitted]

    H.Equal(emitted.name, UgAdmin.Enums.Events.Action)
end)

H.Test('ban durations become seconds, perm stays permanent, anything else is refused', function()
    boot()

    run(ADMIN, Action.Ban, PLAYER, {
        reason = 'cheating',
        duration = '7d',
    })
    run(ADMIN, Action.Ban, PLAYER, {
        reason = 'cheating',
    })
    H.Equal({
        run(ADMIN, Action.Ban, PLAYER, {
            reason = 'x',
            duration = '7x',
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({ run(ADMIN, Action.Ban, PLAYER) }, { false, Errors.InvalidArgs })

    local bans = H.CoreCallsOf('Ban')

    H.Equal(#bans, 2)
    H.Equal(bans[1][2], {
        reason = 'cheating',
        duration = 604800,
        by = 'license:3',
    })
    H.Equal(bans[2][2].duration, nil)
end)

H.Test('unban reports identifiers without bans', function()
    boot()

    H.Equal({
        run(ADMIN, Action.Unban, nil, {
            identifier = 'license:banned',
        }),
    }, { true, nil })
    H.Equal({
        run(ADMIN, Action.Unban, nil, {
            identifier = 'license:clean',
        }),
    }, { false, Errors.NotFound })
end)

H.Test('goto and bring move players to server-side positions, and back undoes it', function()
    boot()

    run(MODERATOR, Action.Goto, PLAYER)

    local teleports = H.SentOf('Teleport')

    H.Equal(teleports[1].source, MODERATOR)
    H.Equal(teleports[1].args[1], vector3(400.0, 400.0, 30.0))

    run(MODERATOR, Action.Bring, PLAYER)
    H.Equal(H.SentOf('Teleport')[2].source, PLAYER)
    H.Equal(H.SentOf('Teleport')[2].args[1], vector3(200.0, 200.0, 30.0))

    run(MODERATOR, Action.Back, PLAYER)
    H.Equal(H.SentOf('Teleport')[3].args[1], vector3(400.0, 400.0, 30.0))

    H.Equal({ run(MODERATOR, Action.Goto, MODERATOR) }, { false, Errors.InvalidArgs })
    H.Equal({ run(0, Action.Goto, PLAYER) }, { false, Errors.InvalidArgs })
end)

H.Test('modes toggle in the statebag and drop when the group is lost', function()
    boot()

    run(ADMIN, Action.Duty)
    run(ADMIN, Action.Noclip)
    run(ADMIN, Action.God)
    H.Equal(H.State[ADMIN][StateBags.Mode], {
        noclip = true,
        god = true,
        duty = true,
    })

    run(ADMIN, Action.Noclip)
    H.Equal(H.State[ADMIN][StateBags.Mode], {
        god = true,
        duty = true,
    })

    -- Moderators keep duty, not god mode.
    H.Players[ADMIN].group = 'moderator'
    H.EmitCore(UgCore.Enums.Events.Permissions.GroupRemoved, 'license:3', 'admin')

    H.Equal(H.State[ADMIN][StateBags.Mode], {
        duty = true,
    })
end)

H.Test('money goes through accounts, a negative amount takes it, zero is refused', function()
    boot()

    H.Equal({
        run(ADMIN, Action.GiveMoney, PLAYER, {
            account = 'cash',
            amount = 50,
        }),
    }, { true, nil })
    H.Equal({
        run(ADMIN, Action.GiveMoney, PLAYER, {
            account = 'cash',
            amount = -500,
        }),
    }, { false, Errors.InsufficientFunds })
    H.Equal({
        run(ADMIN, Action.GiveMoney, PLAYER, {
            account = 'cash',
            amount = -150,
        }),
    }, { true, nil })
    H.Equal({
        run(ADMIN, Action.GiveMoney, PLAYER, {
            account = 'cash',
            amount = 0,
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal(H.Balances[PLAYER].cash, 0)
    H.Equal(H.Ledger[1].reason, 'ug-admin')
end)

H.Test('jobs and items are checked before they are set', function()
    boot()

    H.Equal({
        run(ADMIN, Action.SetJob, PLAYER, {
            job = 'mafia',
        }),
    }, { false, Errors.NotFound })
    H.Equal({
        run(ADMIN, Action.SetJob, PLAYER, {
            job = 'police',
            grade = 2,
        }),
    }, { true, nil })
    H.Equal(H.CoreCallsOf('SetJob'), { { PLAYER, 'police', 2 } })

    H.Equal({
        run(ADMIN, Action.GiveItem, PLAYER, {
            item = 'gold',
        }),
    }, { false, Errors.NotFound })
    H.Equal({
        run(ADMIN, Action.GiveItem, PLAYER, {
            item = 'water',
            count = 3,
        }),
    }, { true, nil })

    H.Players[PLAYER].characterId = nil
    H.Equal({
        run(ADMIN, Action.GiveItem, PLAYER, {
            item = 'water',
        }),
    }, { false, Errors.NotLoaded })
end)

H.Test('nobody grants or removes a group as high as their own', function()
    boot()

    H.Equal({
        run(ADMIN, Action.SetGroup, PLAYER, {
            group = 'moderator',
        }),
    }, { false, Errors.NoPermission })

    H.Players[ADMIN].group = 'founder'
    H.Players[MODERATOR].group = 'founder'

    H.Equal({
        run(FOUNDER, Action.SetGroup, PLAYER, {
            group = 'founder',
        }),
    }, { false, Errors.NoPermission })
    H.Equal({
        run(FOUNDER, Action.SetGroup, PLAYER, {
            group = 'ghost',
        }),
    }, { false, Errors.NotFound })
    H.Equal({
        run(FOUNDER, Action.SetGroup, PLAYER, {
            group = 'admin',
        }),
    }, { true, nil })
    H.Assert(H.State[PLAYER][StateBags.Access] ~= nil, 'the new admin gets access at once')

    H.Equal({
        run(FOUNDER, Action.RemoveGroup, PLAYER, {
            group = 'moderator',
        }),
    }, { false, Errors.NotFound })
    H.Equal({
        run(FOUNDER, Action.RemoveGroup, PLAYER, {
            group = 'admin',
        }),
    }, { true, nil })
end)

H.Test('revive brings a dead player back with full health and needs', function()
    boot()

    H.Players[PLAYER].state = UgCore.Enums.DeathState.Dead
    H.Equal({ run(MODERATOR, Action.Revive, PLAYER) }, { true, nil })

    H.Equal(H.CoreCallsOf('Revive')[1][2], {
        by = MODERATOR,
        reason = 'ug-admin',
        clearInjuries = true,
    })
    H.Equal(#H.CoreCallsOf('ResetNeeds'), 1)
    H.Equal(H.SentOf('Heal')[1].source, PLAYER)
end)

H.Test('heal restores health and needs, and revives a downed player', function()
    boot()

    H.Equal({ run(MODERATOR, Action.Heal) }, { true, nil })
    H.Equal(#H.CoreCallsOf('Revive'), 0)
    H.Equal(#H.CoreCallsOf('ClearInjuries'), 1)
    H.Equal(#H.CoreCallsOf('ResetNeeds'), 1)
    H.Equal(H.SentOf('Heal')[1].source, MODERATOR)

    H.Players[PLAYER].state = UgCore.Enums.DeathState.Downed
    run(MODERATOR, Action.Heal, PLAYER)
    H.Equal(#H.CoreCallsOf('Revive'), 1)
    H.Equal(#H.CoreCallsOf('ResetNeeds'), 2)
end)

H.Test('freeze toggles the statebag and the ped', function()
    boot()

    run(MODERATOR, Action.Freeze, PLAYER)
    H.Equal(H.State[PLAYER][StateBags.Frozen], true)
    H.Equal(H.CallsOf('FreezeEntityPosition')[1].args, { 104, true })

    run(MODERATOR, Action.Freeze, PLAYER)
    H.Equal(H.State[PLAYER][StateBags.Frozen], nil)
end)

H.Test('a report reaches staff, a second /report joins its chat, and a new one waits out the cooldown', function()
    boot(ON_DUTY)

    H.Equal(H.Command('report', PLAYER, {
        message = 'stuck under the map',
    }), true)

    local notified = {}

    for _, sent in ipairs(H.SentOf('Notify')) do
        if sent.args[1] == 'report.new' then
            notified[#notified + 1] = sent.source
        end
    end

    H.Equal(notified, { FOUNDER, MODERATOR, ADMIN })
    H.Equal(lastNotice(PLAYER), 'report.sent')

    H.Command('report', PLAYER, {
        message = 'still stuck',
    })

    local report = UgAdmin.Internal.Reports.GetAll()[1]

    H.Equal(#UgAdmin.Internal.Reports.GetAll(), 1)
    H.Equal(report.message, 'stuck under the map')
    H.Equal({ report.messages[2].author, report.messages[2].text }, { 'player', 'still stuck' })
    H.Equal(lastNotice(MODERATOR), 'report.message')

    H.Equal(H.Call('ReportCancel', PLAYER), {
        ok = true,
    })
    H.Equal(#UgAdmin.Internal.Reports.GetAll(), 0)
    H.Equal(lastSent('MyReport', PLAYER), nil)

    H.Command('report', PLAYER, {
        message = 'again',
    })
    H.Equal(lastNotice(PLAYER), 'error.rate_limited')
end)

H.Test('/report without a message opens the window, and the window sends a category and a player', function()
    boot(ON_DUTY)

    H.Command('report', PLAYER, {})
    H.Equal(H.SentOf('ReportWindow')[1].source, PLAYER)

    -- Reporting yourself or an id nobody has says so, instead of a bare error.
    H.Equal(H.Call('Report', PLAYER, 'he rams me', 'player', PLAYER), {
        ok = false,
        error = Errors.InvalidArgs,
        told = true,
    })
    H.Equal({ lastNotice(PLAYER) }, { 'report.accusedSelf', 'error' })
    H.Equal(H.Call('Report', PLAYER, 'he rams me', 'player', 99), {
        ok = false,
        error = Errors.NotFound,
        told = true,
    })
    H.Equal({ lastNotice(PLAYER) }, { 'report.accusedMissing', 'error' })
    H.Equal(H.Call('Report', PLAYER, 'he rams me', 'hacked'), nil)
    H.Equal(H.Call('Report', PLAYER, 'he rams me', 'player', ADMIN), {
        ok = true,
    })

    local report = UgAdmin.Internal.Reports.GetAll()[1]

    H.Equal({ report.category, report.accused, report.accusedName }, { 'player', ADMIN, 'Player3' })
    H.Equal(lastSent('MyReport', PLAYER).accusedName, 'Player3')
    H.Equal(lastSent('MyReport', PLAYER).accused, nil, 'the reporter never gets sources')
end)

H.Test('staff answer, go to the reporter and back, bring them and send them back, close, and get rated', function()
    boot(ON_DUTY)

    H.Command('report', PLAYER, {
        message = 'help',
    })

    local id = UgAdmin.Internal.Reports.GetAll()[1].id
    local function op(name, text)
        return {
            run(MODERATOR, Action.Reports, nil, {
                report = id,
                op = name,
                text = text,
            }),
        }
    end

    H.Equal(op('reply'), { false, Errors.InvalidArgs })
    H.Equal(op('reply', 'on my way'), { true, nil })

    local report = UgAdmin.Internal.Reports.GetAll()[1]

    H.Equal({ report.status, report.claimer }, { 'claimed', MODERATOR })
    H.Equal(lastNotice(PLAYER), 'report.reply')
    H.Equal(#lastSent('MyReport', PLAYER).messages, 3)

    H.Equal(op('goto'), { true, nil })
    H.Equal(lastSent('Teleport', MODERATOR)[1], vector3(400.0, 400.0, 30.0))
    H.Equal(lastNotice(PLAYER), 'report.arrived')
    H.Equal(lastSent('Reports', MODERATOR)[1].visitors, { MODERATOR })

    H.PedCoords[MODERATOR] = vector3(400.0, 400.0, 30.0)
    H.Equal(op('return'), { true, nil })
    H.Equal(lastSent('Teleport', MODERATOR)[1], vector3(200.0, 200.0, 30.0))
    H.Equal(op('return'), { false, Errors.NotFound })

    H.PedCoords[MODERATOR] = vector3(200.0, 200.0, 30.0)
    H.Equal(op('bring'), { true, nil })
    H.Equal(lastSent('Teleport', PLAYER)[1], vector3(200.0, 200.0, 30.0))
    H.Equal(lastSent('Reports', MODERATOR)[1].brought, true)

    H.PedCoords[PLAYER] = vector3(200.0, 200.0, 30.0)
    H.Equal(op('sendback'), { true, nil })
    H.Equal(lastSent('Teleport', PLAYER)[1], vector3(400.0, 400.0, 30.0))
    H.Equal(op('sendback'), { false, Errors.NotFound })

    H.Equal(H.Call('ReportRate', PLAYER, 5), {
        ok = false,
        error = Errors.NotFound,
    })
    H.Equal(op('close', 'all sorted'), { true, nil })
    H.Equal(lastNotice(PLAYER), 'report.closed')
    H.Equal(lastSent('MyReport', PLAYER).status, 'closed')

    H.Equal(H.Call('ReportRate', PLAYER, 6), nil)
    H.Equal(H.Call('ReportRate', PLAYER, 5), {
        ok = true,
    })
    H.Equal(lastNotice(MODERATOR), 'report.rated')
    H.Equal(lastSent('MyReport', PLAYER), nil)
    H.Equal(lastSent('Reports', MODERATOR)[1].rating, 5)
    H.Equal(H.Call('ReportRate', PLAYER, 1), {
        ok = false,
        error = Errors.NotFound,
    })
    H.Equal(op('close'), { false, Errors.NotFound })

    -- Answers and trips back stay out of the audit log.
    local logged = {}

    for _, row in ipairs(H.Rows) do
        logged[#logged + 1] = row.detail:match('^#%d+ (%a+)')
    end

    H.Equal(logged, { 'goto', 'bring', 'close' })
end)

H.Test('reporters outranking staff are not brought, the console does not travel, and staff who leave give reports back', function()
    boot(ON_DUTY)

    H.Command('report', ADMIN, {
        message = 'bug at the bank',
    })

    local id = UgAdmin.Internal.Reports.GetAll()[1].id

    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'bring',
        }),
    }, { false, Errors.NoPermission })
    H.Equal({
        run(0, Action.Reports, nil, {
            report = id,
            op = 'goto',
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'release',
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'claim',
        }),
    }, { true, nil })
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'claim',
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(FOUNDER, Action.Reports, nil, {
            report = id,
            op = 'claim',
        }),
    }, { true, nil })
    H.Equal(UgAdmin.Internal.Reports.GetAll()[1].claimer, FOUNDER)

    source = FOUNDER
    H.TriggerEvent('playerDropped')

    local report = UgAdmin.Internal.Reports.GetAll()[1]

    H.Equal({ report.status, report.claimer }, { 'open', nil })
    H.Equal(report.messages[#report.messages].text, 'released')
end)

H.Test('staff start on duty; off duty they get no alerts, cannot take reports, and give theirs back', function()
    boot(ON_DUTY)

    H.Equal(H.State[MODERATOR][StateBags.Mode], {
        duty = true,
    })
    H.Equal(H.State[PLAYER] and H.State[PLAYER][StateBags.Mode], nil)

    H.Command('report', PLAYER, {
        message = 'help',
    })

    local id = UgAdmin.Internal.Reports.GetAll()[1].id

    run(MODERATOR, Action.Reports, nil, {
        report = id,
        op = 'claim',
    })
    H.Sent = {}

    -- Going off duty hands the report back, and the others on duty hear about it.
    H.Equal({ run(MODERATOR, Action.Duty) }, { true, nil })
    H.Equal(H.State[MODERATOR][StateBags.Mode], nil)
    H.Equal(UgAdmin.Internal.Reports.GetAll()[1].status, 'open')
    H.Equal(lastNotice(ADMIN), 'report.released')

    for _, op in ipairs({ 'claim', 'reply', 'goto', 'bring' }) do
        H.Sent = {}
        H.Equal({
            run(MODERATOR, Action.Reports, nil, {
                report = id,
                op = op,
                text = 'hi',
            }),
        }, { false, Errors.NoPermission }, op)
        H.Equal({ lastNotice(MODERATOR) }, { 'duty.required', 'warning' }, op)
        H.Equal(#H.SentOf('Notify'), 1, 'told once: ' .. op)
    end

    -- New reports reach staff on duty only.
    run(ADMIN, Action.Duty)
    run(FOUNDER, Action.Duty)
    H.Sent = {}
    H.Command('report', ADMIN, {
        message = 'anyone?',
    })

    for _, sent in ipairs(H.SentOf('Notify')) do
        H.Assert(sent.args[1] ~= 'report.new', 'off duty staff got an alert')
    end

    local told = {}

    for _, sent in ipairs(H.SentOf('Notify')) do
        if sent.source == ADMIN then
            told[#told + 1] = sent.args[1]
        end
    end

    H.Equal(told, { 'report.noStaff', 'report.sent' })

    -- Back on duty, the next one arrives.
    run(MODERATOR, Action.Duty)
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'claim',
        }),
    }, { true, nil })
end)

H.Test('staff start off duty by default, and /duty says which way it went', function()
    boot()

    H.Equal(H.State[MODERATOR][StateBags.Mode], nil)
    H.Equal(UgAdmin.Internal.Reports.IsOnDuty(MODERATOR), false)
    H.Equal(UgAdmin.Internal.Reports.IsOnDuty(0), true)

    local function told()
        local found = nil

        for _, sent in ipairs(H.SentOf('Notify')) do
            if sent.source == MODERATOR and sent.args[1] == 'result.duty' then
                found = sent.args[2]
            end
        end

        return found and found.state
    end

    run(MODERATOR, Action.Duty)
    H.Equal(UgAdmin.Internal.Reports.IsOnDuty(MODERATOR), true)
    H.Equal(told(), UgAdmin.Internal.Notify.Text('duty.on'))

    run(MODERATOR, Action.Duty)
    H.Equal(UgAdmin.Internal.Reports.IsOnDuty(MODERATOR), false)
    H.Equal(told(), UgAdmin.Internal.Notify.Text('duty.off'))
    H.Assert(UgAdmin.Internal.Notify.Text('duty.on') ~= UgAdmin.Internal.Notify.Text('duty.off'), 'on and off read the same')
end)

H.Test('staff ping each other with @id, once each, and only staff are pinged', function()
    boot(ON_DUTY)

    H.Command('report', PLAYER, {
        message = 'help',
    })

    local id = UgAdmin.Internal.Reports.GetAll()[1].id

    -- Pings reach staff off duty too.
    run(ADMIN, Action.Duty)
    H.Sent = {}
    run(MODERATOR, Action.Reports, nil, {
        report = id,
        op = 'reply',
        text = 'need you @3, @4 and @3 again @2',
    })

    local admin = UgAdmin.Internal.NameOf(ADMIN)
    local line = UgAdmin.Internal.Reports.GetAll()[1].messages

    line = line[#line]
    H.Equal(line.text, ('need you @%s, @4 and @%s again @2'):format(admin, admin))
    H.Equal(line.mentions, { ADMIN })

    local pings = {}

    for _, sent in ipairs(H.SentOf('Notify')) do
        if sent.args[1] == 'report.mention' then
            pings[#pings + 1] = sent.source
        end
    end

    H.Equal(pings, { ADMIN })

    -- Staff see who was pinged, the reporter does not.
    local staffView = lastSent('Reports', ADMIN)[1].messages
    local ownView = lastSent('MyReport', PLAYER).messages

    H.Equal(staffView[#staffView].mentions, { ADMIN })
    H.Equal(ownView[#ownView].mentions, nil)
    H.Equal(ownView[#ownView].text, line.text)
end)

H.Test('staff hand a report to someone on duty, from the panel or with /reports', function()
    boot(ON_DUTY)

    H.Command('report', PLAYER, {
        message = 'help',
    })

    local id = UgAdmin.Internal.Reports.GetAll()[1].id
    local report = UgAdmin.Internal.Reports.GetAll()[1]

    run(MODERATOR, Action.Reports, nil, {
        report = id,
        op = 'claim',
    })

    -- Not staff, off duty, or already theirs: refused.
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'assign',
            staff = PLAYER,
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'assign',
            staff = MODERATOR,
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'assign',
        }),
    }, { false, Errors.InvalidArgs })
    run(ADMIN, Action.Duty)
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'assign',
            staff = ADMIN,
        }),
    }, { false, Errors.InvalidArgs })
    run(ADMIN, Action.Duty)

    H.Sent = {}
    H.Equal({
        run(MODERATOR, Action.Reports, nil, {
            report = id,
            op = 'assign',
            staff = ADMIN,
        }),
    }, { true, nil })
    H.Equal({ report.status, report.claimer, report.claimedBy }, { 'claimed', ADMIN, UgAdmin.Internal.NameOf(ADMIN) })
    H.Equal(report.messages[#report.messages].text, 'assigned')
    H.Equal(report.messages[#report.messages].to, UgAdmin.Internal.NameOf(ADMIN))
    H.Equal(lastNotice(ADMIN), 'report.assigned')
    H.Equal(lastNotice(PLAYER), 'report.claimed')
    H.Equal(H.Rows[#H.Rows].detail, ('#%d assign: %s'):format(id, UgAdmin.Internal.NameOf(ADMIN)))

    -- /reports takes the staff id as text.
    H.Command('reports', FOUNDER, {
        report = id,
        op = 'assign',
        text = '2',
    })
    H.Equal(report.claimer, MODERATOR)
end)

H.Test('player rows say who is staff and which character they play', function()
    boot()

    local rows = UgAdmin.Internal.Panel.Players()

    H.Equal({ rows[2].staff, rows[2].character }, { true, 'Character 20' })
    H.Equal({ rows[4].staff, rows[4].character }, { nil, 'Character 40' })

    H.Modules.characters = false
    H.Equal(UgAdmin.Internal.Panel.Players()[2].character, nil)
end)

H.Test('a report of a player who left is never sent to whoever gets their id', function()
    boot(ON_DUTY)

    H.Command('report', PLAYER, {
        message = 'help',
    })
    source = PLAYER
    H.TriggerEvent('playerDropped')

    local id = UgAdmin.Internal.Reports.GetAll()[1].id

    H.Sent = {}
    run(MODERATOR, Action.Reports, nil, {
        report = id,
        op = 'close',
    })

    for _, sent in ipairs(H.SentOf('Notify')) do
        H.Assert(sent.source ~= PLAYER, 'notified a source that left')
    end
end)

H.Test('spectate joins the target bucket, steps over higher ranks and brings the staff member back', function()
    boot()

    H.Bucket[PLAYER] = 7
    H.Equal({ run(MODERATOR, Action.Spectate, PLAYER) }, { true, nil })
    H.Equal(H.Bucket[MODERATOR], 7)
    H.Equal(H.SentOf('Spectate')[1].args[1], PLAYER)

    -- From 4 the next is 1 (founder) then 3 (admin): both outrank the moderator, so it wraps to nobody else.
    H.Equal({ UgAdmin.Internal.Spectate.Step(MODERATOR, 1) }, { false, Errors.NotFound })

    H.Equal(UgAdmin.Internal.Spectate.Stop(MODERATOR), true)
    H.Equal(H.Bucket[MODERATOR], 0)
    H.Equal(H.SentOf('Teleport')[1].args[1], vector3(200.0, 200.0, 30.0))
    H.Equal({ run(MODERATOR, Action.Spectate, ADMIN) }, { false, Errors.NoPermission })
end)

H.Test('vehicles spawn from the type the client reports, unknown types are refused', function()
    boot()

    H.ClientAnswers.VehicleType = function()
        return 'spaceship'
    end
    H.Equal({
        run(ADMIN, Action.Car, nil, {
            model = 'sultan',
        }),
    }, { false, Errors.NotFound })

    H.ClientAnswers.VehicleType = function(_, model)
        return model == 'sultan' and 'automobile' or ''
    end
    H.NativeReturns.CreateVehicleServerSetter = 900

    H.Equal({
        run(ADMIN, Action.Car, nil, {
            model = 'sultan',
        }),
    }, { true, nil })
    H.Equal(H.CallsOf('CreateVehicleServerSetter')[1].args[2], 'automobile')
    H.Equal(H.CallsOf('SetPedIntoVehicle')[1].args, { 103, 900, -1 })

    run(ADMIN, Action.Car, nil, {
        model = 'sultan',
    })
    H.Equal(H.CallsOf('DeleteEntity')[1].args, { 900 })
end)

H.Test('the Run callback rejects unknown actions and argument fields before any check', function()
    boot()

    H.Equal({ H.Call('Run', ADMIN, 'nuke', PLAYER) }, { nil, Errors.InvalidArgs })
    H.Equal({
        H.Call('Run', ADMIN, 'kick', PLAYER, {
            reason = 'x',
            amount = 'lots',
        }),
    }, { nil, Errors.InvalidArgs })
    H.Equal({
        H.Call('Run', ADMIN, 'kick', PLAYER, {
            reason = 'x',
            price = 1,
        }),
    }, { nil, Errors.InvalidArgs })
    H.Equal(H.Call('Run', ADMIN, 'kick', PLAYER, {
        reason = 'x',
    }), {
        ok = true,
    })
end)

H.Test('the panel snapshot is for staff only and hides IP addresses', function()
    boot()

    H.Equal(H.Call('Snapshot', PLAYER), nil)

    local snapshot = H.Call('Snapshot', MODERATOR)

    H.Equal(#snapshot.players, 4)
    H.Equal(snapshot.players[4].id, PLAYER)
    H.Equal(snapshot.catalog.groups[1].name, 'admin')

    local details = H.Call('Inspect', MODERATOR, PLAYER)

    H.Equal(details.identifiers, { 'license:4' })
end)

H.Test('logs come from the database newest first, and from memory when it is down', function()
    boot()

    run(ADMIN, Action.Kick, PLAYER, {
        reason = 'one',
    })
    run(ADMIN, Action.Warn, PLAYER, {
        reason = 'two',
    })

    local entries = H.Call('Logs', MODERATOR)

    H.Equal(entries[1].detail, 'two')
    H.Equal(entries[2].action, 'kick')

    H.DbReady = false
    H.Equal(#H.Call('Logs', MODERATOR, 'one'), 1)
    H.Equal(H.Call('Logs', PLAYER), nil)
end)

H.Test('commands build the same arguments as the panel', function()
    boot()

    H.Command('tp', ADMIN, {
        x = 10,
        y = 20,
    })
    H.Equal(H.SentOf('Teleport')[1].args, { vector3(10.0, 20.0, 0.0), false })

    H.Equal(H.Command('ban', MODERATOR, {
        target = PLAYER,
        duration = '1d',
        reason = 'x',
    }), false)
    H.Command('givemoney', ADMIN, {
        target = PLAYER,
        account = 'cash',
        amount = 5,
    })
    H.Equal(H.Balances[PLAYER].cash, 105)

    H.EmitCore(UgCore.Enums.Events.Commands.Failed, MODERATOR, 'kick', Errors.InvalidArgs, 1)
    H.Equal(lastNotice(MODERATOR), 'error.invalid_args')

    H.Sent = {}
    H.EmitCore(UgCore.Enums.Events.Commands.Failed, MODERATOR, 'someone-elses', Errors.InvalidArgs, 1)
    H.Equal(#H.Sent, 0)
end)

H.Test('/spectate without an id stops watching', function()
    boot()

    H.Command('spectate', MODERATOR, {
        target = PLAYER,
    })
    H.Command('spectate', MODERATOR, {})

    H.Equal(UgAdmin.Internal.Spectate.TargetOf(MODERATOR), nil)
    H.Equal(H.SentOf('Spectate')[2].args[1], nil)
end)

H.Test('only staff with vision on receive the radar', function()
    boot()

    H.Equal(UgAdmin.Internal.Radar.Tick(), 0)

    run(MODERATOR, Action.Vision)
    H.Equal(UgAdmin.Internal.Radar.Tick(), 1)

    local radar = H.SentOf('Radar')

    H.Equal(radar[1].source, MODERATOR)
    H.Equal(#radar[1].args[1], 4)
    H.Equal(radar[1].args[1][1].staff, true)
    H.Equal(radar[1].args[1][4].staff, false)
end)

H.Test('deleting an entity never deletes a player', function()
    boot()

    H.NativeReturns.NetworkGetEntityFromNetworkId = 500
    H.NativeReturns.GetEntityType = 1
    H.NativeReturns.IsPedAPlayer = true
    H.Equal({
        run(ADMIN, Action.DeleteEntity, nil, {
            netId = 12,
        }),
    }, { false, Errors.NotFound })

    H.NativeReturns.GetEntityType = 2
    H.NativeReturns.GetEntityModel = 77
    H.Equal({
        run(ADMIN, Action.DeleteEntity, nil, {
            netId = 12,
        }),
    }, { true, nil })
    H.Equal(H.CallsOf('DeleteEntity')[1].args, { 500 })
end)

H.Test('deleting a map prop hides it for everyone, once, near the staff member only', function()
    boot()

    local key = UgAdmin.Enums.GlobalState.HiddenProps
    local near = vector3(110.0, 100.0, 30.0)
    ---@return { version: integer, props: table[] }
    local function hidden()
        return GlobalState[key] --[[@as { version: integer, props: table[] }]]
    end

    H.Equal({ run(ADMIN, Action.DeleteEntity, nil, {}) }, { false, Errors.InvalidArgs })
    H.Equal({
        run(ADMIN, Action.DeleteEntity, nil, {
            coords = vector3(5000.0, 5000.0, 30.0),
            hash = 7,
        }),
    }, { false, Errors.NotFound })
    H.Equal(GlobalState[key], nil)

    -- An unsigned hash is stored signed, so the same model compares equal.
    H.Equal({
        run(ADMIN, Action.DeleteEntity, nil, {
            coords = near,
            hash = 4294967295,
        }),
    }, { true, nil })
    H.Equal(hidden().props, {
        {
            x = 110.0,
            y = 100.0,
            z = 30.0,
            hash = -1,
        },
    })

    local version = hidden().version

    H.Equal({
        run(ADMIN, Action.DeleteEntity, nil, {
            coords = near + vector3(0.2, 0.0, 0.0),
            hash = -1,
        }),
    }, { true, nil })
    H.Equal(#hidden().props, 1)
    H.Equal(hidden().version, version)
end)

---Runs fn with os.time frozen at a clock it can move. The real clock comes back even when fn fails.
---@param fn fun(advance: fun(seconds: integer))
local function withClock(fn)
    local real, now = os.time, os.time()

    os.time = function()
        return now
    end

    local ok, message = pcall(fn, function(seconds)
        now = now + seconds
    end)

    os.time = real
    assert(ok, message)
end

local JAIL = vector3(1767.4, 2500.7, 45.7)
local RELEASE = vector3(1848.1, 2586.1, 45.7)

H.Test('live stats reach the client, and needs and balances are set to exact values', function()
    boot()

    H.Equal({
        run(ADMIN, Action.SetStats, PLAYER, {
            health = 150,
            armor = 50,
        }),
    }, { true, nil })
    H.Equal(H.SentOf('Stats')[1], {
        source = PLAYER,
        name = 'Stats',
        args = { 150, 50 },
    })
    H.Equal({ run(ADMIN, Action.SetStats, PLAYER, {}) }, { false, Errors.InvalidArgs })
    H.Equal({
        run(MODERATOR, Action.SetStats, PLAYER, {
            armor = 10,
        }),
    }, { false, Errors.NoPermission })

    -- A health value never brings back the dead: revive does.
    H.Players[PLAYER].state = UgCore.Enums.DeathState.Dead
    H.Equal({
        run(ADMIN, Action.SetStats, PLAYER, {
            health = 200,
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(ADMIN, Action.SetStats, PLAYER, {
            armor = 100,
        }),
    }, { true, nil })

    H.Equal({
        run(ADMIN, Action.SetNeed, PLAYER, {
            need = 'hunger',
            value = 25,
        }),
    }, { true, nil })
    H.Equal(H.CoreCallsOf('SetNeed'), { { PLAYER, 'hunger', 25 } })
    H.Equal({
        run(ADMIN, Action.SetNeed, PLAYER, {
            need = 'mana',
            value = 25,
        }),
    }, { false, Errors.NotFound })

    H.Equal({
        run(ADMIN, Action.SetMoney, PLAYER, {
            account = 'cash',
            amount = 1234,
        }),
    }, { true, nil })
    H.Equal(H.Balances[PLAYER].cash, 1234)
    H.Equal(H.Ledger[1], {
        target = PLAYER,
        account = 'cash',
        amount = 1134,
        reason = 'ug-admin',
    })
    H.Equal({
        run(ADMIN, Action.SetMoney, PLAYER, {
            account = 'cash',
            amount = -5,
        }),
    }, { false, Errors.InvalidArgs })
    H.Equal({
        run(ADMIN, Action.SetMoney, PLAYER, {
            account = 'debt',
            amount = -50,
        }),
    }, { true, nil })
    H.Equal({
        run(ADMIN, Action.SetMoney, PLAYER, {
            account = 'gold',
            amount = 1,
        }),
    }, { false, Errors.NotFound })
end)

H.Test('removing an item takes from one slot, never more than it holds', function()
    boot()

    H.Equal({
        run(ADMIN, Action.RemoveItem, PLAYER, {
            slot = 1,
            count = 5,
        }),
    }, { true, nil })
    H.Equal(H.CoreCallsOf('RemoveFromSlot'), { { PLAYER, 1, 2, 'ug-admin' } })
    H.Equal({
        run(ADMIN, Action.RemoveItem, PLAYER, {
            slot = 9,
        }),
    }, { false, Errors.NotFound })
    H.Equal({
        run(ADMIN, Action.RemoveItem, FOUNDER, {
            slot = 1,
        }),
    }, { false, Errors.NoPermission })
end)

H.Test('opening an inventory shows another player only, never the staff member themselves', function()
    boot()

    H.Equal({ run(ADMIN, Action.OpenInventory, PLAYER) }, { true, nil })
    H.Equal(#H.CoreCallsOf('OpenInventory'), 1)
    H.Equal(H.CoreCallsOf('OpenInventory')[1][1], ADMIN)
    H.Equal({ run(ADMIN, Action.OpenInventory, ADMIN) }, { false, Errors.InvalidArgs })
    H.Equal(#H.CoreCallsOf('OpenInventory'), 1, 'own pockets are already on the left')
end)

H.Test('jail holds a player, brings escapees back, survives a reconnect and releases on time', function()
    withClock(function(advance)
        boot()

        H.Equal({
            run(MODERATOR, Action.Jail, PLAYER, {
                minutes = 2,
                reason = 'rdm',
            }),
        }, { true, nil })
        H.Equal(H.SentOf('Teleport')[1].args, { JAIL, true })
        H.Equal(lastNotice(PLAYER), 'jail.start')
        H.Equal(H.Sanctions['license:4/jail'].remaining, 120)
        H.Equal(H.Rows[1].detail, '2m, rdm')

        H.Equal({
            run(MODERATOR, Action.Jail, ADMIN, {
                minutes = 2,
            }),
        }, { false, Errors.NoPermission })
        H.Equal({
            run(MODERATOR, Action.Jail, MODERATOR, {
                minutes = 2,
            }),
        }, { false, Errors.InvalidArgs })

        H.PedCoords[PLAYER] = JAIL
        UgAdmin.Internal.Sanctions.Tick()
        H.Equal(#H.SentOf('Teleport'), 1)

        H.PedCoords[PLAYER] = vector3(400.0, 400.0, 30.0)
        UgAdmin.Internal.Sanctions.Tick()
        H.Equal(#H.SentOf('Teleport'), 2)
        H.Equal(lastNotice(PLAYER), 'jail.escape')

        -- Time served offline does not count.
        advance(30)
        source = PLAYER
        H.TriggerEvent('playerDropped')
        H.Equal(UgAdmin.Internal.Sanctions.Remaining(PLAYER, UgAdmin.Enums.Sanction.Jail), nil)
        H.Equal(H.Sanctions['license:4/jail'].remaining, 90)

        advance(3600)
        UgAdmin.Internal.Sanctions.Load(PLAYER)
        H.Equal(UgAdmin.Internal.Sanctions.Remaining(PLAYER, UgAdmin.Enums.Sanction.Jail), 90)
        H.Equal(H.SentOf('Teleport')[3].args, { JAIL, true })
        H.Equal(H.Call('Snapshot', MODERATOR).players[4].jailed, 90)

        advance(91)
        UgAdmin.Internal.Sanctions.Tick()
        H.Equal(UgAdmin.Internal.Sanctions.Remaining(PLAYER, UgAdmin.Enums.Sanction.Jail), nil)
        H.Equal(H.SentOf('Teleport')[4].args, { RELEASE, true })
        H.Equal(lastNotice(PLAYER), 'jail.end')
        H.Equal(H.Sanctions['license:4/jail'], nil)
        H.Equal({ run(MODERATOR, Action.Unjail, PLAYER) }, { false, Errors.NotFound })
    end)
end)

H.Test('mute blocks chat and reports until staff lift it', function()
    boot()

    H.Equal({
        run(MODERATOR, Action.Mute, PLAYER, {
            minutes = 5,
        }),
    }, { true, nil })
    H.TriggerEvent('chatMessage', PLAYER, 'Player4', 'hello')
    H.Equal(#H.CallsOf('CancelEvent'), 1)
    H.Equal(lastNotice(PLAYER), 'mute.active')

    H.Command('report', PLAYER, {
        message = 'let me talk',
    })
    H.Equal(#UgAdmin.Internal.Reports.GetAll(), 0)
    H.Equal(lastNotice(PLAYER), 'mute.active')
    H.Equal(H.Call('Report', PLAYER, 'let me talk'), {
        ok = false,
        error = Errors.NoPermission,
    })

    H.Equal({ run(MODERATOR, Action.Unmute, PLAYER) }, { true, nil })
    H.Equal(lastNotice(PLAYER), 'mute.end')
    H.Equal({ run(MODERATOR, Action.Unmute, PLAYER) }, { false, Errors.NotFound })
    H.TriggerEvent('chatMessage', PLAYER, 'Player4', 'thanks')
    H.Equal(#H.CallsOf('CancelEvent'), 1)
end)

H.Test('a private message reaches one screen, and the details show history, notes, needs and sanctions', function()
    boot()

    H.Equal({
        run(MODERATOR, Action.Message, PLAYER, {
            text = 'meet me at Legion',
        }),
    }, { true, nil })
    H.Equal(H.SentOf('Shard')[1], {
        source = PLAYER,
        name = 'Shard',
        args = { 'message', 'meet me at Legion' },
    })

    H.Equal({
        run(MODERATOR, Action.Note, PLAYER, {
            text = 'warned twice for RDM',
        }),
    }, { true, nil })
    H.Equal(#H.Rows, 1)

    local details = H.Call('Inspect', MODERATOR, PLAYER)

    H.Equal(details.history[1].action, 'dm')
    H.Equal(details.notes[1].text, 'warned twice for RDM')
    H.Equal(details.notes[1].authorName, 'Player2')
    H.Equal(details.needs, {
        hunger = 80,
        thirst = 60,
    })
    H.Equal(details.armor, 0)
    H.Equal(H.Call('Inspect', MODERATOR, ADMIN).history, {})

    local id = details.notes[1].id

    H.Equal({
        run(MODERATOR, Action.DeleteNote, nil, {
            note = id,
        }),
    }, { false, Errors.NoPermission })
    H.Equal({
        run(ADMIN, Action.DeleteNote, nil, {
            note = id,
        }),
    }, { true, nil })
    H.Equal({
        run(ADMIN, Action.DeleteNote, nil, {
            note = id,
        }),
    }, { false, Errors.NotFound })
    H.Equal(H.Call('Inspect', MODERATOR, PLAYER).notes, {})
end)

H.Test('send to takes players to config places or the staff waypoint', function()
    boot()

    H.Equal({
        run(MODERATOR, Action.SendTo, PLAYER, {
            location = 'hospital',
        }),
    }, { true, nil })
    H.Equal(H.SentOf('Teleport')[1], {
        source = PLAYER,
        name = 'Teleport',
        args = { vector3(298.6, -584.5, 43.3), true },
    })
    H.Equal({
        run(MODERATOR, Action.SendTo, PLAYER, {
            location = 'nowhere',
        }),
    }, { false, Errors.NotFound })
    H.Equal({
        run(MODERATOR, Action.SendTo, PLAYER, {
            location = 'waypoint',
        }),
    }, { false, Errors.NotFound })

    H.ClientAnswers.Waypoint = function()
        return vector3(10.0, 20.0, 0.0)
    end
    H.Equal({
        run(MODERATOR, Action.SendTo, PLAYER, {
            location = 'waypoint',
        }),
    }, { true, nil })
    H.Equal(H.SentOf('Teleport')[2].args, { vector3(10.0, 20.0, 0.0), false })

    local catalog = H.Call('Snapshot', MODERATOR).catalog

    H.Equal(catalog.locations[1], {
        name = 'airport',
        label = 'Airport',
    })
    H.Equal(catalog.needs, {
        {
            name = 'hunger',
            label = 'Hunger',
        },
        {
            name = 'thirst',
            label = 'Thirst',
        },
    })

    local lines = boot("return { locations = { waypoint = { label = 'Mine', coords = vector3(0.0, 0.0, 0.0) } } }")

    H.ExpectLine(lines, 'Config invalid: 1 error(s). ug-admin stays off.')
end)

H.Test('actions on everyone revive the fallen, and bring and freeze only who the staff member outranks', function()
    boot()

    H.Players[FOUNDER].state = UgCore.Enums.DeathState.Dead
    H.Players[PLAYER].state = UgCore.Enums.DeathState.Downed
    H.Equal({ run(ADMIN, Action.ReviveAll) }, { true, nil })
    H.Equal(#H.CoreCallsOf('Revive'), 2)
    H.Equal({ run(ADMIN, Action.ReviveAll) }, { false, Errors.NotFound })

    H.Equal({
        run(ADMIN, Action.BringAll, nil, {
            radius = 100,
        }),
    }, { false, Errors.NotFound })
    H.Equal({ run(ADMIN, Action.BringAll) }, { true, nil })

    local brought = H.SentOf('Teleport')

    H.Equal({ brought[1].source, brought[2].source, #brought }, { MODERATOR, PLAYER, 2 })
    H.Equal(brought[1].args[1], vector3(302.0, 300.0, 30.0))

    run(ADMIN, Action.FreezeAll)
    H.Equal({ H.State[MODERATOR][StateBags.Frozen], H.State[PLAYER][StateBags.Frozen] }, { true, true })
    H.Equal(H.State[FOUNDER][StateBags.Frozen], nil)

    run(ADMIN, Action.FreezeAll)
    H.Equal({ H.State[MODERATOR][StateBags.Frozen], H.State[PLAYER][StateBags.Frozen] }, { nil, nil })
end)

H.Test('look tables merge onto the defaults, shards replace', function()
    H.Reset()
    H.Files['config.lua'] = [[
        return {
            layout = { rail = 'right' },
            noclip = { fov = 75.0 },
            spectate = { swoop = false },
            shards = { announce = { duration = 4000, color = 'green' } },
            tabs = { 'players', 'logs' },
        }
    ]]
    H.Load('server')

    local config = UgAdmin.Internal.Config.Get()
    local defaults = UgAdmin.Internal.Defaults()

    H.Equal(config.layout.rail, 'right')
    H.Equal(config.layout.width, defaults.layout.width)
    H.Equal(config.noclip.fov, 75.0)
    H.Equal(config.noclip.boost, defaults.noclip.boost)
    H.Equal(config.spectate.swoop, false)
    H.Equal(config.spectate.swoopHeight, 90.0)
    H.Equal(config.shards, {
        announce = {
            duration = 4000,
            color = 'green',
        },
    })
    H.Equal(config.tabs, { 'players', 'logs' })
end)

H.Test('bad look values are reported', function()
    H.Reset()
    H.Files['config.lua'] = [[
        return {
            layout = { rail = 'top' },
            noclip = { fov = 500 },
            shards = { announce = { duration = 4000, color = 'pink' } },
            tabs = { 'players', 'bank' },
            theme = { colors = { violet = '#ff00ff' } },
            invisibleAlpha = 300,
        }
    ]]

    local lines = H.Load('server')

    for _, key in ipairs({ 'layout', 'noclip', 'shards', 'tabs', 'theme', 'invisibleAlpha' }) do
        H.ExpectLine(lines, key)
    end
end)

H.Done()
