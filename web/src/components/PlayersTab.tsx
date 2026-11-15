/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { Headset, Lock, MicOff, MousePointerClick, Search, Snowflake } from "lucide-react";
import { Avatar } from "@/components/Avatar";
import { PlayerDetails } from "@/components/PlayerDetails";
import { StateBadge } from "@/components/StateBadge";
import { Input } from "@/components/ui/Field";
import { cn } from "@/lib/cn";
import { score } from "@/lib/format";
import { matchesPlayer } from "@/lib/reports";
import { sendInspect } from "@/lib/nui";
import { useAdmin, useLabel } from "@/store/adminStore";
import { DeathState, type PlayerRow } from "@/types/protocol";

const Filter = {
  All: "all",
  Down: "down",
  Flagged: "flagged",
  Frozen: "frozen",
  Duty: "duty",
} as const;

type Filter = (typeof Filter)[keyof typeof Filter];

const MATCHES: Record<Filter, (player: PlayerRow) => boolean> = {
  [Filter.All]: () => true,
  [Filter.Down]: (player) => player.state !== DeathState.Alive,
  [Filter.Flagged]: (player) => score(player.score) > 0,
  [Filter.Frozen]: (player) => player.frozen,
  [Filter.Duty]: (player) => player.duty,
};

/** Signal bars for a ping: green, amber or red. */
function Ping({ ms }: { ms: number }) {
  const bars = ms < 80 ? 3 : ms < 160 ? 2 : 1;
  const color = bars === 3 ? "bg-success" : bars === 2 ? "bg-warning" : "bg-destructive";

  return (
    <span className="flex h-3 items-end gap-[2px]" title={`${ms} ms`}>
      {[1, 2, 3].map((bar) => (
        <span key={bar} className={cn("w-[3px] rounded-sm", bar <= bars ? color : "bg-white/15")} style={{ height: `${bar * 4}px` }} />
      ))}
    </span>
  );
}

export function PlayersTab() {
  const label = useLabel();
  const players = useAdmin((state) => state.players);
  const selected = useAdmin((state) => state.selected);
  const details = useAdmin((state) => state.details);
  const self = useAdmin((state) => state.self);
  const select = useAdmin((state) => state.select);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<Filter>(Filter.All);

  const shown = useMemo(() => {
    const query = search.trim().toLowerCase();

    return [...players]
      .sort((a, b) => a.id - b.id)
      .filter(MATCHES[filter])
      .filter(
        (player) => matchesPlayer(player, query) || player.job?.label.toLowerCase().includes(query),
      );
  }, [players, search, filter]);

  const row = players.find((player) => player.id === selected);

  const pick = (id: number) => {
    select(id);
    void sendInspect(id);
  };

  return (
    <div className="grid h-full min-h-0 grid-cols-[20rem_1fr]">
      <aside className="flex min-h-0 flex-col border-r border-white/5">
        <div className="space-y-2 p-4 pb-3">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input value={search} maxLength={64} placeholder={label("search")} className="pl-9" onChange={(event) => setSearch(event.target.value)} />
          </div>
          <div className="flex gap-1">
            {Object.values(Filter).map((entry) => {
              const count = players.filter(MATCHES[entry]).length;

              return (
                <button
                  key={entry}
                  type="button"
                  data-filter={entry}
                  onClick={() => setFilter(entry)}
                  className={cn(
                    "relative flex flex-1 items-center justify-center gap-1 rounded-lg px-1.5 py-1 text-[11px] font-medium transition-colors",
                    filter === entry ? "text-violet-300" : "text-muted-foreground hover:bg-white/5 hover:text-foreground",
                  )}
                >
                  {filter === entry && <motion.span layoutId="filter" className="absolute inset-0 rounded-lg bg-violet-500/15 ring-1 ring-violet-400/30" />}
                  <span className="relative">{label(`filter.${entry}`)}</span>
                  <span className="relative font-mono text-[10px] opacity-70">{count}</span>
                </button>
              );
            })}
          </div>
        </div>

        <ul className="min-h-0 flex-1 space-y-1 overflow-y-auto px-3 pb-3">
          {shown.length === 0 && <li className="p-4 text-center text-sm text-muted-foreground">{label("noPlayers")}</li>}
          {shown.map((player) => (
            <li key={player.id}>
              <button
                type="button"
                onClick={() => pick(player.id)}
                data-player={player.id}
                className={cn(
                  "relative flex w-full items-center gap-3 rounded-xl px-2.5 py-2 text-left transition-colors",
                  selected === player.id ? "text-foreground" : "hover:bg-white/[0.04]",
                )}
              >
                {selected === player.id && (
                  <motion.span layoutId="picked" className="absolute inset-0 rounded-xl bg-gradient-to-r from-violet-500/15 to-blue-500/10 ring-1 ring-violet-400/40" transition={{ type: "spring", stiffness: 420, damping: 34 }} />
                )}
                <span className="relative">
                  <Avatar id={player.id} name={player.name} source={player.id} />
                  <span className="absolute -bottom-0.5 -right-0.5 grid size-3.5 place-items-center rounded-full bg-card">
                    <StateBadge state={player.state} compact />
                  </span>
                </span>
                <span className="relative min-w-0 flex-1">
                  <span className="flex items-center gap-1.5 text-sm font-medium">
                    <span className="truncate">{player.name}</span>
                    {player.id === self && <span className="rounded bg-primary/20 px-1 text-[9px] font-bold uppercase text-primary">{label("you")}</span>}
                    {player.duty && <Headset className="size-3 shrink-0 text-emerald-400" data-duty />}
                    {player.frozen && <Snowflake className="size-3 shrink-0 text-sky-400" />}
                    {player.jailed !== undefined && <Lock className="size-3 shrink-0 text-destructive" data-jailed />}
                    {player.muted !== undefined && <MicOff className="size-3 shrink-0 text-warning" data-muted />}
                  </span>
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <span className="font-mono">#{player.id}</span>
                    <span className="truncate">
                      · {player.characterId === undefined ? label("noCharacter") : [player.character, player.job?.label].filter(Boolean).join(" · ") || "—"}
                    </span>
                  </span>
                </span>
                <span className="relative flex flex-col items-end gap-1.5">
                  <Ping ms={player.ping} />
                  {score(player.score) > 0 && (
                    <span
                      className={cn(
                        "rounded-md px-1.5 font-mono text-[10px] font-semibold",
                        player.score >= 20 ? "bg-destructive/20 text-destructive" : "bg-warning/20 text-warning",
                      )}
                    >
                      {score(player.score)}
                    </span>
                  )}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </aside>

      <div className="min-h-0">
        {row ? (
          <PlayerDetails row={row} details={details} />
        ) : (
          <div className="grid h-full place-items-center text-center">
            <div>
              <div className="mx-auto mb-4 grid size-16 place-items-center rounded-2xl bg-primary/10 text-primary ring-1 ring-primary/20">
                <MousePointerClick className="size-7" />
              </div>
              <p className="max-w-xs text-sm text-muted-foreground">{label("select")}</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
