/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useState, type FormEvent } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ClockArrowDown, Plus, StickyNote, X } from "lucide-react";
import { Card } from "@/components/Card";
import { ACTION_ICONS } from "@/components/icons";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Field";
import { fill, since } from "@/lib/format";
import { sendRun } from "@/lib/nui";
import { Tone } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action, type PlayerDetails } from "@/types/protocol";

const MAX_NOTE = 256;

/** What staff did to this player, and the private notes they keep about them. */
export function HistoryCard({ details }: { details: PlayerDetails }) {
  const label = useLabel();
  const access = useAdmin((state) => state.access);
  const [text, setText] = useState("");

  const add = (event: FormEvent) => {
    event.preventDefault();

    const note = text.trim();

    if (note === "") {
      return;
    }

    void sendRun(Action.Note, details.id, { text: note });
    setText("");
  };

  return (
    <div className="col-span-2 grid grid-cols-2 gap-3">
      <Card icon={ClockArrowDown} title={label("history")} tone={Tone.Sky} extra={<span className="font-mono">{details.history.length}</span>}>
        {details.history.length === 0 ? (
          <p className="text-sm text-muted-foreground">{label("noHistory")}</p>
        ) : (
          <ol className="max-h-56 space-y-1 overflow-y-auto pr-1">
            {details.history.map((entry, index) => {
              const Icon = ACTION_ICONS[entry.action as Action];

              return (
                <li key={entry.id ?? `h${index}`} data-history={entry.action} className="flex items-start gap-2 rounded-lg bg-white/[0.03] px-2 py-1.5 text-xs">
                  <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-md bg-primary/15 text-primary">
                    {Icon ? <Icon className="size-3" /> : null}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-1.5">
                      <span className="font-medium">{label(`action.${entry.action}`)}</span>
                      <span className="truncate text-muted-foreground">{fill(label("by"), { name: entry.actorName })}</span>
                      <span className="ml-auto shrink-0 text-muted-foreground">{fill(label("ago"), { time: since(entry.at) })}</span>
                    </span>
                    {entry.detail !== "" && <span className="block truncate text-muted-foreground">{entry.detail}</span>}
                  </span>
                </li>
              );
            })}
          </ol>
        )}
      </Card>

      <Card icon={StickyNote} title={label("notes")} tone={Tone.Amber} extra={<span className="font-mono">{details.notes.length}</span>}>
        {access.has(Action.Note) && (
          <form onSubmit={add} className="mb-2 flex gap-1.5">
            <Input
              value={text}
              maxLength={MAX_NOTE}
              placeholder={label("notePlaceholder")}
              className="h-8 text-xs"
              onChange={(event) => setText(event.target.value)}
              data-note-input
            />
            <Button type="submit" className="h-8 shrink-0 rounded-lg px-2.5 text-xs" disabled={text.trim() === ""}>
              <Plus className="size-3.5" />
              {label("addNote")}
            </Button>
          </form>
        )}
        {details.notes.length === 0 ? (
          <p className="text-sm text-muted-foreground">{label("noNotes")}</p>
        ) : (
          <ul className="max-h-44 space-y-1.5 overflow-y-auto pr-1">
            <AnimatePresence initial={false}>
              {details.notes.map((note) => (
                <motion.li
                  key={note.id}
                  layout
                  initial={{ opacity: 0, y: -4 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, x: 20 }}
                  data-note={note.id}
                  className="group relative rounded-lg border-l-2 border-warning/60 bg-warning/[0.06] px-2.5 py-1.5 text-xs"
                >
                  <p className="whitespace-pre-wrap break-words pr-5">{note.text}</p>
                  <p className="mt-0.5 text-[10px] text-muted-foreground">
                    {note.authorName} · {fill(label("ago"), { time: since(note.at) })}
                  </p>
                  {access.has(Action.DeleteNote) && (
                    <button
                      type="button"
                      title={label("deleteNote")}
                      onClick={() => void sendRun(Action.DeleteNote, details.id, { note: note.id })}
                      className="absolute right-1 top-1 grid size-5 place-items-center rounded text-muted-foreground opacity-0 transition-opacity hover:bg-destructive/20 hover:text-destructive group-hover:opacity-100"
                      data-delete-note={note.id}
                    >
                      <X className="size-3" />
                    </button>
                  )}
                </motion.li>
              ))}
            </AnimatePresence>
          </ul>
        )}
      </Card>
    </div>
  );
}
