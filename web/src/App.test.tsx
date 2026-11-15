/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { readFileSync } from "node:fs";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MotionGlobalConfig } from "framer-motion";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "@/App";
import { buildArgs, Field } from "@/lib/actions";
import { fill, score, since, speedShare } from "@/lib/format";
import { DEFAULT_LAYOUT, handleMessage, readLayout, readTabs, resetAdmin, useAdmin } from "@/store/adminStore";
import { toneShades } from "@/lib/theme";
import { Action, DeathState, NuiAction, ReportAuthor, ReportCategory, ReportStatus, TargetKind, type ActionArgs } from "@/types/protocol";

MotionGlobalConfig.skipAnimations = true;

const nui = vi.hoisted(() => ({
  isEnvBrowser: () => false,
  sendReady: vi.fn(async () => true),
  sendRefresh: vi.fn(async () => true),
  sendInspect: vi.fn(async (_id: number) => true),
  sendLogs: vi.fn(async (_search: string) => true),
  sendClose: vi.fn(async () => true),
  sendRun: vi.fn(async (_action: string, _target?: number, _args?: ActionArgs) => true),
  sendReportOpen: vi.fn(async (_message: string, _category: string, _accused?: number) => true),
  sendReportReply: vi.fn(async (_text: string) => true),
  sendReportCancel: vi.fn(async () => true),
  sendReportRate: vi.fn(async (_rating: number) => true),
  sendReportHide: vi.fn(async () => true),
  sendSettings: vi.fn(async (_settings: unknown) => true),
}));

vi.mock("@/lib/nui", () => nui);

const english = JSON.parse(readFileSync("../locales/en.json", "utf8")) as { page: Record<string, unknown> };

const send = (action: string, payload?: unknown) => act(() => handleMessage({ action: action as NuiAction, payload }));
const panel = () => document.querySelector("[data-panel]");
const button = (action: string) => document.querySelector(`[data-details] [data-action="${action}"]`) as HTMLElement;

const catalog = {
  accounts: [{ name: "bank", label: "Bank" }],
  jobs: [{ name: "police", label: "LSPD", grades: [{ grade: 1, label: "Cadet" }, { grade: 2, label: "Officer" }] }],
  gangs: [],
  items: [{ name: "water", label: "Water" }],
  groups: [{ name: "moderator", label: "Moderator", weight: 10 }],
  needs: [{ name: "hunger", label: "Hunger" }, { name: "thirst", label: "Thirst" }],
  locations: [{ name: "hospital", label: "Pillbox Hospital" }],
  banDurations: ["1d", "perm"],
};

const BOB = {
  id: 4,
  name: "Bob",
  characterId: 7,
  identifiers: ["license:4"],
  groups: [],
  state: DeathState.Downed,
  score: 12,
  back: false,
  armor: 10,
  accounts: { bank: 100 },
  items: [{ name: "water", count: 3, slot: 1 }],
  needs: { hunger: 50, thirst: 40 },
  history: [],
  notes: [],
};

const details = (extra: Record<string, unknown> = {}) => send(NuiAction.Player, { ...BOB, ...extra });
const find = (selector: string) => document.querySelector(selector) as HTMLElement;
const tab = (name: string) => fireEvent.click(find(`[data-detail-tab="${name}"]`));
const tabs = () => [...document.querySelectorAll("[data-detail-tab]")].map((entry) => entry.getAttribute("data-detail-tab"));

function open(access: string[] = Object.values(Action), extra: Record<string, unknown> = {}) {
  render(<App />);
  send(NuiAction.Config, { labels: english.page, locale: "en" });
  send(NuiAction.Open, {
    self: 1,
    access,
    players: [
      { id: 1, name: "Me", ping: 10, health: 200, state: DeathState.Alive, frozen: false, score: 0 },
      { id: 4, name: "Bob", characterId: 7, ping: 50, health: 150, state: DeathState.Downed, frozen: true, score: 12 },
    ],
    reports: [
      {
        id: 3,
        source: 4,
        name: "Bob",
        message: "help",
        category: ReportCategory.Stuck,
        status: ReportStatus.Open,
        at: 0,
        messages: [{ author: ReportAuthor.Player, name: "Bob", text: "help", at: 0 }],
        visitors: [],
        brought: false,
      },
    ],
    catalog,
    ...extra,
  });
}

function pickBob() {
  fireEvent.click(document.querySelector('[data-player="4"]') as HTMLElement);
}

beforeEach(() => {
  vi.clearAllMocks();
  act(() => resetAdmin());
});

describe("panel", () => {
  it("says ready once, and shows nothing until Lua opens it", () => {
    render(<App />);

    expect(nui.sendReady).toHaveBeenCalledTimes(1);
    expect(panel()).toBeNull();
  });

  it("lists players, filters them and inspects the one picked", () => {
    open();

    expect(screen.getByText("2 online")).toBeTruthy();

    fireEvent.change(screen.getByPlaceholderText("Search by name or id"), { target: { value: "bo" } });
    expect(document.querySelector('[data-player="1"]')).toBeNull();

    pickBob();
    expect(nui.sendInspect).toHaveBeenCalledWith(4);
    expect(document.querySelector("[data-details]")?.getAttribute("data-details")).toBe("4");
  });

  it("shows only the actions the staff member has", () => {
    open([Action.Panel, Action.Goto, Action.Kick]);
    pickBob();

    expect(button(Action.Goto)).toBeTruthy();
    expect(button(Action.Kick)).toBeTruthy();
    expect(button(Action.Ban)).toBeNull();
    expect(document.querySelector('[data-tab="reports"]')).toBeNull();
  });

  it("runs a simple action on the target in one click", () => {
    open();
    pickBob();

    fireEvent.click(button(Action.Bring));

    expect(nui.sendRun).toHaveBeenCalledWith(Action.Bring, 4, undefined);
  });

  it("asks a second click before a destructive action", () => {
    open();
    pickBob();

    fireEvent.click(button(Action.Kill));
    expect(nui.sendRun).not.toHaveBeenCalled();

    fireEvent.click(button(Action.Kill));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.Kill, 4, undefined);
  });

  it("sends form values as typed arguments", () => {
    open();
    pickBob();

    fireEvent.click(button(Action.SetJob));

    const [job, grade] = document.querySelectorAll("[data-details] form select");

    fireEvent.change(job as HTMLElement, { target: { value: "police" } });
    fireEvent.change(grade as HTMLElement, { target: { value: "2" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));

    expect(nui.sendRun).toHaveBeenCalledWith(Action.SetJob, 4, { job: "police", grade: 2 });
  });

  it("does not send a form with a missing field", () => {
    open();
    pickBob();

    fireEvent.click(button(Action.Warn));
    fireEvent.click(screen.getByRole("button", { name: "Send" }));

    expect(nui.sendRun).not.toHaveBeenCalled();
  });

  it("lights up the modes that are on and ignores unknown ones", () => {
    open();

    const toggle = (action: string) => document.querySelector(`[data-on][data-action="${action}"]`);

    expect(toggle(Action.God)?.getAttribute("data-on")).toBe("false");

    send(NuiAction.Modes, [Action.God, Action.Noclip, "<b>", Action.Kick]);
    expect(toggle(Action.God)?.getAttribute("data-on")).toBe("true");
    expect(toggle(Action.Noclip)?.getAttribute("data-on")).toBe("true");
    expect([...useAdmin.getState().modes].sort()).toEqual([Action.God, Action.Noclip]);

    send(NuiAction.Modes, {});
    expect(toggle(Action.God)?.getAttribute("data-on")).toBe("false");
  });

  it("filters players that are down, flagged or frozen", () => {
    open();

    fireEvent.click(document.querySelector('[data-filter="down"]') as HTMLElement);
    expect(document.querySelector('[data-player="1"]')).toBeNull();
    expect(document.querySelector('[data-player="4"]')).not.toBeNull();

    fireEvent.click(document.querySelector('[data-filter="all"]') as HTMLElement);
    expect(document.querySelector('[data-player="1"]')).not.toBeNull();
  });

  it("opens the report chat, answers, claims and travels", () => {
    open();
    send(NuiAction.Modes, [Action.Duty]);

    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);

    expect(document.querySelector("[data-chat]")?.getAttribute("data-chat")).toBe("3");
    expect(document.querySelectorAll('[data-chat] [data-line="player"]').length).toBe(1);
    expect(document.querySelector('[data-op="return"]')).toBeNull();
    expect(document.querySelector('[data-op="sendback"]')).toBeNull();

    fireEvent.click(document.querySelector('[data-op="claim"]') as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "claim" });

    fireEvent.click(document.querySelector('[data-op="goto"]') as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "goto" });

    fireEvent.change(document.querySelector("[data-composer]") as HTMLElement, { target: { value: "  on my way  " } });
    fireEvent.submit(document.querySelector("[data-composer]")?.closest("form") as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "reply", text: "on my way" });

    fireEvent.click(document.querySelector('[data-quick="done"]') as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "reply", text: "All sorted. Have fun!" });

    fireEvent.click(document.querySelector('[data-op="spectate"]') as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Spectate, 4);
  });

  it("pings staff with @: picks by player or character name, and sends their id", () => {
    open();
    send(NuiAction.Modes, [Action.Duty]);
    send(NuiAction.Players, [
      { id: 1, name: "Me", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true, duty: true },
      { id: 2, name: "Ann", characterId: 5, character: "Rita Vale", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true },
      { id: 4, name: "Bob", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0 },
    ]);
    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);

    const composer = document.querySelector("[data-composer]") as HTMLElement;

    // Only other staff are offered, found by character name too.
    fireEvent.change(composer, { target: { value: "ask @" } });
    expect([...document.querySelectorAll("[data-mention]")].map((entry) => entry.getAttribute("data-mention"))).toEqual(["2"]);

    fireEvent.change(composer, { target: { value: "ask @rita" } });
    fireEvent.click(document.querySelector('[data-mention="2"]') as HTMLElement);
    expect((composer as HTMLInputElement).value).toBe("ask @Ann ");
    expect(document.querySelector("[data-mentions]")).toBeNull();

    fireEvent.change(composer, { target: { value: "ask @Ann about it" } });
    fireEvent.submit(composer.closest("form") as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "reply", text: "ask @2 about it" });
  });

  it("says when nobody else can be pinged", () => {
    open();
    send(NuiAction.Modes, [Action.Duty]);
    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);
    fireEvent.change(document.querySelector("[data-composer]") as HTMLElement, { target: { value: "@" } });

    expect(document.querySelector("[data-mentions-empty]")?.textContent).toBe("No other staff online to ping.");
  });

  it("shows character faces the game sends, keeps their address, and drops broken ones", () => {
    open();
    send(NuiAction.Faces, { "4": "PEDHEADSHOT_2", "1": "bad/../x", "0": "PEDHEADSHOT_9", x: "PEDHEADSHOT_3" });

    const face = () => document.querySelector('[data-player="4"] [data-face]') as HTMLImageElement | null;
    const url = face()?.getAttribute("src");

    expect(url).toMatch(/^https:\/\/nui-img\/PEDHEADSHOT_2\/PEDHEADSHOT_2\?t=\d+$/);
    expect(document.querySelector('[data-player="1"] [data-face]')).toBeNull();
    expect(Object.keys(useAdmin.getState().faces)).toEqual(["4"]);

    send(NuiAction.Faces, { "4": "PEDHEADSHOT_2" });
    expect(face()?.getAttribute("src")).toBe(url);

    fireEvent.error(face() as HTMLImageElement);
    expect(face()).toBeNull();
  });

  it("highlights lines that ping the staff member", () => {
    open();
    send(NuiAction.Reports, [
      {
        id: 3,
        source: 4,
        name: "Bob",
        message: "help",
        category: ReportCategory.Stuck,
        status: ReportStatus.Open,
        at: 0,
        messages: [
          { author: ReportAuthor.Staff, name: "Ann", text: "@Me look", at: 0, mentions: [1] },
          { author: ReportAuthor.Staff, name: "Ann", text: "@Zed look", at: 0, mentions: [9, "x"] },
        ],
        visitors: [],
        brought: false,
      },
    ]);
    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);

    expect(document.querySelectorAll("[data-mentioned]").length).toBe(1);
    expect(useAdmin.getState().reports[0]?.messages[1]?.mentions).toEqual([9]);
  });

  it("hands a report to staff on duty from a searchable staff list", () => {
    open();
    send(NuiAction.Players, [
      { id: 1, name: "Me", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true, duty: true },
      { id: 2, name: "Ann", character: "Rita Vale", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true, duty: true },
      { id: 5, name: "Cid", character: "Carl Ito", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true },
      { id: 4, name: "Bob", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0 },
    ]);
    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);
    fireEvent.click(document.querySelector('[data-op="assign"]') as HTMLElement);

    const listed = () => [...document.querySelectorAll("[data-assign-to]")].map((entry) => entry.getAttribute("data-assign-to"));

    expect(listed()).toEqual(["2", "1", "5"]);
    expect((document.querySelector('[data-assign-to="5"]') as HTMLButtonElement).disabled).toBe(true);

    fireEvent.change(document.querySelector("[data-assign-search]") as HTMLElement, { target: { value: "rita" } });
    expect(listed()).toEqual(["2"]);

    fireEvent.click(document.querySelector('[data-assign-to="2"]') as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "assign", staff: 2 });
  });

  it("inserts emojis at the caret and mentions staff picked from the box", async () => {
    open();
    send(NuiAction.Modes, [Action.Duty]);
    send(NuiAction.Players, [
      { id: 1, name: "Me", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true, duty: true },
      { id: 2, name: "Ann", character: "Rita Vale", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, staff: true },
      { id: 4, name: "Bob", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0 },
    ]);
    fireEvent.click(find('[data-tab="reports"]'));

    const composer = find("[data-composer]") as HTMLInputElement;

    fireEvent.change(composer, { target: { value: "hi there" } });
    fireEvent.click(find('[data-tool="emoji"]'));
    fireEvent.click([...document.querySelectorAll("[data-emoji]")].find((entry) => entry.getAttribute("data-emoji") === "👋") as HTMLElement);
    expect(composer.value).toBe("hi there👋");

    fireEvent.mouseDown(composer);
    await waitFor(() => expect(document.querySelector("[data-tool-panel]")).toBeNull());

    fireEvent.click(find('[data-tool="mention"]'));
    expect(document.querySelector('[data-tool-panel="mention"]')).not.toBeNull();
    fireEvent.mouseDown(composer);
    await waitFor(() => expect(document.querySelector("[data-tool-panel]")).toBeNull());

    fireEvent.click(find('[data-tool="mention"]'));
    expect([...document.querySelectorAll("[data-pick-staff]")].map((entry) => entry.getAttribute("data-pick-staff"))).toEqual(["2"]);
    fireEvent.change(find("[data-tool-search]"), { target: { value: "nobody" } });
    expect(document.querySelector("[data-pick-staff]")).toBeNull();
    fireEvent.change(find("[data-tool-search]"), { target: { value: "rita" } });
    fireEvent.click(find('[data-pick-staff="2"]'));
    expect(composer.value).toBe("hi there👋 @Ann ");

    fireEvent.submit(composer.closest("form") as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "reply", text: "hi there👋 @2" });
  });

  it("orders and hides quick actions, hides actions on everyone, and saves it all", async () => {
    open();
    fireEvent.click(find('[data-tab="settings"]'));

    const bar = () => [...document.querySelectorAll("[data-on][data-action]")].map((entry) => entry.getAttribute("data-action"));

    expect(bar().slice(0, 2)).toEqual([Action.Duty, Action.Noclip]);

    fireEvent.click(find(`[data-down="${Action.Duty}"]`));
    expect(bar().slice(0, 2)).toEqual([Action.Noclip, Action.Duty]);
    expect(find(`[data-up="${Action.Noclip}"]`)).toHaveProperty("disabled", true);

    fireEvent.click(find(`[data-toggle="${Action.Vision}"]`));
    expect(bar()).not.toContain(Action.Vision);
    expect(find(`[data-quick-item="${Action.Vision}"]`).getAttribute("data-shown")).toBe("false");

    expect(document.querySelector("[data-bulk]")).not.toBeNull();
    fireEvent.click(find('[data-setting="everyone"]'));
    expect(document.querySelector("[data-bulk]")).toBeNull();

    await waitFor(() => expect(nui.sendSettings).toHaveBeenCalledTimes(1));
    expect(nui.sendSettings).toHaveBeenLastCalledWith(
      expect.objectContaining({ hidden: [Action.Vision], everyone: false, replies: null, tab: "players", confirm: true }),
    );

    const saved = (nui.sendSettings.mock.lastCall?.[0] ?? {}) as { order: string[] };

    expect(saved.order.slice(0, 2)).toEqual([Action.Noclip, Action.Duty]);

    fireEvent.click(find("[data-reset]"));
    expect(bar().slice(0, 3)).toEqual([Action.Duty, Action.Noclip, Action.Vision]);
  });

  it("drops the second click when confirmations are off", () => {
    open();
    fireEvent.click(find('[data-tab="settings"]'));
    fireEvent.click(find('[data-setting="confirm"]'));
    fireEvent.click(find('[data-tab="players"]'));
    pickBob();

    fireEvent.click(button(Action.Kill));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.Kill, 4, undefined);
  });

  it("opens on the saved tab, and reads broken settings as defaults", () => {
    open(Object.values(Action), { settings: { tab: "reports", order: ["nope", Action.Vision, Action.Vision], hidden: "x", replies: ["Hi!", 5, " "] } });

    const state = useAdmin.getState();

    expect(state.tab).toBe("reports");
    expect(state.settings).toEqual({ order: [Action.Vision], hidden: [], everyone: true, tab: "reports", confirm: true, replies: ["Hi!"] });

    // Without reports access, the panel opens on the players.
    open([Action.Panel], { settings: { tab: "reports" } });
    expect(useAdmin.getState().tab).toBe("players");
  });

  it("own quick replies replace the built-in ones in the report chat", () => {
    open();
    send(NuiAction.Modes, [Action.Duty]);
    fireEvent.click(find('[data-tab="settings"]'));

    expect(document.querySelectorAll("[data-reply]").length).toBe(4);

    fireEvent.change(find("[data-reply-input]"), { target: { value: "  Be right there  " } });
    fireEvent.click(find("[data-add-reply]"));
    fireEvent.click(find('[data-remove-reply="0"]'));
    expect(useAdmin.getState().settings.replies).toEqual([
      "Can you tell me more about what happened?",
      "Give me a minute, I am looking into it.",
      "All sorted. Have fun!",
      "Be right there",
    ]);

    fireEvent.click(find('[data-tab="reports"]'));
    expect(document.querySelector('[data-quick="onMyWay"]')).toBeNull();
    fireEvent.click(find('[data-quick="own-3"]'));
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "reply", text: "Be right there" });
  });

  it("keeps staff off duty from taking reports, and puts them on duty in one click", () => {
    open();
    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);

    expect(document.querySelector("[data-off-duty]")).not.toBeNull();
    expect(document.querySelector('[data-op="claim"]')).toBeNull();
    expect(document.querySelector('[data-op="goto"]')).toBeNull();
    expect(document.querySelector('[data-op="close"]')).not.toBeNull();
    expect((document.querySelector("[data-composer]") as HTMLInputElement).disabled).toBe(true);
    expect(document.querySelector("[data-on-duty]")?.textContent).toBe("0 on duty");

    fireEvent.click(document.querySelector("[data-go-on-duty]") as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Duty);

    send(NuiAction.Modes, [Action.Duty]);
    expect(document.querySelector("[data-off-duty]")).toBeNull();
    expect(document.querySelector('[data-op="claim"]')).not.toBeNull();
  });

  it("shows trips back, marks new messages and closes with a note", async () => {
    open();
    send(NuiAction.Modes, [Action.Duty]);
    fireEvent.click(document.querySelector('[data-tab="reports"]') as HTMLElement);

    const report = (id: number, extra: Record<string, unknown>) => ({
      id,
      source: 4,
      name: "Bob",
      message: "help",
      category: ReportCategory.Player,
      status: ReportStatus.Claimed,
      claimer: 1,
      claimedBy: "Me",
      at: 0,
      messages: [{ author: ReportAuthor.Player, name: "Bob", text: "help", at: 0 }],
      visitors: [1],
      brought: true,
      ...extra,
    });

    send(NuiAction.Reports, [
      report(3, { accused: 9, accusedName: "Trevor" }),
      report(5, {
        status: ReportStatus.Open,
        claimer: undefined,
        visitors: [],
        brought: false,
        messages: [
          { author: ReportAuthor.Player, name: "Bob", text: "help", at: 0 },
          { author: ReportAuthor.Player, name: "Bob", text: "hello?", at: 1 },
        ],
      }),
    ]);

    expect(document.querySelector('[data-op="return"]')).not.toBeNull();
    expect(document.querySelector('[data-op="sendback"]')).not.toBeNull();
    expect(document.querySelector('[data-op="release"]')).not.toBeNull();
    expect(document.querySelector("[data-accused]")?.textContent).toContain("Trevor");
    expect(document.querySelector('[data-report="5"] [data-unread]')).not.toBeNull();
    expect(document.querySelector('[data-report="3"] [data-unread]')).toBeNull();

    fireEvent.click(document.querySelector('[data-desk-filter="mine"]') as HTMLElement);
    await waitFor(() => expect(document.querySelector('[data-report="5"]')).toBeNull());

    fireEvent.click(document.querySelector('[data-op="close"]') as HTMLElement);
    fireEvent.change(document.querySelector("[data-composer]") as HTMLElement, { target: { value: "sorted" } });
    fireEvent.submit(document.querySelector("[data-composer]")?.closest("form") as HTMLElement);
    expect(nui.sendRun).toHaveBeenLastCalledWith(Action.Reports, undefined, { report: 3, op: "close", text: "sorted" });

    send(NuiAction.Reports, [report(3, { status: ReportStatus.Closed, closedBy: "Me", rating: 4 })]);
    fireEvent.click(document.querySelector('[data-desk-filter="closed"]') as HTMLElement);
    expect(document.querySelector("[data-rating]")?.getAttribute("data-rating")).toBe("4");
    expect(document.querySelector("[data-composer]")).toBeNull();
  });

  it("searches logs after a pause", async () => {
    open();

    fireEvent.click(document.querySelector('[data-tab="logs"]') as HTMLElement);
    await waitFor(() => expect(nui.sendLogs).toHaveBeenCalledWith(""));

    send(NuiAction.Logs, [{ id: 1, actor: "console", actorName: "Console", action: Action.Kick, targetName: "Bob", detail: "afk", at: 0 }]);
    expect(document.querySelectorAll("[data-log]").length).toBe(1);
  });

  it("shows results as text and drops unknown actions", () => {
    open();

    send(NuiAction.Result, { action: Action.Ban, ok: false, error: "no_permission" });
    expect(screen.getByText("You are not allowed to do that.")).toBeTruthy();

    send(NuiAction.Result, { action: "<img src=x>", ok: true });
    expect(useAdmin.getState().toast?.action).toBe(Action.Ban);
  });

  it("drops broken messages", () => {
    render(<App />);
    send(NuiAction.Open, null);
    send(NuiAction.Players, [{ id: "1" }, null, { id: 2, name: "Ok" }]);

    expect(panel()).toBeNull();
    expect(useAdmin.getState().players.map((player) => player.id)).toEqual([2]);
  });

  it("ignores details of a player that is not selected", () => {
    open();
    send(NuiAction.Player, { id: 4, name: "Bob", identifiers: [], groups: [], state: DeathState.Alive, score: 0, back: false });

    expect(useAdmin.getState().details).toBeNull();
  });

  it("closes with Escape", async () => {
    open();

    fireEvent.keyDown(window, { key: "Escape" });

    expect(nui.sendClose).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(panel()).toBeNull());
  });
});

describe("player management", () => {
  it("splits the details into tabs, shows only the ones that apply and keeps the header in place", () => {
    open([Action.Panel, Action.Goto, Action.Note]);
    pickBob();

    expect(tabs()).toEqual(["actions"]);
    expect(find("[data-detail-panel]").getAttribute("data-detail-panel")).toBe("actions");

    details({ notes: [{ id: 5, authorName: "Ann", text: "watch him", at: 0 }] });
    expect(tabs()).toEqual(["actions", "inventory", "records", "info"]);
    expect(find('[data-detail-tab="records"]').textContent).toContain("1");

    tab("records");
    expect(find('[data-note="5"]')).not.toBeNull();
    expect(button(Action.Goto)).toBeNull();
    expect(screen.getAllByText("Bob").length).toBeGreaterThan(0);

    tab("info");
    expect(screen.getByText("license:4")).toBeTruthy();
  });

  it("jails with minutes and an optional reason, then counts down and releases", () => {
    open();
    pickBob();

    fireEvent.click(button(Action.Jail));
    fireEvent.change(document.querySelectorAll("[data-details] form input")[0] as HTMLElement, { target: { value: "30" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.Jail, 4, { minutes: 30 });

    details({ jail: 125 });
    expect(find('[data-sanction="unjail"]').textContent).toContain("2:05");

    fireEvent.click(screen.getByRole("button", { name: "Release" }));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.Unjail, 4);
  });

  it("sends a player to a config place or to the staff waypoint", () => {
    open();
    pickBob();

    fireEvent.click(button(Action.SendTo));

    const select = find("[data-details] form select") as HTMLSelectElement;

    expect([...select.options].map((option) => option.value)).toEqual(["", "waypoint", "hospital"]);
    fireEvent.change(select, { target: { value: "hospital" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.SendTo, 4, { location: "hospital" });
  });

  it("applies only the stats that changed, and never health on a downed player", () => {
    open();
    pickBob();
    details();
    tab("stats");

    expect((find('[data-meter="health"]') as HTMLInputElement).disabled).toBe(true);

    fireEvent.change(find('[data-meter="armor"]'), { target: { value: "80" } });
    fireEvent.change(find('[data-meter="hunger"]'), { target: { value: "90" } });
    fireEvent.click(find("[data-apply-stats]"));

    expect(nui.sendRun).toHaveBeenCalledWith(Action.SetStats, 4, { health: undefined, armor: 80 });
    expect(nui.sendRun).toHaveBeenCalledWith(Action.SetNeed, 4, { need: "hunger", value: 90 });
    expect(nui.sendRun).toHaveBeenCalledTimes(2);
  });

  it("sets an exact balance and removes items from one slot", () => {
    open();
    pickBob();
    details();
    tab("inventory");

    fireEvent.click(find('[data-account="bank"] button'));
    fireEvent.change(find("[data-balance-input]"), { target: { value: "2500" } });
    fireEvent.submit(find("[data-balance-input]"));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.SetMoney, 4, { account: "bank", amount: 2500 });

    fireEvent.click(find('[data-slot="1"]'));
    fireEvent.change(find("[data-remove-count]"), { target: { value: "2" } });
    fireEvent.click(find("[data-remove]"));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.RemoveItem, 4, { slot: 1, count: 2 });
  });

  it("shows history, adds notes and deletes them", () => {
    open();
    pickBob();
    details({
      history: [{ id: 1, actor: "license:1", actorName: "Ann", action: Action.Warn, detail: "rdm", at: 0 }],
      notes: [{ id: 5, authorName: "Ann", text: "watch him", at: 0 }],
    });
    tab("records");

    expect(find('[data-history="warn"]').textContent).toContain("rdm");
    expect(find('[data-note="5"]').textContent).toContain("watch him");

    fireEvent.change(find("[data-note-input]"), { target: { value: "  second strike  " } });
    fireEvent.submit(find("[data-note-input]"));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.Note, 4, { text: "second strike" });

    fireEvent.click(find('[data-delete-note="5"]'));
    expect(nui.sendRun).toHaveBeenCalledWith(Action.DeleteNote, 4, { note: 5 });
  });

  it("keeps actions on everyone in a menu, and asks a second click before them", () => {
    open();

    expect(document.querySelector(`[data-action="${Action.ReviveAll}"]`)).toBeNull();
    fireEvent.click(find("[data-bulk-toggle]"));

    const revive = find(`[data-bulk] [data-action="${Action.ReviveAll}"]`);

    fireEvent.click(revive);
    expect(nui.sendRun).not.toHaveBeenCalled();

    fireEvent.click(revive);
    expect(nui.sendRun).toHaveBeenCalledWith(Action.ReviveAll, undefined, undefined);
  });

  it("marks staff on duty in the list and filters them", () => {
    open();
    send(NuiAction.Players, [
      { id: 2, name: "Mod", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, duty: true },
      { id: 4, name: "Bob", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, duty: "yes" },
    ]);

    expect(document.querySelector('[data-player="2"] [data-duty]')).not.toBeNull();
    expect(document.querySelector('[data-player="4"] [data-duty]')).toBeNull();

    fireEvent.click(find('[data-filter="duty"]'));
    expect(document.querySelector('[data-player="2"]')).not.toBeNull();
    expect(document.querySelector('[data-player="4"]')).toBeNull();
  });

  it("marks jailed and muted players in the list, and drops broken management fields", () => {
    open();
    send(NuiAction.Players, [{ id: 4, name: "Bob", ping: 1, health: 200, state: DeathState.Alive, frozen: false, score: 0, jailed: 60, muted: -1 }]);

    expect(document.querySelector('[data-player="4"] [data-jailed]')).not.toBeNull();
    expect(document.querySelector('[data-player="4"] [data-muted]')).toBeNull();

    pickBob();
    details({ jail: -5, needs: { hunger: "x", thirst: 500 }, notes: [{ id: "a" }], history: {} });

    const state = useAdmin.getState().details;

    expect(state?.jail).toBeUndefined();
    expect(state?.needs).toEqual({ thirst: 100 });
    expect(state?.notes).toEqual([]);
    expect(state?.history).toEqual([]);
  });
});

describe("noclip", () => {
  const flight = {
    active: true,
    hud: true,
    speed: 12.4,
    minSpeed: 1.5,
    maxSpeed: 200,
    leave: "F2",
    coords: { x: 1, y: 2, z: 3 },
    heading: 90,
    target: { kind: TargetKind.Vehicle, name: "Sultan", plate: "UG 042", model: 970598228, netId: 31, owner: 1 },
    can: { land: true, delete: true, freeze: false, board: true },
  };
  const row = (name: string) => document.querySelector(`[data-key-row="${name}"]`);

  function fly(payload: unknown) {
    render(<App />);
    send(NuiAction.Config, { labels: english.page, locale: "en" });
    send(NuiAction.Noclip, payload);
  }

  it("shows the keys, the speed and the target, and enables only the keys that apply", () => {
    fly(flight);

    expect(document.querySelector("[data-noclip-legend]")).not.toBeNull();
    expect(document.querySelector("[data-speed]")?.textContent).toBe("12");
    expect(document.querySelector("[data-target]")?.getAttribute("data-target")).toBe(TargetKind.Vehicle);
    expect(screen.getByText("UG 042")).toBeTruthy();
    expect(row("delete")?.getAttribute("data-enabled")).toBe("true");
    expect(row("freeze")?.getAttribute("data-enabled")).toBe("false");
    expect(row("board")?.getAttribute("data-enabled")).toBe("true");
    expect(screen.getByText("F2")).toBeTruthy();
  });

  it("collapses to one hint, and goes away when noclip stops", async () => {
    fly({ ...flight, hud: false });

    await waitFor(() => expect(document.querySelector("[data-noclip-legend]")).toBeNull());
    expect(document.querySelector("[data-noclip-collapsed]")).not.toBeNull();
    expect(document.querySelector("[data-target]")).toBeNull();

    send(NuiAction.Noclip, { active: false });
    await waitFor(() => expect(document.querySelector("[data-noclip]")).toBeNull());
  });

  it("drops broken flight payloads and unknown targets", () => {
    fly({ ...flight, speed: "fast", target: { kind: "plane", model: 1 }, can: "all", coords: null });

    expect(document.querySelector("[data-speed]")?.textContent).toBe("1.5");
    expect(document.querySelector("[data-target]")).toBeNull();
    expect(row("land")?.getAttribute("data-enabled")).toBe("false");

    send(NuiAction.Noclip, "nope");
    expect(useAdmin.getState().noclip).toBeNull();
  });

  it("scales speed on a log range", () => {
    expect(speedShare(1.5, 1.5, 200)).toBe(0);
    expect(speedShare(200, 1.5, 200)).toBe(1);
    expect(speedShare(Math.sqrt(1.5 * 200), 1.5, 200)).toBeCloseTo(0.5);
    expect(speedShare(5, 5, 5)).toBe(1);
  });
});

describe("owner config", () => {
  function openWith(config: Record<string, unknown>, access: string[] = Object.values(Action)) {
    render(<App />);
    send(NuiAction.Config, { labels: english.page, locale: "en", ...config });
    send(NuiAction.Open, { self: 1, access, players: [], reports: [], catalog });
  }

  const tabIds = () => [...document.querySelectorAll("[data-tab]")].map((entry) => entry.getAttribute("data-tab"));

  it("sizes the window, moves the rail and drops the extras the owner turned off", () => {
    openWith({ layout: { width: 60, height: 40, rail: "right", backdrop: 0.2, glow: false, logo: false, quickBar: false } });

    const windowElement = find("[data-panel-window]");

    expect(windowElement.style.width).toBe("min(60rem, 96vw)");
    expect(windowElement.dataset.rail).toBe("right");
    expect(windowElement.className).toContain("flex-row-reverse");
    expect(find("[data-panel]").style.backgroundColor).toContain("0.2");
    expect(document.querySelector("[data-glow]")).toBeNull();
    expect(document.querySelector("[data-logo]")).toBeNull();
    expect(document.querySelector("[data-quickbar]")).toBeNull();
  });

  it("shows the owner's tabs in order, and opens on the first one when the saved tab is hidden", () => {
    openWith({ tabs: ["logs", "settings"] });

    expect(tabIds()).toEqual(["logs", "settings"]);
    expect(useAdmin.getState().tab).toBe("logs");
  });

  it("keeps reports hidden from staff who may not take them", () => {
    openWith({ tabs: ["reports", "settings"] }, [Action.Panel]);

    expect(tabIds()).toEqual(["settings"]);
  });

  it("hides the noclip HUD when the owner turned it off", () => {
    render(<App />);
    send(NuiAction.Config, { labels: english.page, locale: "en", layout: { noclipHud: false } });
    send(NuiAction.Noclip, { active: true, hud: true, speed: 1, minSpeed: 1, maxSpeed: 10, leave: "F2", coords: { x: 0, y: 0, z: 0 }, heading: 0, can: { land: false, delete: false, freeze: false, board: false } });

    expect(document.querySelector("[data-noclip]")).toBeNull();
  });

  it("recolors a tone and derives its shades", () => {
    render(<App />);
    send(NuiAction.Config, { labels: english.page, locale: "en", theme: { colors: { violet: "10 80% 50%" } } });

    const style = document.documentElement.style;

    expect(style.getPropertyValue("--ug-tone-violet-500")).toBe("10 80% 50%");
    expect(style.getPropertyValue("--ug-tone-violet-300")).toBe("10 80% 68%");
    expect(style.getPropertyValue("--ug-tone-indigo-500")).toBe("");
    expect(toneShades("200 50% 90%")[200]).toBe("200 50% 94%");
  });

  it("reads layout and tabs field by field", () => {
    expect(readLayout(null)).toEqual(DEFAULT_LAYOUT);
    expect(readLayout({ width: 500, rail: "up", toasts: "top", glow: "no" })).toEqual({ ...DEFAULT_LAYOUT, width: 160, toasts: "top" });
    expect(readTabs(["logs", "logs", "nope"])).toEqual(["logs"]);
    expect(readTabs([])).toEqual(["players", "reports", "logs", "settings"]);
  });
});

describe("helpers", () => {
  it("builds arguments from form values", () => {
    expect(buildArgs([Field.Account, Field.Amount], { account: "bank", amount: "-50" })).toEqual({ account: "bank", amount: -50 });
    expect(buildArgs([Field.Amount], { amount: "1e9" })).toBeNull();
    expect(buildArgs([Field.Gang, Field.Grade], { gang: "ballas" })).toEqual({ job: "ballas" });
    expect(buildArgs([Field.Reason], { reason: "  " })).toBeNull();
  });

  it("fills placeholders and formats times", () => {
    expect(fill("In {time} for {who}", { time: "1:00" })).toBe("In 1:00 for {who}");
    expect(since(100, 145)).toBe("45s");
    expect(since(0, 7200)).toBe("2h");
    expect(since(0, 200_000)).toBe("2d");
    expect(score(0.37876666666666)).toBe(0.4);
    expect(score(0.04)).toBe(0);
    expect(score(12)).toBe(12);
  });
});

describe("report window", () => {
  const own = (extra: Record<string, unknown> = {}) => ({
    id: 2,
    message: "stuck",
    category: ReportCategory.Stuck,
    status: ReportStatus.Open,
    at: 0,
    messages: [{ author: ReportAuthor.Player, name: "Bob", text: "stuck", at: 0 }],
    ...extra,
  });

  function openWindow() {
    render(<App />);
    send(NuiAction.Config, { labels: english.page, locale: "en" });
    send(NuiAction.ReportWindow, { open: true });
  }

  it("sends a report with a category and the player reported", async () => {
    openWindow();

    fireEvent.click(document.querySelector('[data-category="player"]') as HTMLElement);
    fireEvent.change(document.querySelector("[data-accused-input]") as HTMLElement, { target: { value: "1x2" } });
    fireEvent.change(document.querySelector("[data-report-message]") as HTMLElement, { target: { value: " he rams me " } });
    fireEvent.submit(document.querySelector("[data-report-form]") as HTMLElement);

    expect(nui.sendReportOpen).toHaveBeenCalledWith("he rams me", "player", 12);

    fireEvent.keyDown(window, { key: "Escape" });
    expect(nui.sendReportHide).toHaveBeenCalledOnce();
    await waitFor(() => expect(document.querySelector("[data-report-window]")).toBeNull());
  });

  it("chats with staff, cancels, and rates a closed report", () => {
    openWindow();
    send(NuiAction.MyReport, own({ status: ReportStatus.Claimed, claimedBy: "Urging" }));

    expect(document.querySelector("[data-my-status]")?.textContent).toContain("Urging is on it");

    const reply = document.querySelector("[data-reply]") as HTMLInputElement;
    const pick = (emoji: string) =>
      fireEvent.click([...document.querySelectorAll("[data-emoji]")].find((entry) => entry.getAttribute("data-emoji") === emoji) as HTMLElement);

    fireEvent.change(reply, { target: { value: "still here" } });
    fireEvent.click(reply.closest("form")?.querySelector('[data-tool="emoji"]') as HTMLElement);
    pick("👋");
    expect(reply.value).toBe("still here👋");
    fireEvent.submit(reply.closest("form") as HTMLElement);
    expect(nui.sendReportReply).toHaveBeenCalledWith("still here👋");

    fireEvent.click(document.querySelector("[data-cancel]") as HTMLElement);
    expect(nui.sendReportCancel).toHaveBeenCalledOnce();

    send(NuiAction.MyReport, own({ status: ReportStatus.Closed, closedBy: "Urging" }));
    fireEvent.click(document.querySelector('[data-star="4"]') as HTMLElement);
    expect(nui.sendReportRate).toHaveBeenCalledWith(4);
    expect(screen.getByText("Thanks for the feedback!")).toBeTruthy();
  });

  it("pops a bubble for a staff answer while the window is closed", async () => {
    render(<App />);
    send(NuiAction.Config, { labels: english.page, locale: "en" });
    send(NuiAction.MyReport, own());

    expect(document.querySelector("[data-report-bubble]")).toBeNull();

    send(NuiAction.MyReport, own({ messages: [...own().messages, { author: ReportAuthor.Staff, name: "Urging", text: "on my way", at: 1 }] }));
    expect(document.querySelector("[data-report-bubble]")?.textContent).toContain("on my way");

    send(NuiAction.ReportWindow, { open: true });
    await waitFor(() => expect(document.querySelector("[data-report-bubble]")).toBeNull());
    expect(document.querySelector('[data-report-window] [data-line="staff"]')?.textContent).toContain("on my way");
  });

  it("drops broken chat lines", () => {
    render(<App />);
    send(NuiAction.MyReport, own({ messages: [{ author: "hacker", name: "x", text: "y", at: 0 }, null, { author: ReportAuthor.Staff, text: 5 }], category: "nope" }));

    expect(useAdmin.getState().myReport?.messages).toEqual([]);
    expect(useAdmin.getState().myReport?.category).toBe(ReportCategory.Other);
  });
});
