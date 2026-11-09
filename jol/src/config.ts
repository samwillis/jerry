import { z } from "zod";
export type Config = {
  origin: string;
  instanceID: string;
  name: string;
  authURL: string;
  jwksURL: string;
  clientID: string;
  realtimeURL?: string;
  realtimeSecret?: string;
  databaseName: string;
  photoBucket?: string;
};
export function config(env = process.env): Config {
  const origin = z.url().parse(env.JOL_ORIGIN).replace(/\/$/, "");
  if (
    !origin.startsWith("https://") &&
    !(
      env.NODE_ENV !== "production" &&
      /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
    )
  )
    throw new Error("JOL_ORIGIN must use HTTPS");
  const authURL = z.url().parse(env.NEON_AUTH_BASE_URL).replace(/\/$/, "");
  if (!authURL.startsWith("https://"))
    throw new Error("Neon Auth must use HTTPS");
  return {
    origin,
    instanceID: z.uuid().parse(env.JOL_INSTANCE_ID),
    name: env.JOL_NAME || "Jerry On Line",
    authURL,
    jwksURL: env.NEON_AUTH_JWKS_URL || `${authURL}/.well-known/jwks.json`,
    clientID: z.string().min(1).parse(env.JOL_OAUTH_CLIENT_ID),
    realtimeURL: env.NEON_REALTIME_URL,
    realtimeSecret: env.NEON_REALTIME_SECRET,
    databaseName: env.DATABASE_URL
      ? new URL(env.DATABASE_URL).pathname.slice(1)
      : "neondb",
    photoBucket: env.JOL_PHOTO_BUCKET,
  };
}
