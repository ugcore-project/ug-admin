/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Headset, Inbox, RefreshCw, ScrollText, Settings, Users, X } from "lucide-react";
import { Logo } from "@/components/Logo";
import { LogsTab } from "@/components/LogsTab";
import { PlayersTab } from "@/components/PlayersTab";
import { QuickBar } from "@/components/QuickBar";
import { ReportsTab } from "@/components/ReportsTab";
import { SettingsTab } from "@/components/SettingsTab";
import { Toast } from "@/components/Toast";
import { cn } from "@/lib/cn";
import { fill } from "@/lib/format";
import { sendClose, sendRefresh } from "@/lib/nui";
import { BRAND_TEXT, Tone, TONES } from "@/lib/tones";
import { Tab, useAdmin, useLabel, visibleTabs } from "@/store/adminStore";
import { Action, ReportStatus } from "@/types/protocol";

// The list refreshes on its own while the panel is open, every layout.refreshInterval ms. The server allows 4
// snapshots per 4 s.
const SPRING = { type: "spring", stiffness: 380, damping: 32 } as const;

export function Panel() {
  const label = useLabel();
  const open = useAdmin((state) => state.open);
  const tab = useAdmin((state) => state.tab);
  const setTab = useAdmin((state) => state.setTab);
  const players = useAdmin((state) => state.players);
  const access = useAdmin((state) => state.access);
  const layout = useAdmin((state) => state.config.layout);
  const ownerTabs = useAdmin((state) => state.config.tabs);
  const pending = useAdmin((state) => state.reports.filter((report) => report.status === ReportStatus.Open).length);
  const onDuty = players.filter((player) => player.duty).length;
  const [spin, setSpin] = useState(0);

  const close = () => {
    useAdmin.setState({ open: false });
    void sendClose();
  };

  const refresh = () => {
    setSpin((turns) => turns + 1);
    void sendRefresh();
  };

  useEffect(() => {
    if (!open) {
      return;
    }

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        close();
      }
    };
    const timer = setInterval(() => void sendRefresh(), layout.refreshInterval);

    window.addEventListener("keydown", onKey);

    return () => {
      window.removeEventListener("keydown", onKey);
      clearInterval(timer);
    };
  }, [open, layout.refreshInterval]);

  const entries = {
    [Tab.Players]: { id: Tab.Players, icon: Users, text: label("players"), badge: 0, tone: Tone.Violet },
    [Tab.Reports]: { id: Tab.Reports, icon: Inbox, text: label("reports"), badge: pending, tone: Tone.Amber },
    [Tab.Logs]: { id: Tab.Logs, icon: ScrollText, text: label("logs"), badge: 0, tone: Tone.Sky },
    [Tab.Settings]: { id: Tab.Settings, icon: Settings, text: label("settings"), badge: 0, tone: Tone.Indigo },
  };
  const tabs = visibleTabs(ownerTabs as Tab[], access).map((id) => entries[id]);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          key="panel"
          data-panel
          className="fixed inset-0 grid place-items-center"
          style={{ backgroundColor: `rgb(0 0 0 / ${layout.backdrop})` }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.94, y: 24 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.97, y: 10 }}
            transition={SPRING}
            className="relative"
          >
            <div
              data-panel-window
              data-rail={layout.rail}
              className={cn(
                "relative flex overflow-hidden rounded-2xl border border-white/10 bg-card text-card-foreground shadow-ug-lg",
                layout.rail === "right" && "flex-row-reverse",
              )}
              style={{ width: `min(${layout.width}rem, 96vw)`, height: `min(${layout.height}rem, 94vh)` }}
            >
              {/* Ambient light. A blur over the page's own layers, never over the game. */}
              {layout.glow && (
                <>
                  <div data-glow className="pointer-events-none absolute -left-40 -top-40 size-[28rem] rounded-full bg-primary/20 blur-3xl" />
                  <div className="pointer-events-none absolute -bottom-48 right-0 size-[24rem] rounded-full bg-primary/10 blur-3xl" />
                </>
              )}

              <nav
                className={cn(
                  "relative z-10 flex w-[5.5rem] shrink-0 flex-col items-center gap-1 border-white/5 bg-background/40 py-5",
                  layout.rail === "right" ? "border-l" : "border-r",
                )}
              >
                {layout.logo && (
                  <>
                    <div data-logo className="mb-1 grid size-12 place-items-center rounded-2xl bg-white/[0.04] ring-1 ring-violet-400/25">
                      <Logo className="size-9" />
                    </div>
                    <span className={cn("mb-4 text-[10px] font-bold uppercase tracking-[0.18em]", BRAND_TEXT)}>
                      {label("title")}
                    </span>
                  </>
                )}

                {tabs.map(({ id, icon: Icon, text, badge, tone }) => (
                  <button
                    key={id}
                    type="button"
                    data-tab={id}
                    onClick={() => setTab(id)}
                    className={cn(
                      "relative flex w-[4.25rem] flex-col items-center gap-1 rounded-xl py-2.5 text-[11px] font-medium transition-colors",
                      tab === id ? TONES[tone].text : "text-muted-foreground hover:bg-white/5 hover:text-foreground",
                    )}
                  >
                    {tab === id && (
                      <motion.span
                        layoutId="rail"
                        transition={SPRING}
                        className={cn("absolute inset-0 rounded-xl border", TONES[tone].active)}
                      />
                    )}
                    <Icon className="relative size-5" />
                    <span className="relative max-w-full truncate px-1">{text}</span>
                    {badge > 0 && (
                      <span className="absolute right-1.5 top-1.5 grid min-w-[1.1rem] place-items-center rounded-full bg-warning px-1 text-[10px] font-bold leading-[1.1rem] text-warning-foreground shadow-ug-sm">
                        {badge}
                      </span>
                    )}
                  </button>
                ))}

                <div className="mt-auto flex flex-col gap-1">
                  <button
                    type="button"
                    title={label("refresh")}
                    onClick={refresh}
                    className="grid size-10 place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-white/5 hover:text-foreground"
                  >
                    <motion.span
                      animate={{ rotate: spin * 360 }}
                      transition={{ duration: 0.6, ease: "easeInOut" }}
                      className="grid"
                    >
                      <RefreshCw className="size-4" />
                    </motion.span>
                  </button>
                  <button
                    type="button"
                    title={label("close")}
                    onClick={close}
                    className="grid size-10 place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-destructive/20 hover:text-destructive"
                  >
                    <X className="size-4" />
                  </button>
                </div>
              </nav>

              <div className="relative z-10 flex min-w-0 flex-1 flex-col">
                <header className="flex items-end gap-4 px-6 pb-4 pt-5">
                  <div className="min-w-0">
                    <h1 className={cn("text-2xl font-semibold tracking-tight", BRAND_TEXT)}>
                      {tabs.find((entry) => entry.id === tab)?.text}
                    </h1>
                    <p className="text-sm text-muted-foreground">{label(`subtitle.${tab}`)}</p>
                  </div>
                  <div className="ml-auto flex items-center gap-2">
                    <span className="flex items-center gap-2 rounded-full border border-white/10 bg-background/50 px-3 py-1.5 text-xs font-medium">
                      <span className="relative flex size-2">
                        <span className="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60" />
                        <span className="relative inline-flex size-2 rounded-full bg-success" />
                      </span>
                      {fill(label("online"), { count: players.length })}
                    </span>
                    {access.has(Action.Reports) && (
                      <span
                        data-on-duty={onDuty}
                        className={cn(
                          "flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-medium",
                          onDuty > 0
                            ? "border-emerald-400/30 bg-emerald-500/10 text-emerald-300"
                            : "border-destructive/40 bg-destructive/10 text-destructive",
                        )}
                      >
                        <Headset className="size-3.5" />
                        {fill(label("onDuty"), { count: onDuty })}
                      </span>
                    )}
                    {access.has(Action.Reports) && (
                      <button
                        type="button"
                        onClick={() => setTab(Tab.Reports)}
                        className={cn(
                          "flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-medium transition-colors",
                          pending > 0
                            ? "border-warning/40 bg-warning/15 text-warning hover:bg-warning/25"
                            : "border-white/10 bg-background/50 text-muted-foreground",
                        )}
                      >
                        <Inbox className="size-3.5" />
                        {fill(label("pending"), { count: pending })}
                      </button>
                    )}
                  </div>
                </header>

                {layout.quickBar && <QuickBar />}

                <main className="relative min-h-0 flex-1 border-t border-white/5">
                  {/* Enter-only: the new tab shows at once instead of waiting for the old one to leave. */}
                  <motion.div
                    key={tab}
                    className="h-full"
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.18 }}
                  >
                    {tab === Tab.Players && <PlayersTab />}
                    {tab === Tab.Reports && <ReportsTab />}
                    {tab === Tab.Logs && <LogsTab />}
                    {tab === Tab.Settings && <SettingsTab />}
                  </motion.div>
                </main>
              </div>
            </div>
            <Toast />
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
