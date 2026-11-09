import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { generateKeyPair, exportJWK, SignJWT } from "jose";
import { authentication } from "../src/auth.js";
import type { Config } from "../src/config.js";
const { publicKey, privateKey } = await generateKeyPair("EdDSA");
let server: Server, auth: ReturnType<typeof authentication>;
const issuer = "https://branch.neonauth.example/neondb/auth",
  resource = "https://jol.example/api";
before(async () => {
  const jwk = await exportJWK(publicKey);
  jwk.kid = "test";
  server = createServer((_req, res) => {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ keys: [jwk] }));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as { port: number };
  auth = authentication({
    origin: "https://jol.example",
    authURL: issuer,
    jwksURL: `http://127.0.0.1:${address.port}/jwks`,
  } as Config);
});
after(() => new Promise<void>((resolve) => server.close(() => resolve())));
async function token(
  iss = issuer,
  aud: string | string[] = resource,
  expiration = "1h",
) {
  return new SignJWT({})
    .setProtectedHeader({ alg: "EdDSA", kid: "test" })
    .setSubject("alice")
    .setIssuer(iss)
    .setAudience(aud)
    .setIssuedAt()
    .setExpirationTime(expiration)
    .sign(privateKey);
}
const request = (bearer: string) =>
  new Request(resource, { headers: { Authorization: `Bearer ${bearer}` } });
test("native OAuth verifies exact branch issuer, resource and audience arrays", async () => {
  assert.equal((await auth(request(await token()))).id, issuer + "|alice");
  assert.equal(
    (
      await auth(
        request(await token(issuer, [resource, issuer + "/oauth2/userinfo"])),
      )
    ).id,
    issuer + "|alice",
  );
});
test("a token from a sibling branch with the same signing key is rejected", async () => {
  await assert.rejects(
    auth(request(await token("https://sibling.neonauth.example/neondb/auth"))),
  );
});
test("valid signatures do not allow wrong audiences or expired access", async () => {
  await assert.rejects(
    auth(request(await token(issuer, "https://another.example/api"))),
  );
  await assert.rejects(auth(request(await token(issuer, resource, "-1h"))));
});
test("missing and forged bearer tokens fail before protected work", async () => {
  await assert.rejects(auth(new Request(resource)));
  await assert.rejects(auth(request("not.a.token")));
});
