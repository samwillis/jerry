import { build } from "esbuild";
import { mkdir } from "node:fs/promises";
import { loadWebAssets } from "./web-assets.js";

const assets = Object.fromEntries(
  Object.entries(await loadWebAssets("dist/web/client")).map(
    ([path, { body, type }]) => [
      path,
      { base64: Buffer.from(body).toString("base64"), type },
    ],
  ),
);
await mkdir("dist", { recursive: true });
for (const entry of ["index", "local"])
  await build({
    entryPoints: [`src/${entry}.ts`],
    outfile: `dist/${entry}.mjs`,
    bundle: true,
    minify: true,
    platform: "node",
    target: "node24",
    format: "esm",
    banner: {
      js: "import {createRequire as __jolCreateRequire} from 'node:module';const require=__jolCreateRequire(import.meta.url);",
    },
    define: { __JOL_ASSETS__: JSON.stringify(assets) },
  });
console.log("Built JOL API and bundled web journal");
