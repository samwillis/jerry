import { z } from "zod";
import { createHash } from "node:crypto";

export const uuid = z.uuid().transform((s) => s.toLowerCase());
export const recordSchema = z
  .object({
    version: z.literal(1),
    id: uuid,
    date: z.number().finite(),
    event: z.enum([
      "created",
      "entry",
      "textAppended",
      "textReplaced",
      "detailsAppended",
      "state",
      "titleChanged",
      "redacted",
    ]),
    expedition: z
      .object({
        id: uuid,
        date: z.number().finite(),
        title: z.string().max(200),
      })
      .optional(),
    entry: z
      .object({
        id: uuid,
        date: z.number().finite(),
        kind: z.enum(["request", "response", "activity"]),
        text: z.string().max(500_000),
        details: z.string().max(500_000),
        photo: z
          .string()
          .regex(/^[a-f0-9-]{36}\.jpg$/i)
          .optional(),
      })
      .optional(),
    entryID: uuid.optional(),
    text: z.string().max(500_000).optional(),
    status: z.string().max(1000).optional(),
    isRunning: z.boolean().optional(),
    isFinished: z.boolean().optional(),
  })
  .superRefine((r, c) => {
    const required = (ok: unknown) => {
      if (!ok) c.addIssue({ code: "custom", message: "Missing event payload" });
    };
    if (r.event === "created") required(r.expedition);
    if (r.event === "entry") required(r.entry);
    if (["textAppended", "textReplaced", "detailsAppended"].includes(r.event))
      required(r.entryID && r.text !== undefined);
    if (r.event === "titleChanged") required(r.text !== undefined);
  });
export type JournalRecord = z.infer<typeof recordSchema>;
export const detailChangeSchema = z.object({
  sequence: z.number().int().min(1).max(2_000_000_000),
  id: uuid,
  date: z.number().finite(),
  event: z.enum(["entry", "detailsAppended"]),
  entryID: uuid,
  text: z.string().min(1).max(500_000),
});
export type DetailChange = z.infer<typeof detailChangeSchema>;
export const batchSchema = z.object({
  start: z.number().int().min(1).max(2_000_000_000),
  records: z.array(recordSchema).min(1).max(100),
});
export const commandSchema = z
  .object({
    id: uuid,
    deviceID: uuid,
    expeditionID: uuid.optional(),
    kind: z.enum(["start", "continue", "stop", "finish"]),
    prompt: z.string().trim().max(20_000).default(""),
    ttlMinutes: z.number().int().min(1).max(1440).default(60),
  })
  .superRefine((x, c) => {
    if (["continue", "finish", "stop"].includes(x.kind) && !x.expeditionID)
      c.addIssue({ code: "custom", message: "Choose the target expedition" });
    if (["start", "continue"].includes(x.kind) && !x.prompt)
      c.addIssue({ code: "custom", message: "Enter a direction" });
  });
export function digest(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}
export class APIError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
