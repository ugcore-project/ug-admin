/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Mirrors `UgAdmin.Enums` in shared/enums.lua. tests/nui.lua checks both sides match.

/** Messages Lua sends: `{ action, payload }`. */
export const NuiAction = {
  Config: "config",
  Open: "open",
  Players: "players",
  Player: "player",
  Reports: "reports",
  Logs: "logs",
  Result: "result",
  Close: "close",
  Noclip: "noclip",
  Modes: "modes",
  MyReport: "myReport",
  ReportWindow: "reportWindow",
  Faces: "faces",
} as const;

export type NuiAction = (typeof NuiAction)[keyof typeof NuiAction];

/** Callbacks the page posts. Lua checks every body. */
export const NuiCallback = {
  Ready: "ready",
  Refresh: "refresh",
  Inspect: "inspect",
  Run: "run",
  Logs: "logs",
  Close: "close",
  ReportOpen: "reportOpen",
  ReportReply: "reportReply",
  ReportCancel: "reportCancel",
  ReportRate: "reportRate",
  ReportHide: "reportHide",
  Settings: "settings",
} as const;

/** Tabs the panel MAY open on, `UgAdmin.Enums.PanelTab`. */
export const PanelTab = {
  Players: "players",
  Reports: "reports",
  Logs: "logs",
} as const;

export type PanelTab = (typeof PanelTab)[keyof typeof PanelTab];

/** Panel settings of the staff member, saved on their PC. Mirrors `UgAdmin.Rules.Settings`. */
export interface PanelSettings {
  /** Quick bar actions in the wanted order. Others keep their default place, after these. */
  order: Action[];
  hidden: Action[];
  /** Show the actions on everyone. */
  everyone: boolean;
  tab: PanelTab;
  /** Ask a second click before risky actions. */
  confirm: boolean;
  /** Own quick replies, or null for the built-in ones. */
  replies: string[] | null;
}

export type NuiCallback = (typeof NuiCallback)[keyof typeof NuiCallback];

/** Staff actions, `UgAdmin.Enums.Action`. Values are the chat command names. */
export const Action = {
  Panel: "admin",
  Noclip: "noclip",
  Vision: "vision",
  God: "god",
  Invisible: "invisible",
  Waypoint: "tpm",
  Coords: "tp",
  Back: "back",
  Goto: "goto",
  Bring: "bring",
  Spectate: "spectate",
  Revive: "revive",
  Heal: "heal",
  Kill: "kill",
  Freeze: "freeze",
  Warn: "warn",
  Kick: "kick",
  Ban: "ban",
  Unban: "unban",
  Message: "dm",
  SendTo: "sendto",
  Jail: "jail",
  Unjail: "unjail",
  Mute: "mute",
  Unmute: "unmute",
  Note: "note",
  DeleteNote: "delnote",
  GiveMoney: "givemoney",
  SetJob: "setjob",
  SetGang: "setgang",
  GiveItem: "giveitem",
  ClearInventory: "clearinv",
  OpenInventory: "inventory",
  SetGroup: "setgroup",
  RemoveGroup: "removegroup",
  SetStats: "setstats",
  SetNeed: "setneed",
  SetMoney: "setmoney",
  RemoveItem: "removeitem",
  ReviveAll: "reviveall",
  BringAll: "bringall",
  FreezeAll: "freezeall",
  Car: "car",
  DeleteVehicle: "dv",
  Fix: "fix",
  DeleteEntity: "delentity",
  Announce: "announce",
  Reports: "reports",
  Duty: "duty",
} as const;

export type Action = (typeof Action)[keyof typeof Action];

/** What staff do with a report, `UgAdmin.Enums.ReportOp`. */
export const ReportOp = {
  Claim: "claim",
  Release: "release",
  Reply: "reply",
  Goto: "goto",
  Return: "return",
  Bring: "bring",
  SendBack: "sendback",
  Close: "close",
  Assign: "assign",
} as const;

export type ReportOp = (typeof ReportOp)[keyof typeof ReportOp];

/** Report states, `UgAdmin.Enums.ReportStatus`. */
export const ReportStatus = {
  Open: "open",
  Claimed: "claimed",
  Closed: "closed",
} as const;

export type ReportStatus = (typeof ReportStatus)[keyof typeof ReportStatus];

/** What a report is about, `UgAdmin.Enums.ReportCategory`. */
export const ReportCategory = {
  Question: "question",
  Player: "player",
  Bug: "bug",
  Stuck: "stuck",
  Other: "other",
} as const;

export type ReportCategory = (typeof ReportCategory)[keyof typeof ReportCategory];

/** Who wrote a chat line, `UgAdmin.Enums.ReportAuthor`. */
export const ReportAuthor = {
  Player: "player",
  Staff: "staff",
  System: "system",
} as const;

export type ReportAuthor = (typeof ReportAuthor)[keyof typeof ReportAuthor];

/** What a system line says happened, `UgAdmin.Enums.ReportEvent`. */
export const ReportEvent = {
  Claimed: "claimed",
  Released: "released",
  Arrived: "arrived",
  Brought: "brought",
  SentBack: "sentBack",
  Closed: "closed",
  Cancelled: "cancelled",
  Assigned: "assigned",
} as const;

export type ReportEvent = (typeof ReportEvent)[keyof typeof ReportEvent];

/** ug-core death states, `UgCore.Enums.DeathState`. */
export const DeathState = {
  Alive: "Alive",
  Downed: "Downed",
  Dead: "Dead",
} as const;

export type DeathState = (typeof DeathState)[keyof typeof DeathState];

/** ug-core error codes, `UgCore.Enums.Errors`. */
export const ErrorCode = {
  InvalidArgs: "invalid_args",
  NotFound: "not_found",
  NotLoaded: "not_loaded",
  RateLimited: "rate_limited",
  NoPermission: "no_permission",
  InsufficientFunds: "insufficient_funds",
  InsufficientItems: "insufficient_items",
  CannotCarry: "cannot_carry",
  Timeout: "timeout",
  InternalError: "internal_error",
} as const;

export type ErrorCode = (typeof ErrorCode)[keyof typeof ErrorCode];

/** ug-lib's theme, from `GlobalState['ug-lib:Config'].theme`. */
export interface ThemeConfig {
  mode: string;
  colors: Record<string, string>;
  radius: string;
  font: string;
  scale: number;
}

/** The owner's panel layout: config.lua's `layout`. */
export interface PanelLayout {
  /** rem */
  width: number;
  /** rem */
  height: number;
  rail: "left" | "right";
  backdrop: number;
  glow: boolean;
  logo: boolean;
  quickBar: boolean;
  toasts: "top" | "bottom";
  toastDuration: number;
  animations: boolean;
  refreshInterval: number;
  noclipHud: boolean;
}

export interface PageConfig {
  theme?: ThemeConfig | undefined;
  labels: Record<string, string>;
  locale: string;
  layout: PanelLayout;
  /** Tabs in the owner's order. MUST match UgAdmin.Enums.Tab. */
  tabs: string[];
}

/** A job or a gang with its grade. */
export interface Role {
  name: string;
  label: string;
  grade: number;
  gradeLabel: string;
}

export interface PlayerRow {
  id: number;
  name: string;
  characterId?: number | undefined;
  job?: Role | undefined;
  ping: number;
  health: number;
  state: DeathState;
  group?: string | undefined;
  frozen: boolean;
  score: number;
  /** Seconds of jail left. */
  jailed?: number | undefined;
  /** Seconds of mute left. */
  muted?: number | undefined;
  /** Staff on duty for reports. */
  duty: boolean;
  /** Staff who handle reports. */
  staff: boolean;
  /** Name of the character they play. */
  character?: string | undefined;
}

export interface Slot {
  name: string;
  count: number;
  slot: number;
}

export interface PlayerDetails {
  id: number;
  name: string;
  characterId?: number | undefined;
  identifiers: string[];
  groups: string[];
  state: DeathState;
  score: number;
  back: boolean;
  accounts?: Record<string, number> | undefined;
  items?: Slot[] | undefined;
  job?: Role | undefined;
  gang?: Role | undefined;
  armor: number;
  /** Need values from 0 to 100, by name. */
  needs?: Record<string, number> | undefined;
  /** Seconds of jail left. */
  jail?: number | undefined;
  /** Seconds of mute left. */
  mute?: number | undefined;
  /** Staff actions taken on this player, newest first. */
  history: LogEntry[];
  notes: Note[];
}

/** A private staff note about a player. */
export interface Note {
  id: number;
  authorName: string;
  text: string;
  /** Unix seconds. */
  at: number;
}

export interface ReportMessage {
  author: ReportAuthor;
  name: string;
  /** A ReportEvent for system lines. */
  text: string;
  /** Unix seconds. */
  at: number;
  /** Staff name an Assigned line handed the report to. */
  to?: string | undefined;
  /** Sources of the staff a staff line pinged. Staff only. */
  mentions?: number[] | undefined;
}

/** A report as staff see it. */
export interface Report {
  id: number;
  /** 0 once the reporter left. */
  source: number;
  name: string;
  message: string;
  category: ReportCategory;
  /** Source of the player reported, 0 once they left. */
  accused?: number | undefined;
  accusedName?: string | undefined;
  status: ReportStatus;
  /** Source of the staff member handling it. */
  claimer?: number | undefined;
  claimedBy?: string | undefined;
  /** Missing on a closed report: the player cancelled it. */
  closedBy?: string | undefined;
  /** Unix seconds. */
  at: number;
  claimedAt?: number | undefined;
  closedAt?: number | undefined;
  rating?: number | undefined;
  messages: ReportMessage[];
  /** Staff who went to the reporter and have a way back. */
  visitors: number[];
  /** The reporter was brought and has a way back. */
  brought: boolean;
}

/** The reporter's own report. */
export interface OwnReport {
  id: number;
  message: string;
  category: ReportCategory;
  accusedName?: string | undefined;
  status: ReportStatus;
  claimedBy?: string | undefined;
  closedBy?: string | undefined;
  at: number;
  rating?: number | undefined;
  messages: ReportMessage[];
}

export interface LogEntry {
  id?: number | undefined;
  actor: string;
  actorName: string;
  action: string;
  target?: string | undefined;
  targetName?: string | undefined;
  detail: string;
  /** Unix seconds. */
  at: number;
}

export interface Choice {
  name: string;
  label: string;
}

export interface Assignment extends Choice {
  grades: { grade: number; label: string }[];
}

export interface Group extends Choice {
  weight: number;
}

export interface Catalog {
  accounts: Choice[];
  jobs: Assignment[];
  gangs: Assignment[];
  items: Choice[];
  groups: Group[];
  needs: Choice[];
  /** Places from config for "send to". */
  locations: Choice[];
  banDurations: string[];
}

export interface OpenPayload {
  self: number;
  access: Action[];
  players: PlayerRow[];
  reports: Report[];
  catalog: Catalog;
}

export interface RunResult {
  action: Action;
  ok: boolean;
  error?: ErrorCode | undefined;
}

/** Arguments of an action. Lua checks them with `UgAdmin.Rules.Args`. */
export interface ActionArgs {
  reason?: string | undefined;
  duration?: string | undefined;
  account?: string | undefined;
  amount?: number | undefined;
  job?: string | undefined;
  grade?: number | undefined;
  item?: string | undefined;
  count?: number | undefined;
  group?: string | undefined;
  text?: string | undefined;
  model?: string | undefined;
  radius?: number | undefined;
  identifier?: string | undefined;
  report?: number | undefined;
  op?: ReportOp | undefined;
  staff?: number | undefined;
  health?: number | undefined;
  armor?: number | undefined;
  need?: string | undefined;
  value?: number | undefined;
  minutes?: number | undefined;
  slot?: number | undefined;
  location?: string | undefined;
  note?: number | undefined;
}

/** What the noclip crosshair targets, `UgAdmin.Enums.TargetKind`. */
export const TargetKind = {
  Vehicle: "vehicle",
  Ped: "ped",
  Player: "player",
  Object: "object",
} as const;

export type TargetKind = (typeof TargetKind)[keyof typeof TargetKind];

export interface NoclipTarget {
  kind: TargetKind;
  name?: string | undefined;
  plate?: string | undefined;
  model: number;
  netId?: number | undefined;
  owner?: number | undefined;
  player?: number | undefined;
}

/** Keys that apply to what the crosshair targets right now. */
export interface NoclipAbilities {
  land: boolean;
  delete: boolean;
  freeze: boolean;
  board: boolean;
}

/** The flight state Lua sends while noclip is on. */
export interface NoclipState {
  hud: boolean;
  speed: number;
  minSpeed: number;
  maxSpeed: number;
  leave: string;
  coords: { x: number; y: number; z: number };
  heading: number;
  target?: NoclipTarget | undefined;
  can: NoclipAbilities;
}

export interface NuiMessage {
  action: NuiAction;
  payload?: unknown | undefined;
}
