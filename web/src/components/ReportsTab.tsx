/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The report desk: a queue on the left, the chat with the reporter on the right. Every button is intent: the server
// checks access, rank and distance, and the list comes back from it.

import { useEffect, useRef, useState, type ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  AtSign,
  CheckCheck,
  Smile,
  Clock,
  Eye,
  Hand,
  Headset,
  HeartPulse,
  LockOpen,
  Magnet,
  Navigation,
  PartyPopper,
  Search,
  Send,
  Star,
  Undo2,
  UserCheck,
  UserPlus,
  type LucideIcon,
} from "lucide-react";
import { Avatar } from "@/components/Avatar";
import { EmojiGrid } from "@/components/EmojiPicker";
import { ReportThread } from "@/components/ReportThread";
import { Input } from "@/components/ui/Field";
import { cn } from "@/lib/cn";
import { useDismiss } from "@/lib/dismiss";
import { cut, insertAt, placeCaret } from "@/lib/text";
import { fill, since } from "@/lib/format";
import { sendRun } from "@/lib/nui";
import { CATEGORY_ICONS, CATEGORY_TONES, MAX_TEXT, matchesPlayer, QUICK_REPLIES } from "@/lib/reports";
import { Tone, TONES } from "@/lib/tones";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action, ReportAuthor, ReportOp, ReportStatus, type PlayerRow, type Report } from "@/types/protocol";

const Filter = {
  Queue: "queue",
  Mine: "mine",
  Closed: "closed",
} as const;

type Filter = (typeof Filter)[keyof typeof Filter];

const FILTERS: Filter[] = [Filter.Queue, Filter.Mine, Filter.Closed];

function runOp(report: number, op: ReportOp, text?: string, staff?: number) {
  return sendRun(Action.Reports, undefined, { report, op, ...(text ? { text } : {}), ...(staff ? { staff } : {}) });
}

// Staff the mention list shows at once.
const MENTIONS_SHOWN = 5;

/** The `@word` being typed at the end of a draft, or undefined. */
function mentionQuery(draft: string): string | undefined {
  return /(?:^|\s)@([^\s@]*)$/.exec(draft)?.[1];
}

/** Picked `@Name` become `@id` on the wire: the server turns them back into names and pings those staff. */
function toWire(text: string, picks: Map<string, number>): string {
  let wire = text;

  for (const [name, id] of [...picks].sort((a, b) => b[0].length - a[0].length)) {
    wire = wire.split(`@${name}`).join(`@${id}`);
  }

  return wire;
}

/** A player line the staff member has not read yet. */
function isUnread(report: Report, seen: Record<number, number>): boolean {
  const last = report.messages[report.messages.length - 1];

  return (
    report.status !== ReportStatus.Closed &&
    last?.author === ReportAuthor.Player &&
    report.messages.length > (seen[report.id] ?? 0)
  );
}

export function ReportsTab() {
  const label = useLabel();
  const reports = useAdmin((state) => state.reports);
  const self = useAdmin((state) => state.self);
  const seen = useAdmin((state) => state.seen);
  const [filter, setFilter] = useState<Filter>(Filter.Queue);
  const [picked, setPicked] = useState<number | null>(null);
  const offDuty = useAdmin((state) => state.access.has(Action.Duty) && !state.modes.has(Action.Duty));

  const lists: Record<Filter, Report[]> = {
    [Filter.Queue]: reports.filter((report) => report.status !== ReportStatus.Closed),
    [Filter.Mine]: reports.filter((report) => report.status === ReportStatus.Claimed && report.claimer === self),
    [Filter.Closed]: reports.filter((report) => report.status === ReportStatus.Closed),
  };
  const shown = lists[filter];
  const current = shown.find((report) => report.id === picked) ?? shown[0] ?? null;

  if (reports.length === 0) {
    return (
      <div className="grid h-full place-items-center text-center">
        <div>
          <div className="mx-auto mb-4 grid size-16 place-items-center rounded-2xl bg-success/10 text-success ring-1 ring-success/25">
            <PartyPopper className="size-7" />
          </div>
          <p className="text-sm text-muted-foreground">{label("noReports")}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      {offDuty && (
        <div
          data-off-duty
          className="flex items-center gap-3 border-b border-white/5 bg-destructive/10 px-5 py-2.5 text-sm text-destructive"
        >
          <Headset className="size-4 shrink-0" />
          <span className="flex-1">{label("desk.offDuty")}</span>
          <button
            type="button"
            data-go-on-duty
            onClick={() => void sendRun(Action.Duty)}
            className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-semibold text-white shadow-ug-sm transition hover:brightness-110"
          >
            {label("desk.goOnDuty")}
          </button>
        </div>
      )}
      <div className="grid min-h-0 flex-1 grid-cols-[21rem_1fr]">
        <aside className="flex min-h-0 flex-col border-r border-white/5">
          <div className="flex gap-1 p-3">
            {FILTERS.map((entry) => (
              <button
                key={entry}
                type="button"
                data-desk-filter={entry}
                onClick={() => setFilter(entry)}
                className={cn(
                  "flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 text-xs font-medium transition-colors",
                  filter === entry
                    ? TONES[Tone.Amber].active
                    : "text-muted-foreground hover:bg-white/5 hover:text-foreground",
                )}
              >
                {label(`desk.${entry}`)}
                <span className="rounded-full bg-white/10 px-1.5 text-[10px]">{lists[entry].length}</span>
              </button>
            ))}
          </div>

          <ul className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-3 pb-3">
            {shown.length === 0 && (
              <li className="py-10 text-center text-sm text-muted-foreground">{label("desk.empty")}</li>
            )}
            <AnimatePresence initial={false}>
              {shown.map((report) => (
                <ReportCard
                  key={report.id}
                  report={report}
                  active={report.id === current?.id}
                  unread={report.id !== current?.id && isUnread(report, seen)}
                  onPick={() => setPicked(report.id)}
                />
              ))}
            </AnimatePresence>
          </ul>
        </aside>

        {current ? (
          <ReportChat key={current.id} report={current} offDuty={offDuty} />
        ) : (
          <div className="grid place-items-center text-sm text-muted-foreground">{label("desk.pick")}</div>
        )}
      </div>
    </div>
  );
}

function ReportCard({
  report,
  active,
  unread,
  onPick,
}: {
  report: Report;
  active: boolean;
  unread: boolean;
  onPick: () => void;
}) {
  const label = useLabel();
  const tone = TONES[CATEGORY_TONES[report.category]];
  const Icon = CATEGORY_ICONS[report.category];
  const last = [...report.messages].reverse().find((message) => message.author !== ReportAuthor.System);
  const waiting = report.status === ReportStatus.Open;

  return (
    <motion.li layout initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}>
      <button
        type="button"
        data-report={report.id}
        onClick={onPick}
        className={cn(
          "relative flex w-full flex-col gap-1.5 overflow-hidden rounded-xl border p-3 text-left transition-colors",
          active
            ? "border-primary/50 bg-primary/10"
            : "border-white/5 bg-background/40 hover:border-white/15 hover:bg-white/[0.04]",
        )}
      >
        <span
          className={cn(
            "absolute inset-y-0 left-0 w-1",
            waiting ? "bg-warning" : report.status === ReportStatus.Claimed ? "bg-primary" : "bg-white/10",
          )}
        />
        <div className="flex items-center gap-2">
          <span className={cn("grid size-7 shrink-0 place-items-center rounded-lg", tone.chip)}>
            <Icon className="size-3.5" />
          </span>
          <span className="min-w-0 flex-1 truncate text-sm font-semibold">{report.name}</span>
          {unread && (
            <span data-unread className="size-2 animate-pulse rounded-full bg-warning" title={label("desk.unread")} />
          )}
          <span className="font-mono text-[11px] text-muted-foreground">#{report.id}</span>
        </div>
        <p className="line-clamp-2 text-xs text-muted-foreground">{last?.text ?? report.message}</p>
        <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
          <Clock className="size-3" />
          {since(report.at)}
          {report.claimedBy && report.status === ReportStatus.Claimed && (
            <span className="ml-auto flex min-w-0 items-center gap-1 truncate text-primary">
              <UserCheck className="size-3 shrink-0" />
              {report.claimedBy}
            </span>
          )}
          {report.rating !== undefined && (
            <span className="ml-auto flex items-center gap-0.5 text-amber-300">
              <Star className="size-3 fill-current" />
              {report.rating}
            </span>
          )}
        </div>
      </button>
    </motion.li>
  );
}

function OpButton({
  icon: Icon,
  text,
  tone,
  onClick,
  op,
}: {
  icon: LucideIcon;
  text: string;
  tone: Tone;
  onClick: () => void;
  op: string;
}) {
  return (
    <button
      type="button"
      data-op={op}
      onClick={onClick}
      className={cn(
        "flex items-center gap-1.5 rounded-lg border border-white/10 bg-background/40 px-2.5 py-1.5 text-xs font-medium transition-colors",
        TONES[tone].hover,
      )}
    >
      <Icon className={cn("size-3.5", TONES[tone].text)} />
      {text}
    </button>
  );
}

function ReportChat({ report, offDuty }: { report: Report; offDuty: boolean }) {
  const label = useLabel();
  const self = useAdmin((state) => state.self);
  const access = useAdmin((state) => state.access);
  const markSeen = useAdmin((state) => state.markSeen);
  const players = useAdmin((state) => state.players);
  const [draft, setDraft] = useState("");
  const [closing, setClosing] = useState(false);
  const [assigning, setAssigning] = useState(false);
  const picks = useRef(new Map<string, number>());
  const composer = useRef<HTMLInputElement>(null);
  const settings = useAdmin((state) => state.settings);
  const replies = settings.replies
    ? settings.replies.map((text, index) => ({ key: `own-${index}`, text }))
    : QUICK_REPLIES.map((key) => ({ key, text: label(`quick.${key}`) }));

  const closed = report.status === ReportStatus.Closed;
  const online = report.source > 0;
  const mine = report.status === ReportStatus.Claimed && report.claimer === self;
  const away = report.visitors.includes(self);
  const tone = CATEGORY_TONES[report.category];
  const Icon = CATEGORY_ICONS[report.category];

  useEffect(() => {
    markSeen(report.id, report.messages.length);
  }, [report.id, report.messages.length, markSeen]);

  const send = (text: string) => {
    const trimmed = cut(toWire(text, picks.current).trim(), MAX_TEXT);

    if (trimmed === "") {
      return;
    }

    void runOp(report.id, closing ? ReportOp.Close : ReportOp.Reply, trimmed);
    setDraft("");
    setClosing(false);
    picks.current.clear();
  };

  const query = offDuty && !closing ? undefined : mentionQuery(draft);
  const candidates =
    query === undefined
      ? []
      : players.filter((player) => player.staff && player.id !== self && matchesPlayer(player, query)).slice(0, MENTIONS_SHOWN);

  const mention = (player: PlayerRow) => {
    setDraft((value) => value.replace(/@[^\s@]*$/, `@${player.name} `));
    picks.current.set(player.name, player.id);
  };

  /** Puts text where the caret is, and the caret after it. */
  const insert = (text: string) => {
    const result = insertAt(composer.current, draft, text, MAX_TEXT);

    if (result) {
      setDraft(result.value);
      placeCaret(composer.current, result.caret);
    }
  };

  const mentionFromBox = (player: PlayerRow) => {
    const start = composer.current?.selectionStart ?? draft.length;
    const before = draft.slice(0, start);

    picks.current.set(player.name, player.id);
    insert(`${before === "" || /\s$/.test(before) ? "" : " "}@${player.name} `);
  };

  const ops: { op: string; icon: LucideIcon; tone: Tone; show: boolean; run: () => void }[] = [
    {
      op: ReportOp.Claim,
      icon: Hand,
      tone: Tone.Violet,
      show: !mine && !offDuty,
      run: () => void runOp(report.id, ReportOp.Claim),
    },
    {
      op: ReportOp.Release,
      icon: LockOpen,
      tone: Tone.Indigo,
      show: mine,
      run: () => void runOp(report.id, ReportOp.Release),
    },
    {
      op: ReportOp.Goto,
      icon: Navigation,
      tone: Tone.Sky,
      show: online && !offDuty,
      run: () => void runOp(report.id, ReportOp.Goto),
    },
    {
      op: ReportOp.Return,
      icon: Undo2,
      tone: Tone.Blue,
      show: away,
      run: () => void runOp(report.id, ReportOp.Return),
    },
    {
      op: ReportOp.Bring,
      icon: Magnet,
      tone: Tone.Fuchsia,
      show: online && !offDuty,
      run: () => void runOp(report.id, ReportOp.Bring),
    },
    {
      op: ReportOp.SendBack,
      icon: Undo2,
      tone: Tone.Teal,
      show: online && report.brought,
      run: () => void runOp(report.id, ReportOp.SendBack),
    },
    {
      op: ReportOp.Assign,
      icon: UserPlus,
      tone: Tone.Amber,
      show: true,
      run: () => setAssigning((value) => !value),
    },
  ];

  const tools: { action: Action; icon: LucideIcon; tone: Tone; target: number }[] = [
    { action: Action.Spectate, icon: Eye, tone: Tone.Indigo, target: report.source },
    { action: Action.Heal, icon: HeartPulse, tone: Tone.Emerald, target: report.source },
  ];

  return (
    <section data-chat={report.id} className="flex min-h-0 flex-col">
      <header className="flex items-center gap-3 border-b border-white/5 px-5 py-3">
        <Avatar id={report.source || report.id} name={report.name} source={report.source || undefined} size="md" />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate text-base font-semibold">{report.name}</span>
            {online ? (
              <span className="font-mono text-xs text-muted-foreground">#{report.source}</span>
            ) : (
              <span className="rounded-full bg-destructive/15 px-2 py-0.5 text-[11px] text-destructive">
                {label("desk.left")}
              </span>
            )}
          </div>
          <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-xs">
            <span className={cn("flex items-center gap-1 rounded-full px-2 py-0.5", TONES[tone].chip)}>
              <Icon className="size-3" />
              {label(`category.${report.category}`)}
            </span>
            <StatusPill report={report} />
            {report.accusedName && (
              <span
                data-accused
                className="flex items-center gap-1 rounded-full bg-rose-500/10 px-2 py-0.5 text-rose-300"
              >
                {label("desk.accused")}: {report.accusedName}
                {report.accused ? <span className="font-mono">#{report.accused}</span> : null}
                {report.accused && access.has(Action.Spectate) ? (
                  <button
                    type="button"
                    data-spectate-accused
                    title={label(`action.${Action.Spectate}`)}
                    onClick={() => void sendRun(Action.Spectate, report.accused)}
                    className="ml-0.5 rounded p-0.5 hover:bg-rose-500/20"
                  >
                    <Eye className="size-3" />
                  </button>
                ) : null}
              </span>
            )}
          </div>
        </div>
        <span className="text-xs text-muted-foreground">#{report.id}</span>
      </header>

      {!closed && (
        <div className="flex flex-wrap items-center gap-1.5 border-b border-white/5 px-5 py-2.5">
          {ops
            .filter((entry) => entry.show)
            .map((entry) => (
              <OpButton
                key={entry.op}
                op={entry.op}
                icon={entry.icon}
                tone={entry.tone}
                text={label(`reportOp.${entry.op}`)}
                onClick={entry.run}
              />
            ))}
          {online &&
            tools
              .filter((tool) => access.has(tool.action))
              .map((tool) => (
                <OpButton
                  key={tool.action}
                  op={tool.action}
                  icon={tool.icon}
                  tone={tool.tone}
                  text={label(`action.${tool.action}`)}
                  onClick={() => void sendRun(tool.action, tool.target)}
                />
              ))}
          <button
            type="button"
            data-op={ReportOp.Close}
            onClick={() => setClosing((value) => !value)}
            className={cn(
              "ml-auto flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition-colors",
              closing ? "bg-success text-success-foreground" : "bg-success/15 text-success hover:bg-success/25",
            )}
          >
            <CheckCheck className="size-3.5" />
            {label(`reportOp.${ReportOp.Close}`)}
          </button>
        </div>
      )}

      <AnimatePresence initial={false}>
        {!closed && assigning && <AssignPicker report={report} onDone={() => setAssigning(false)} />}
      </AnimatePresence>

      <ReportThread messages={report.messages} mine={ReportAuthor.Staff} className="min-h-0 flex-1 px-5 py-4" />

      {closed ? (
        <footer className="flex items-center justify-center gap-2 border-t border-white/5 px-5 py-4 text-sm text-muted-foreground">
          {report.closedBy === undefined ? (
            label("desk.cancelled")
          ) : report.rating !== undefined ? (
            <span data-rating={report.rating} className="flex items-center gap-1 text-amber-300">
              {[1, 2, 3, 4, 5].map((star) => (
                <Star
                  key={star}
                  className={cn("size-4", star <= (report.rating ?? 0) ? "fill-current" : "opacity-30")}
                />
              ))}
              <span className="ml-1 text-muted-foreground">
                {fill(label("desk.rating"), { rating: report.rating })}
              </span>
            </span>
          ) : (
            label("desk.noRating")
          )}
        </footer>
      ) : (
        <footer className="flex flex-col gap-2 border-t border-white/5 px-5 py-3">
          {!closing && online && !offDuty && (
            <div className="flex flex-wrap gap-1.5">
              {replies.map((reply) => (
                <button
                  key={reply.key}
                  type="button"
                  data-quick={reply.key}
                  onClick={() => send(reply.text)}
                  className="max-w-full truncate rounded-full border border-white/10 bg-white/[0.03] px-2.5 py-1 text-[11px] text-muted-foreground transition-colors hover:border-violet-400/40 hover:text-foreground"
                >
                  {reply.text}
                </button>
              ))}
            </div>
          )}
          <form
            className="relative flex gap-2"
            onSubmit={(event) => {
              event.preventDefault();

              if (closing && draft.trim() === "") {
                void runOp(report.id, ReportOp.Close);
                setClosing(false);

                return;
              }

              send(draft);
            }}
          >
            {query !== undefined && candidates.length === 0 && (
              <p
                data-mentions-empty
                className="absolute bottom-full left-0 z-10 mb-2 rounded-xl border border-white/10 bg-card px-3 py-2 text-xs text-muted-foreground shadow-ug-sm"
              >
                {label("desk.noOtherStaff")}
              </p>
            )}
            {candidates.length > 0 && (
              <ul
                data-mentions
                className="absolute bottom-full left-0 z-10 mb-2 w-80 overflow-hidden rounded-xl border border-white/10 bg-card p-1 shadow-ug-sm"
              >
                {candidates.map((player) => (
                  <li key={player.id}>
                    <button
                      type="button"
                      data-mention={player.id}
                      onClick={() => mention(player)}
                      className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition-colors hover:bg-white/5"
                    >
                      <AtSign className="size-3.5 shrink-0 text-violet-300" />
                      <span className="truncate font-medium">{player.name}</span>
                      {player.character && (
                        <span className="truncate text-xs text-muted-foreground">{player.character}</span>
                      )}
                      {player.duty && <Headset className="ml-auto size-3.5 shrink-0 text-emerald-400" />}
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <ComposerTools
              disabled={offDuty && !closing}
              staff={players.filter((player) => player.staff && player.id !== self)}
              onMention={mentionFromBox}
              onEmoji={insert}
            />
            <Input
              ref={composer}
              data-composer
              disabled={offDuty && !closing}
              value={draft}
              maxLength={MAX_TEXT}
              placeholder={
                closing ? label("desk.closePlaceholder") : fill(label("desk.placeholder"), { name: report.name })
              }
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={(event) => {
                const first = candidates[0];

                if (event.key === "Tab" && first) {
                  event.preventDefault();
                  mention(first);
                }
              }}
              className={cn(closing && "border-success/50 focus:border-success/60 focus:ring-success/30")}
            />
            <SubmitButton closing={closing}>
              {closing ? label("desk.closeConfirm") : label(`reportOp.${ReportOp.Reply}`)}
            </SubmitButton>
          </form>
        </footer>
      )}
    </section>
  );
}

/** Staff who MAY take the report, searchable by player or character name. Only staff on duty MAY get it. */
function AssignPicker({ report, onDone }: { report: Report; onDone: () => void }) {
  const label = useLabel();
  const players = useAdmin((state) => state.players);
  const [search, setSearch] = useState("");

  const staff = players
    .filter((player) => player.staff && player.id !== report.claimer && matchesPlayer(player, search))
    .sort((a, b) => Number(b.duty) - Number(a.duty) || a.name.localeCompare(b.name));

  return (
    <motion.div
      data-assign
      initial={{ opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: "auto" }}
      exit={{ opacity: 0, height: 0 }}
      className="overflow-hidden border-b border-white/5 bg-background/40"
    >
      <div className="space-y-2 px-5 py-3">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            data-assign-search
            autoFocus
            value={search}
            maxLength={64}
            placeholder={label("desk.assignSearch")}
            className="pl-9"
            onChange={(event) => setSearch(event.target.value)}
          />
        </div>
        <ul className="flex max-h-48 flex-col gap-1 overflow-y-auto">
          {staff.length === 0 && (
            <li className="py-3 text-center text-xs text-muted-foreground">{label("desk.noStaff")}</li>
          )}
          {staff.map((player) => (
            <li key={player.id}>
              <button
                type="button"
                data-assign-to={player.id}
                disabled={!player.duty}
                onClick={() => {
                  void runOp(report.id, ReportOp.Assign, undefined, player.id);
                  onDone();
                }}
                className="flex w-full items-center gap-3 rounded-lg px-2.5 py-1.5 text-left transition-colors hover:bg-white/[0.05] disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent"
              >
                <Avatar id={player.id} name={player.name} source={player.id} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium">{player.name}</span>
                  <span className="block truncate text-xs text-muted-foreground">
                    {player.character ?? label("noCharacter")}
                  </span>
                </span>
                <span className="font-mono text-[11px] text-muted-foreground">#{player.id}</span>
                {player.duty ? (
                  <Headset className="size-3.5 shrink-0 text-emerald-400" />
                ) : (
                  <span className="text-[11px] text-muted-foreground">{label("desk.staffOffDuty")}</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </motion.div>
  );
}

const Tool = {
  Mention: "mention",
  Emoji: "emoji",
} as const;

type Tool = (typeof Tool)[keyof typeof Tool];

/** Buttons beside the chat input: pick staff to mention, or an emoji. Both insert at the caret. */
function ComposerTools({
  disabled,
  staff,
  onMention,
  onEmoji,
}: {
  disabled: boolean;
  staff: PlayerRow[];
  onMention: (player: PlayerRow) => void;
  onEmoji: (emoji: string) => void;
}) {
  const label = useLabel();
  const [open, setOpen] = useState<Tool | null>(null);
  const [search, setSearch] = useState("");
  const box = useRef<HTMLDivElement>(null);
  const found = staff
    .filter((player) => matchesPlayer(player, search))
    .sort((a, b) => Number(b.duty) - Number(a.duty) || a.name.localeCompare(b.name));

  const toggle = (tool: Tool) => {
    setOpen((current) => (current === tool ? null : tool));
    setSearch("");
  };

  const buttons: { tool: Tool; icon: LucideIcon; title: string }[] = [
    { tool: Tool.Mention, icon: AtSign, title: label("desk.mention") },
    { tool: Tool.Emoji, icon: Smile, title: label("desk.emoji") },
  ];

  useDismiss(box, open !== null, () => setOpen(null));

  return (
    <div ref={box} className="flex shrink-0 gap-1">
      {buttons.map(({ tool, icon: Icon, title }) => (
        <button
          key={tool}
          type="button"
          data-tool={tool}
          title={title}
          aria-label={title}
          aria-expanded={open === tool}
          disabled={disabled}
          onClick={() => toggle(tool)}
          className={cn(
            "grid size-10 place-items-center rounded-lg border transition-colors disabled:opacity-40",
            open === tool
              ? "border-violet-400/50 bg-violet-500/15 text-violet-200"
              : "border-white/10 bg-background/70 text-muted-foreground hover:border-white/20 hover:text-foreground",
          )}
        >
          <Icon className="size-4" />
        </button>
      ))}

      <AnimatePresence>
        {open !== null && !disabled && (
          <motion.div
            key={open}
            data-tool-panel={open}
            initial={{ opacity: 0, y: 6, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 6, scale: 0.98 }}
            transition={{ duration: 0.12 }}
            className="absolute bottom-full left-0 z-20 mb-2 w-80 rounded-xl border border-white/10 bg-card p-2 shadow-ug-lg"
          >
            {open === Tool.Mention ? (
              <>
                <Input
                  autoFocus
                  data-tool-search
                  value={search}
                  maxLength={64}
                  placeholder={label("desk.mentionSearch")}
                  className="mb-2 h-9"
                  onChange={(event) => setSearch(event.target.value)}
                />
                <ul className="flex max-h-56 flex-col gap-0.5 overflow-y-auto">
                  {found.length === 0 && (
                    <li className="px-2 py-3 text-center text-xs text-muted-foreground">{label("desk.noOtherStaff")}</li>
                  )}
                  {found.map((player) => (
                    <li key={player.id}>
                      <button
                        type="button"
                        data-pick-staff={player.id}
                        onClick={() => {
                          onMention(player);
                          setOpen(null);
                        }}
                        className="flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left transition-colors hover:bg-white/5"
                      >
                        <Avatar id={player.id} name={player.name} source={player.id} />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-sm font-medium">{player.name}</span>
                          {player.character && (
                            <span className="block truncate text-xs text-muted-foreground">{player.character}</span>
                          )}
                        </span>
                        {player.duty && <Headset className="size-3.5 shrink-0 text-emerald-400" />}
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            ) : (
              <EmojiGrid onPick={onEmoji} />
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function SubmitButton({ closing, children }: { closing: boolean; children: ReactNode }) {
  return (
    <button
      type="submit"
      data-submit
      className={cn(
        "flex h-10 shrink-0 items-center gap-2 rounded-lg px-4 text-sm font-semibold text-white shadow-ug-sm transition hover:brightness-110",
        closing ? "bg-success" : "bg-gradient-to-r from-violet-500 to-indigo-500",
      )}
    >
      {closing ? <CheckCheck className="size-4" /> : <Send className="size-4" />}
      {children}
    </button>
  );
}

function StatusPill({ report }: { report: Report }) {
  const label = useLabel();
  const styles: Record<ReportStatus, string> = {
    [ReportStatus.Open]: "bg-warning/15 text-warning",
    [ReportStatus.Claimed]: "bg-primary/15 text-primary",
    [ReportStatus.Closed]: "bg-white/10 text-muted-foreground",
  };
  const text =
    report.status === ReportStatus.Open
      ? fill(label("desk.waiting"), { time: since(report.at) })
      : report.status === ReportStatus.Claimed
        ? fill(label("desk.handling"), { name: report.claimedBy ?? "?" })
        : label(`reportStatus.${report.status}`);

  return (
    <span
      data-status={report.status}
      className={cn("flex items-center gap-1 rounded-full px-2 py-0.5", styles[report.status])}
    >
      {report.status === ReportStatus.Open && <span className="size-1.5 animate-pulse rounded-full bg-warning" />}
      {text}
    </span>
  );
}
