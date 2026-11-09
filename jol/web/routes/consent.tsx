import { createFileRoute } from "@tanstack/react-router";
import { App } from "../session.js";

export const Route = createFileRoute("/consent")({
  ssr: false,
  component: App,
});
