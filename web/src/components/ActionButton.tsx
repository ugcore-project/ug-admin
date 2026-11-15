/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useState, type FormEvent } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Send } from "lucide-react";
import { ACTION_ICONS } from "@/components/icons";
import { Button } from "@/components/ui/Button";
import { Input, Select } from "@/components/ui/Field";
import { buildArgs, Field, type ActionSpec, type FormValues } from "@/lib/actions";
import { cn } from "@/lib/cn";
import { sendRun } from "@/lib/nui";
import { ACTION_TONES, Tone, TONES } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action } from "@/types/protocol";

const CONFIRM_MS = 3000;
const NUMERIC = new Set<Field>([Field.Amount, Field.Count, Field.Grade, Field.Minutes]);
// The location value that means the staff member's own waypoint.
const WAYPOINT = "waypoint";

interface ActionButtonProps {
  spec: ActionSpec;
  target?: number;
  /** Groups the target has, for removing one. */
  targetGroups?: string[] | undefined;
  expanded: boolean;
  onExpand: (expanded: boolean) => void;
  /** `tile` in the player grid, `pill` in the quick bar. */
  look?: "tile" | "pill";
  /** Accent color. Quick bar actions have their own. */
  tone?: Tone;
}

/** One action: a button, an inline form when it needs values, and a second click when it is destructive. */
export function ActionButton({ spec, target, targetGroups, expanded, onExpand, look = "tile", tone }: ActionButtonProps) {
  const label = useLabel();
  const confirm = useAdmin((state) => state.settings.confirm);
  const catalog = useAdmin((state) => state.catalog);
  const [values, setValues] = useState<FormValues>({});
  const [armed, setArmed] = useState(false);
  const [invalid, setInvalid] = useState(false);
  const Icon = ACTION_ICONS[spec.action];
  const colors = TONES[tone ?? ACTION_TONES[spec.action] ?? Tone.Indigo];
  const chip = spec.danger ? "bg-destructive/15 text-destructive" : colors.chip;

  useEffect(() => {
    if (!armed) {
      return;
    }

    const timer = setTimeout(() => setArmed(false), CONFIRM_MS);

    return () => clearTimeout(timer);
  }, [armed]);

  useEffect(() => {
    if (!expanded) {
      setValues({});
      setArmed(false);
      setInvalid(false);
    }
  }, [expanded]);

  const run = (args?: ReturnType<typeof buildArgs>) => {
    if (spec.confirm && confirm && !armed) {
      setArmed(true);

      return;
    }

    setArmed(false);
    void sendRun(spec.action, target, args ?? undefined);
    onExpand(false);
  };

  const submit = (event: FormEvent) => {
    event.preventDefault();

    const args = buildArgs(spec.fields, values, spec.optional);

    if (!args) {
      setInvalid(true);

      return;
    }

    setInvalid(false);
    run(args);
  };

  const set = (field: Field, value: string) => {
    setValues((current) => {
      const next = { ...current, [field]: value };

      // A new job or gang has other grades.
      if (field === Field.Job || field === Field.Gang) {
        delete next[Field.Grade];
      }

      return next;
    });
  };

  const assignment =
    spec.fields.includes(Field.Job) ? catalog.jobs.find((job) => job.name === values.job)
    : spec.fields.includes(Field.Gang) ? catalog.gangs.find((gang) => gang.name === values.gang)
    : undefined;

  const options: Partial<Record<Field, { value: string; label: string }[]>> = {
    [Field.Account]: catalog.accounts.map((entry) => ({ value: entry.name, label: entry.label })),
    [Field.Job]: catalog.jobs.map((entry) => ({ value: entry.name, label: entry.label })),
    [Field.Gang]: catalog.gangs.map((entry) => ({ value: entry.name, label: entry.label })),
    [Field.Item]: catalog.items.map((entry) => ({ value: entry.name, label: `${entry.label} · ${entry.name}` })),
    [Field.Duration]: catalog.banDurations.map((entry) => ({ value: entry, label: entry })),
    [Field.Location]: [
      { value: WAYPOINT, label: label("waypoint") },
      ...catalog.locations.map((entry) => ({ value: entry.name, label: entry.label })),
    ],
    [Field.Grade]: (assignment?.grades ?? []).map((entry) => ({ value: String(entry.grade), label: `${entry.grade} · ${entry.label}` })),
    [Field.Group]: spec.action === Action.RemoveGroup && targetGroups
      ? targetGroups.map((name) => ({ value: name, label: catalog.groups.find((group) => group.name === name)?.label ?? name }))
      : catalog.groups.map((entry) => ({ value: entry.name, label: entry.label })),
  };

  const placeholders: Partial<Record<Field, string | undefined>> = {
    [Field.Model]: label("spawnPlaceholder"),
    [Field.Text]: spec.action === Action.Announce ? label("announcePlaceholder") : undefined,
    [Field.Identifier]: "license:...",
  };

  const click = () => {
    if (spec.fields.length > 0) {
      onExpand(!expanded);
    } else {
      run();
    }
  };

  const text = armed && spec.fields.length === 0 ? label("confirm") : label(`action.${spec.action}`);

  return (
    <div className="contents">
      {look === "pill" ? (
        <motion.button
          type="button"
          onClick={click}
          data-action={spec.action}
          whileTap={{ scale: 0.94 }}
          className={cn(
            "flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-xs font-medium transition-colors",
            expanded ? colors.active : cn("border-transparent text-foreground/90", colors.hover),
            armed && "animate-pulse border-destructive bg-destructive/20 text-foreground",
          )}
        >
          <Icon className={cn("size-3.5", !expanded && colors.text)} />
          {text}
        </motion.button>
      ) : (
        <motion.button
          type="button"
          onClick={click}
          data-action={spec.action}
          whileHover={{ y: -2 }}
          whileTap={{ scale: 0.96 }}
          className={cn(
            "group flex h-[4.75rem] flex-col items-center justify-center gap-1.5 rounded-xl border px-2 text-xs font-medium transition-colors",
            "border-white/5 bg-white/[0.03]",
            colors.hover,
            spec.danger && "hover:border-destructive/50 hover:bg-destructive/10",
            expanded && colors.active,
            armed && "animate-pulse border-destructive bg-destructive/20 text-foreground ring-1 ring-destructive/60",
          )}
        >
          <span
            className={cn(
              "grid size-8 place-items-center rounded-lg transition-transform group-hover:scale-110",
              chip,
            )}
          >
            <Icon className="size-4" />
          </span>
          <span className="max-w-full truncate">{text}</span>
        </motion.button>
      )}

      <AnimatePresence initial={false}>
        {expanded && spec.fields.length > 0 && (
          <motion.form
            key="form"
            onSubmit={submit}
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="col-span-full basis-full overflow-hidden"
          >
            <div
              className={cn(
                "flex flex-wrap items-end gap-3 rounded-xl border bg-background/60 p-3",
                invalid ? "border-destructive/70" : "border-white/10",
              )}
            >
              <span className={cn("grid size-9 shrink-0 place-items-center rounded-lg", chip)}>
                <Icon className="size-4" />
              </span>
              {spec.fields.map((field) => (
                <label key={field} className="flex min-w-[9rem] flex-1 flex-col gap-1 text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
                  <span>
                    {label(`field.${field}`)}
                    {spec.optional?.includes(field) && <span className="ml-1 normal-case tracking-normal opacity-60">({label("optional")})</span>}
                  </span>
                  {options[field] ? (
                    <Select
                      value={values[field] ?? ""}
                      placeholder="—"
                      options={options[field]}
                      onChange={(event) => set(field, event.target.value)}
                    />
                  ) : (
                    <Input
                      value={values[field] ?? ""}
                      inputMode={NUMERIC.has(field) ? "numeric" : undefined}
                      placeholder={placeholders[field]}
                      maxLength={field === Field.Text ? 256 : field === Field.Reason ? 200 : 64}
                      autoFocus={field === spec.fields[0]}
                      onChange={(event) => set(field, event.target.value)}
                    />
                  )}
                </label>
              ))}
              <Button type="submit" variant={spec.danger ? "destructive" : "default"} className={cn("h-10 rounded-lg", armed && "animate-pulse")}>
                <Send className="size-4" />
                {armed ? label("confirm") : label("send")}
              </Button>
            </div>
          </motion.form>
        )}
      </AnimatePresence>
    </div>
  );
}
