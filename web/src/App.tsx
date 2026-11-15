/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { MotionConfig } from "framer-motion";
import { lazy, Suspense, useEffect } from "react";
import { NoclipHud } from "@/components/NoclipHud";
import { Panel } from "@/components/Panel";
import { ReportWindow } from "@/components/ReportWindow";
import { isEnvBrowser, sendReady } from "@/lib/nui";
import { installMessages, useAdmin } from "@/store/adminStore";

// Dev and showcase builds only: removed from production builds.
const Preview = import.meta.env.DEV || import.meta.env.MODE === "showcase" ? lazy(() => import("@/dev/Preview")) : null;

export default function App() {
  const layout = useAdmin((state) => state.config.layout);

  useEffect(() => {
    const uninstall = installMessages();

    // Lua queues messages until the page says it listens.
    void sendReady();

    return uninstall;
  }, []);

  return (
    <MotionConfig reducedMotion={layout.animations ? "user" : "always"}>
      {layout.noclipHud && <NoclipHud />}
      <Panel />
      <ReportWindow />
      {Preview && isEnvBrowser() && (
        <Suspense fallback={null}>
          <Preview />
        </Suspense>
      )}
    </MotionConfig>
  );
}
