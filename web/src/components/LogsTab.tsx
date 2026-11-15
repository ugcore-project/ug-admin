/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { ArrowRight, Loader2, Search } from "lucide-react";
import { ACTION_ICONS } from "@/components/icons";
import { Input } from "@/components/ui/Field";
import { fill, since } from "@/lib/format";
import { sendLogs } from "@/lib/nui";
import { useAdmin, useLabel } from "@/store/adminStore";
import type { Action } from "@/types/protocol";

const SEARCH_DELAY_MS = 350;
// Only the first rows animate in, so a long log does not crawl.
const STAGGER_ROWS = 12;

export function LogsTab() {
  const label = useLabel();
  const logs = useAdmin((state) => state.logs);
  const [search, setSearch] = useState("");

  // The server allows 3 searches per 3 s: typing waits for a pause.
  useEffect(() => {
    const timer = setTimeout(() => void sendLogs(search.trim()), SEARCH_DELAY_MS);

    return () => clearTimeout(timer);
  }, [search]);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="relative px-5 pb-3 pt-4">
        <Search className="pointer-events-none absolute left-8 top-1/2 mt-0.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input value={search} maxLength={64} placeholder={label("searchLogs")} className="pl-9" onChange={(event) => setSearch(event.target.value)} />
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-5">
        {logs === null && <Loader2 className="mx-auto mt-10 size-6 animate-spin text-muted-foreground" />}
        {logs?.length === 0 && <p className="p-4 text-center text-sm text-muted-foreground">{label("noLogs")}</p>}
        {logs !== null && logs.length > 0 && (
          <ol className="relative">
            <span className="absolute bottom-3 left-[17px] top-3 w-px bg-gradient-to-b from-primary/40 via-white/10 to-transparent" />
            {logs.map((entry, index) => {
              const Icon = ACTION_ICONS[entry.action as Action];

              return (
                <motion.li
                  key={entry.id ?? `m${index}`}
                  data-log
                  initial={index < STAGGER_ROWS ? { opacity: 0, x: -6 } : false}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: Math.min(index, STAGGER_ROWS) * 0.02 }}
                  className="relative flex items-start gap-3 py-1.5"
                >
                  <span className="relative z-10 grid size-9 shrink-0 place-items-center rounded-xl border border-white/10 bg-card text-primary shadow-ug-sm">
                    {Icon ? <Icon className="size-4" /> : null}
                  </span>
                  <div className="min-w-0 flex-1 rounded-xl border border-white/5 bg-white/[0.03] px-3 py-2 text-sm transition-colors hover:bg-white/[0.05]">
                    <div className="flex items-center gap-2">
                      <span className="truncate">
                        <span className="font-semibold">{entry.actorName}</span>
                        <span className="text-muted-foreground"> · {label(`action.${entry.action}`)}</span>
                      </span>
                      {entry.targetName && (
                        <span className="flex min-w-0 items-center gap-1 truncate">
                          <ArrowRight className="size-3 shrink-0 text-muted-foreground" />
                          <span className="truncate font-medium text-primary">{entry.targetName}</span>
                        </span>
                      )}
                      <span className="ml-auto shrink-0 text-xs text-muted-foreground" title={new Date(entry.at * 1000).toLocaleString()}>
                        {fill(label("ago"), { time: since(entry.at) })}
                      </span>
                    </div>
                    {entry.detail !== "" && <div className="mt-0.5 truncate text-xs text-muted-foreground">{entry.detail}</div>}
                  </div>
                </motion.li>
              );
            })}
          </ol>
        )}
      </div>
    </div>
  );
}
