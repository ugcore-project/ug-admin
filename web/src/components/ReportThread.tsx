/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The chat of a report. `mine` is the side that reads it: staff in the panel, the player in their window. Their own
// lines go right, the other side's left, and what happened sits in the middle.

import { useEffect, useRef } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/cn";
import { fill, since } from "@/lib/format";
import { useAdmin, useLabel } from "@/store/adminStore";
import { ReportAuthor, type ReportMessage } from "@/types/protocol";

export function ReportThread({ messages, mine, className }: { messages: ReportMessage[]; mine: ReportAuthor; className?: string }) {
  const label = useLabel();
  const self = useAdmin((state) => state.self);
  const end = useRef<HTMLDivElement>(null);

  useEffect(() => {
    end.current?.scrollIntoView?.({ block: "end" });
  }, [messages.length]);

  return (
    <div className={cn("flex flex-col gap-2 overflow-y-auto", className)} data-thread>
      {messages.map((message, index) => {
        if (message.author === ReportAuthor.System) {
          return (
            <div key={index} data-line="system" className="my-1 flex items-center gap-2 text-[11px] text-muted-foreground">
              <span className="h-px flex-1 bg-white/5" />
              <span className="rounded-full bg-white/[0.04] px-2.5 py-0.5">
                {fill(label(`reportEvent.${message.text}`), { name: message.name, to: message.to ?? "?" })} · {since(message.at)}
              </span>
              <span className="h-px flex-1 bg-white/5" />
            </div>
          );
        }

        const own = message.author === mine;
        const staff = message.author === ReportAuthor.Staff;
        const pinged = message.mentions?.includes(self) ?? false;

        return (
          <motion.div
            key={index}
            data-line={message.author}
            initial={{ opacity: 0, y: 6, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ duration: 0.16 }}
            className={cn("flex max-w-[85%] flex-col gap-1", own ? "items-end self-end" : "items-start self-start")}
          >
            <span className="px-1 text-[11px] text-muted-foreground">
              {message.name} · {since(message.at)}
              {pinged && <span className="ml-1.5 font-semibold text-amber-300">{label("desk.mentioned")}</span>}
            </span>
            <p
              data-mentioned={pinged || undefined}
              className={cn(
                pinged && "ring-2 ring-amber-300/80",
                "whitespace-pre-wrap break-words rounded-2xl px-3.5 py-2 text-sm shadow-ug-sm",
                staff
                  ? "bg-gradient-to-br from-violet-500 to-indigo-500 text-white"
                  : "border border-white/10 bg-background/70 text-foreground",
                own ? "rounded-br-md" : "rounded-bl-md",
              )}
            >
              {message.text}
            </p>
          </motion.div>
        );
      })}
      <div ref={end} />
    </div>
  );
}
