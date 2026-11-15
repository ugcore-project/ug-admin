/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useRef, type RefObject } from "react";

/** Calls `close` on a mouse press outside `box` while `open` is true. */
export function useDismiss(box: RefObject<HTMLElement | null>, open: boolean, close: () => void) {
  const latest = useRef(close);

  useEffect(() => {
    latest.current = close;
  });

  useEffect(() => {
    if (!open) {
      return;
    }

    const away = (event: MouseEvent) => {
      if (box.current && !box.current.contains(event.target as Node)) {
        latest.current();
      }
    };

    window.addEventListener("mousedown", away);

    return () => window.removeEventListener("mousedown", away);
  }, [box, open]);
}
