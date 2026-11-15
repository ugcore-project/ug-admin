/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Page state. Messages from Lua are read field by field: a broken payload is dropped, never rendered as is.

import { create } from "zustand";
import { flattenLabels } from "@/lib/labels";
import { applyTheme } from "@/lib/theme";
import {
  Action,
  DeathState,
  NuiAction,
  ReportAuthor,
  ReportCategory,
  ReportStatus,
  TargetKind,
  type Catalog,
  type LogEntry,
  type NoclipState,
  type NoclipTarget,
  type Note,
  type NuiMessage,
  type OwnReport,
  type PageConfig,
  type PanelLayout,
  type PlayerDetails,
  type PlayerRow,
  type Report,
  type ReportMessage,
  type Role,
  type RunResult,
  type ThemeConfig,
  PanelTab,
  type PanelSettings,
} from "@/types/protocol";
import { sendSettings } from "@/lib/nui";

export const Tab = {
  ...PanelTab,
  Settings: "settings",
} as const;

export type Tab = (typeof Tab)[keyof typeof Tab];

export const DEFAULT_LAYOUT: PanelLayout = {
  width: 84,
  height: 50,
  rail: "left",
  backdrop: 0.5,
  glow: true,
  logo: true,
  quickBar: true,
  toasts: "bottom",
  toastDuration: 2600,
  animations: true,
  refreshInterval: 5000,
  noclipHud: true,
};

const ALL_TABS: Tab[] = [Tab.Players, Tab.Reports, Tab.Logs, Tab.Settings];

/** The owner's layout from Lua. Lua checked it; it is checked again, field by field. */
export function readLayout(value: unknown): PanelLayout {
  if (!isObject(value)) {
    return DEFAULT_LAYOUT;
  }

  const within = (input: unknown, min: number, max: number, fallback: number) =>
    typeof input === "number" && Number.isFinite(input) ? Math.min(Math.max(input, min), max) : fallback;
  const flag = (key: keyof PanelLayout) => (typeof value[key] === "boolean" ? (value[key] as boolean) : (DEFAULT_LAYOUT[key] as boolean));

  return {
    width: within(value.width, 40, 160, DEFAULT_LAYOUT.width),
    height: within(value.height, 25, 100, DEFAULT_LAYOUT.height),
    rail: value.rail === "right" ? "right" : "left",
    backdrop: within(value.backdrop, 0, 1, DEFAULT_LAYOUT.backdrop),
    glow: flag("glow"),
    logo: flag("logo"),
    quickBar: flag("quickBar"),
    toasts: value.toasts === "top" ? "top" : "bottom",
    toastDuration: within(value.toastDuration, 500, 15000, DEFAULT_LAYOUT.toastDuration),
    animations: flag("animations"),
    refreshInterval: within(value.refreshInterval, 2000, 60000, DEFAULT_LAYOUT.refreshInterval),
    noclipHud: flag("noclipHud"),
  };
}

/** The owner's tabs, in order, without unknown or repeated ones. All of them when the list is missing or empty. */
export function readTabs(value: unknown): Tab[] {
  const tabs = Array.isArray(value) ? value.filter((entry, index): entry is Tab => ALL_TABS.includes(entry as Tab) && value.indexOf(entry) === index) : [];

  return tabs.length > 0 ? tabs : ALL_TABS;
}

/** The tabs this staff member sees: the owner's, without reports for staff who may not take them. */
export function visibleTabs(tabs: readonly Tab[], access: ReadonlySet<Action>): Tab[] {
  return tabs.filter((tab) => tab !== Tab.Reports || access.has(Action.Reports));
}

export interface Toast extends RunResult {
  key: number;
}

/** The latest staff answer, shown while the report window is closed. */
export interface Bubble {
  key: number;
  name: string;
  text: string;
}

interface AdminState {
  config: PageConfig;
  open: boolean;
  tab: Tab;
  self: number;
  access: Set<Action>;
  players: PlayerRow[];
  reports: Report[];
  logs: LogEntry[] | null;
  catalog: Catalog;
  selected: number | null;
  details: PlayerDetails | null;
  /** Grows with every details message, so forms seeded from them start over. */
  detailsVersion: number;
  toast: Toast | null;
  noclip: NoclipState | null;
  /** Staff modes that are on: noclip, vision, god, invisible. */
  modes: Set<Action>;
  /** Chat lines staff read, per report id. */
  seen: Record<number, number>;
  /** Character headshots by server id, for players the game can see. */
  faces: Record<number, Face>;
  /** The player's own report. */
  myReport: OwnReport | null;
  reportWindow: boolean;
  bubble: Bubble | null;
  settings: PanelSettings;
  saveSettings: (settings: PanelSettings) => void;
  setTab: (tab: Tab) => void;
  select: (id: number | null) => void;
  markSeen: (id: number, count: number) => void;
}

const EMPTY_CATALOG: Catalog = { accounts: [], jobs: [], gangs: [], items: [], groups: [], needs: [], locations: [], banDurations: [] };
const ACTIONS = new Set<string>(Object.values(Action));
const STATES = new Set<string>(Object.values(DeathState));
const STATUSES = new Set<string>(Object.values(ReportStatus));
const CATEGORIES = new Set<string>(Object.values(ReportCategory));
const AUTHORS = new Set<string>(Object.values(ReportAuthor));
const MAX_MESSAGES = 100;
const KINDS = new Set<string>(Object.values(TargetKind));
const MODES = new Set<string>([Action.Noclip, Action.Vision, Action.God, Action.Invisible, Action.Duty]);
const MAX_ROWS = 1024;
const MAX_TEXT = 64;
const MAX_SPEED = 1000;
const MAX_COORD = 100000;

export const DEFAULT_SETTINGS: PanelSettings = {
  order: [],
  hidden: [],
  everyone: true,
  tab: PanelTab.Players,
  confirm: true,
  replies: null,
};

const initial = () => ({
  config: { labels: {}, locale: "en", layout: DEFAULT_LAYOUT, tabs: ALL_TABS } as PageConfig,
  open: false,
  tab: Tab.Players as Tab,
  self: 0,
  access: new Set<Action>(),
  players: [] as PlayerRow[],
  reports: [] as Report[],
  logs: null as LogEntry[] | null,
  catalog: EMPTY_CATALOG,
  selected: null as number | null,
  details: null as PlayerDetails | null,
  detailsVersion: 0,
  toast: null as Toast | null,
  noclip: null as NoclipState | null,
  modes: new Set<Action>(),
  seen: {} as Record<number, number>,
  faces: {} as Record<number, Face>,
  myReport: null as OwnReport | null,
  reportWindow: false,
  bubble: null as Bubble | null,
  settings: DEFAULT_SETTINGS,
});

export const useAdmin = create<AdminState>()((set) => ({
  ...initial(),
  setTab: (tab) => set({ tab }),
  saveSettings: (settings) => {
    set({ settings });
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => void sendSettings(settings), SAVE_MS);
  },
  select: (selected) => set((state) => ({ selected, details: state.details?.id === selected ? state.details : null })),
  markSeen: (id, count) => set((state) => (state.seen[id] === count ? state : { seen: { ...state.seen, [id]: count } })),
}));

type Raw = Record<string, unknown>;

const isObject = (value: unknown): value is Raw => typeof value === "object" && value !== null && !Array.isArray(value);
const str = (value: unknown, fallback = "") => (typeof value === "string" ? value : fallback);
const optStr = (value: unknown) => (typeof value === "string" && value !== "" ? value : undefined);
const num = (value: unknown, fallback = 0) => (typeof value === "number" && Number.isFinite(value) ? value : fallback);
const optNum = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? value : undefined);
const optSeconds = (value: unknown) => {
  const seconds = optNum(value);

  return seconds !== undefined && seconds >= 0 ? Math.min(seconds, 31 * 86400) : undefined;
};

/** Lua encodes an empty table as `{}`, so lists MAY arrive as objects. */
function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value.slice(0, MAX_ROWS) : [];
}

function strings(value: unknown): string[] {
  return list(value).filter((entry): entry is string => typeof entry === "string");
}

function readRole(value: unknown): Role | undefined {
  if (!isObject(value) || typeof value.name !== "string") {
    return undefined;
  }

  return { name: value.name, label: str(value.label, value.name), grade: num(value.grade), gradeLabel: str(value.gradeLabel) };
}

const readState = (value: unknown) => (typeof value === "string" && STATES.has(value) ? (value as DeathState) : DeathState.Alive);

function readPlayer(value: unknown): PlayerRow | null {
  if (!isObject(value) || typeof value.id !== "number") {
    return null;
  }

  return {
    id: value.id,
    name: str(value.name, `#${value.id}`),
    characterId: optNum(value.characterId),
    job: readRole(value.job),
    ping: num(value.ping),
    health: num(value.health),
    state: readState(value.state),
    group: optStr(value.group),
    frozen: value.frozen === true,
    score: num(value.score),
    jailed: optSeconds(value.jailed),
    muted: optSeconds(value.muted),
    duty: value.duty === true,
    staff: value.staff === true,
    character: optStr(value.character),
  };
}

function readNote(value: unknown): Note | null {
  if (!isObject(value) || typeof value.id !== "number" || typeof value.text !== "string") {
    return null;
  }

  return { id: value.id, authorName: str(value.authorName, "?"), text: value.text, at: num(value.at) };
}

function readDetails(value: unknown): PlayerDetails | null {
  if (!isObject(value) || typeof value.id !== "number") {
    return null;
  }

  const accounts: Record<string, number> = {};

  if (isObject(value.accounts)) {
    for (const [name, balance] of Object.entries(value.accounts)) {
      if (typeof balance === "number") {
        accounts[name] = balance;
      }
    }
  }

  const needs: Record<string, number> = {};

  if (isObject(value.needs)) {
    for (const [name, level] of Object.entries(value.needs)) {
      if (typeof level === "number" && Number.isFinite(level)) {
        needs[name] = Math.max(0, Math.min(100, level));
      }
    }
  }

  const items = list(value.items).flatMap((slot) =>
    isObject(slot) && typeof slot.name === "string" ? [{ name: slot.name, count: num(slot.count, 1), slot: num(slot.slot) }] : [],
  );

  return {
    id: value.id,
    name: str(value.name, `#${value.id}`),
    characterId: optNum(value.characterId),
    identifiers: strings(value.identifiers),
    groups: strings(value.groups),
    state: readState(value.state),
    score: num(value.score),
    back: value.back === true,
    accounts: value.accounts === undefined ? undefined : accounts,
    items: value.items === undefined ? undefined : items,
    job: readRole(value.job),
    gang: readRole(value.gang),
    armor: Math.max(0, Math.min(100, num(value.armor))),
    needs: value.needs === undefined ? undefined : needs,
    jail: optSeconds(value.jail),
    mute: optSeconds(value.mute),
    history: readAll(value.history, readLog),
    notes: readAll(value.notes, readNote),
  };
}

const PANEL_TABS = new Set<string>(Object.values(PanelTab));
const MAX_ORDER = 64;
const MAX_REPLIES = 8;
export const MAX_REPLY = 100;

/** Distinct known actions, at most MAX_ORDER. */
function readActions(value: unknown): Action[] {
  return [...new Set(strings(value).filter((action) => ACTIONS.has(action)))].slice(0, MAX_ORDER) as Action[];
}

/** Settings from Lua, field by field. Anything missing or broken takes its default. */
export function readSettings(value: unknown): PanelSettings {
  if (!isObject(value)) {
    return DEFAULT_SETTINGS;
  }

  const replies = Array.isArray(value.replies)
    ? strings(value.replies)
        .map((reply) => reply.trim())
        .filter((reply) => reply !== "" && [...reply].length <= MAX_REPLY)
        .slice(0, MAX_REPLIES)
    : null;

  return {
    order: readActions(value.order),
    hidden: readActions(value.hidden),
    everyone: typeof value.everyone === "boolean" ? value.everyone : DEFAULT_SETTINGS.everyone,
    tab: typeof value.tab === "string" && PANEL_TABS.has(value.tab) ? (value.tab as PanelTab) : DEFAULT_SETTINGS.tab,
    confirm: typeof value.confirm === "boolean" ? value.confirm : DEFAULT_SETTINGS.confirm,
    replies,
  };
}

// Settings change on every drag step: Lua hears the last one only.
const SAVE_MS = 300;
let saveTimer: ReturnType<typeof setTimeout> | undefined;

export interface Face {
  txd: string;
  /** `nui-img` address of the headshot texture. */
  url: string;
}

const TXD = /^[A-Za-z0-9_]{1,64}$/;
const SERVER_ID = /^[1-9][0-9]{0,4}$/;

/** Headshots by server id. A known texture keeps its address, so the image is not loaded again on every refresh. */
function readFaces(value: unknown, previous: Record<number, Face>): Record<number, Face> {
  const faces: Record<number, Face> = {};

  if (!isObject(value)) {
    return faces;
  }

  let count = 0;

  for (const [key, txd] of Object.entries(value)) {
    if (count >= MAX_FACES || !SERVER_ID.test(key) || typeof txd !== "string" || !TXD.test(txd)) {
      continue;
    }

    const id = Number(key);
    const known = previous[id];

    // A headshot slot MAY be reused for another ped, so a new texture gets a fresh address past the image cache.
    faces[id] = known?.txd === txd ? known : { txd, url: `https://nui-img/${txd}/${txd}?t=${Date.now()}` };
    count += 1;
  }

  return faces;
}

// Headshots the page keeps at once, above what Lua sends.
const MAX_FACES = 64;

// Staff one chat line MAY ping, as on the server.
const MAX_MENTIONS = 5;

function readMessage(value: unknown): ReportMessage | null {
  if (!isObject(value) || typeof value.text !== "string" || typeof value.author !== "string" || !AUTHORS.has(value.author)) {
    return null;
  }

  return {
    author: value.author as ReportAuthor,
    name: str(value.name, "?"),
    text: value.text,
    at: num(value.at),
    to: optStr(value.to),
    mentions: Array.isArray(value.mentions)
      ? value.mentions.filter((entry): entry is number => typeof entry === "number").slice(0, MAX_MENTIONS)
      : undefined,
  };
}

const readStatus = (value: unknown) => (typeof value === "string" && STATUSES.has(value) ? (value as ReportStatus) : ReportStatus.Open);
const readCategory = (value: unknown) => (typeof value === "string" && CATEGORIES.has(value) ? (value as ReportCategory) : ReportCategory.Other);
const readMessages = (value: unknown) => readAll(value, readMessage).slice(-MAX_MESSAGES);
const optRating = (value: unknown) => {
  const rating = optNum(value);

  return rating !== undefined && rating >= 1 && rating <= 5 ? Math.round(rating) : undefined;
};

function readReport(value: unknown): Report | null {
  if (!isObject(value) || typeof value.id !== "number" || typeof value.message !== "string") {
    return null;
  }

  return {
    id: value.id,
    source: num(value.source),
    name: str(value.name, "?"),
    message: value.message,
    category: readCategory(value.category),
    accused: optNum(value.accused),
    accusedName: optStr(value.accusedName),
    status: readStatus(value.status),
    claimer: optNum(value.claimer),
    claimedBy: optStr(value.claimedBy),
    closedBy: optStr(value.closedBy),
    at: num(value.at),
    claimedAt: optNum(value.claimedAt),
    closedAt: optNum(value.closedAt),
    rating: optRating(value.rating),
    messages: readMessages(value.messages),
    visitors: list(value.visitors).filter((entry): entry is number => typeof entry === "number"),
    brought: value.brought === true,
  };
}

function readOwnReport(value: unknown): OwnReport | null {
  if (!isObject(value) || typeof value.id !== "number" || typeof value.message !== "string") {
    return null;
  }

  return {
    id: value.id,
    message: value.message,
    category: readCategory(value.category),
    accusedName: optStr(value.accusedName),
    status: readStatus(value.status),
    claimedBy: optStr(value.claimedBy),
    closedBy: optStr(value.closedBy),
    at: num(value.at),
    rating: optRating(value.rating),
    messages: readMessages(value.messages),
  };
}

function readLog(value: unknown): LogEntry | null {
  if (!isObject(value) || typeof value.action !== "string") {
    return null;
  }

  return {
    id: optNum(value.id),
    actor: str(value.actor),
    actorName: str(value.actorName, "?"),
    action: value.action,
    target: optStr(value.target),
    targetName: optStr(value.targetName),
    detail: str(value.detail),
    at: num(value.at),
  };
}

function choices(value: unknown) {
  return list(value).flatMap((entry) =>
    isObject(entry) && typeof entry.name === "string" ? [{ name: entry.name, label: str(entry.label, entry.name), raw: entry }] : [],
  );
}

function readCatalog(value: unknown): Catalog {
  if (!isObject(value)) {
    return EMPTY_CATALOG;
  }

  const assignments = (raw: unknown) =>
    choices(raw).map(({ name, label, raw: entry }) => ({
      name,
      label,
      grades: list(entry.grades).flatMap((grade) =>
        isObject(grade) && typeof grade.grade === "number" ? [{ grade: grade.grade, label: str(grade.label, String(grade.grade)) }] : [],
      ),
    }));

  return {
    accounts: choices(value.accounts).map(({ name, label }) => ({ name, label })),
    jobs: assignments(value.jobs),
    gangs: assignments(value.gangs),
    items: choices(value.items).map(({ name, label }) => ({ name, label })),
    groups: choices(value.groups).map(({ name, label, raw }) => ({ name, label, weight: num(raw.weight) })),
    needs: choices(value.needs).map(({ name, label }) => ({ name, label })),
    locations: choices(value.locations).map(({ name, label }) => ({ name, label })),
    banDurations: strings(value.banDurations),
  };
}

const text = (value: unknown) => (typeof value === "string" && value !== "" ? value.slice(0, MAX_TEXT) : undefined);
const bounded = (value: unknown, max: number) => Math.max(-max, Math.min(max, num(value)));
const optId = (value: unknown) => {
  const id = optNum(value);

  return id !== undefined && Number.isInteger(id) && id >= 0 && id <= 0xffffffff ? id : undefined;
};

function readTarget(value: unknown): NoclipTarget | undefined {
  if (!isObject(value) || typeof value.kind !== "string" || !KINDS.has(value.kind)) {
    return undefined;
  }

  return {
    kind: value.kind as TargetKind,
    name: text(value.name),
    plate: text(value.plate)?.trim(),
    model: Math.trunc(bounded(value.model, 0xffffffff)),
    netId: optId(value.netId),
    owner: optId(value.owner),
    player: optId(value.player),
  };
}

function readNoclip(value: unknown): NoclipState | null {
  if (!isObject(value) || value.active !== true) {
    return null;
  }

  const coords = isObject(value.coords) ? value.coords : {};
  const can = isObject(value.can) ? value.can : {};
  const minSpeed = Math.max(0, bounded(value.minSpeed, MAX_SPEED));
  const maxSpeed = Math.max(minSpeed, bounded(value.maxSpeed, MAX_SPEED));

  return {
    hud: value.hud !== false,
    speed: Math.max(minSpeed, Math.min(maxSpeed, num(value.speed, minSpeed))),
    minSpeed,
    maxSpeed,
    leave: text(value.leave) ?? "",
    coords: { x: bounded(coords.x, MAX_COORD), y: bounded(coords.y, MAX_COORD), z: bounded(coords.z, MAX_COORD) },
    heading: ((bounded(value.heading, 360) % 360) + 360) % 360,
    target: readTarget(value.target),
    can: { land: can.land === true, delete: can.delete === true, freeze: can.freeze === true, board: can.board === true },
  };
}

function readAll<T>(value: unknown, read: (entry: unknown) => T | null): T[] {
  return list(value).flatMap((entry) => {
    const row = read(entry);

    return row ? [row] : [];
  });
}

let toastKey = 0;
let bubbleKey = 0;

/** A new staff line the player has not seen in the window. */
function newAnswer(before: OwnReport | null, after: OwnReport | null): ReportMessage | undefined {
  if (!after || (before && before.id === after.id && before.messages.length >= after.messages.length)) {
    return undefined;
  }

  const last = after.messages[after.messages.length - 1];

  return last?.author === ReportAuthor.Staff ? last : undefined;
}

/** Applies one message from Lua. Unknown or broken messages are ignored. */
export function handleMessage(message: NuiMessage): void {
  const { payload } = message;

  switch (message.action) {
    case NuiAction.Config: {
      if (!isObject(payload)) {
        return;
      }

      const labels = isObject(payload.labels) ? flattenLabels(payload.labels) : {};

      applyTheme(isObject(payload.theme) ? (payload.theme as unknown as ThemeConfig) : undefined);
      useAdmin.setState({ config: { labels, locale: str(payload.locale, "en"), layout: readLayout(payload.layout), tabs: readTabs(payload.tabs) } });
      break;
    }

    case NuiAction.Open: {
      if (!isObject(payload)) {
        return;
      }

      const access = new Set(strings(payload.access).filter((action) => ACTIONS.has(action)) as Action[]);
      const settings = readSettings(payload.settings);

      useAdmin.setState({
        open: true,
        self: num(payload.self),
        access,
        players: readAll(payload.players, readPlayer),
        reports: readAll(payload.reports, readReport),
        catalog: readCatalog(payload.catalog),
        logs: null,
        faces: {},
        settings,
        tab: (() => {
          const tabs = visibleTabs(readTabs(useAdmin.getState().config.tabs), access);

          return tabs.includes(settings.tab) ? settings.tab : (tabs[0] ?? Tab.Players);
        })(),
      });
      break;
    }

    case NuiAction.Faces:
      useAdmin.setState((state) => ({ faces: readFaces(payload, state.faces) }));
      break;

    case NuiAction.Players:
      useAdmin.setState({ players: readAll(payload, readPlayer) });
      break;

    case NuiAction.Player: {
      const details = readDetails(payload);

      if (details && details.id === useAdmin.getState().selected) {
        useAdmin.setState((state) => ({ details, detailsVersion: state.detailsVersion + 1 }));
      }

      break;
    }

    case NuiAction.Reports:
      useAdmin.setState({ reports: readAll(payload, readReport) });
      break;

    case NuiAction.Logs:
      useAdmin.setState({ logs: readAll(payload, readLog) });
      break;

    case NuiAction.Result: {
      if (!isObject(payload) || typeof payload.action !== "string" || !ACTIONS.has(payload.action)) {
        return;
      }

      toastKey += 1;
      useAdmin.setState({
        toast: {
          key: toastKey,
          action: payload.action as Action,
          ok: payload.ok === true,
          error: optStr(payload.error) as RunResult["error"],
        },
      });
      break;
    }

    case NuiAction.Close:
      useAdmin.setState({ open: false });
      break;

    case NuiAction.Modes:
      useAdmin.setState({ modes: new Set(strings(payload).filter((mode) => MODES.has(mode)) as Action[]) });
      break;

    case NuiAction.Noclip:
      useAdmin.setState({ noclip: readNoclip(payload) });
      break;

    case NuiAction.MyReport: {
      const state = useAdmin.getState();
      const report = readOwnReport(payload);
      const answer = state.reportWindow ? undefined : newAnswer(state.myReport, report);

      if (answer) {
        bubbleKey += 1;
      }

      useAdmin.setState({ myReport: report, ...(answer ? { bubble: { key: bubbleKey, name: answer.name, text: answer.text } } : {}) });
      break;
    }

    case NuiAction.ReportWindow: {
      const open = isObject(payload) && payload.open === true;

      useAdmin.setState(open ? { reportWindow: true, bubble: null } : { reportWindow: false });
      break;
    }
  }
}

/** Listens to Lua. Returns the cleanup. */
export function installMessages(): () => void {
  const listener = (event: MessageEvent) => {
    if (isObject(event.data) && typeof event.data.action === "string") {
      handleMessage(event.data as unknown as NuiMessage);
    }
  };

  window.addEventListener("message", listener);

  return () => window.removeEventListener("message", listener);
}

/** Tests only. */
export function resetAdmin(): void {
  useAdmin.setState(initial());
}

/** A label by dotted key, or the key itself. */
export function useLabel() {
  const labels = useAdmin((state) => state.config.labels);

  return (key: string) => labels[key] ?? key;
}
