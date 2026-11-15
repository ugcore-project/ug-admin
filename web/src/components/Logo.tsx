/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useId } from "react";
import { cn } from "@/lib/cn";

/** The ug-core mark: a cube inside a hexagon, violet to blue. */
export function Logo({ className }: { className?: string }) {
  const id = useId();
  const stroke = `${id}-stroke`;
  const face = `${id}-face`;

  return (
    <svg viewBox="0 0 64 64" aria-hidden className={cn("drop-shadow-[0_0_10px_rgb(139_92_246/0.55)]", className)}>
      <defs>
        <linearGradient id={stroke} x1="1" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c084fc" />
          <stop offset="0.5" stopColor="#818cf8" />
          <stop offset="1" stopColor="#60a5fa" />
        </linearGradient>
        <linearGradient id={face} x1="1" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#a855f7" />
          <stop offset="1" stopColor="#3b82f6" />
        </linearGradient>
      </defs>
      <path d="M32 5 55.4 18.5v27L32 59 8.6 45.5v-27Z" fill="none" stroke={`url(#${stroke})`} strokeWidth="5" strokeLinejoin="round" />
      <path d="M32 5v15M55.4 45.5 42 37.7M8.6 45.5 22 37.7" stroke={`url(#${stroke})`} strokeWidth="2.5" strokeLinecap="round" opacity="0.55" />
      <path d="M32 20 42 25.8v11.9L32 43.5l-10-5.8V25.8Z" fill={`url(#${face})`} />
      <path d="M32 20 42 25.8 32 31.6 22 25.8Z" fill="#fff" opacity="0.35" />
      <path d="M32 31.6 42 25.8v11.9L32 43.5Z" fill="#000" opacity="0.18" />
    </svg>
  );
}
