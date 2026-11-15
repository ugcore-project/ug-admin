--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Player reports with a chat between the reporter and staff. A player opens one with /report or the report window;
-- staff claim it, answer, go to the player or bring them, send everyone back, and close it. The reporter rates the
-- help. Reports live for the session: the audit log keeps what staff did with them.

---@class UgAdmin.Internal.Reports
local Reports = {}
UgAdmin.Internal.Reports = Reports

---@class UgAdminReportMessage
---@field author UgAdminReportAuthor
---@field name string
---@field text string a UgAdminReportEvent for system lines
---@field at integer Unix seconds
---@field to? string staff name an Assigned line handed the report to
---@field mentions? integer[] sources of the staff a staff line pinged

---@class UgAdminReport
---@field id integer
---@field source integer 0 once the reporter left
---@field name string
---@field message string the first message
---@field category UgAdminReportCategory
---@field accused? integer source of the player reported, 0 once they left
---@field accusedName? string
---@field coords vector3 where the reporter stood when they opened it
---@field status UgAdminReportStatus
---@field claimer? integer source of the staff member handling it
---@field claimedBy? string staff name
---@field closedBy? string staff name, nil when the reporter cancelled
---@field at integer Unix seconds
---@field claimedAt? integer
---@field closedAt? integer
---@field rating? integer 1 to 5
---@field messages UgAdminReportMessage[] oldest first
---@field visits table<integer, vector3> where each staff member stood before they went to the reporter
---@field from? vector3 where the reporter stood before staff brought them

local Config = UgAdmin.Internal.Config
local Staff = UgAdmin.Internal.Staff
local Notify = UgAdmin.Internal.Notify
local World = UgAdmin.Internal.World
local Audit = UgAdmin.Internal.Audit
local Status = UgAdmin.Enums.ReportStatus
local Op = UgAdmin.Enums.ReportOp
local Category = UgAdmin.Enums.ReportCategory
local Author = UgAdmin.Enums.ReportAuthor
local ReportEvent = UgAdmin.Enums.ReportEvent
local Action = UgAdmin.Enums.Action
local Mode = UgAdmin.Enums.Mode
local ClientEvents = UgAdmin.Enums.ClientEvents
local Errors = UgCore.Enums.Errors
local Logger = UgCore.Logger
local NotifyType = UgLib.Enums.NotifyType

local RESOURCE = GetCurrentResourceName()
local STAFF_EVENT = RESOURCE .. ':' .. ClientEvents.Reports
local OWN_EVENT = RESOURCE .. ':' .. ClientEvents.MyReport
local WINDOW_EVENT = RESOURCE .. ':' .. ClientEvents.ReportWindow
local CONSOLE = 0
-- Lines kept per report. The first message stays in `message`, so old lines MAY go.
local MAX_MESSAGES = 60
-- Closed reports staff still see, newest first.
local CLOSED_SHOWN = 15
-- Seconds a reporter has to rate a closed report.
local RATE_WINDOW = 600
-- Characters of a message in a notification.
local PREVIEW = 80
-- Staff one chat line MAY ping.
local MAX_MENTIONS = 5

---@type UgAdminReport[] oldest first
local list = {}
---@type table<integer, integer> source -> GetGameTimer() of their last new report
local lastAt = {}
local nextId = 0

---@param id integer
---@return UgAdminReport?
local function find(id)
    for _, report in ipairs(list) do
        if report.id == id then
            return report
        end
    end

    return nil
end

---The report a player has open or claimed.
---@param source integer
---@return UgAdminReport?
local function activeOf(source)
    for _, report in ipairs(list) do
        if report.source == source and report.status ~= Status.Closed then
            return report
        end
    end

    return nil
end

---@param text string
---@return string
local function preview(text)
    return utf8.len(text) and utf8.len(text) > PREVIEW and (text:sub(1, utf8.offset(text, PREVIEW - 2) - 1) .. '...') or text
end

---@param report UgAdminReport
---@param author UgAdminReportAuthor
---@param name string
---@param text string
---@param extra? { to?: string, mentions?: integer[] }
local function append(report, author, name, text, extra)
    report.messages[#report.messages + 1] = {
        author = author,
        name = name,
        text = text,
        at = os.time(),
        to = extra and extra.to,
        mentions = extra and extra.mentions,
    }

    if #report.messages > MAX_MESSAGES then
        table.remove(report.messages, 1)
    end
end

---A copy of the chat, so a page never holds the server's tables. Only staff learn who was pinged.
---@param report UgAdminReport
---@param staff boolean
---@return UgAdminReportMessage[]
local function messagesOf(report, staff)
    local copy = {}

    for index, message in ipairs(report.messages) do
        copy[index] = {
            author = message.author,
            name = message.name,
            text = message.text,
            at = message.at,
            to = message.to,
            mentions = staff and message.mentions and { table.unpack(message.mentions) } or nil,
        }
    end

    return copy
end

---What staff see. Positions stay on the server: the page only learns who has a way back.
---@param report UgAdminReport
---@return table
local function staffView(report)
    local visitors = {}

    for source in pairs(report.visits) do
        visitors[#visitors + 1] = source
    end

    table.sort(visitors)

    return {
        id = report.id,
        source = report.source,
        name = report.name,
        message = report.message,
        category = report.category,
        accused = report.accused,
        accusedName = report.accusedName,
        status = report.status,
        claimer = report.claimer,
        claimedBy = report.claimedBy,
        closedBy = report.closedBy,
        at = report.at,
        claimedAt = report.claimedAt,
        closedAt = report.closedAt,
        rating = report.rating,
        messages = messagesOf(report, true),
        visitors = visitors,
        brought = report.from ~= nil,
    }
end

---What the reporter sees: no sources, no positions.
---@param report UgAdminReport
---@return table
local function ownView(report)
    return {
        id = report.id,
        message = report.message,
        category = report.category,
        accusedName = report.accusedName,
        status = report.status,
        claimedBy = report.claimedBy,
        closedBy = report.closedBy,
        at = report.at,
        rating = report.rating,
        messages = messagesOf(report, false),
    }
end

---Open and claimed reports, oldest first.
---@return UgAdminReport[]
function Reports.GetAll()
    local active = {}

    for _, report in ipairs(list) do
        if report.status ~= Status.Closed then
            active[#active + 1] = report
        end
    end

    return active
end

---What the panel lists: every open and claimed report, then the latest closed ones.
---@return table[]
function Reports.List()
    local views, closed = {}, {}

    for _, report in ipairs(list) do
        if report.status ~= Status.Closed then
            views[#views + 1] = staffView(report)
        else
            closed[#closed + 1] = report
        end
    end

    for index = #closed, math.max(1, #closed - CLOSED_SHOWN + 1), -1 do
        views[#views + 1] = staffView(closed[index])
    end

    return views
end

---Sends the list to every staff member who handles reports, and the report to its reporter.
---@param report? UgAdminReport the one that changed
local function broadcast(report)
    local views = Reports.List()

    for _, source in ipairs(Staff.With(Action.Reports)) do
        UgCore.Network.TriggerClient(source, STAFF_EVENT, views)
    end

    if report and report.source ~= 0 then
        -- A cancelled or rated report is over for the reporter. A closed one stays until they rate it.
        local over = report.status == Status.Closed and (report.rating ~= nil or report.closedBy == nil)

        UgCore.Network.TriggerClient(report.source, OWN_EVENT, not over and ownView(report) or nil)
    end
end

---True for staff who handle reports and are on duty. The console always is.
---@param source integer
---@return boolean
function Reports.IsOnDuty(source)
    return source == CONSOLE or (Staff.Can(source, Action.Reports) and Staff.HasMode(source, Mode.Duty))
end

---Staff on duty, sorted by source.
---@return integer[]
local function onDuty()
    local list = {}

    for _, source in ipairs(Staff.With(Action.Reports)) do
        if Staff.HasMode(source, Mode.Duty) then
            list[#list + 1] = source
        end
    end

    return list
end

---Puts a staff member on duty when they join, if the config says so.
---@param source integer
function Reports.StartDuty(source)
    if Config.Get().startOnDuty and Staff.Can(source, Action.Duty) and not Staff.HasMode(source, Mode.Duty) then
        Staff.SetMode(source, Mode.Duty, true)
    end
end

---Tells staff about a report. Once claimed, only the staff member handling it; before, staff on duty.
---@param report UgAdminReport
---@param key string
---@param vars table
---@param kind UgNotifyType
local function tellStaff(report, key, vars, kind)
    if report.claimer then
        Notify.Send(report.claimer, key, vars, kind)

        return
    end

    for _, source in ipairs(onDuty()) do
        Notify.Send(source, key, vars, kind)
    end
end

---@param report UgAdminReport
---@param key string
---@param vars? table
---@param kind? UgNotifyType
local function tellReporter(report, key, vars, kind)
    if report.source ~= 0 and UgCore.Players.Get(report.source) then
        Notify.Send(report.source, key, vars, kind)
    end
end

---Turns `@<id>` of staff into `@<name>` and pings each of them once, on duty or not. Other `@` stay as typed.
---@param report UgAdminReport
---@param actor integer
---@param staffName string
---@param text string
---@return string text
---@return integer[]? mentions
local function mention(report, actor, staffName, text)
    local mentions, seen = {}, {}

    local resolved = text:gsub('@(%d+)', function(digits)
        local target = math.tointeger(tonumber(digits))

        if not target or target == actor or not UgCore.Players.Get(target) or not Staff.Can(target, Action.Reports) then
            return nil
        end

        if not seen[target] then
            if #mentions >= MAX_MENTIONS then
                return nil
            end

            seen[target] = true
            mentions[#mentions + 1] = target
        end

        return '@' .. UgAdmin.Internal.NameOf(target)
    end)

    for _, target in ipairs(mentions) do
        Notify.Send(target, 'report.mention', {
            id = report.id,
            name = staffName,
            text = preview(resolved),
        }, NotifyType.Warning)
    end

    return resolved, #mentions > 0 and mentions or nil
end

---Drops closed reports first, then the oldest open ones, past the limit.
local function trim()
    local limit = Config.Get().maxReports

    while #list > limit do
        local removed = false

        for index, entry in ipairs(list) do
            if entry.status == Status.Closed then
                table.remove(list, index)
                removed = true

                break
            end
        end

        if not removed then
            table.remove(list, 1)
        end
    end
end

---@param source integer
---@return UgErrorCode? errorCode `no_permission` while muted
local function muted(source)
    if UgAdmin.Internal.Sanctions.Remaining(source, UgAdmin.Enums.Sanction.Mute) then
        return Errors.NoPermission
    end

    return nil
end

---Adds a line from the reporter to their report.
---@param source integer
---@param text string validated, 1 to 256 characters
---@return boolean ok
---@return UgErrorCode? errorCode
function Reports.Reply(source, text)
    local refused = muted(source)

    if refused then
        return false, refused
    end

    local report = activeOf(source)

    if not report then
        return false, Errors.NotFound
    end

    append(report, Author.Player, report.name, text)
    tellStaff(report, 'report.message', {
        id = report.id,
        name = report.name,
        text = preview(text),
    }, NotifyType.Info)
    broadcast(report)

    return true, nil
end

---Opens a report for a player. With one open already, the message joins its chat.
---@param source integer
---@param message string validated, 1 to 256 characters
---@param category? UgAdminReportCategory defaults to other
---@param accused? integer source of a player they report
---@return boolean ok
---@return UgErrorCode? errorCode `rate_limited` during the cooldown, `no_permission` while muted
---@return boolean? told true when the player was already told why it failed
function Reports.Open(source, message, category, accused)
    local refused = muted(source)

    if refused then
        return false, refused
    end

    if activeOf(source) then
        return Reports.Reply(source, message)
    end

    local now = GetGameTimer()

    if lastAt[source] and now - lastAt[source] < Config.Get().reportCooldown * 1000 then
        return false, Errors.RateLimited
    end

    local coords = World.CoordsOf(source)

    if not coords then
        return false, Errors.NotLoaded
    end

    if accused == source then
        Notify.Send(source, 'report.accusedSelf', nil, NotifyType.Error)

        return false, Errors.InvalidArgs, true
    end

    if accused and not UgCore.Players.Get(accused) then
        Notify.Send(source, 'report.accusedMissing', {
            id = accused,
        }, NotifyType.Error)

        return false, Errors.NotFound, true
    end

    nextId = nextId + 1
    lastAt[source] = now

    ---@type UgAdminReport
    local report = {
        id = nextId,
        source = source,
        name = UgAdmin.Internal.NameOf(source),
        message = message,
        category = category or Category.Other,
        accused = accused,
        accusedName = accused and UgAdmin.Internal.NameOf(accused) or nil,
        coords = coords,
        status = Status.Open,
        at = os.time(),
        messages = {},
        visits = {},
    }

    append(report, Author.Player, report.name, message)
    list[#list + 1] = report
    trim()

    local staff = onDuty()

    for _, source in ipairs(staff) do
        Notify.Send(source, 'report.new', {
            id = report.id,
            name = report.name,
            text = preview(message),
        }, NotifyType.Warning)
    end

    if #staff == 0 then
        Notify.Send(source, 'report.noStaff', nil, NotifyType.Info)
    end

    broadcast(report)
    UgCore.Events.Emit(UgAdmin.Enums.Events.Reported, report)

    return true, nil
end

---The reporter closes their own report, such as when the problem went away.
---@param source integer
---@return boolean ok
---@return UgErrorCode? errorCode
function Reports.Cancel(source)
    local report = activeOf(source)

    if not report then
        return false, Errors.NotFound
    end

    report.status, report.closedAt = Status.Closed, os.time()
    append(report, Author.System, report.name, ReportEvent.Cancelled)

    if report.claimer then
        Notify.Send(report.claimer, 'report.cancelled', {
            id = report.id,
            name = report.name,
        }, NotifyType.Info)
    end

    broadcast(report)

    return true, nil
end

---The reporter rates the help on their last closed report, once.
---@param source integer
---@param rating integer validated, 1 to 5
---@return boolean ok
---@return UgErrorCode? errorCode
function Reports.Rate(source, rating)
    local now = os.time()

    for index = #list, 1, -1 do
        local report = list[index]

        if report.source == source and report.status == Status.Closed and report.closedBy and not report.rating
            and now - (report.closedAt or 0) <= RATE_WINDOW then
            report.rating = rating
            broadcast(report)
            Logger.Info('Report #%d: %s rated %s %d/5.', report.id, report.name, report.closedBy, rating)
            UgCore.Events.Emit(UgAdmin.Enums.Events.ReportRated, report, rating)

            if report.claimer and UgCore.Players.Get(report.claimer) then
                Notify.Send(report.claimer, 'report.rated', {
                    id = report.id,
                    name = report.name,
                    rating = rating,
                }, NotifyType.Success)
            end

            return true, nil
        end
    end

    return false, Errors.NotFound
end

---Takes a report for a staff member. A report claimed by someone else changes hands.
---@param report UgAdminReport
---@param actor integer
---@param staffName string
---@return boolean changed
local function claim(report, actor, staffName)
    if report.status == Status.Claimed and report.claimer == actor then
        return false
    end

    report.status, report.claimer, report.claimedBy, report.claimedAt = Status.Claimed, actor, staffName, os.time()
    append(report, Author.System, staffName, ReportEvent.Claimed)
    tellReporter(report, 'report.claimed', {
        name = staffName,
    }, NotifyType.Info)

    return true
end

---Puts a report back in the queue.
---@param report UgAdminReport
---@param staffName string
local function release(report, staffName)
    report.status, report.claimer, report.claimedBy, report.claimedAt = Status.Open, nil, nil, nil
    append(report, Author.System, staffName, ReportEvent.Released)
end

---@alias UgAdminReportHandler fun(report: UgAdminReport, actor: integer, staffName: string, text?: string, staff?: integer): boolean, UgErrorCode?, boolean?, string?

-- Each returns ok, errorCode, true when the audit log records it, and what the log says when not the text.
---@type table<UgAdminReportOp, UgAdminReportHandler>
local OPS = {
    [Op.Claim] = function(report, actor, staffName)
        if not claim(report, actor, staffName) then
            return false, Errors.InvalidArgs
        end

        return true, nil, true
    end,

    [Op.Release] = function(report, _, staffName)
        if report.status ~= Status.Claimed then
            return false, Errors.InvalidArgs
        end

        release(report, staffName)

        return true, nil, true
    end,

    [Op.Reply] = function(report, actor, staffName, text)
        if not text then
            return false, Errors.InvalidArgs
        end

        if report.status == Status.Open and actor ~= CONSOLE then
            claim(report, actor, staffName)
        end

        local line, mentions = mention(report, actor, staffName, text)

        append(report, Author.Staff, staffName, line, {
            mentions = mentions,
        })
        tellReporter(report, 'report.reply', {
            name = staffName,
            text = preview(line),
        }, NotifyType.Info)

        return true, nil, false
    end,

    [Op.Goto] = function(report, actor, staffName)
        local here = World.CoordsOf(actor)
        local there = report.source ~= 0 and World.CoordsOf(report.source) or nil

        if not here or not there then
            return false, Errors.NotFound
        end

        -- A second trip keeps the first way back: that is where the staff member came from.
        report.visits[actor] = report.visits[actor] or here
        World.Teleport(actor, there, true)

        if report.status == Status.Open then
            claim(report, actor, staffName)
        end

        append(report, Author.System, staffName, ReportEvent.Arrived)
        tellReporter(report, 'report.arrived', {
            name = staffName,
        }, NotifyType.Info)

        return true, nil, true
    end,

    [Op.Return] = function(report, actor)
        local back = report.visits[actor]

        if not back then
            return false, Errors.NotFound
        end

        report.visits[actor] = nil
        World.Teleport(actor, back, true)

        return true, nil, false
    end,

    [Op.Bring] = function(report, actor, staffName)
        local here = World.CoordsOf(actor)
        local there = report.source ~= 0 and World.CoordsOf(report.source) or nil

        if not here or not there then
            return false, Errors.NotFound
        end

        if not Staff.Outranks(actor, report.source) then
            return false, Errors.NoPermission
        end

        report.from = report.from or there
        World.Teleport(report.source, here, true)

        if report.status == Status.Open then
            claim(report, actor, staffName)
        end

        append(report, Author.System, staffName, ReportEvent.Brought)

        return true, nil, true
    end,

    [Op.SendBack] = function(report, _, staffName)
        if not report.from or report.source == 0 or not World.CoordsOf(report.source) then
            return false, Errors.NotFound
        end

        World.Teleport(report.source, report.from, true)
        report.from = nil
        append(report, Author.System, staffName, ReportEvent.SentBack)

        return true, nil, false
    end,

    [Op.Close] = function(report, actor, staffName, text)
        if text then
            local line, mentions = mention(report, actor, staffName, text)

            append(report, Author.Staff, staffName, line, {
                mentions = mentions,
            })
        end

        report.status, report.closedBy, report.closedAt = Status.Closed, staffName, os.time()
        append(report, Author.System, staffName, ReportEvent.Closed)
        tellReporter(report, 'report.closed', {
            name = staffName,
        }, NotifyType.Success)

        return true, nil, true
    end,

    [Op.Assign] = function(report, actor, staffName, _, staff)
        -- Only staff on duty MAY take a report, so only they MAY get one.
        if not staff or staff == report.claimer or not UgCore.Players.Get(staff) or not Reports.IsOnDuty(staff) then
            return false, Errors.InvalidArgs
        end

        local name = UgAdmin.Internal.NameOf(staff)

        report.status, report.claimer, report.claimedBy, report.claimedAt = Status.Claimed, staff, name, os.time()
        append(report, Author.System, staffName, ReportEvent.Assigned, {
            to = name,
        })
        tellReporter(report, 'report.claimed', {
            name = name,
        }, NotifyType.Info)

        if staff ~= actor then
            Notify.Send(staff, 'report.assigned', {
                id = report.id,
                name = staffName,
                text = preview(report.message),
            }, NotifyType.Warning)
        end

        return true, nil, true, name
    end,
}

-- Ops that move the staff member or to them need a ped.
local NEEDS_PED = {
    [Op.Goto] = true,
    [Op.Return] = true,
    [Op.Bring] = true,
}
-- Ops that take the report, or act on the player as the one handling it. Off duty, staff MAY still release, close
-- and finish trips back.
local NEEDS_DUTY = {
    [Op.Claim] = true,
    [Op.Reply] = true,
    [Op.Goto] = true,
    [Op.Bring] = true,
}

---Gives back every report a staff member handles, such as when they go off duty.
---@param actor integer
---@return integer count released
function Reports.ReleaseAll(actor)
    local count = 0
    local staffName = UgAdmin.Internal.NameOf(actor)

    for _, report in ipairs(list) do
        if report.status == Status.Claimed and report.claimer == actor then
            release(report, staffName)
            count = count + 1
        end
    end

    if count > 0 then
        broadcast()

        for _, source in ipairs(onDuty()) do
            Notify.Send(source, 'report.released', {
                name = staffName,
                count = count,
            }, NotifyType.Warning)
        end
    end

    return count
end

---Runs a staff op on a report. Writes the audit log itself: chat lines and trips back are not logged.
---@param actor integer
---@param id integer
---@param op UgAdminReportOp
---@param text? string
---@param staff? integer the staff member an Assign hands the report to
---@return boolean ok
---@return UgErrorCode? errorCode
---@return string? detail
---@return table? vars
---@return boolean? told true when the staff member was already told why it failed
function Reports.Handle(actor, id, op, text, staff)
    local report = find(id)

    if not report or report.status == Status.Closed or not OPS[op] then
        return false, Errors.NotFound
    end

    if NEEDS_PED[op] and actor == CONSOLE then
        return false, Errors.InvalidArgs
    end

    if NEEDS_DUTY[op] and not Reports.IsOnDuty(actor) then
        Notify.Send(actor, 'duty.required', nil, NotifyType.Warning)

        return false, Errors.NoPermission, nil, nil, true
    end

    local staffName = UgAdmin.Internal.NameOf(actor)
    local ok, errorCode, logged, summary = OPS[op](report, actor, staffName, text, staff)

    if not ok then
        return false, errorCode
    end

    broadcast(report)

    local detail = ('#%d %s: %s'):format(id, op, summary or text or report.message)

    -- Chat lines and trips back are neither logged nor confirmed: the chat shows them.
    if logged then
        Audit.Record(actor, Action.Reports, report.source ~= 0 and report.source or nil, detail)
        Notify.Send(actor, 'result.reports', {
            id = id,
            op = Notify.Text('reportOp.' .. op),
        }, NotifyType.Success)
    end

    return true, nil, detail, {
        id = id,
    }
end

---Sends the list to one staff member, such as when they open the panel.
---@param source integer
function Reports.SendTo(source)
    UgCore.Network.TriggerClient(source, STAFF_EVENT, Reports.List())
end

---Opens the report window of a player, with their report when they have one.
---@param source integer
function Reports.ShowWindow(source)
    local report = activeOf(source)

    if report then
        UgCore.Network.TriggerClient(source, OWN_EVENT, ownView(report))
    end

    UgCore.Network.TriggerClient(source, WINDOW_EVENT)
end

AddEventHandler('playerDropped', function()
    local dropped = math.tointeger(tonumber(source))

    if not dropped then
        return
    end

    lastAt[dropped] = nil

    local changed = false

    -- Reports stay for staff. Source 0 means gone, so a player who gets the same source later is never notified.
    for _, report in ipairs(list) do
        if report.source == dropped then
            report.source, report.from, changed = 0, nil, true
        end

        if report.accused == dropped then
            report.accused, changed = 0, true
        end

        if report.visits[dropped] then
            report.visits[dropped], changed = nil, true
        end

        if report.claimer == dropped then
            if report.status == Status.Claimed then
                release(report, report.claimedBy or '?')
            end

            report.claimer, changed = nil, true
        end
    end

    if changed then
        broadcast()
    end
end)
