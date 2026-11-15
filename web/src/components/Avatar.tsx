/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useState } from "react";
import { cn } from "@/lib/cn";
import { useAdmin } from "@/store/adminStore";

/** Up to two initials from a name. */
function initials(name: string): string {
  const words = name.trim().split(/\s+/).filter((word) => word !== "");
  const letters = words.length > 1 ? `${words[0]?.[0] ?? ""}${words[1]?.[0] ?? ""}` : (words[0]?.slice(0, 2) ?? "");

  return letters.toUpperCase() || "?";
}

const SIZES = {
  sm: "size-9 text-xs",
  md: "size-11 text-sm",
  lg: "size-16 text-xl",
} as const;

/**
 * A colored badge with initials. The color comes from the id, so a player keeps it between sessions of the panel.
 * With a `source` the game can see, the character's face covers it.
 */
export function Avatar({
  id,
  name,
  source,
  size = "sm",
  className,
}: {
  id: number;
  name: string;
  source?: number | undefined;
  size?: keyof typeof SIZES;
  className?: string;
}) {
  const hue = (id * 47) % 360;
  const face = useAdmin((state) => (source === undefined ? undefined : state.faces[source]?.url));
  const [broken, setBroken] = useState<string | null>(null);

  return (
    <span
      aria-hidden
      className={cn("relative grid shrink-0 place-items-center overflow-hidden rounded-xl font-semibold text-white shadow-ug-sm", SIZES[size], className)}
      style={{ backgroundImage: `linear-gradient(135deg, hsl(${hue} 72% 58%), hsl(${(hue + 40) % 360} 70% 42%))` }}
    >
      {initials(name)}
      {face !== undefined && broken !== face && (
        <img
          src={face}
          alt=""
          data-face={source}
          draggable={false}
          onError={() => setBroken(face)}
          className="absolute inset-0 size-full bg-black/40 object-cover"
        />
      )}
    </span>
  );
}
