/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// What staff and the reporter both use: a color and an icon per category, and the order categories are offered in.

import { Bug, CircleQuestionMark, MapPinOff, MessageCircle, UserX, type LucideIcon } from "lucide-react";
import { Tone } from "@/lib/tones";
import { ReportCategory, type PlayerRow } from "@/types/protocol";

export const CATEGORY_ORDER: ReportCategory[] = [
  ReportCategory.Question,
  ReportCategory.Player,
  ReportCategory.Bug,
  ReportCategory.Stuck,
  ReportCategory.Other,
];

export const CATEGORY_ICONS: Record<ReportCategory, LucideIcon> = {
  [ReportCategory.Question]: CircleQuestionMark,
  [ReportCategory.Player]: UserX,
  [ReportCategory.Bug]: Bug,
  [ReportCategory.Stuck]: MapPinOff,
  [ReportCategory.Other]: MessageCircle,
};

export const CATEGORY_TONES: Record<ReportCategory, Tone> = {
  [ReportCategory.Question]: Tone.Sky,
  [ReportCategory.Player]: Tone.Rose,
  [ReportCategory.Bug]: Tone.Amber,
  [ReportCategory.Stuck]: Tone.Violet,
  [ReportCategory.Other]: Tone.Teal,
};

/** Quick answers staff send in one click, by label key under `quick`. */
export const QUICK_REPLIES = ["onMyWay", "details", "wait", "done"] as const;

/** Longest chat line the server accepts. */
export const MAX_TEXT = 256;

/** True when a search matches a player's id, player name or character name. */
export function matchesPlayer(player: PlayerRow, query: string): boolean {
  const lower = query.trim().toLowerCase();

  return (
    lower === "" ||
    String(player.id) === lower ||
    player.name.toLowerCase().includes(lower) ||
    (player.character?.toLowerCase().includes(lower) ?? false)
  );
}
