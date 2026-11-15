/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Showcase scenes: what the page shows for the README. The preview plays them, and `npm run capture` saves each one
// to .github/assets/<id>.webp, animated when `animated` is set. Add a scene for every screen worth showing.

import {
  Action,
  DeathState,
  NuiAction,
  ReportAuthor,
  ReportCategory,
  ReportEvent,
  ReportStatus,
  TargetKind,
  type NuiMessage,
  type OpenPayload,
} from "@/types/protocol";

/** One step: a message as Lua would send it, or a click on an element, then a pause. */
export interface SceneStep {
  send?: NuiMessage;
  /** CSS selector of the element to click. */
  click?: string;
  /** Text typed into the element `click` selected, as the user would. */
  type?: string;
  /** Milliseconds before the next step. */
  wait?: number;
}

export interface Scene {
  /** File name of the capture: lowercase, digits and dashes. */
  id: string;
  title: string;
  steps: SceneStep[];
  /** Captured as an animated image of the whole run, instead of a still of the end. */
  animated?: boolean;
  /** CSS selector of the element the capture is cropped to, with a margin. The whole screen when unset. */
  crop?: string;
}

/** A screen area in CSS pixels. */
export interface Area {
  x: number;
  y: number;
  width: number;
  height: number;
}

const now = Math.floor(Date.now() / 1000);
const police = { name: "police", label: "LSPD", grade: 3, gradeLabel: "Sergeant" };

export const OPEN: OpenPayload = {
  self: 1,
  access: Object.values(Action),
  players: [
    { id: 1, name: "Urging", characterId: 1, job: police, ping: 24, health: 200, state: DeathState.Alive, group: "founder", frozen: false, score: 0, duty: true, staff: true, character: "Diogo Silva" },
    { id: 4, name: "Bob Mulligan", characterId: 7, ping: 61, health: 120, state: DeathState.Alive, frozen: true, score: 12, duty: false, staff: true, character: "Bob Mulligan Jr." },
    { id: 9, name: "Trevor P.", characterId: 3, ping: 140, health: 0, state: DeathState.Downed, frozen: false, score: 27, duty: false, staff: false },
    { id: 12, name: "NewPlayer", ping: 80, health: 200, state: DeathState.Alive, frozen: false, score: 0, duty: false, staff: false },
  ],
  reports: [
    {
      id: 1,
      source: 4,
      name: "Bob Mulligan",
      message: "Someone keeps ramming my car at Legion.",
      category: ReportCategory.Player,
      accused: 9,
      accusedName: "Trevor P.",
      status: ReportStatus.Open,
      at: now - 95,
      messages: [
        { author: ReportAuthor.Player, name: "Bob Mulligan", text: "Someone keeps ramming my car at Legion.", at: now - 95 },
        { author: ReportAuthor.Player, name: "Bob Mulligan", text: "He is doing it again right now!", at: now - 20 },
      ],
      visitors: [],
      brought: false,
    },
    {
      id: 2,
      source: 9,
      name: "Trevor P.",
      message: "Stuck under the map.",
      category: ReportCategory.Stuck,
      status: ReportStatus.Claimed,
      claimer: 1,
      claimedBy: "Urging",
      at: now - 900,
      claimedAt: now - 600,
      messages: [
        { author: ReportAuthor.Player, name: "Trevor P.", text: "Stuck under the map.", at: now - 900 },
        { author: ReportAuthor.System, name: "Urging", text: ReportEvent.Claimed, at: now - 600 },
        { author: ReportAuthor.Staff, name: "Urging", text: "On my way!", at: now - 590 },
        { author: ReportAuthor.System, name: "Urging", text: ReportEvent.Arrived, at: now - 580 },
        { author: ReportAuthor.Player, name: "Trevor P.", text: "I can see you, I am right below.", at: now - 560 },
      ],
      visitors: [1],
      brought: false,
    },
    {
      id: 3,
      source: 12,
      name: "NewPlayer",
      message: "How do I get a job?",
      category: ReportCategory.Question,
      status: ReportStatus.Closed,
      claimer: 1,
      claimedBy: "Urging",
      closedBy: "Urging",
      at: now - 4000,
      closedAt: now - 3500,
      rating: 5,
      messages: [
        { author: ReportAuthor.Player, name: "NewPlayer", text: "How do I get a job?", at: now - 4000 },
        { author: ReportAuthor.Staff, name: "Urging", text: "Head to the job center at City Hall.", at: now - 3600 },
        { author: ReportAuthor.System, name: "Urging", text: ReportEvent.Closed, at: now - 3500 },
      ],
      visitors: [],
      brought: false,
    },
  ],
  catalog: {
    accounts: [{ name: "bank", label: "Bank" }, { name: "cash", label: "Cash" }],
    jobs: [{ name: "police", label: "LSPD", grades: [{ grade: 1, label: "Cadet" }, { grade: 2, label: "Officer" }, { grade: 3, label: "Sergeant" }] }],
    gangs: [{ name: "ballas", label: "Ballas", grades: [{ grade: 1, label: "Recruit" }, { grade: 2, label: "OG" }] }],
    items: [{ name: "water", label: "Water" }, { name: "bread", label: "Bread" }, { name: "weapon_pistol", label: "Pistol" }],
    groups: [{ name: "moderator", label: "Moderator", weight: 10 }, { name: "admin", label: "Admin", weight: 50 }],
    needs: [{ name: "hunger", label: "Hunger" }, { name: "thirst", label: "Thirst" }],
    locations: [{ name: "hospital", label: "Pillbox Hospital" }, { name: "police", label: "Mission Row PD" }],
    banDurations: ["1h", "1d", "7d", "30d", "perm"],
  },
};

export const NOCLIP = {
  active: true,
  hud: true,
  speed: 12.4,
  minSpeed: 1.5,
  maxSpeed: 200,
  leave: "F2",
  coords: { x: 215.76, y: -810.12, z: 30.73 },
  heading: 248,
  target: { kind: TargetKind.Vehicle, name: "Sultan", plate: " UG 042 ", model: 970598228, netId: 31, owner: 1 },
  can: { land: true, delete: true, freeze: false, board: true },
};

export const NOCLIP_PLAYER = {
  ...NOCLIP,
  target: { kind: TargetKind.Player, name: "Bob Mulligan", player: 4, model: 1885233650, netId: 12, owner: 4 },
  can: { land: true, freeze: true },
};

export const DETAILS: NuiMessage = {
  action: NuiAction.Player,
  payload: {
    id: 4,
    name: "Bob Mulligan",
    characterId: 7,
    identifiers: ["license:0123456789abcdef", "discord:123456789012345678"],
    groups: [],
    state: DeathState.Alive,
    score: 12,
    back: true,
    accounts: { bank: 15200, cash: 340 },
    items: [{ name: "water", count: 3, slot: 1 }, { name: "bread", count: 1, slot: 2 }],
    armor: 40,
    needs: { hunger: 72, thirst: 18 },
    jail: 754,
    mute: 120,
    history: [
      { id: 9, actor: "license:1", actorName: "Urging", action: "warn", target: "license:4", detail: "ramming cars", at: now - 400 },
      { id: 4, actor: "license:1", actorName: "Urging", action: "freeze", target: "license:4", detail: "on", at: now - 7200 },
    ],
    notes: [{ id: 2, authorName: "Urging", text: "Second warning for VDM this week.", at: now - 3600 }],
  },
};

export const LOGS: NuiMessage = {
  action: NuiAction.Logs,
  payload: [
    { id: 4, actor: "license:a", actorName: "Urging", action: Action.Kick, target: "license:b", targetName: "Trevor P.", detail: "Combat logging", at: now - 30 },
    { id: 3, actor: "license:a", actorName: "Urging", action: Action.Freeze, target: "license:c", targetName: "Bob Mulligan", detail: "on", at: now - 420 },
    { id: 2, actor: "license:a", actorName: "Urging", action: Action.Revive, target: "license:b", targetName: "Trevor P.", at: now - 1900 },
    { id: 1, actor: "console", actorName: "Console", action: Action.Announce, detail: "Restart in 10 minutes", at: now - 4000 },
  ],
};

export const MY_REPORT_CHAT: NuiMessage = {
  action: NuiAction.MyReport,
  payload: {
    id: 2,
    message: "Stuck under the map.",
    category: ReportCategory.Stuck,
    status: ReportStatus.Claimed,
    claimedBy: "Urging",
    at: now - 900,
    messages: [
      { author: ReportAuthor.Player, name: "Trevor P.", text: "Stuck under the map.", at: now - 900 },
      { author: ReportAuthor.System, name: "Urging", text: ReportEvent.Claimed, at: now - 600 },
      { author: ReportAuthor.Staff, name: "Urging", text: "On my way!", at: now - 590 },
    ],
  },
};

export const MY_REPORT_CLOSED: NuiMessage = {
  action: NuiAction.MyReport,
  payload: {
    id: 2,
    message: "Stuck under the map.",
    category: ReportCategory.Stuck,
    status: ReportStatus.Closed,
    claimedBy: "Urging",
    closedBy: "Urging",
    at: now - 900,
    messages: [
      { author: ReportAuthor.Player, name: "Trevor P.", text: "Stuck under the map.", at: now - 900 },
      { author: ReportAuthor.Staff, name: "Urging", text: "On my way!", at: now - 590 },
      { author: ReportAuthor.Staff, name: "Urging", text: "All sorted. Have fun!", at: now - 30 },
      { author: ReportAuthor.System, name: "Urging", text: ReportEvent.Closed, at: now - 20 },
    ],
  },
};

// Opens the panel on duty, so the report desk takes reports.
const OPEN_PANEL: SceneStep[] = [
  { send: { action: NuiAction.Open, payload: OPEN } },
  { send: { action: NuiAction.Modes, payload: [Action.Duty] }, wait: 600 },
];
const WINDOW = "[data-panel-window]";
const REPORT_WINDOW = "[data-report-window]";

export const SCENES: Scene[] = [
  {
    id: "panel-players",
    title: "Players",
    crop: WINDOW,
    steps: [...OPEN_PANEL, { click: '[data-player="4"]', wait: 100 }, { send: DETAILS }],
  },
  {
    id: "panel-reports",
    title: "Report desk",
    crop: WINDOW,
    steps: [...OPEN_PANEL, { click: '[data-tab="reports"]', wait: 300 }, { click: '[data-report="2"]' }],
  },
  {
    id: "panel-logs",
    title: "Audit log",
    crop: WINDOW,
    steps: [...OPEN_PANEL, { click: '[data-tab="logs"]', wait: 100 }, { send: LOGS }],
  },
  {
    id: "panel-settings",
    title: "Settings",
    crop: WINDOW,
    steps: [...OPEN_PANEL, { click: '[data-tab="settings"]' }],
  },
  {
    id: "report-window",
    title: "Player report window",
    crop: REPORT_WINDOW,
    steps: [{ send: { action: NuiAction.ReportWindow, payload: { open: true } } }, { send: MY_REPORT_CHAT }],
  },
  {
    id: "noclip",
    title: "Noclip targeting",
    animated: true,
    steps: [
      { send: { action: NuiAction.Noclip, payload: { ...NOCLIP, target: undefined, can: { land: true } } }, wait: 1400 },
      { send: { action: NuiAction.Noclip, payload: NOCLIP }, wait: 2200 },
      { send: { action: NuiAction.Noclip, payload: NOCLIP_PLAYER }, wait: 2200 },
    ],
  },
  {
    id: "report-desk",
    title: "Answering a report",
    animated: true,
    crop: WINDOW,
    steps: [
      ...OPEN_PANEL,
      { click: '[data-tab="reports"]', wait: 700 },
      { click: '[data-report="2"]', wait: 900 },
      { click: "[data-composer]", type: "Pulling you up now ", wait: 300 },
      { click: '[data-tool="emoji"]', wait: 600 },
      { click: '[data-emoji="👍"]', wait: 400 },
      { click: "[data-composer]", wait: 1600 },
    ],
  },
];

/** Sets an input's value so React sees it, as typing would. */
function typeInto(element: HTMLElement, text: string) {
  if (!(element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement)) {
    return;
  }

  const prototype = element instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;

  setter?.call(element, element.value + text);
  element.dispatchEvent(new Event("input", { bubbles: true }));
}

/**
 * Plays a scene through `send`. Resolves after the last step's pause, with the area the crop element covered after
 * any step, or null without a crop or when it never showed.
 */
export async function playScene(scene: Scene, send: (message: NuiMessage) => void): Promise<Area | null> {
  let area: Area | null = null;

  for (const step of scene.steps) {
    if (step.send) {
      send(step.send);
    }

    const element = step.click ? document.querySelector<HTMLElement>(step.click) : null;

    if (element) {
      // React listens to mousedown for outside clicks: a bare click() would not close a menu.
      element.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
      element.click();
      element.focus();

      if (step.type) {
        // Letter by letter, so an animated capture shows the text being written.
        for (const letter of step.type) {
          typeInto(element, letter);
          await new Promise((resolve) => setTimeout(resolve, 45));
        }
      }
    }

    await new Promise((resolve) => setTimeout(resolve, step.wait ?? 0));

    const box = scene.crop ? document.querySelector(scene.crop)?.getBoundingClientRect() : undefined;

    if (box && box.width > 0) {
      const left = Math.min(area?.x ?? box.left, box.left);
      const top = Math.min(area?.y ?? box.top, box.top);
      const right = Math.max(area ? area.x + area.width : box.right, box.right);
      const bottom = Math.max(area ? area.y + area.height : box.bottom, box.bottom);

      area = { x: left, y: top, width: right - left, height: bottom - top };
    }
  }

  return area;
}
