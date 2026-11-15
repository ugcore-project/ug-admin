/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useState, type ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";
import { duration } from "@/lib/format";
import { Tone, TONES } from "@/lib/tones";

interface CardProps {
  icon: LucideIcon;
  title: string;
  className?: string | undefined;
  tone?: Tone;
  /** Shown at the right of the title. */
  extra?: ReactNode;
  children: ReactNode;
}

/** A titled section of the player details. */
export function Card({ icon: Icon, title, className, extra, tone = Tone.Indigo, children }: CardProps) {
  return (
    <section className={cn("rounded-xl border border-white/5 bg-white/[0.02] p-3", className)}>
      <h3 className="mb-2 flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
        <span className={cn("grid size-5 place-items-center rounded-md", TONES[tone].chip)}>
          <Icon className="size-3" />
        </span>
        {title}
        {extra !== undefined && <span className="ml-auto normal-case tracking-normal">{extra}</span>}
      </h3>
      {children}
    </section>
  );
}

/** Seconds left, ticking down from the value the server sent. */
export function Countdown({ seconds }: { seconds: number }) {
  const [since] = useState(() => Date.now());
  const [now, setNow] = useState(since);

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);

    return () => clearInterval(timer);
  }, []);

  return <span className="font-mono tabular-nums">{duration(seconds * 1000 - (now - since))}</span>;
}
