/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Chat text the server counts in characters, not UTF-16 units: an emoji is one character there, two here.

/** Characters as the server counts them. */
export function length(text: string): number {
  return Array.from(text).length;
}

/** Cuts at a number of characters, never inside an emoji: a lone surrogate would not pass the server. */
export function cut(text: string, max: number): string {
  return Array.from(text).slice(0, max).join("");
}

/**
 * Puts `text` where the caret of `field` is, replacing any selection. Returns the new value and where the caret
 * goes, or null when the result would pass `max` characters.
 */
export function insertAt(
  field: HTMLInputElement | HTMLTextAreaElement | null,
  value: string,
  text: string,
  max: number,
): { value: string; caret: number } | null {
  const start = field?.selectionStart ?? value.length;
  const end = field?.selectionEnd ?? value.length;
  const next = value.slice(0, start) + text + value.slice(end);

  return length(next) > max ? null : { value: next, caret: start + text.length };
}

/** Focuses a field and puts its caret at `caret`, once React has written the new value. */
export function placeCaret(field: HTMLInputElement | HTMLTextAreaElement | null, caret: number) {
  requestAnimationFrame(() => {
    field?.focus();
    field?.setSelectionRange(caret, caret);
  });
}
