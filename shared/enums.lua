--[[

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Every magic value lives here. Error codes come from UgCore.Enums.Errors, never from strings.

---@class UgAdmin.Enums
UgAdmin.Enums = {}

---Every staff action. Values are the chat command names and the keys of `access` in config.lua.
---@enum UgAdminAction
UgAdmin.Enums.Action = {
    -- Self
    Panel = 'admin',
    Noclip = 'noclip',
    Vision = 'vision',
    God = 'god',
    Invisible = 'invisible',
    Waypoint = 'tpm',
    Coords = 'tp',
    Back = 'back',
    -- Players
    Goto = 'goto',
    Bring = 'bring',
    Spectate = 'spectate',
    Revive = 'revive',
    Heal = 'heal',
    Kill = 'kill',
    Freeze = 'freeze',
    Warn = 'warn',
    Kick = 'kick',
    Ban = 'ban',
    Unban = 'unban',
    Message = 'dm',
    SendTo = 'sendto',
    Jail = 'jail',
    Unjail = 'unjail',
    Mute = 'mute',
    Unmute = 'unmute',
    Note = 'note',
    DeleteNote = 'delnote',
    -- Character
    GiveMoney = 'givemoney',
    SetJob = 'setjob',
    SetGang = 'setgang',
    GiveItem = 'giveitem',
    ClearInventory = 'clearinv',
    OpenInventory = 'inventory',
    SetGroup = 'setgroup',
    RemoveGroup = 'removegroup',
    SetStats = 'setstats',
    SetNeed = 'setneed',
    SetMoney = 'setmoney',
    RemoveItem = 'removeitem',
    -- Everyone
    ReviveAll = 'reviveall',
    BringAll = 'bringall',
    FreezeAll = 'freezeall',
    -- World
    Car = 'car',
    DeleteVehicle = 'dv',
    Fix = 'fix',
    DeleteEntity = 'delentity',
    Announce = 'announce',
    -- Reports
    Reports = 'reports',
    Duty = 'duty',
}

---Toggles kept in the `ug-admin:Mode` statebag of a staff member. The server writes it, the client applies it.
---@enum UgAdminMode
UgAdmin.Enums.Mode = {
    Noclip = 'noclip',
    Vision = 'vision',
    God = 'god',
    Invisible = 'invisible',
    -- On duty: report alerts, and reports may be assigned to this staff member.
    Duty = 'duty',
}

---Statebag keys. Written by the server only.
---@enum UgAdminStateBag
UgAdmin.Enums.StateBags = {
    -- Player: { [UgAdminMode]: true } toggles that are on.
    Mode = 'ug-admin:Mode',
    -- Player: UgAdminAction[] the player may use, sorted. Drives keybinds and the panel buttons.
    Access = 'ug-admin:Access',
    -- Player: true while frozen by staff.
    Frozen = 'ug-admin:Frozen',
}

---GlobalState keys. Written by the server only.
---@enum UgAdminGlobalState
UgAdmin.Enums.GlobalState = {
    -- Owner config values that clients read.
    Config = 'ug-admin:Config',
    -- { version, props = { { x, y, z, hash } } }: map props staff deleted, hidden for everyone until restart.
    HiddenProps = 'ug-admin:HiddenProps',
}

---Sanctions that last a number of minutes. They count down while the player is online and survive reconnects.
---@enum UgAdminSanction
UgAdmin.Enums.Sanction = {
    Jail = 'jail',
    Mute = 'mute',
}

---What staff do with a report. Values are the `op` of /reports, 8 characters at most.
---@enum UgAdminReportOp
UgAdmin.Enums.ReportOp = {
    -- Take the report. Replying or going to the player claims it too.
    Claim = 'claim',
    -- Give it back to the queue.
    Release = 'release',
    -- Answer in the report chat. Needs `text`.
    Reply = 'reply',
    -- Teleport to the reporter. Remembers where the staff member was.
    Goto = 'goto',
    -- Teleport back to where the staff member was before Goto.
    Return = 'return',
    -- Teleport the reporter to the staff member. Remembers where the reporter was.
    Bring = 'bring',
    -- Teleport the reporter back to where they were before Bring.
    SendBack = 'sendback',
    -- Resolve it. An optional `text` is sent as the last message.
    Close = 'close',
    -- Hand it to a staff member on duty. Needs `staff`, or the staff id as `text` from /reports.
    Assign = 'assign',
}

---What a report is about. The player picks one.
---@enum UgAdminReportCategory
UgAdmin.Enums.ReportCategory = {
    Question = 'question',
    Player = 'player',
    Bug = 'bug',
    Stuck = 'stuck',
    Other = 'other',
}

---Who wrote a line of the report chat.
---@enum UgAdminReportAuthor
UgAdmin.Enums.ReportAuthor = {
    Player = 'player',
    Staff = 'staff',
    -- What happened, such as a claim. The text is a UgAdminReportEvent.
    System = 'system',
}

---Lines the server adds to the report chat. The page translates them.
---@enum UgAdminReportEvent
UgAdmin.Enums.ReportEvent = {
    Claimed = 'claimed',
    Released = 'released',
    Arrived = 'arrived',
    Brought = 'brought',
    SentBack = 'sentBack',
    Closed = 'closed',
    Cancelled = 'cancelled',
    -- The line carries `to`, the name of the staff member who got it.
    Assigned = 'assigned',
}

---Report states.
---@enum UgAdminReportStatus
UgAdmin.Enums.ReportStatus = {
    Open = 'open',
    Claimed = 'claimed',
    Closed = 'closed',
}

---Events this resource emits through UgCore.Events, on the server. Names MUST start with the resource name.
---@enum UgAdminEvent
UgAdmin.Enums.Events = {
    -- (entry: UgAdminLogEntry) after a staff action succeeded.
    Action = 'ug-admin:Action',
    -- (report: UgAdminReport) when a player opens a report.
    Reported = 'ug-admin:Reported',
    -- (report: UgAdminReport, rating: integer) when a player rates the help they got, 1 to 5.
    ReportRated = 'ug-admin:ReportRated',
}

---Server callbacks, without the `ug-admin:` prefix ug-core adds.
---@enum UgAdminCallback
UgAdmin.Enums.Callbacks = {
    Run = 'Run',
    Snapshot = 'Snapshot',
    Inspect = 'Inspect',
    Logs = 'Logs',
    Report = 'Report',
    -- Player side of a report: answer, cancel, rate.
    ReportReply = 'ReportReply',
    ReportCancel = 'ReportCancel',
    ReportRate = 'ReportRate',
    SpectateStep = 'SpectateStep',
    StopSpectate = 'StopSpectate',
}

---Server-to-client callbacks, answered by the staff member's client. Answers are untrusted.
---@enum UgAdminClientCallback
UgAdmin.Enums.ClientCallbacks = {
    -- (model) -> vehicle type for CreateVehicleServerSetter, '' for unknown models.
    VehicleType = 'VehicleType',
    -- () -> vector3 of the waypoint on the ground, vector3(0, 0, 0) without one.
    Waypoint = 'Waypoint',
}

---Net events the server sends to clients, without the `ug-admin:` prefix.
---@enum UgAdminClientEvent
UgAdmin.Enums.ClientEvents = {
    Notify = 'Notify',
    Panel = 'Panel',
    Teleport = 'Teleport',
    Heal = 'Heal',
    Fix = 'Fix',
    Spectate = 'Spectate',
    Radar = 'Radar',
    Shard = 'Shard',
    Reports = 'Reports',
    -- (report?) the reporter's own report, nil once it is over.
    MyReport = 'MyReport',
    -- () opens the report window, from /report without a message.
    ReportWindow = 'ReportWindow',
    -- (health?, armor?) set by staff.
    Stats = 'Stats',
}

---Big screen messages.
---@enum UgAdminShard
UgAdmin.Enums.Shard = {
    Announce = 'announce',
    Warn = 'warn',
    Message = 'message',
}

---Shard title colors owners pick from, mapped to the game's text color codes in client/events.lua.
---@enum UgAdminShardColor
UgAdmin.Enums.ShardColor = {
    Purple = 'purple',
    Red = 'red',
    Blue = 'blue',
    Green = 'green',
    Yellow = 'yellow',
    Orange = 'orange',
    White = 'white',
    Grey = 'grey',
}

---Panel tabs owners show, in order. MUST match Tab in web/src/store/adminStore.ts.
---@enum UgAdminTab
UgAdmin.Enums.Tab = {
    Players = 'players',
    Reports = 'reports',
    Logs = 'logs',
    Settings = 'settings',
}

---Section tones of the panel. Owners MAY recolor them through `theme.colors`. MUST match Tone in web/src/lib/tones.ts.
---@enum UgAdminTone
UgAdmin.Enums.Tone = {
    Violet = 'violet',
    Indigo = 'indigo',
    Blue = 'blue',
    Sky = 'sky',
    Teal = 'teal',
    Emerald = 'emerald',
    Amber = 'amber',
    Rose = 'rose',
    Fuchsia = 'fuchsia',
}

---Messages Lua sends to the page. MUST match web/src/types/protocol.ts.
---@enum UgAdminNuiAction
UgAdmin.Enums.NuiAction = {
    Config = 'config',
    Open = 'open',
    Players = 'players',
    Player = 'player',
    Reports = 'reports',
    Logs = 'logs',
    Result = 'result',
    Close = 'close',
    Noclip = 'noclip',
    Modes = 'modes',
    -- The player's own report, or nil.
    MyReport = 'myReport',
    -- { open: boolean } the player's report window.
    ReportWindow = 'reportWindow',
    -- { [server id]: texture name } headshots of the players this client can see.
    Faces = 'faces',
}

---What the noclip crosshair targets. MUST match web/src/types/protocol.ts.
---@enum UgAdminTargetKind
UgAdmin.Enums.TargetKind = {
    Vehicle = 'vehicle',
    Ped = 'ped',
    Player = 'player',
    Object = 'object',
}

---Callbacks the page posts. MUST match web/src/types/protocol.ts.
---@enum UgAdminNuiCallback
UgAdmin.Enums.NuiCallback = {
    Ready = 'ready',
    Refresh = 'refresh',
    Inspect = 'inspect',
    Run = 'run',
    Logs = 'logs',
    Close = 'close',
    -- The player's report window.
    ReportOpen = 'reportOpen',
    ReportReply = 'reportReply',
    ReportCancel = 'reportCancel',
    ReportRate = 'reportRate',
    ReportHide = 'reportHide',
    -- The staff member's panel settings, saved on their PC.
    Settings = 'settings',
}

---Tabs the panel MAY open on. MUST match web/src/types/protocol.ts.
---@enum UgAdminPanelTab
UgAdmin.Enums.PanelTab = {
    Players = 'players',
    Reports = 'reports',
    Logs = 'logs',
}
