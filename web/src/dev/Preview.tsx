/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Dev and showcase builds only: a stand-in for the game, buttons that play the scenes of scenes.ts, and buttons that
// send single messages as Lua would. `?scene=<id>` plays a scene on load, `?clean` hides the buttons.
// `npm run capture` drives it through window.__showcase.

import english from "../../../locales/en.json?raw";
import { DETAILS, LOGS, MY_REPORT_CHAT, MY_REPORT_CLOSED, NOCLIP, NOCLIP_PLAYER, OPEN, playScene, SCENES, type Area } from "@/dev/scenes";
import { handleMessage } from "@/store/adminStore";
import { Action, ErrorCode, NuiAction, type NuiMessage } from "@/types/protocol";

const send = (message: NuiMessage) => handleMessage(message);

const page = (JSON.parse(english) as { page: Record<string, unknown> }).page;

send({ action: NuiAction.Config, payload: { labels: page, locale: "en" } });

// An in-game screenshot without HUD, saved as src/dev/backdrop.jpg (or .png, .webp), replaces the gradient.
const BACKDROPS = import.meta.glob<string>("./backdrop.{jpg,png,webp}", { eager: true, query: "?url", import: "default" });
const backdrop = Object.values(BACKDROPS)[0];

const params = new URLSearchParams(window.location.search);
const clean = params.has("clean");

const MESSAGES: { label: string; message: NuiMessage }[] = [
  { label: "Open", message: { action: NuiAction.Open, payload: OPEN } },
  { label: "Details of #4", message: DETAILS },
  { label: "Logs", message: LOGS },
  { label: "Result: kicked", message: { action: NuiAction.Result, payload: { action: Action.Kick, ok: true } } },
  { label: "Result: outranked", message: { action: NuiAction.Result, payload: { action: Action.Ban, ok: false, error: ErrorCode.NoPermission } } },
  { label: "Close", message: { action: NuiAction.Close } },
  { label: "Report window", message: { action: NuiAction.ReportWindow, payload: { open: true } } },
  { label: "My report: chat", message: MY_REPORT_CHAT },
  { label: "My report: closed", message: MY_REPORT_CLOSED },
  { label: "My report: none", message: { action: NuiAction.MyReport } },
  { label: "Report window: close", message: { action: NuiAction.ReportWindow, payload: { open: false } } },
  { label: "Noclip: nothing", message: { action: NuiAction.Noclip, payload: { ...NOCLIP, target: undefined, can: { land: true } } } },
  { label: "Noclip: vehicle", message: { action: NuiAction.Noclip, payload: NOCLIP } },
  { label: "Noclip: player", message: { action: NuiAction.Noclip, payload: NOCLIP_PLAYER } },
  { label: "Noclip: keys hidden", message: { action: NuiAction.Noclip, payload: { ...NOCLIP, hud: false } } },
  { label: "Noclip: off", message: { action: NuiAction.Noclip, payload: { active: false } } },
];

declare global {
  interface Window {
    __showcase?: {
      scenes: { id: string; animated: boolean; crop: string | null }[];
      /** Plays a scene. Resolves with the area to crop to, null for the whole screen, undefined for an unknown id. */
      play: (id: string) => Promise<Area | null | undefined>;
    };
  }
}

window.__showcase = {
  scenes: SCENES.map((scene) => ({ id: scene.id, animated: scene.animated === true, crop: scene.crop ?? null })),
  play: async (id) => {
    const scene = SCENES.find((entry) => entry.id === id);

    return scene ? playScene(scene, send) : undefined;
  },
};

const initial = params.get("scene");

if (initial) {
  void window.__showcase.play(initial);
}

const BUTTON = "rounded-md bg-black/60 px-3 py-1.5 text-left text-xs text-white hover:bg-black/80";

export default function Preview() {
  return (
    <>
      {/* The game would be behind the page. */}
      {backdrop ? (
        <img src={backdrop} alt="" className="fixed inset-0 -z-10 size-full object-cover" />
      ) : (
        <div className="fixed inset-0 -z-10 bg-gradient-to-br from-slate-700 via-slate-800 to-slate-950" />
      )}
      {!clean && (
        <div className="fixed left-4 top-4 z-50 flex max-h-[calc(100vh-2rem)] flex-col gap-2 overflow-y-auto">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-white/50">Scenes</span>
          {SCENES.map((scene) => (
            <button key={scene.id} type="button" className={BUTTON} onClick={() => void playScene(scene, send)}>
              {scene.title}
            </button>
          ))}
          <span className="mt-2 text-[10px] font-semibold uppercase tracking-wider text-white/50">Messages</span>
          {MESSAGES.map((entry) => (
            <button key={entry.label} type="button" className={BUTTON} onClick={() => send(entry.message)}>
              {entry.label}
            </button>
          ))}
        </div>
      )}
    </>
  );
}
