/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Every player's help window, opened with /report: a form, then the chat with staff, then a rating. While it is
// closed, a staff answer pops up as a bubble so the player knows to come back.

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { CheckCheck, LifeBuoy, MessageCircle, Send, Star, X } from "lucide-react";
import { EmojiPicker } from "@/components/EmojiPicker";
import { ReportThread } from "@/components/ReportThread";
import { Input } from "@/components/ui/Field";
import { cn } from "@/lib/cn";
import { fill } from "@/lib/format";
import { sendReportCancel, sendReportHide, sendReportOpen, sendReportRate, sendReportReply } from "@/lib/nui";
import { CATEGORY_ICONS, CATEGORY_ORDER, CATEGORY_TONES, MAX_TEXT } from "@/lib/reports";
import { cut, insertAt, length, placeCaret } from "@/lib/text";
import { TONES } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { ReportAuthor, ReportCategory, ReportStatus, type OwnReport } from "@/types/protocol";

const BUBBLE_MS = 9000;
const THANKS_MS = 2500;
const SPRING = { type: "spring", stiffness: 420, damping: 34 } as const;

function hide() {
  useAdmin.setState({ reportWindow: false });
  void sendReportHide();
}

export function ReportWindow() {
  const label = useLabel();
  const open = useAdmin((state) => state.reportWindow);
  const report = useAdmin((state) => state.myReport);
  const [thanks, setThanks] = useState(false);

  useEffect(() => {
    if (!open) {
      return;
    }

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        hide();
      }
    };

    window.addEventListener("keydown", onKey);

    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  useEffect(() => {
    if (!thanks) {
      return;
    }

    const timer = setTimeout(() => setThanks(false), THANKS_MS);

    return () => clearTimeout(timer);
  }, [thanks]);

  return (
    <>
      <AnimatePresence>
        {open && (
          <motion.section
            key="report-window"
            data-report-window
            initial={{ opacity: 0, x: 40, scale: 0.96 }}
            animate={{ opacity: 1, x: 0, scale: 1 }}
            exit={{ opacity: 0, x: 30, scale: 0.97 }}
            transition={SPRING}
            className="fixed bottom-24 right-8 flex h-[min(34rem,78vh)] w-[24rem] flex-col overflow-hidden rounded-2xl border border-white/10 bg-card text-card-foreground shadow-ug-lg"
          >
            <div className="h-1 bg-gradient-to-r from-violet-500 via-indigo-500 to-blue-500" />
            <header className="flex items-center gap-3 px-4 py-3">
              <span className="grid size-9 place-items-center rounded-xl bg-gradient-to-br from-violet-500 to-indigo-500 text-white shadow-ug-sm">
                <LifeBuoy className="size-5" />
              </span>
              <div className="min-w-0 flex-1">
                <h2 className="text-sm font-semibold">{label("myReport.title")}</h2>
                <p className="truncate text-xs text-muted-foreground">{label("myReport.subtitle")}</p>
              </div>
              <button
                type="button"
                title={label("myReport.close")}
                onClick={hide}
                className="grid size-8 place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-white/5 hover:text-foreground"
              >
                <X className="size-4" />
              </button>
            </header>

            {thanks ? (
              <motion.div initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} className="grid flex-1 place-items-center p-6 text-center">
                <div>
                  <Star className="mx-auto mb-3 size-10 fill-amber-300 text-amber-300" />
                  <p className="text-sm font-medium">{label("myReport.thanks")}</p>
                </div>
              </motion.div>
            ) : report === null ? (
              <ReportForm />
            ) : report.status === ReportStatus.Closed ? (
              <ReportRating report={report} onRated={() => setThanks(true)} />
            ) : (
              <ReportChat report={report} />
            )}
          </motion.section>
        )}
      </AnimatePresence>
      <ReportBubble />
    </>
  );
}

function ReportForm() {
  const label = useLabel();
  const [category, setCategory] = useState<ReportCategory>(ReportCategory.Question);
  const [message, setMessage] = useState("");
  const [accused, setAccused] = useState("");
  const field = useRef<HTMLTextAreaElement>(null);

  const addEmoji = (emoji: string) => {
    const result = insertAt(field.current, message, emoji, MAX_TEXT);

    if (result) {
      setMessage(result.value);
      placeCaret(field.current, result.caret);
    }
  };

  const submit = () => {
    const text = cut(message.trim(), MAX_TEXT);
    const id = Number.parseInt(accused, 10);

    if (text === "") {
      return;
    }

    void sendReportOpen(text, category, category === ReportCategory.Player && id >= 1 && id <= 65535 ? id : undefined);
    setMessage("");
    setAccused("");
  };

  return (
    <form
      data-report-form
      className="flex flex-1 flex-col gap-3 overflow-y-auto px-4 pb-4"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      <span className="text-xs font-medium text-muted-foreground">{label("myReport.category")}</span>
      <div className="grid grid-cols-3 gap-2">
        {CATEGORY_ORDER.map((entry) => {
          const Icon = CATEGORY_ICONS[entry];
          const tone = TONES[CATEGORY_TONES[entry]];

          return (
            <button
              key={entry}
              type="button"
              data-category={entry}
              aria-pressed={category === entry}
              onClick={() => setCategory(entry)}
              className={cn(
                "flex flex-col items-center gap-1.5 rounded-xl border px-2 py-2.5 text-xs font-medium transition-colors",
                category === entry ? tone.active : cn("border-white/10 bg-background/40 text-muted-foreground", tone.hover),
              )}
            >
              <span className={cn("grid size-7 place-items-center rounded-lg", tone.chip)}>
                <Icon className="size-4" />
              </span>
              {label(`category.${entry}`)}
            </button>
          );
        })}
      </div>

      {category === ReportCategory.Player && (
        <Input
          data-accused-input
          inputMode="numeric"
          value={accused}
          placeholder={label("myReport.accused")}
          onChange={(event) => setAccused(event.target.value.replace(/\D/g, "").slice(0, 5))}
        />
      )}

      <textarea
        ref={field}
        data-report-message
        value={message}
        maxLength={MAX_TEXT}
        placeholder={label("myReport.message")}
        onChange={(event) => setMessage(event.target.value)}
        className="min-h-28 flex-1 resize-none rounded-lg border border-white/10 bg-background/70 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary/60 focus:outline-none focus:ring-2 focus:ring-primary/30"
      />
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-2 text-[11px] text-muted-foreground">
          <EmojiPicker onPick={addEmoji} />
          {length(message)}/{MAX_TEXT}
        </span>
        <button
          type="submit"
          disabled={message.trim() === ""}
          className="flex h-10 items-center gap-2 rounded-lg bg-gradient-to-r from-violet-500 to-indigo-500 px-4 text-sm font-semibold text-white shadow-ug-sm transition hover:brightness-110 disabled:opacity-50"
        >
          <Send className="size-4" />
          {label("myReport.send")}
        </button>
      </div>
    </form>
  );
}

function ReportChat({ report }: { report: OwnReport }) {
  const label = useLabel();
  const [draft, setDraft] = useState("");
  const field = useRef<HTMLInputElement>(null);
  const handling = report.status === ReportStatus.Claimed;

  const addEmoji = (emoji: string) => {
    const result = insertAt(field.current, draft, emoji, MAX_TEXT);

    if (result) {
      setDraft(result.value);
      placeCaret(field.current, result.caret);
    }
  };

  return (
    <>
      <div
        data-my-status={report.status}
        className={cn(
          "mx-4 flex items-center gap-2 rounded-lg px-3 py-2 text-xs font-medium",
          handling ? "bg-primary/15 text-primary" : "bg-warning/15 text-warning",
        )}
      >
        <span className={cn("size-2 rounded-full", handling ? "bg-primary" : "animate-pulse bg-warning")} />
        {handling ? fill(label("myReport.handling"), { name: report.claimedBy ?? "?" }) : label("myReport.waiting")}
        <button
          type="button"
          data-cancel
          onClick={() => void sendReportCancel()}
          className="ml-auto flex items-center gap-1 rounded-md px-1.5 py-0.5 text-success transition-colors hover:bg-success/15"
        >
          <CheckCheck className="size-3.5" />
          {label("myReport.cancel")}
        </button>
      </div>

      <ReportThread messages={report.messages} mine={ReportAuthor.Player} className="min-h-0 flex-1 px-4 py-3" />

      <form
        className="flex gap-2 border-t border-white/5 p-3"
        onSubmit={(event) => {
          event.preventDefault();

          const text = cut(draft.trim(), MAX_TEXT);

          if (text !== "") {
            void sendReportReply(text);
            setDraft("");
          }
        }}
      >
        <EmojiPicker onPick={addEmoji} />
        <Input ref={field} data-reply value={draft} maxLength={MAX_TEXT} placeholder={label("myReport.reply")} onChange={(event) => setDraft(event.target.value)} />
        <button
          type="submit"
          title={label("reportOp.reply")}
          className="grid size-10 shrink-0 place-items-center rounded-lg bg-gradient-to-r from-violet-500 to-indigo-500 text-white transition hover:brightness-110"
        >
          <Send className="size-4" />
        </button>
      </form>
    </>
  );
}

function ReportRating({ report, onRated }: { report: OwnReport; onRated: () => void }) {
  const label = useLabel();
  const [hover, setHover] = useState(0);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <ReportThread messages={report.messages} mine={ReportAuthor.Player} className="min-h-0 flex-1 px-4 py-3 opacity-70" />
      <div className="flex flex-col items-center gap-2 border-t border-white/5 p-4">
        <p className="text-xs text-muted-foreground">{fill(label("myReport.closed"), { name: report.closedBy ?? "?" })}</p>
        <p className="text-sm font-semibold">{label("myReport.rate")}</p>
        <div className="flex gap-1" onMouseLeave={() => setHover(0)}>
          {[1, 2, 3, 4, 5].map((star) => (
            <motion.button
              key={star}
              type="button"
              data-star={star}
              whileHover={{ scale: 1.2, rotate: -8 }}
              whileTap={{ scale: 0.9 }}
              onMouseEnter={() => setHover(star)}
              onClick={() => {
                void sendReportRate(star);
                onRated();
              }}
              className="p-1 text-amber-300"
            >
              <Star className={cn("size-7 transition-all", star <= hover ? "fill-current drop-shadow-[0_0_8px_rgb(252_211_77)]" : "opacity-40")} />
            </motion.button>
          ))}
        </div>
      </div>
    </div>
  );
}

function ReportBubble() {
  const label = useLabel();
  const bubble = useAdmin((state) => state.bubble);

  useEffect(() => {
    if (!bubble) {
      return;
    }

    const timer = setTimeout(() => useAdmin.setState({ bubble: null }), BUBBLE_MS);

    return () => clearTimeout(timer);
  }, [bubble]);

  return (
    <AnimatePresence>
      {bubble && (
        <motion.div
          key={bubble.key}
          data-report-bubble
          initial={{ opacity: 0, y: 20, scale: 0.9 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, x: 40 }}
          transition={SPRING}
          className="fixed bottom-24 right-8 w-[22rem] overflow-hidden rounded-2xl border border-violet-400/30 bg-card/95 text-card-foreground shadow-[0_0_32px_-8px_rgb(139_92_246)]"
        >
          <div className="flex items-start gap-3 p-3.5">
            <span className="relative grid size-9 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-violet-500 to-indigo-500 text-white">
              <MessageCircle className="size-4" />
              <span className="absolute -right-0.5 -top-0.5 size-2.5 animate-ping rounded-full bg-violet-300" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[11px] font-semibold uppercase tracking-wider text-violet-300">{label("myReport.newReply")}</p>
              <p className="text-sm">
                <span className="font-semibold">{bubble.name}:</span> <span className="break-words">{bubble.text}</span>
              </p>
              <p className="mt-1 text-[11px] text-muted-foreground">{label("myReport.hint")}</p>
            </div>
          </div>
          <motion.div
            className="h-0.5 origin-left bg-gradient-to-r from-violet-500 to-blue-500"
            initial={{ scaleX: 1 }}
            animate={{ scaleX: 0 }}
            transition={{ duration: BUBBLE_MS / 1000, ease: "linear" }}
          />
        </motion.div>
      )}
    </AnimatePresence>
  );
}
