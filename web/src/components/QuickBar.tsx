/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown, Users } from "lucide-react";
import { ActionButton } from "@/components/ActionButton";
import { ACTION_ICONS } from "@/components/icons";
import { BULK_ACTIONS, orderQuick, QUICK_ITEMS, QUICK_TOGGLES, QUICK_TOOLS } from "@/lib/actions";
import { cn } from "@/lib/cn";
import { sendRun } from "@/lib/nui";
import { ACTION_TONES, BRAND_TEXT, Tone, TONES } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action } from "@/types/protocol";

// Modes stay on until turned off: they get their own row and light up while on.
const MODES = new Set<Action>([Action.Duty, Action.Noclip, Action.Vision, Action.God, Action.Invisible]);
const TOGGLES = new Set<Action>(QUICK_TOGGLES);
const TOOLS = new Map(QUICK_TOOLS.map((spec) => [spec.action, spec]));

function RowLabel({ text }: { text: string }) {
  return <span className={cn("w-14 shrink-0 px-1 text-[10px] font-bold uppercase tracking-[0.14em]", BRAND_TEXT)}>{text}</span>;
}

/** A one-click action on the staff member: a mode that lights up while on, or an instant one. */
function QuickToggle({ action, on }: { action: Action; on: boolean }) {
  const label = useLabel();
  const Icon = ACTION_ICONS[action];
  const colors = TONES[ACTION_TONES[action] ?? Tone.Indigo];

  return (
    <motion.button
      type="button"
      data-action={action}
      data-on={on}
      title={label(`action.${action}`)}
      whileTap={{ scale: 0.94 }}
      onClick={() => void sendRun(action)}
      className={cn(
        "relative flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-xs font-medium transition-colors",
        on ? cn(colors.active, "shadow-ug-sm") : cn("border-transparent text-foreground/90", colors.hover),
      )}
    >
      <Icon className={cn("size-3.5", colors.text)} />
      {label(`action.${action}`)}
      {on && (
        <span className="relative ml-0.5 flex size-1.5">
          <span className="absolute inline-flex size-full animate-ping rounded-full bg-current opacity-60" />
          <span className="relative inline-flex size-1.5 rounded-full bg-current" />
        </span>
      )}
    </motion.button>
  );
}

/** Actions on every player, tucked in a menu: they are rare and loud. Each still asks a second click. */
function EveryoneMenu() {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const bulk = BULK_ACTIONS.filter((spec) => access.has(spec.action));

  useEffect(() => {
    if (!open) {
      return;
    }

    const away = (event: MouseEvent) => {
      if (box.current && !box.current.contains(event.target as Node)) {
        setOpen(false);
      }
    };

    window.addEventListener("mousedown", away);

    return () => window.removeEventListener("mousedown", away);
  }, [open]);

  if (bulk.length === 0) {
    return null;
  }

  return (
    <div ref={box} className="relative" data-bulk>
      <button
        type="button"
        data-bulk-toggle
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className={cn(
          "flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-xs font-medium transition-colors",
          open
            ? "border-rose-400/40 bg-rose-500/15 text-rose-200"
            : "border-rose-400/20 bg-rose-500/[0.06] text-rose-300 hover:bg-rose-500/15",
        )}
      >
        <Users className="size-3.5" />
        {label("everyone")}
        <ChevronDown className={cn("size-3.5 transition-transform", open && "rotate-180")} />
      </button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -4, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -4, scale: 0.98 }}
            transition={{ duration: 0.12 }}
            className="absolute right-0 top-full z-30 mt-2 flex w-48 flex-col gap-1 rounded-xl border border-white/10 bg-card p-1.5 shadow-ug-lg [&_button]:w-full"
          >
            {bulk.map((spec) => (
              <ActionButton key={spec.action} spec={spec} look="pill" expanded={false} onExpand={() => undefined} />
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/**
 * Actions on the staff member, one click away: modes on the first row, teleports and world tools on the second,
 * actions on everyone in a menu. The staff member orders and hides them in the settings.
 */
export function QuickBar() {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const modes = useAdmin((state) => state.modes);
  const settings = useAdmin((state) => state.settings);
  const [expanded, setExpanded] = useState<string | null>(null);
  const hidden = new Set(settings.hidden);
  const items = orderQuick(QUICK_ITEMS, settings.order).filter((action) => access.has(action) && !hidden.has(action));
  const modeItems = items.filter((action) => MODES.has(action));
  const toolItems = items.filter((action) => !MODES.has(action));
  const everyone = settings.everyone && BULK_ACTIONS.some((spec) => access.has(spec.action));

  if (items.length === 0 && !everyone) {
    return null;
  }

  return (
    <div data-quickbar className="mx-6 mb-4 flex flex-col gap-1.5 rounded-2xl border border-white/5 bg-background/40 p-2">
      {(modeItems.length > 0 || everyone) && (
        <div className="flex items-center gap-2">
          <RowLabel text={label("modes")} />
          {modeItems.length > 0 && (
            <div className="flex flex-wrap items-center gap-1 rounded-xl bg-white/[0.03] p-1 ring-1 ring-white/5">
              {modeItems.map((action) => (
                <QuickToggle key={action} action={action} on={modes.has(action)} />
              ))}
            </div>
          )}
          <span className="ml-auto">{everyone && <EveryoneMenu />}</span>
        </div>
      )}
      {toolItems.length > 0 && (
        <div className="flex items-start gap-2">
          <span className="flex h-10 items-center">
            <RowLabel text={label("tools")} />
          </span>
          <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1 rounded-xl bg-white/[0.03] p-1 ring-1 ring-white/5">
            {toolItems.map((action) => {
              const tool = TOOLS.get(action);

              if (tool) {
                return (
                  <ActionButton
                    key={action}
                    spec={tool}
                    look="pill"
                    expanded={expanded === action}
                    onExpand={(open) => setExpanded(open ? action : null)}
                  />
                );
              }

              return TOGGLES.has(action) ? <QuickToggle key={action} action={action} on={modes.has(action)} /> : null;
            })}
          </div>
        </div>
      )}
    </div>
  );
}
