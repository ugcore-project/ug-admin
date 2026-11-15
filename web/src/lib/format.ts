/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

/** Fills `{name}` placeholders, like ug-lib's locale. Unknown placeholders stay as they are. */
export function fill(text: string, vars: Record<string, string | number>): string {
  return text.replace(/\{(\w+)\}/g, (match, name: string) => (name in vars ? String(vars[name]) : match));
}

/** Money in the player's locale, without decimals. */
export function money(amount: number, locale: string): string {
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(amount);
  } catch {
    return `$${Math.round(amount)}`;
  }
}

/** A wait such as `9:05` or `1:02:03`. */
export function duration(ms: number): string {
  const total = Math.ceil(Math.max(ms, 0) / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = String(total % 60).padStart(2, "0");

  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${seconds}` : `${minutes}:${seconds}`;
}

/** Time since a Unix timestamp in seconds, such as `45s`, `3m`, `2h` or `4d`. */
export function since(at: number, now = Date.now() / 1000): string {
  const seconds = Math.max(Math.floor(now - at), 0);

  if (seconds < 60) {
    return `${seconds}s`;
  }

  if (seconds < 3600) {
    return `${Math.floor(seconds / 60)}m`;
  }

  if (seconds < 86400) {
    return `${Math.floor(seconds / 3600)}h`;
  }

  return `${Math.floor(seconds / 86400)}d`;
}

/** Speed as a share of the configured range, on a log scale so slow speeds get room. */
export function speedShare(speed: number, min: number, max: number): number {
  if (max <= min) {
    return 1;
  }

  const share = min > 0 ? Math.log(speed / min) / Math.log(max / min) : (speed - min) / (max - min);

  return Math.max(0, Math.min(1, share));
}

/** A Guard score to one decimal. Scores decay continuously, so the raw value has a long tail of digits. */
export function score(value: number): number {
  return Math.round(value * 10) / 10;
}
