/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useState, type FormEvent, type KeyboardEvent } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Backpack, PackageMinus, Pencil, Wallet } from "lucide-react";
import { Card } from "@/components/Card";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Field";
import { cn } from "@/lib/cn";
import { money } from "@/lib/format";
import { sendRun } from "@/lib/nui";
import { Tone } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action, type Slot } from "@/types/protocol";

const INTEGER = /^-?\d{1,9}$/;

interface AccountsCardProps {
  target: number;
  accounts: Record<string, number>;
}

/** Balances. Staff who may set them click one to type the exact value. */
export function AccountsCard({ target, accounts }: AccountsCardProps) {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const catalog = useAdmin((state) => state.catalog);
  const locale = useAdmin((state) => state.config.locale);
  const [editing, setEditing] = useState<string | null>(null);
  const [value, setValue] = useState("");
  const editable = access.has(Action.SetMoney);

  const start = (name: string, balance: number) => {
    setEditing(name);
    setValue(String(balance));
  };

  const submit = (event: FormEvent) => {
    event.preventDefault();

    if (editing && INTEGER.test(value.trim())) {
      void sendRun(Action.SetMoney, target, { account: editing, amount: Number(value.trim()) });
      setEditing(null);
    }
  };

  const cancel = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      setEditing(null);
    }
  };

  return (
    <Card icon={Wallet} title={label("accounts")} tone={Tone.Emerald}>
      <div className="space-y-1.5">
        {Object.entries(accounts).map(([name, balance]) => (
          <div key={name} className="flex items-center justify-between gap-2 rounded-lg bg-white/[0.03] px-2.5 py-1.5" data-account={name}>
            <span className="text-xs text-muted-foreground">{catalog.accounts.find((account) => account.name === name)?.label ?? name}</span>
            {editing === name ? (
              <form onSubmit={submit} className="flex w-32">
                <Input
                  autoFocus
                  inputMode="numeric"
                  value={value}
                  maxLength={10}
                  onChange={(event) => setValue(event.target.value)}
                  onKeyDown={cancel}
                  onBlur={() => setEditing(null)}
                  className="h-7 px-2 text-right font-mono text-sm"
                  data-balance-input
                />
              </form>
            ) : (
              <button
                type="button"
                disabled={!editable}
                title={editable ? label("editBalance") : undefined}
                onClick={() => start(name, balance)}
                className={cn(
                  "group flex items-center gap-1.5 rounded-md px-1 font-mono text-sm font-semibold transition-colors",
                  editable && "hover:bg-primary/15 hover:text-primary",
                  balance < 0 && "text-destructive",
                )}
              >
                {money(balance, locale)}
                {editable && <Pencil className="size-3 opacity-0 transition-opacity group-hover:opacity-70" />}
              </button>
            )}
          </div>
        ))}
      </div>
    </Card>
  );
}

interface InventoryCardProps {
  target: number;
  items: Slot[];
}

/** Inventory slots. Staff who may remove items click a slot to take some or all of it. */
export function InventoryCard({ target, items }: InventoryCardProps) {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const catalog = useAdmin((state) => state.catalog);
  const [picked, setPicked] = useState<number | null>(null);
  const [count, setCount] = useState("1");
  const editable = access.has(Action.RemoveItem);
  const itemLabel = (name: string) => catalog.items.find((item) => item.name === name)?.label ?? name;
  const slot = items.find((entry) => entry.slot === picked);

  const pick = (entry: Slot) => {
    setPicked(picked === entry.slot ? null : entry.slot);
    setCount(String(entry.count));
  };

  const remove = (amount: number) => {
    if (slot && Number.isInteger(amount) && amount >= 1) {
      void sendRun(Action.RemoveItem, target, { slot: slot.slot, count: Math.min(amount, slot.count) });
      setPicked(null);
    }
  };

  return (
    <Card icon={Backpack} title={label("items")} className="col-span-2" tone={Tone.Amber}>
      {items.length === 0 ? (
        <p className="text-sm text-muted-foreground">{label("noItems")}</p>
      ) : (
        <>
          <div className="grid grid-cols-5 gap-1.5">
            {items.map((entry) => (
              <button
                key={entry.slot}
                type="button"
                disabled={!editable}
                onClick={() => pick(entry)}
                data-slot={entry.slot}
                className={cn(
                  "relative rounded-lg border px-2 pb-1.5 pt-4 text-left text-xs transition-colors",
                  picked === entry.slot ? "border-destructive/60 bg-destructive/10" : "border-white/5 bg-white/[0.03]",
                  editable && picked !== entry.slot && "hover:border-primary/40 hover:bg-primary/[0.08]",
                )}
              >
                <span className="absolute left-1.5 top-1 font-mono text-[9px] text-muted-foreground">{entry.slot}</span>
                <span className="absolute right-1.5 top-1 rounded bg-primary/20 px-1 font-mono text-[10px] font-semibold text-primary">×{entry.count}</span>
                <span className="block truncate font-medium">{itemLabel(entry.name)}</span>
              </button>
            ))}
          </div>
          <AnimatePresence initial={false}>
            {slot && (
              <motion.div
                key="remove"
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                className="overflow-hidden"
              >
                <div className="mt-2 flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/[0.06] p-2" data-remove-bar>
                  <PackageMinus className="size-4 shrink-0 text-destructive" />
                  <span className="min-w-0 flex-1 truncate text-xs">
                    {itemLabel(slot.name)} · {label("slot")} {slot.slot}
                  </span>
                  <Input
                    inputMode="numeric"
                    value={count}
                    maxLength={7}
                    onChange={(event) => setCount(event.target.value)}
                    className="h-8 w-20 text-right font-mono text-xs"
                    data-remove-count
                  />
                  <Button variant="destructive" className="h-8 rounded-lg px-2.5 text-xs" onClick={() => remove(Number(count))} data-remove>
                    {label("remove")}
                  </Button>
                  <Button variant="outline" className="h-8 rounded-lg border-white/10 px-2.5 text-xs" onClick={() => remove(slot.count)} data-remove-all>
                    {label("removeAll")}
                  </Button>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </>
      )}
    </Card>
  );
}
