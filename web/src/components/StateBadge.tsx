/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { cn } from "@/lib/cn";
import { useLabel } from "@/store/adminStore";
import { DeathState } from "@/types/protocol";

const DOTS: Record<DeathState, string> = {
  [DeathState.Alive]: "bg-success",
  [DeathState.Downed]: "bg-warning animate-pulse",
  [DeathState.Dead]: "bg-destructive",
};

const PILLS: Record<DeathState, string> = {
  [DeathState.Alive]: "bg-success/15 text-success ring-success/30",
  [DeathState.Downed]: "bg-warning/15 text-warning ring-warning/30",
  [DeathState.Dead]: "bg-destructive/20 text-destructive ring-destructive/40",
};

/** A death state: a dot in lists, a pill with its name elsewhere. */
export function StateBadge({ state, compact }: { state: DeathState; compact?: boolean }) {
  const label = useLabel();

  if (compact) {
    return <span title={label(`state.${state}`)} className={cn("inline-block size-2 rounded-full", DOTS[state])} />;
  }

  return (
    <span className={cn("inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-medium ring-1", PILLS[state])}>
      <span className={cn("size-1.5 rounded-full", DOTS[state])} />
      {label(`state.${state}`)}
    </span>
  );
}
