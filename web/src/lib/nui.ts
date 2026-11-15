/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The only file that calls `fetch`. NUI callbacks are POSTs to `https://<resource>/<callback>`.

import { NuiCallback, type Action, type ActionArgs, type PanelSettings, type ReportCategory } from "@/types/protocol";

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

/** True in a normal browser (`npm run dev`), where no NUI callback endpoint exists. */
export function isEnvBrowser(): boolean {
  return typeof window.GetParentResourceName !== "function";
}

function resourceName(): string {
  return window.GetParentResourceName?.() ?? "ug-admin";
}

/** Sent requests in a browser, for the dev preview and tests. */
export const browserLog: { callback: string; data: unknown }[] = [];

/** Posts to Lua. Resolves whether Lua accepted the body. */
export async function postNui(callback: NuiCallback, data: unknown): Promise<boolean> {
  if (isEnvBrowser()) {
    browserLog.push({ callback, data });

    return true;
  }

  try {
    const response = await fetch(`https://${resourceName()}/${callback}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    });
    const reply = (await response.json()) as { ok?: unknown };

    return reply.ok === true;
  } catch {
    return false;
  }
}

export const sendReady = () => postNui(NuiCallback.Ready, {});
export const sendRefresh = () => postNui(NuiCallback.Refresh, {});
export const sendInspect = (id: number) => postNui(NuiCallback.Inspect, { id });
export const sendLogs = (search: string) => postNui(NuiCallback.Logs, { search });
export const sendClose = () => postNui(NuiCallback.Close, {});

/** The player's report window. */
export function sendReportOpen(message: string, category: ReportCategory, accused?: number) {
  return postNui(NuiCallback.ReportOpen, accused === undefined ? { message, category } : { message, category, accused });
}

export const sendReportReply = (text: string) => postNui(NuiCallback.ReportReply, { text });
export const sendReportCancel = () => postNui(NuiCallback.ReportCancel, {});
export const sendReportRate = (rating: number) => postNui(NuiCallback.ReportRate, { rating });
export const sendReportHide = () => postNui(NuiCallback.ReportHide, {});

/** Saves the panel settings on this PC. Built-in replies are left out, so Lua keeps none. */
export function sendSettings(settings: PanelSettings) {
  const { replies, ...rest } = settings;

  return postNui(NuiCallback.Settings, replies === null ? rest : { ...rest, replies });
}

/** Asks the server to run an action. The page sends intent only: the server checks access, rank and arguments. */
export function sendRun(action: Action, target?: number, args?: ActionArgs) {
  const body: { action: Action; target?: number; args?: ActionArgs } = { action };

  if (target !== undefined) {
    body.target = target;
  }

  if (args && Object.keys(args).length > 0) {
    body.args = args;
  }

  return postNui(NuiCallback.Run, body);
}
