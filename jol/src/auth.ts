import { createRemoteJWKSet, decodeJwt, jwtVerify } from "jose";
import { APIError } from "./protocol.js";
import type { Config } from "./config.js";
export type Identity = { id: string; expires: number };
export type Authenticate = (request: Request) => Promise<Identity>;
export function authentication(config: Config): Authenticate {
  const jwks = createRemoteJWKSet(new URL(config.jwksURL));
  return async (request) => {
    const header = request.headers.get("authorization");
    if (!header?.startsWith("Bearer "))
      throw new APIError(401, "Sign in to this JOL server");
    try {
      const token = header.slice(7),
        hint = decodeJwt(token);
      // Session JWTs and OAuth resource tokens have distinct configured issuers.
      // Unverified claims only select between these two fixed verification policies.
      const oauth = hint.iss === config.authURL;
      const { payload } = await jwtVerify(token, jwks, {
        algorithms: ["EdDSA"],
        issuer: oauth ? config.authURL : new URL(config.authURL).origin,
        ...(oauth ? { audience: `${config.origin}/api` } : {}),
        requiredClaims: ["sub", "exp", "iat"],
      });
      if (!payload.sub || !payload.exp) throw new Error("Missing claims");
      return {
        id: `${config.authURL}|${payload.sub}`,
        expires: payload.exp * 1000,
      };
    } catch {
      throw new APIError(
        401,
        "Your JOL sign-in has expired. Reconnect to continue.",
      );
    }
  };
}
