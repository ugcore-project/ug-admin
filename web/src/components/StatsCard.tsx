/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useState } from "react";
import { Activity, Check, RotateCcw } from "lucide-react";
import { Card } from "@/components/Card";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/cn";
import { sendRun } from "@/lib/nui";
import { Tone } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action, DeathState, type PlayerDetails, type PlayerRow } from "@/types/protocol";

// A GTA ped is dead at 100 health and full at 200.
const MIN_HEALTH = 101;
const MAX_HEALTH = 200;

interface MeterProps {
  name: string;
  text: string;
  value: number;
  min: number;
  max: number;
  /** What the value reads as, such as `75%`. */
  shown: string;
  tone: string;
  disabled?: boolean;
  onChange: (value: number) => void;
}

/** A labelled slider with a colored fill. */
function Meter({ name, text, value, min, max, shown, tone, disabled, onChange }: MeterProps) {
  const share = ((value - min) / (max - min)) * 100;

  return (
    <label className={cn("block", disabled && "opacity-40")}>
      <span className="mb-1 flex items-baseline justify-between text-xs">
        <span className="text-muted-foreground">{text}</span>
        <span className="font-mono text-[11px] font-semibold tabular-nums">{shown}</span>
      </span>
      <span className="relative block h-2 rounded-full bg-white/10">
        <span className={cn("absolute inset-y-0 left-0 rounded-full transition-[width]", tone)} style={{ width: `${share}%` }} />
        <input
          type="range"
          data-meter={name}
          min={min}
          max={max}
          value={value}
          disabled={disabled}
          onChange={(event) => onChange(Number(event.target.value))}
          className="absolute inset-0 h-2 w-full cursor-pointer opacity-0 disabled:cursor-not-allowed"
        />
      </span>
    </label>
  );
}

interface StatsCardProps {
  row: PlayerRow;
  details: PlayerDetails;
}

/** Health, armor and needs as sliders. Apply sends only what changed. */
export function StatsCard({ row, details }: StatsCardProps) {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const catalog = useAdmin((state) => state.catalog);
  // Seeded once: the row refreshes every few seconds, and a moving health MUST NOT undo what staff typed.
  const [start] = useState(() => ({
    health: Math.max(MIN_HEALTH, Math.min(MAX_HEALTH, row.health)),
    armor: details.armor,
    needs: details.needs ?? {},
  }));
  const { health: startHealth, needs: startNeeds } = start;
  const [health, setHealth] = useState(start.health);
  const [armor, setArmor] = useState(start.armor);
  const [needs, setNeeds] = useState<Record<string, number>>(start.needs);
  const canStats = access.has(Action.SetStats);
  const canNeeds = access.has(Action.SetNeed) && details.needs !== undefined && catalog.needs.length > 0;
  // Health is never set on a downed or dead player: revive brings them back.
  const alive = row.state === DeathState.Alive;
  const changedNeeds = catalog.needs.filter((need) => Math.round(needs[need.name] ?? 0) !== Math.round(startNeeds[need.name] ?? 0));
  const changed = health !== startHealth || armor !== start.armor || changedNeeds.length > 0;

  if (!canStats && !canNeeds) {
    return null;
  }

  const reset = () => {
    setHealth(startHealth);
    setArmor(start.armor);
    setNeeds(startNeeds);
  };

  const apply = () => {
    if (canStats && (health !== startHealth || armor !== start.armor)) {
      void sendRun(Action.SetStats, row.id, {
        health: health !== startHealth ? health : undefined,
        armor: armor !== start.armor ? armor : undefined,
      });
    }

    for (const need of canNeeds ? changedNeeds : []) {
      void sendRun(Action.SetNeed, row.id, { need: need.name, value: Math.round(needs[need.name] ?? 0) });
    }
  };

  return (
    <Card
      icon={Activity}
      title={label("stats")}
      tone={Tone.Emerald}
      className="col-span-2"
      extra={
        <span className="flex gap-1.5">
          <Button variant="outline" className="h-7 rounded-lg border-white/10 px-2 text-xs" disabled={!changed} onClick={reset} title={label("reset")}>
            <RotateCcw className="size-3.5" />
          </Button>
          <Button className="h-7 rounded-lg px-2.5 text-xs" disabled={!changed} onClick={apply} data-apply-stats>
            <Check className="size-3.5" />
            {label("apply")}
          </Button>
        </span>
      }
    >
      <div className="grid grid-cols-2 gap-x-5 gap-y-3">
        {canStats && (
          <>
            <Meter
              name="health"
              text={label("health")}
              value={health}
              min={MIN_HEALTH}
              max={MAX_HEALTH}
              shown={`${health - 100}%`}
              tone="bg-success"
              disabled={!alive}
              onChange={setHealth}
            />
            <Meter name="armor" text={label("armor")} value={armor} min={0} max={100} shown={`${armor}%`} tone="bg-sky-400" onChange={setArmor} />
          </>
        )}
        {canNeeds &&
          catalog.needs.map((need) => {
            const value = Math.round(needs[need.name] ?? 0);

            return (
              <Meter
                key={need.name}
                name={need.name}
                text={need.label}
                value={value}
                min={0}
                max={100}
                shown={`${value}%`}
                tone={value > 50 ? "bg-gradient-to-r from-violet-500 to-blue-500" : value > 20 ? "bg-warning" : "bg-destructive"}
                onChange={(next) => setNeeds((current) => ({ ...current, [need.name]: next }))}
              />
            );
          })}
      </div>
    </Card>
  );
}
