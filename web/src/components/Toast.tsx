/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { CircleAlert, CircleCheck } from "lucide-react";
import { cn } from "@/lib/cn";
import { useAdmin, useLabel } from "@/store/adminStore";
import { Action } from "@/types/protocol";

/** The answer to the last action run from the panel. */
export function Toast() {
  const label = useLabel();
  // The report desk shows its own changes: only its refusals need a toast.
  const toast = useAdmin((state) => (state.toast?.action === Action.Reports && state.toast.ok ? null : state.toast));
  const layout = useAdmin((state) => state.config.layout);
  const top = layout.toasts === "top";

  useEffect(() => {
    if (!toast) {
      return;
    }

    const timer = setTimeout(() => useAdmin.setState({ toast: null }), layout.toastDuration);

    return () => clearTimeout(timer);
  }, [toast, layout.toastDuration]);

  return (
    <AnimatePresence>
      {toast && (
        <motion.div
          key={toast.key}
          role="status"
          data-place={layout.toasts}
          initial={{ opacity: 0, y: top ? -16 : 16, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: top ? -8 : 8 }}
          className={cn(
            top ? "top-4" : "bottom-4",
            "absolute left-1/2 flex -translate-x-1/2 items-center gap-2 rounded-full border px-4 py-2 text-sm shadow-ug-lg",
            toast.ok ? "border-success/50 bg-card text-foreground" : "border-destructive/60 bg-card text-foreground",
          )}
        >
          {toast.ok ? <CircleCheck className="size-4 text-success" /> : <CircleAlert className="size-4 text-destructive" />}
          <span className="font-medium">{label(`action.${toast.action}`)}</span>
          {!toast.ok && <span className="text-muted-foreground">{label(`error.${toast.error ?? "internal_error"}`)}</span>}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
