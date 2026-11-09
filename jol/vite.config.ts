import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import { fileURLToPath } from "node:url";

const fixture = process.env.JOL_PREVIEW_FIXTURE === "1";

export default defineConfig({
  publicDir: false,
  build: { outDir: fixture ? "dist/web-fixture" : "dist/web" },
  resolve: {
    alias: fixture
      ? [
          {
            find: "@neon/auth",
            replacement: fileURLToPath(
              new URL("./web/preview-auth.ts", import.meta.url),
            ),
          },
        ]
      : [],
  },
  plugins: [
    tanstackStart({ srcDirectory: "web", spa: { enabled: true } }),
    react(),
  ],
});
