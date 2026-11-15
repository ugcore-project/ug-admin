/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The staff member's own panel: quick bar order and visibility, the tab it opens on, confirmations and quick
// replies. Saved on their PC through Lua, which checks every field again.

import { useState, type ReactNode } from "react";
import { Reorder } from "framer-motion";
import { ChevronDown, ChevronUp, Eye, EyeOff, GripVertical, Plus, RotateCcw, Trash2 } from "lucide-react";
import { ACTION_ICONS } from "@/components/icons";
import { Input } from "@/components/ui/Field";
import { orderQuick, QUICK_ITEMS } from "@/lib/actions";
import { cn } from "@/lib/cn";
import { QUICK_REPLIES } from "@/lib/reports";
import { ACTION_TONES, Tone, TONES } from "@/lib/tones";
import { MAX_REPLY, useAdmin, useLabel } from "@/store/adminStore";
import { Action, PanelTab, type PanelSettings } from "@/types/protocol";

const MAX_REPLIES = 8;

function Section({ title, hint, action, children }: { title: string; hint?: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-2xl border border-white/5 bg-background/40 p-4">
      <header className="mb-3 flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="text-sm font-semibold">{title}</h2>
          {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
        </div>
        {action}
      </header>
      {children}
    </section>
  );
}

function Switch({ name, on, onChange }: { name: string; on: boolean; onChange: (on: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      data-setting={name}
      onClick={() => onChange(!on)}
      className={cn("relative h-6 w-11 shrink-0 rounded-full transition-colors", on ? "bg-primary" : "bg-white/15")}
    >
      <span className={cn("absolute top-0.5 size-5 rounded-full bg-white shadow-ug-sm transition-all", on ? "left-[1.375rem]" : "left-0.5")} />
    </button>
  );
}

function IconButton({ title, onClick, disabled, children, ...data }: { title: string; onClick: () => void; disabled?: boolean; children: ReactNode; [key: `data-${string}`]: string | boolean | undefined }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      disabled={disabled}
      onClick={onClick}
      className="grid size-7 place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-white/10 hover:text-foreground disabled:pointer-events-none disabled:opacity-30"
      {...data}
    >
      {children}
    </button>
  );
}

/** A copy of a list with one entry moved by `delta`. */
function moved<T>(list: T[], index: number, delta: number): T[] {
  const next = [...list];
  const [entry] = next.splice(index, 1);

  if (entry !== undefined) {
    next.splice(index + delta, 0, entry);
  }

  return next;
}

function ResetButton({ onClick }: { onClick: () => void }) {
  const label = useLabel();

  return (
    <button
      type="button"
      data-reset
      onClick={onClick}
      className="flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs text-muted-foreground transition-colors hover:bg-white/5 hover:text-foreground"
    >
      <RotateCcw className="size-3.5" />
      {label("setting.reset")}
    </button>
  );
}

export function SettingsTab() {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const settings = useAdmin((state) => state.settings);
  const saveSettings = useAdmin((state) => state.saveSettings);

  const update = (patch: Partial<PanelSettings>) => saveSettings({ ...settings, ...patch });

  return (
    <div data-settings className="grid h-full grid-cols-1 content-start gap-4 overflow-y-auto p-6 lg:grid-cols-2">
      <QuickSection settings={settings} access={access} update={update} />
      <div className="flex flex-col gap-4">
        <Section title={label("setting.panel")}>
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <span className="flex-1 text-sm">{label("setting.tab")}</span>
              <div className="flex gap-1 rounded-xl bg-white/[0.04] p-1">
                {Object.values(PanelTab)
                  .filter((tab) => tab !== PanelTab.Reports || access.has(Action.Reports))
                  .map((tab) => (
                    <button
                      key={tab}
                      type="button"
                      data-open-tab={tab}
                      aria-pressed={settings.tab === tab}
                      onClick={() => update({ tab })}
                      className={cn(
                        "rounded-lg px-3 py-1 text-xs font-medium transition-colors",
                        settings.tab === tab ? TONES[Tone.Violet].active : "text-muted-foreground hover:text-foreground",
                      )}
                    >
                      {label(tab)}
                    </button>
                  ))}
              </div>
            </div>
            <label className="flex items-center gap-3">
              <span className="flex-1">
                <span className="block text-sm">{label("setting.confirm")}</span>
                <span className="block text-xs text-muted-foreground">{label("setting.confirmHint")}</span>
              </span>
              <Switch name="confirm" on={settings.confirm} onChange={(confirm) => update({ confirm })} />
            </label>
            <label className="flex items-center gap-3">
              <span className="flex-1">
                <span className="block text-sm">{label("setting.everyone")}</span>
                <span className="block text-xs text-muted-foreground">{label("setting.everyoneHint")}</span>
              </span>
              <Switch name="everyone" on={settings.everyone} onChange={(everyone) => update({ everyone })} />
            </label>
          </div>
        </Section>
        {access.has(Action.Reports) && <RepliesSection settings={settings} update={update} />}
      </div>
    </div>
  );
}

function QuickSection({
  settings,
  access,
  update,
}: {
  settings: PanelSettings;
  access: Set<Action>;
  update: (patch: Partial<PanelSettings>) => void;
}) {
  const label = useLabel();
  const items = orderQuick(QUICK_ITEMS, settings.order).filter((action) => access.has(action));
  const hidden = new Set(settings.hidden);

  const toggle = (action: Action) =>
    update({ hidden: hidden.has(action) ? settings.hidden.filter((entry) => entry !== action) : [...settings.hidden, action] });

  return (
    <Section
      title={label("setting.quick")}
      hint={label("setting.quickHint")}
      action={<ResetButton onClick={() => update({ order: [], hidden: [] })} />}
    >
      <Reorder.Group as="ul" axis="y" values={items} onReorder={(order: Action[]) => update({ order })} className="flex flex-col gap-1.5">
        {items.map((action, index) => {
          const Icon = ACTION_ICONS[action];
          const shown = !hidden.has(action);

          return (
            <Reorder.Item
              key={action}
              value={action}
              data-quick-item={action}
              data-shown={shown}
              className={cn(
                "flex cursor-grab items-center gap-2 rounded-xl border border-white/5 bg-card px-2 py-1.5 active:cursor-grabbing",
                !shown && "opacity-50",
              )}
            >
              <GripVertical className="size-4 shrink-0 text-muted-foreground" />
              <span className={cn("grid size-7 place-items-center rounded-lg", TONES[ACTION_TONES[action] ?? Tone.Indigo].chip)}>
                <Icon className="size-3.5" />
              </span>
              <span className="min-w-0 flex-1 truncate text-sm">{label(`action.${action}`)}</span>
              <IconButton title={label("setting.up")} data-up={action} disabled={index === 0} onClick={() => update({ order: moved(items, index, -1) })}>
                <ChevronUp className="size-4" />
              </IconButton>
              <IconButton
                title={label("setting.down")}
                data-down={action}
                disabled={index === items.length - 1}
                onClick={() => update({ order: moved(items, index, 1) })}
              >
                <ChevronDown className="size-4" />
              </IconButton>
              <IconButton title={label(shown ? "setting.hide" : "setting.show")} data-toggle={action} onClick={() => toggle(action)}>
                {shown ? <Eye className="size-4" /> : <EyeOff className="size-4" />}
              </IconButton>
            </Reorder.Item>
          );
        })}
      </Reorder.Group>
    </Section>
  );
}

function RepliesSection({ settings, update }: { settings: PanelSettings; update: (patch: Partial<PanelSettings>) => void }) {
  const label = useLabel();
  const [draft, setDraft] = useState("");
  const replies = settings.replies ?? QUICK_REPLIES.map((key) => label(`quick.${key}`));
  const text = draft.trim();
  const full = replies.length >= MAX_REPLIES;

  // An empty own list would bring the built-in replies back: removing the last one keeps nothing instead.
  const setReplies = (next: string[]) => update({ replies: next });

  const add = () => {
    if (text === "" || full || [...text].length > MAX_REPLY) {
      return;
    }

    setReplies([...replies, text]);
    setDraft("");
  };

  return (
    <Section
      title={label("setting.replies")}
      hint={label("setting.repliesHint")}
      action={<ResetButton onClick={() => update({ replies: null })} />}
    >
      <ul className="flex flex-col gap-1.5">
        {replies.map((reply, index) => (
          <li key={`${index}-${reply}`} data-reply={index} className="flex items-center gap-2 rounded-xl border border-white/5 bg-card px-3 py-1.5">
            <span className="min-w-0 flex-1 truncate text-sm">{reply}</span>
            <IconButton title={label("setting.up")} disabled={index === 0} onClick={() => setReplies(moved(replies, index, -1))}>
              <ChevronUp className="size-4" />
            </IconButton>
            <IconButton title={label("setting.down")} disabled={index === replies.length - 1} onClick={() => setReplies(moved(replies, index, 1))}>
              <ChevronDown className="size-4" />
            </IconButton>
            <IconButton title={label("setting.remove")} data-remove-reply={index} onClick={() => setReplies(replies.filter((_, at) => at !== index))}>
              <Trash2 className="size-4" />
            </IconButton>
          </li>
        ))}
      </ul>
      <form
        className="mt-3 flex gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          add();
        }}
      >
        <Input
          data-reply-input
          value={draft}
          maxLength={MAX_REPLY}
          disabled={full}
          placeholder={label("setting.replyPlaceholder")}
          onChange={(event) => setDraft(event.target.value)}
        />
        <button
          type="submit"
          data-add-reply
          disabled={full || text === ""}
          className="flex h-10 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-sm font-semibold text-primary-foreground transition hover:brightness-110 disabled:opacity-40"
        >
          <Plus className="size-4" />
          {label("setting.add")}
        </button>
      </form>
    </Section>
  );
}
