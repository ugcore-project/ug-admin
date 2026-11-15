/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The owner's ug-lib theme, applied to this page too, so every UgCore screen looks the same. Same rules as ug-lib.

import type { ThemeConfig } from "@/types/protocol";

/** Theme tokens owners MAY override, mapped to their CSS variable. */
const THEME_TOKENS: Record<string, string> = {
  background: "--ug-background",
  foreground: "--ug-foreground",
  card: "--ug-card",
  cardForeground: "--ug-card-foreground",
  popover: "--ug-popover",
  popoverForeground: "--ug-popover-foreground",
  primary: "--ug-primary",
  primaryForeground: "--ug-primary-foreground",
  secondary: "--ug-secondary",
  secondaryForeground: "--ug-secondary-foreground",
  muted: "--ug-muted",
  mutedForeground: "--ug-muted-foreground",
  accent: "--ug-accent",
  accentForeground: "--ug-accent-foreground",
  destructive: "--ug-destructive",
  destructiveForeground: "--ug-destructive-foreground",
  success: "--ug-success",
  successForeground: "--ug-success-foreground",
  warning: "--ug-warning",
  warningForeground: "--ug-warning-foreground",
  border: "--ug-border",
  input: "--ug-input",
  ring: "--ug-ring",
};

const HSL_TRIPLET = /^\d+(\.\d+)? \d+(\.\d+)?% \d+(\.\d+)?%$/;

/** Section tones owners MAY recolor. The value is the 500 shade; the others are derived by lightness. */
export const TONE_TOKENS = ["violet", "indigo", "blue", "sky", "teal", "emerald", "amber", "rose", "fuchsia"] as const;
const SHADE_LIGHTNESS: Record<number, (lightness: number) => number> = {
  200: (lightness) => Math.min(lightness + 30, 94),
  300: (lightness) => Math.min(lightness + 18, 88),
  400: (lightness) => Math.min(lightness + 8, 80),
  500: (lightness) => lightness,
  950: () => 12,
};

/** The shades of a tone from its 500 shade, as HSL triplets. */
export function toneShades(base: string): Record<number, string> {
  const [hue, saturation, lightness] = base.split(" ").map((part) => Number.parseFloat(part));
  const shades: Record<number, string> = {};

  for (const [shade, lighten] of Object.entries(SHADE_LIGHTNESS)) {
    shades[Number(shade)] = `${hue} ${saturation}% ${Math.round(lighten(lightness ?? 50) * 10) / 10}%`;
  }

  return shades;
}
const SIZE = /^\d*\.?\d+(rem|px)$/;
const FONTS: Record<string, string> = {
  Inter: '"Inter Variable", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
};

/** Applies theme values to `<html>`. Lua checked them; they are checked again before reaching CSS. */
export function applyTheme(theme: ThemeConfig | undefined): void {
  const root = document.documentElement;

  root.classList.toggle("dark", theme?.mode !== "light");

  for (const [token, cssVar] of Object.entries(THEME_TOKENS)) {
    const value = theme?.colors?.[token];

    if (typeof value === "string" && HSL_TRIPLET.test(value)) {
      root.style.setProperty(cssVar, value);
    } else {
      root.style.removeProperty(cssVar);
    }
  }

  for (const tone of TONE_TOKENS) {
    const value = theme?.colors?.[tone];
    const valid = typeof value === "string" && HSL_TRIPLET.test(value);
    const shades = valid ? toneShades(value) : {};

    for (const shade of Object.keys(SHADE_LIGHTNESS)) {
      const cssVar = `--ug-tone-${tone}-${shade}`;
      const color = shades[Number(shade)];

      if (color) {
        root.style.setProperty(cssVar, color);
      } else {
        root.style.removeProperty(cssVar);
      }
    }
  }

  if (theme && SIZE.test(theme.radius)) {
    root.style.setProperty("--ug-radius", theme.radius);
  }

  const font = theme ? FONTS[theme.font] : undefined;

  if (font) {
    root.style.setProperty("--ug-font-sans", font);
  }

  const scale = theme && Number.isFinite(theme.scale) ? Math.min(Math.max(theme.scale, 0.75), 1.5) : 1;

  root.style.setProperty("--ug-scale", String(scale));
}
