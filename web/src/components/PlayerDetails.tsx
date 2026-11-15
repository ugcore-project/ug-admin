/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useState, type ReactNode } from "react";
import { motion } from "framer-motion";
import { Activity, Backpack, Briefcase, Check, Copy, Fingerprint, Lock, MicOff, NotebookText, ShieldAlert, ShieldCheck, Snowflake, Swords, Wifi, Zap, type LucideIcon } from "lucide-react";
import { ActionButton } from "@/components/ActionButton";
import { AccountsCard, InventoryCard } from "@/components/AssetCards";
import { Avatar } from "@/components/Avatar";
import { Card, Countdown } from "@/components/Card";
import { HistoryCard } from "@/components/HistoryCard";
import { StateBadge } from "@/components/StateBadge";
import { StatsCard } from "@/components/StatsCard";
import { Button } from "@/components/ui/Button";
import { PLAYER_ACTIONS, type ActionGroup } from "@/lib/actions";
import { cn } from "@/lib/cn";
import { fill, score } from "@/lib/format";
import { sendRun } from "@/lib/nui";
import { BRAND_GRADIENT, GROUP_TONES, Tone, TONES } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action, type PlayerDetails as Details, type PlayerRow } from "@/types/protocol";

const MAX_HEALTH = 200;
const GAUGE_RADIUS = 26;
const GAUGE_LENGTH = 2 * Math.PI * GAUGE_RADIUS;

function CopyLine({ value }: { value: string }) {
  const label = useLabel();
  const [copied, setCopied] = useState(false);

  // CEF blocks the async clipboard API, so this goes through a hidden selection.
  const copy = () => {
    const field = document.createElement("textarea");

    field.value = value;
    document.body.appendChild(field);
    field.select();
    document.execCommand("copy");
    field.remove();
    setCopied(true);
    setTimeout(() => setCopied(false), 1200);
  };

  return (
    <button
      type="button"
      onClick={copy}
      title={label(copied ? "copied" : "copy")}
      className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left font-mono text-[11px] text-muted-foreground transition-colors hover:bg-white/5 hover:text-foreground"
    >
      <span className="flex-1 truncate">{value}</span>
      {copied ? <Check className="size-3.5 text-success" /> : <Copy className="size-3.5 opacity-60" />}
    </button>
  );
}

function Stat({ icon: Icon, title, tone, children }: { icon: LucideIcon; title: string; tone: string; children: ReactNode }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-white/5 bg-white/[0.03] px-3 py-2.5">
      <span className={cn("grid size-8 shrink-0 place-items-center rounded-lg", tone)}>
        <Icon className="size-4" />
      </span>
      <div className="min-w-0">
        <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">{title}</div>
        <div className="truncate text-sm font-medium">{children}</div>
      </div>
    </div>
  );
}

interface SanctionBarProps {
  icon: LucideIcon;
  title: string;
  seconds: number;
  release: Action;
  target: number;
  tone: string;
}

/** A running jail or mute, with its countdown and a way to end it early. */
function SanctionBar({ icon: Icon, title, seconds, release, target, tone }: SanctionBarProps) {
  const label = useLabel();
  const access = useAdmin((state) => state.access);

  return (
    <motion.div
      initial={{ opacity: 0, y: -6 }}
      animate={{ opacity: 1, y: 0 }}
      data-sanction={release}
      className={cn("flex items-center gap-3 rounded-xl border px-3 py-2", tone)}
    >
      <span className="grid size-8 place-items-center rounded-lg bg-white/10">
        <Icon className="size-4" />
      </span>
      <span className="flex-1 text-sm">
        <span className="font-semibold">{title}</span>
        <span className="opacity-80"> · </span>
        <Countdown key={seconds} seconds={seconds} />
      </span>
      {access.has(release) && (
        <Button variant="outline" className="h-8 rounded-lg border-white/15 bg-transparent px-3 text-xs" onClick={() => void sendRun(release, target)}>
          {label(`action.${release}`)}
        </Button>
      )}
    </motion.div>
  );
}

/** Health as a ring around its percentage. */
function HealthGauge({ health }: { health: number }) {
  const label = useLabel();
  const color = health > 0.5 ? "hsl(var(--ug-success))" : health > 0.25 ? "hsl(var(--ug-warning))" : "hsl(var(--ug-destructive))";

  return (
    <div className="relative grid size-[4.5rem] shrink-0 place-items-center" title={label("health")}>
      <svg viewBox="0 0 64 64" className="absolute inset-0 -rotate-90">
        <circle cx="32" cy="32" r={GAUGE_RADIUS} fill="none" stroke="rgb(255 255 255 / 0.08)" strokeWidth="6" />
        <motion.circle
          cx="32"
          cy="32"
          r={GAUGE_RADIUS}
          fill="none"
          stroke={color}
          strokeWidth="6"
          strokeLinecap="round"
          strokeDasharray={GAUGE_LENGTH}
          initial={{ strokeDashoffset: GAUGE_LENGTH }}
          animate={{ strokeDashoffset: GAUGE_LENGTH * (1 - health) }}
          transition={{ type: "spring", stiffness: 120, damping: 20 }}
        />
      </svg>
      <span className="text-center leading-none">
        <span className="block text-base font-semibold tabular-nums">{Math.round(health * 100)}</span>
        <span className="text-[9px] uppercase tracking-wider text-muted-foreground">HP</span>
      </span>
    </div>
  );
}

const DetailTab = {
  Actions: "actions",
  Stats: "stats",
  Inventory: "inventory",
  Records: "records",
  Info: "info",
} as const;

type DetailTab = (typeof DetailTab)[keyof typeof DetailTab];

const TAB_TONES: Record<DetailTab, Tone> = {
  [DetailTab.Actions]: Tone.Violet,
  [DetailTab.Stats]: Tone.Emerald,
  [DetailTab.Inventory]: Tone.Amber,
  [DetailTab.Records]: Tone.Sky,
  [DetailTab.Info]: Tone.Indigo,
};

const TAB_ICONS: Record<DetailTab, LucideIcon> = {
  [DetailTab.Actions]: Zap,
  [DetailTab.Stats]: Activity,
  [DetailTab.Inventory]: Backpack,
  [DetailTab.Records]: NotebookText,
  [DetailTab.Info]: Fingerprint,
};

interface PlayerDetailsProps {
  row: PlayerRow;
  details: Details | null;
}

/** The selected player: who they are on top, then tabs for actions, stats, belongings, records and identifiers. */
export function PlayerDetails({ row, details }: PlayerDetailsProps) {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const self = useAdmin((state) => state.self);
  const catalog = useAdmin((state) => state.catalog);
  const version = useAdmin((state) => state.detailsVersion);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [picked, setPicked] = useState<DetailTab>(DetailTab.Actions);
  const health = Math.max(0, Math.min(row.health / MAX_HEALTH, 1));
  const groups = (Object.keys(PLAYER_ACTIONS) as ActionGroup[])
    .map((group) => [group, PLAYER_ACTIONS[group].filter((spec) => access.has(spec.action))] as const)
    .filter(([, specs]) => specs.length > 0);

  // A tab shows only when it has something for this player and this staff member.
  const shown: Record<DetailTab, boolean> = {
    [DetailTab.Actions]: groups.length > 0,
    [DetailTab.Stats]: details !== null && (access.has(Action.SetStats) || (access.has(Action.SetNeed) && details.needs !== undefined)),
    [DetailTab.Inventory]: details?.accounts !== undefined || details?.items !== undefined,
    [DetailTab.Records]: details !== null,
    [DetailTab.Info]: details !== null,
  };
  const tabs = Object.values(DetailTab).filter((entry) => shown[entry]);
  // A tab the next player does not have falls back to the first one.
  const tab = tabs.includes(picked) ? picked : tabs[0];
  const badges: Partial<Record<DetailTab, number>> = {
    [DetailTab.Records]: details ? details.history.length + details.notes.length : 0,
    [DetailTab.Inventory]: details?.items?.length ?? 0,
  };

  return (
    <motion.div
      key={row.id}
      initial={{ opacity: 0, x: 16 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ type: "spring", stiffness: 380, damping: 34 }}
      className="flex h-full min-h-0 flex-col"
      data-details={row.id}
    >
      {/* Pinned: who the player is and what holds them. Only the tab below scrolls. */}
      <div className="shrink-0 space-y-3 px-5 pt-5">
        <header className="relative overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-br from-violet-500/25 via-indigo-500/[0.08] to-blue-500/[0.04] p-4">
          <div className="pointer-events-none absolute -right-10 -top-16 size-48 rounded-full bg-primary/20 blur-3xl" />
          <div className={cn("absolute inset-y-0 left-0 w-1", BRAND_GRADIENT)} />
          <div className="relative flex items-center gap-4">
            <div className="relative">
              <Avatar id={row.id} name={row.name} source={row.id} size="lg" className="ring-2 ring-white/15" />
              {row.frozen && <Snowflake className="absolute -right-1.5 -top-1.5 size-5 rounded-full bg-card p-0.5 text-sky-400" />}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h2 className="truncate text-xl font-semibold tracking-tight">{row.name}</h2>
                {row.id === self && <span className={cn("rounded px-1.5 text-[10px] font-bold uppercase text-white", BRAND_GRADIENT)}>{label("you")}</span>}
              </div>
              <div className="mt-1.5 flex flex-wrap items-center gap-1.5 text-xs">
                <span className="rounded-full bg-white/10 px-2 py-0.5 font-mono">#{row.id}</span>
                {row.characterId !== undefined && (
                  <span className="rounded-full bg-white/10 px-2 py-0.5 text-muted-foreground">{fill(label("character"), { id: row.characterId })}</span>
                )}
                <StateBadge state={row.state} />
                {row.frozen && (
                  <span className="inline-flex items-center gap-1 rounded-full bg-sky-400/15 px-2 py-0.5 text-[11px] font-medium text-sky-300 ring-1 ring-sky-400/30">
                    <Snowflake className="size-3" />
                    {label("frozen")}
                  </span>
                )}
              </div>
            </div>
            <HealthGauge health={health} />
          </div>
        </header>

        <div className="grid grid-cols-4 gap-2">
          <Stat icon={Briefcase} title={label("job")} tone={TONES[Tone.Blue].chip}>{row.job ? `${row.job.label} · ${row.job.gradeLabel}` : "—"}</Stat>
          <Stat icon={Swords} title={label("gang")} tone={TONES[Tone.Rose].chip}>{details?.gang ? `${details.gang.label} · ${details.gang.gradeLabel}` : "—"}</Stat>
          <Stat icon={Wifi} title={label("ping")} tone={TONES[row.ping > 150 ? Tone.Amber : Tone.Teal].chip}>{row.ping} ms</Stat>
          <Stat
            icon={score(row.score) > 0 ? ShieldAlert : ShieldCheck}
            title={label("score")}
            tone={row.score >= 20 ? "bg-destructive/15 text-destructive" : row.score >= 10 ? "bg-warning/15 text-warning" : "bg-success/15 text-success"}
          >
            {score(row.score)}
          </Stat>
        </div>

        {details?.jail !== undefined && (
          <SanctionBar
            icon={Lock}
            title={label("jailed")}
            seconds={details.jail}
            release={Action.Unjail}
            target={row.id}
            tone="border-destructive/40 bg-destructive/10 text-destructive"
          />
        )}
        {details?.mute !== undefined && (
          <SanctionBar
            icon={MicOff}
            title={label("muted")}
            seconds={details.mute}
            release={Action.Unmute}
            target={row.id}
            tone="border-warning/40 bg-warning/10 text-warning"
          />
        )}

        {row.characterId === undefined && (
          <p className="rounded-xl border border-warning/30 bg-warning/10 px-3 py-2 text-sm text-warning">{label("noCharacter")}</p>
        )}

        <nav className="flex gap-1 rounded-xl border border-white/5 bg-background/40 p-1">
          {tabs.map((entry) => {
            const Icon = TAB_ICONS[entry];
            const colors = TONES[TAB_TONES[entry]];
            const badge = badges[entry] ?? 0;

            return (
              <button
                key={entry}
                type="button"
                data-detail-tab={entry}
                onClick={() => setPicked(entry)}
                className={cn(
                  "relative flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 text-xs font-medium transition-colors",
                  tab === entry ? colors.text : "text-muted-foreground hover:bg-white/5 hover:text-foreground",
                )}
              >
                {tab === entry && (
                  <motion.span layoutId="detail-tab" className={cn("absolute inset-0 rounded-lg border", colors.active)} transition={{ type: "spring", stiffness: 420, damping: 34 }} />
                )}
                <Icon className={cn("relative size-3.5", colors.text)} />
                <span className="relative">{label(`detailTab.${entry}`)}</span>
                {badge > 0 && <span className="relative rounded-full bg-white/10 px-1.5 font-mono text-[10px]">{badge}</span>}
              </button>
            );
          })}
        </nav>
      </div>

      <motion.div
        key={tab}
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.15 }}
        className="min-h-0 flex-1 space-y-4 overflow-y-auto p-5"
        data-detail-panel={tab}
      >
        {tab === DetailTab.Actions &&
          groups.map(([group, specs]) => (
            <section key={group}>
              <h3 className={cn("mb-2 flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.14em]", TONES[GROUP_TONES[group]].text)}>
                <span className={cn("size-1.5 rounded-full", TONES[GROUP_TONES[group]].dot)} />
                {label(`group.${group}`)}
                <span className="h-px flex-1 bg-gradient-to-r from-white/10 to-transparent" />
              </h3>
              <div className="grid grid-cols-5 gap-2">
                {specs.map((spec) => (
                  <ActionButton
                    key={spec.action}
                    spec={spec}
                    tone={GROUP_TONES[group]}
                    target={row.id}
                    targetGroups={details?.groups}
                    expanded={expanded === spec.action}
                    onExpand={(open) => setExpanded(open ? spec.action : null)}
                  />
                ))}
              </div>
            </section>
          ))}

        {details && tab === DetailTab.Stats && (
          <div className="grid grid-cols-2 gap-3">
            <StatsCard key={version} row={row} details={details} />
          </div>
        )}

        {details && tab === DetailTab.Inventory && (
          <div className="grid grid-cols-2 gap-3">
            {details.accounts && <AccountsCard target={row.id} accounts={details.accounts} />}
            {details.items && <InventoryCard target={row.id} items={details.items} />}
          </div>
        )}

        {details && tab === DetailTab.Records && (
          <div className="grid grid-cols-2 gap-3">
            <HistoryCard details={details} />
          </div>
        )}

        {details && tab === DetailTab.Info && (
          <div className="grid grid-cols-2 gap-3">
            <Card icon={ShieldCheck} title={label("groups")} className="col-span-2" tone={Tone.Fuchsia}>
              {details.groups.length === 0 ? (
                <p className="text-sm text-muted-foreground">{label("noGroups")}</p>
              ) : (
                <div className="flex flex-wrap gap-1.5">
                  {details.groups.map((group) => (
                    <span key={group} className="rounded-full bg-fuchsia-500/15 px-2.5 py-1 text-xs font-medium text-fuchsia-300 ring-1 ring-fuchsia-400/25">
                      {catalog.groups.find((entry) => entry.name === group)?.label ?? group}
                    </span>
                  ))}
                </div>
              )}
            </Card>

            <Card icon={Fingerprint} title={label("identifiers")} className="col-span-2" tone={Tone.Indigo}>
              {details.identifiers.map((identifier) => (
                <CopyLine key={identifier} value={identifier} />
              ))}
            </Card>
          </div>
        )}
      </motion.div>
    </motion.div>
  );
}
