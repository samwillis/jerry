import { readdir, readFile } from "node:fs/promises";
import { extname } from "node:path";

const mime: Record<string, string> = {
  ".js": "text/javascript",
  ".css": "text/css",
};

export async function loadWebAssets(output: string) {
  const assets: Record<string, { body: Uint8Array; type: string }> = {};
  const shell = await readFile(output + "/_shell.html");
  for (const route of ["/", "/login", "/consent"]) {
    assets[route] = { body: shell, type: "text/html; charset=utf-8" };
  }
  for (const file of await readdir(output + "/assets")) {
    const type = mime[extname(file)];
    if (!type) throw new Error("Unexpected web asset: " + file);
    assets["/assets/" + file] = {
      body: await readFile(output + "/assets/" + file),
      type,
    };
  }
  for (const [, path] of shell
    .toString()
    .matchAll(/(?:src|href)="(\/assets\/[^"]+)"/g)) {
    if (!assets[path])
      throw new Error("Start shell references a missing asset: " + path);
  }
  assets["/jol-logo.svg"] = {
    body: await readFile("web/jol-logo.svg"),
    type: "image/svg+xml",
  };
  assets["/Caveat.ttf"] = {
    body: await readFile("../Jerry/Resources/Caveat.ttf"),
    type: "font/ttf",
  };
  assets["/Caveat-OFL.txt"] = {
    body: await readFile("../Jerry/Resources/Caveat-OFL.txt"),
    type: "text/plain",
  };
  return assets;
}
