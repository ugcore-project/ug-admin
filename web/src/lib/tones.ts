/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Accent colors that tell the sections of the panel apart. The brand gradient follows the ug-core logo:
// violet to indigo to blue. Class names are written out in full so Tailwind finds them.

import { ActionGroup } from "@/lib/actions";
import { Action } from "@/types/protocol";

export const Tone = {
  Violet: "violet",
  Indigo: "indigo",
  Blue: "blue",
  Sky: "sky",
  Teal: "teal",
  Emerald: "emerald",
  Amber: "amber",
  Rose: "rose",
  Fuchsia: "fuchsia",
} as const;

export type Tone = (typeof Tone)[keyof typeof Tone];

export interface ToneClasses {
  /** Icon chip: tinted background and text. */
  chip: string;
  /** Text and icon color alone. */
  text: string;
  /** Hover state of a neutral tile or pill. */
  hover: string;
  /** Selected or open state. */
  active: string;
  /** A switched-on toggle, solid with a glow. */
  solid: string;
  /** A small dot or bar. */
  dot: string;
}

export const TONES: Record<Tone, ToneClasses> = {
  [Tone.Violet]: {
    chip: "bg-violet-500/15 text-violet-300",
    text: "text-violet-300",
    hover: "hover:border-violet-400/40 hover:bg-violet-500/10",
    active: "border-violet-400/60 bg-violet-500/15 text-violet-200 ring-1 ring-violet-400/30",
    solid: "border-violet-400/70 bg-violet-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-violet-500))]",
    dot: "bg-violet-400",
  },
  [Tone.Indigo]: {
    chip: "bg-indigo-500/15 text-indigo-300",
    text: "text-indigo-300",
    hover: "hover:border-indigo-400/40 hover:bg-indigo-500/10",
    active: "border-indigo-400/60 bg-indigo-500/15 text-indigo-200 ring-1 ring-indigo-400/30",
    solid: "border-indigo-400/70 bg-indigo-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-indigo-500))]",
    dot: "bg-indigo-400",
  },
  [Tone.Blue]: {
    chip: "bg-blue-500/15 text-blue-300",
    text: "text-blue-300",
    hover: "hover:border-blue-400/40 hover:bg-blue-500/10",
    active: "border-blue-400/60 bg-blue-500/15 text-blue-200 ring-1 ring-blue-400/30",
    solid: "border-blue-400/70 bg-blue-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-blue-500))]",
    dot: "bg-blue-400",
  },
  [Tone.Sky]: {
    chip: "bg-sky-500/15 text-sky-300",
    text: "text-sky-300",
    hover: "hover:border-sky-400/40 hover:bg-sky-500/10",
    active: "border-sky-400/60 bg-sky-500/15 text-sky-200 ring-1 ring-sky-400/30",
    solid: "border-sky-400/70 bg-sky-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-sky-500))]",
    dot: "bg-sky-400",
  },
  [Tone.Teal]: {
    chip: "bg-teal-500/15 text-teal-300",
    text: "text-teal-300",
    hover: "hover:border-teal-400/40 hover:bg-teal-500/10",
    active: "border-teal-400/60 bg-teal-500/15 text-teal-200 ring-1 ring-teal-400/30",
    solid: "border-teal-400/70 bg-teal-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-teal-500))]",
    dot: "bg-teal-400",
  },
  [Tone.Emerald]: {
    chip: "bg-emerald-500/15 text-emerald-300",
    text: "text-emerald-300",
    hover: "hover:border-emerald-400/40 hover:bg-emerald-500/10",
    active: "border-emerald-400/60 bg-emerald-500/15 text-emerald-200 ring-1 ring-emerald-400/30",
    solid: "border-emerald-400/70 bg-emerald-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-emerald-500))]",
    dot: "bg-emerald-400",
  },
  [Tone.Amber]: {
    chip: "bg-amber-500/15 text-amber-300",
    text: "text-amber-300",
    hover: "hover:border-amber-400/40 hover:bg-amber-500/10",
    active: "border-amber-400/60 bg-amber-500/15 text-amber-200 ring-1 ring-amber-400/30",
    solid: "border-amber-400/70 bg-amber-500 text-amber-950 shadow-[0_0_18px_-4px_hsl(var(--ug-tone-amber-500))]",
    dot: "bg-amber-400",
  },
  [Tone.Rose]: {
    chip: "bg-rose-500/15 text-rose-300",
    text: "text-rose-300",
    hover: "hover:border-rose-400/40 hover:bg-rose-500/10",
    active: "border-rose-400/60 bg-rose-500/15 text-rose-200 ring-1 ring-rose-400/30",
    solid: "border-rose-400/70 bg-rose-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-rose-500))]",
    dot: "bg-rose-400",
  },
  [Tone.Fuchsia]: {
    chip: "bg-fuchsia-500/15 text-fuchsia-300",
    text: "text-fuchsia-300",
    hover: "hover:border-fuchsia-400/40 hover:bg-fuchsia-500/10",
    active: "border-fuchsia-400/60 bg-fuchsia-500/15 text-fuchsia-200 ring-1 ring-fuchsia-400/30",
    solid: "border-fuchsia-400/70 bg-fuchsia-500 text-white shadow-[0_0_18px_-4px_hsl(var(--ug-tone-fuchsia-500))]",
    dot: "bg-fuchsia-400",
  },
};

/** The ug-core logo gradient. */
export const BRAND_GRADIENT = "bg-gradient-to-br from-violet-500 via-indigo-500 to-blue-500";
export const BRAND_TEXT = "bg-gradient-to-r from-violet-300 via-indigo-300 to-blue-300 bg-clip-text text-transparent";

export const GROUP_TONES: Record<ActionGroup, Tone> = {
  [ActionGroup.Move]: Tone.Sky,
  [ActionGroup.Care]: Tone.Emerald,
  [ActionGroup.Discipline]: Tone.Amber,
  [ActionGroup.Character]: Tone.Violet,
  [ActionGroup.Staff]: Tone.Fuchsia,
};

/** Quick bar and bulk actions, each with its own color. */
export const ACTION_TONES: Partial<Record<Action, Tone>> = {
  [Action.Duty]: Tone.Emerald,
  [Action.Noclip]: Tone.Violet,
  [Action.Vision]: Tone.Teal,
  [Action.God]: Tone.Amber,
  [Action.Invisible]: Tone.Indigo,
  [Action.Waypoint]: Tone.Sky,
  [Action.Back]: Tone.Blue,
  [Action.Fix]: Tone.Emerald,
  [Action.DeleteVehicle]: Tone.Rose,
  [Action.Car]: Tone.Blue,
  [Action.Announce]: Tone.Fuchsia,
  [Action.Unban]: Tone.Teal,
  [Action.ReviveAll]: Tone.Emerald,
  [Action.BringAll]: Tone.Sky,
  [Action.FreezeAll]: Tone.Indigo,
};
