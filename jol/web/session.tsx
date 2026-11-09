import { createAuthClient, type VanillaBetterAuthClient } from "@neon/auth";
import { Button } from "@base-ui/react/button";
import { useEffect, useState, type FormEvent } from "react";
import { Brand, Journal } from "./journal.js";

type Config = { authURL: string; origin: string; realtimeURL: string | null };
type Auth = VanillaBetterAuthClient & {
  oauth2: {
    consent(x: { accept: boolean }): Promise<unknown>;
    continue(x: { selected: boolean }): Promise<unknown>;
    publicClient(x: { query: { client_id: string } }): Promise<{
      data?: { client_name?: string } | null;
      error?: { message?: string } | null;
    }>;
  };
};
export type JournalAPI = {
  read<T>(path: string, body?: unknown): Promise<T>;
  photo(path: string, signal: AbortSignal): Promise<Blob>;
  signOut(): Promise<void>;
};
type Screen =
  | { kind: "login" | "consent"; auth: Auth; config: Config }
  | { kind: "journal"; config: Config; api: JournalAPI }
  | { kind: "error"; message: string };

const message = (error: unknown) =>
  error instanceof Error ? error.message : "Could not connect to JOL.";
function checkAuth(result: unknown) {
  if (result && typeof result === "object" && "error" in result && result.error)
    throw new Error(
      "This sign-in link could not be completed. Return to Jerry and connect again.",
    );
}
function signedFlow() {
  const query = new URLSearchParams(location.search);
  return query.has("sig") && query.has("ba_param");
}

export function App() {
  const [screen, setScreen] = useState<Screen>();
  useEffect(() => {
    let current = true;
    let closed = false;
    const show = (value: Screen) => {
      if (current) setScreen(value);
    };
    const expire = (text: string) => {
      closed = true;
      show({ kind: "error", message: text });
      return new Error(text);
    };
    async function boot() {
      const response = await fetch("/public-config");
      if (!response.ok) throw new Error("Could not open Jerry On Line.");
      const config: Config = await response.json();
      const auth = createAuthClient(config.authURL) as Auth;
      const session = await auth.getSession();
      if (!current) return;
      if (session.error) throw new Error("JOL could not check your session.");
      if (!session.data?.user) return show({ kind: "login", config, auth });
      if (location.pathname === "/consent")
        return show({ kind: "consent", config, auth });
      if (signedFlow()) {
        checkAuth(await auth.oauth2.continue({ selected: true }));
        return;
      }

      const identity = config.authURL + "|" + session.data.user.id;
      async function authorized(path: string, init?: RequestInit) {
        if (closed || !current) throw new Error("Session closed");
        // The SDK puts the JWT on the session, including its warm cache.
        const { data, error } = await auth.getSession();
        if (closed || !current) throw new Error("Session closed");
        if (error) throw new Error("Could not check your session. Try again.");
        if (
          !data?.session?.token ||
          config.authURL + "|" + data.user.id !== identity
        ) {
          throw expire("Your session changed. Reconnect to open your journal.");
        }
        const headers = new Headers(init?.headers);
        headers.set("Authorization", "Bearer " + data.session.token);
        headers.set("X-JOL-Expected-User", identity);
        const result = await fetch("/api" + path, { ...init, headers });
        if (result.status === 401)
          throw expire(
            "JOL could not verify your session. Try connecting again.",
          );
        if (result.status === 409) {
          const conflict = await result.clone().json();
          if (conflict.error === "Account changed; reload JOL")
            throw expire(
              "Your account changed. Reconnect to open its journal.",
            );
        }
        return result;
      }
      const api: JournalAPI = {
        async read<T>(path: string, body?: unknown) {
          const result = await authorized(
            path,
            body === undefined
              ? undefined
              : {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify(body),
                },
          );
          const value = await result.json();
          if (!result.ok)
            throw new Error(value.error ?? "Could not reach JOL.");
          return value as T;
        },
        async photo(path, signal) {
          const result = await authorized(path, { signal });
          if (!result.ok) throw new Error("Could not open the photograph.");
          return result.blob();
        },
        async signOut() {
          const result = await auth.signOut();
          if (result.error) throw new Error("Could not sign out. Try again.");
          closed = true;
          location.assign("/");
        },
      };
      await api.read("/me");
      show({ kind: "journal", config, api });
    }
    void boot().catch((error) =>
      show({ kind: "error", message: message(error) }),
    );
    return () => {
      current = false;
      closed = true;
    };
  }, []);

  if (!screen)
    return <p className="connecting">Connecting to Jerry On Line…</p>;
  if (screen.kind === "error")
    return (
      <section className="connecting">
        <p role="alert">{screen.message}</p>
        <Button onClick={() => location.reload()}>Try again</Button>
      </section>
    );
  if (screen.kind === "journal")
    return <Journal api={screen.api} realtimeURL={screen.config.realtimeURL} />;
  return (
    <Login
      auth={screen.auth}
      config={screen.config}
      consent={screen.kind === "consent"}
    />
  );
}

function Login({
  auth,
  config,
  consent,
}: {
  auth: Auth;
  config: Config;
  consent: boolean;
}) {
  const [signup, setSignup] = useState(false);
  const [clientName, setClientName] = useState("");
  const [issue, setIssue] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!consent) return;
    let current = true;
    const client_id =
      new URLSearchParams(location.search).get("client_id") ?? "";
    void auth.oauth2
      .publicClient({ query: { client_id } })
      .then((result) => {
        if (!result.data?.client_name)
          throw new Error(
            "This authorization link is invalid or expired. Return to Jerry and connect again.",
          );
        if (current) setClientName(result.data.client_name);
      })
      .catch((error) => {
        if (current) setIssue(message(error));
      });
    return () => {
      current = false;
    };
  }, [auth, consent]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setIssue("");
    const form = new FormData(event.currentTarget);
    try {
      if (consent) {
        checkAuth(await auth.oauth2.consent({ accept: true }));
        return;
      }
      const values = {
        email: String(form.get("email")),
        password: String(form.get("password")),
      };
      const result = signup
        ? await auth.signUp.email({
            ...values,
            name: String(form.get("name") || "Explorer"),
          })
        : await auth.signIn.email(values);
      if (result.error)
        throw new Error(result.error.message || "Sign-in failed.");
      if (result.data && "redirect" in result.data && result.data.redirect)
        return;
      if (signedFlow())
        checkAuth(await auth.oauth2.continue({ selected: true }));
      else location.assign("/");
    } catch (error) {
      setIssue(message(error));
    } finally {
      setBusy(false);
    }
  }

  async function google() {
    try {
      const result = await auth.signIn.social({
        provider: "google",
        callbackURL:
          config.origin + (signedFlow() ? "/login" + location.search : "/"),
      });
      if (result.error)
        throw new Error(result.error.message || "Google sign-in failed.");
    } catch (error) {
      setIssue(message(error));
    }
  }

  return (
    <main className="shell">
      <header className="masthead">
        <Brand />
      </header>
      <section className="notebook login">
        <div className="small">{new URL(config.origin).host}</div>
        <h1>
          {consent
            ? clientName
              ? `Connect ${clientName}?`
              : "Let Jerry connect?"
            : "Your explorer. On line."}
        </h1>
        <p>
          {consent
            ? "Jerry can sync the journals you choose and receive directions when you enable remote missions on your Mac."
            : "Sign in to read Jerry’s field notes and send him his next expedition."}
        </p>
        {!consent && (
          <Button className="primary" onClick={() => void google()}>
            Continue with Google
          </Button>
        )}
        <form onSubmit={submit}>
          {!consent && (
            <>
              <label>
                Email
                <input
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                />
              </label>
              <label>
                Password
                <input
                  name="password"
                  type="password"
                  autoComplete={signup ? "new-password" : "current-password"}
                  minLength={8}
                  required
                />
              </label>
              {signup && (
                <label>
                  Your name
                  <input name="name" autoComplete="name" />
                </label>
              )}
            </>
          )}
          {issue && (
            <p className="error" role="alert">
              {issue}
            </p>
          )}
          <div className="actions">
            <Button
              className="primary"
              type="submit"
              disabled={busy || (consent && !clientName)}
            >
              {consent
                ? "Connect Jerry"
                : signup
                  ? "Create account"
                  : "Sign in"}
            </Button>
            <Button
              onClick={() => {
                if (!consent) setSignup(!signup);
                else
                  void auth.oauth2
                    .consent({ accept: false })
                    .then(checkAuth)
                    .catch((error) => setIssue(message(error)));
              }}
            >
              {consent
                ? "Decline"
                : signup
                  ? "Already have an account?"
                  : "Create account"}
            </Button>
          </div>
        </form>
        <p className="small">
          {consent
            ? "Only connect an app you opened yourself. You can disconnect in Jerry’s Settings."
            : "Your account belongs to this JOL server."}
        </p>
      </section>
    </main>
  );
}
