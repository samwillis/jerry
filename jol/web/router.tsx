import { createRouter } from "@tanstack/react-router";
import { routeTree } from "./routeTree.gen.js";

export function getRouter() {
  return createRouter({ routeTree, defaultPendingComponent: Pending });
}

function Pending() {
  return <p className="connecting">Connecting to Jerry On Line…</p>;
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof getRouter>;
  }
}
