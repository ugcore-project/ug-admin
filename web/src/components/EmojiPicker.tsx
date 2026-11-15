/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Smile } from "lucide-react";
import { cn } from "@/lib/cn";
import { useDismiss } from "@/lib/dismiss";
import { EMOJIS } from "@/lib/emojis";
import { useLabel } from "@/store/adminStore";

/** The emoji grid. A click picks one and leaves the grid open, so several MAY follow. */
export function EmojiGrid({ onPick }: { onPick: (emoji: string) => void }) {
  return (
    <div className="grid grid-cols-8 gap-0.5">
      {EMOJIS.map((emoji) => (
        <button
          key={emoji}
          type="button"
          data-emoji={emoji}
          onClick={() => onPick(emoji)}
          className="grid aspect-square place-items-center rounded-lg text-lg transition-transform hover:scale-110 hover:bg-white/10"
        >
          {emoji}
        </button>
      ))}
    </div>
  );
}

/** A button that opens the emoji grid above it. Closes on a click anywhere else. */
export function EmojiPicker({
  onPick,
  disabled = false,
  align = "left",
}: {
  onPick: (emoji: string) => void;
  disabled?: boolean;
  align?: "left" | "right";
}) {
  const label = useLabel();
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);

  useDismiss(box, open, () => setOpen(false));

  return (
    <div ref={box} className="relative shrink-0">
      <button
        type="button"
        data-tool="emoji"
        title={label("desk.emoji")}
        aria-label={label("desk.emoji")}
        aria-expanded={open}
        disabled={disabled}
        onClick={() => setOpen((value) => !value)}
        className={cn(
          "grid size-10 place-items-center rounded-lg border transition-colors disabled:opacity-40",
          open
            ? "border-violet-400/50 bg-violet-500/15 text-violet-200"
            : "border-white/10 bg-background/70 text-muted-foreground hover:border-white/20 hover:text-foreground",
        )}
      >
        <Smile className="size-4" />
      </button>
      <AnimatePresence>
        {open && !disabled && (
          <motion.div
            data-tool-panel="emoji"
            initial={{ opacity: 0, y: 6, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 6, scale: 0.98 }}
            transition={{ duration: 0.12 }}
            className={cn(
              "absolute bottom-full z-20 mb-2 w-72 rounded-xl border border-white/10 bg-card p-2 shadow-ug-lg",
              align === "left" ? "left-0" : "right-0",
            )}
          >
            <EmojiGrid onPick={onPick} />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
