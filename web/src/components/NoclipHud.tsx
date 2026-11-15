/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The noclip overlay: crosshair, the card of what it targets, the key legend and the position. Lua sends the state;
// the page only draws it and never takes focus, so the game keeps every key.

import type { ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Box, Car, Compass, Move3d, PersonStanding, User, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";
import { speedShare } from "@/lib/format";
import { useAdmin, useLabel } from "@/store/adminStore";
import { TargetKind, type NoclipState, type NoclipTarget } from "@/types/protocol";

const SPRING = { type: "spring", stiffness: 420, damping: 32 } as const;

const KIND_ICONS: Record<TargetKind, LucideIcon> = {
  [TargetKind.Vehicle]: Car,
  [TargetKind.Ped]: PersonStanding,
  [TargetKind.Player]: User,
  [TargetKind.Object]: Box,
};

const formatSpeed = (speed: number) => (speed < 10 ? speed.toFixed(1) : speed.toFixed(0));

function Kbd({ children, dim }: { children: ReactNode; dim?: boolean }) {
  return (
    <kbd
      className={cn(
        "inline-flex h-6 min-w-6 items-center justify-center rounded-md border px-1.5 font-sans text-[11px] font-semibold leading-none",
        "shadow-[inset_0_-2px_0_rgb(0_0_0/0.3)] transition-colors duration-200",
        dim ? "border-white/5 bg-white/5 text-muted-foreground" : "border-white/15 bg-white/10 text-foreground",
      )}
    >
      {children}
    </kbd>
  );
}

function Row({ keys, label, enabled = true, name }: { keys: string[]; label: string; enabled?: boolean; name: string }) {
  return (
    <li
      data-key-row={name}
      data-enabled={enabled}
      className={cn("flex items-center justify-between gap-3 py-1 transition-opacity duration-200", !enabled && "opacity-35")}
    >
      <span className={cn("text-[13px]", enabled ? "text-foreground" : "text-muted-foreground")}>{label}</span>
      <span className="flex shrink-0 gap-1">
        {keys.map((key) => (
          <Kbd key={key} dim={!enabled}>
            {key}
          </Kbd>
        ))}
      </span>
    </li>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="border-t border-white/5 px-4 py-2.5">
      <h3 className="mb-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">{title}</h3>
      <ul>{children}</ul>
    </section>
  );
}

function Crosshair({ locked }: { locked: boolean }) {
  return (
    <div className="pointer-events-none absolute inset-0 grid place-items-center">
      <motion.div
        className="rounded-full border-2 [grid-area:1/1]"
        initial={false}
        animate={
          locked
            ? { width: 26, height: 26, opacity: 1, borderColor: "hsl(var(--ug-primary))" }
            : { width: 14, height: 14, opacity: 0.45, borderColor: "rgb(255 255 255)" }
        }
        transition={SPRING}
      />
      <motion.div
        className="size-1 rounded-full [grid-area:1/1]"
        initial={false}
        animate={{ backgroundColor: locked ? "hsl(var(--ug-primary))" : "rgb(255 255 255)", scale: locked ? 1.4 : 1 }}
        transition={SPRING}
      />
    </div>
  );
}

function TargetCard({ target, state }: { target: NoclipTarget; state: NoclipState }) {
  const label = useLabel();
  const Icon = KIND_ICONS[target.kind];
  const title = target.player !== undefined ? `[${target.player}] ${target.name ?? ""}` : (target.name ?? label(`noclip.kind.${target.kind}`));
  const actions = [
    { name: "delete", key: "Del", on: state.can.delete },
    { name: "freeze", key: "G", on: state.can.freeze },
    { name: "board", key: "F", on: state.can.board },
  ].filter((action) => action.on);

  return (
    <motion.div
      data-target={target.kind}
      initial={{ opacity: 0, x: -8, scale: 0.96 }}
      animate={{ opacity: 1, x: 0, scale: 1 }}
      exit={{ opacity: 0, x: -6, scale: 0.97 }}
      transition={SPRING}
      className="pointer-events-none absolute left-[calc(50%+28px)] top-[calc(50%+18px)] w-60 overflow-hidden rounded-lg border border-white/10 bg-card/90 shadow-ug-lg"
    >
      <div className="flex items-center gap-3 px-3 py-2.5">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-md bg-primary/15 text-primary">
          <Icon className="size-[18px]" />
        </span>
        <div className="min-w-0">
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-primary">{label(`noclip.kind.${target.kind}`)}</p>
          <p className="truncate text-sm font-semibold text-foreground">{title}</p>
        </div>
        {target.plate && (
          <span className="ml-auto shrink-0 rounded border border-white/15 bg-white/5 px-1.5 py-0.5 font-mono text-[11px] tracking-wider text-foreground">
            {target.plate}
          </span>
        )}
      </div>
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 border-t border-white/5 px-3 py-2 text-[11px]">
        <dt className="text-muted-foreground">{label("noclip.model")}</dt>
        <dd className="truncate text-right font-mono text-foreground">{target.model}</dd>
        {target.netId !== undefined ? (
          <>
            <dt className="text-muted-foreground">{label("noclip.net")}</dt>
            <dd className="text-right font-mono text-foreground">{target.netId}</dd>
            <dt className="text-muted-foreground">{label("noclip.owner")}</dt>
            <dd className="text-right font-mono text-foreground">{target.owner ?? "-"}</dd>
          </>
        ) : (
          <dd className="col-span-2 text-muted-foreground">{label("noclip.local")}</dd>
        )}
      </dl>
      {actions.length > 0 && (
        <div className="flex flex-wrap gap-x-3 gap-y-1 border-t border-white/5 bg-white/[0.03] px-3 py-2">
          {actions.map((action) => (
            <span key={action.name} className="flex items-center gap-1.5 text-[11px] text-foreground">
              <Kbd>{action.key}</Kbd>
              {label(`noclip.${action.name}`)}
            </span>
          ))}
        </div>
      )}
    </motion.div>
  );
}

function Legend({ state }: { state: NoclipState }) {
  const label = useLabel();
  const share = speedShare(state.speed, state.minSpeed, state.maxSpeed);

  return (
    <div className="pointer-events-none absolute inset-y-0 right-6 flex items-center">
    <motion.aside
      data-noclip-legend
      initial={{ opacity: 0, x: 24 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 24 }}
      transition={SPRING}
      className="w-64 overflow-hidden rounded-lg border border-white/10 bg-card/90 shadow-ug-lg"
    >
      <header className="flex items-center gap-2.5 px-4 pb-2 pt-3">
        <span className="flex size-8 items-center justify-center rounded-md bg-primary/15 text-primary">
          <Move3d className="size-4" />
        </span>
        <p className="text-sm font-semibold text-foreground">{label("noclip.title")}</p>
        {state.leave && (
          <span className="ml-auto flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <Kbd>{state.leave}</Kbd>
            {label("noclip.exit")}
          </span>
        )}
      </header>

      <div className="px-4 pb-3">
        <div className="flex items-end justify-between">
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">{label("noclip.speed")}</p>
          <p className="text-foreground">
            <span data-speed className="text-2xl font-semibold tabular-nums">
              {formatSpeed(state.speed)}
            </span>
            <span className="ml-1 text-xs text-muted-foreground">m/s</span>
          </p>
        </div>
        <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/10">
          <motion.div
            className="h-full rounded-full bg-gradient-to-r from-primary/60 to-primary"
            initial={false}
            animate={{ width: `${Math.max(4, share * 100)}%` }}
            transition={SPRING}
          />
        </div>
        <div className="mt-1.5 flex items-center justify-between text-[11px] text-muted-foreground">
          <span>{formatSpeed(state.minSpeed)}</span>
          <span className="flex items-center gap-1.5">
            <Kbd>{label("noclip.scroll")}</Kbd>
          </span>
          <span>{formatSpeed(state.maxSpeed)}</span>
        </div>
      </div>

      <Section title={label("noclip.movement")}>
        <Row name="move" keys={["W", "A", "S", "D"]} label={label("noclip.move")} />
        <Row name="up" keys={["Space", "Q"]} label={label("noclip.up")} />
        <Row name="down" keys={["Ctrl", "E"]} label={label("noclip.down")} />
        <Row name="boost" keys={["Shift"]} label={label("noclip.boost")} />
        <Row name="slow" keys={["Alt"]} label={label("noclip.slow")} />
      </Section>

      <Section title={label("noclip.targetGroup")}>
        <Row name="land" keys={["LMB"]} label={label("noclip.land")} enabled={state.can.land} />
        <Row name="delete" keys={["Del"]} label={label("noclip.delete")} enabled={state.can.delete} />
        <Row name="freeze" keys={["G"]} label={label("noclip.freeze")} enabled={state.can.freeze} />
        <Row name="board" keys={["F"]} label={label("noclip.board")} enabled={state.can.board} />
      </Section>

      <Section title={label("noclip.tools")}>
        <Row name="copy" keys={["C"]} label={label("noclip.copy")} />
        <Row name="hide" keys={["H"]} label={label("noclip.hide")} />
      </Section>
    </motion.aside>
    </div>
  );
}

function Position({ state }: { state: NoclipState }) {
  const { x, y, z } = state.coords;

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-6 flex justify-center">
    <motion.div
      data-noclip-position
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 12 }}
      transition={SPRING}
      className="flex items-center gap-3 rounded-full border border-white/10 bg-card/90 px-4 py-1.5 font-mono text-xs tabular-nums text-foreground shadow-ug-md"
    >
      <span className="flex items-center gap-1.5 text-primary">
        <Compass className="size-3.5" style={{ transform: `rotate(${-state.heading}deg)` }} />
        {Math.round(state.heading)}°
      </span>
      <span className="h-3 w-px bg-white/15" />
      <span>
        {x.toFixed(1)}, {y.toFixed(1)}, {z.toFixed(1)}
      </span>
    </motion.div>
    </div>
  );
}

export function NoclipHud() {
  const label = useLabel();
  const state = useAdmin((admin) => admin.noclip);

  return (
    <AnimatePresence>
      {state && (
        <motion.div
          key="noclip"
          data-noclip
          className="pointer-events-none fixed inset-0"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
        >
          <Crosshair locked={state.target !== undefined} />
          <AnimatePresence>
            {state.hud && state.target && (
              <TargetCard key={`${state.target.kind}:${state.target.netId ?? state.target.model}`} target={state.target} state={state} />
            )}
          </AnimatePresence>
          <AnimatePresence mode="wait">
            {state.hud ? (
              <Legend key="legend" state={state} />
            ) : (
              <div key="collapsed" className="pointer-events-none absolute inset-y-0 right-6 flex items-center">
              <motion.div
                data-noclip-collapsed
                initial={{ opacity: 0, x: 16 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 16 }}
                transition={SPRING}
                className="flex items-center gap-2 rounded-full border border-white/10 bg-card/90 py-1 pl-1 pr-3 text-xs text-foreground shadow-ug-md"
              >
                <Kbd>H</Kbd>
                {label("noclip.show")}
              </motion.div>
              </div>
            )}
          </AnimatePresence>
          <AnimatePresence>{state.hud && <Position key="position" state={state} />}</AnimatePresence>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
