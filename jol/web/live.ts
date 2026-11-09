import { useEffect, useState } from "react";
import { createCollection, useLiveQuery } from "@tanstack/react-db";
import { realtimeCollectionOptions } from "@neon/realtime-tanstack";
import type { RealtimeClient, SealedLiveQuery } from "@neon/realtime/client";
import type { JournalAPI } from "./session.js";

export type LiveSpec = {
  kind: "devices" | "expeditions" | "expedition" | "entries" | "commands";
  deviceID?: string;
  expeditionID?: string;
};
function collectionFor<Row extends object>(
  client: RealtimeClient,
  query: SealedLiveQuery<Row>,
  renew: () => Promise<SealedLiveQuery<Row>>,
  key: (row: Row) => string,
) {
  return createCollection(
    realtimeCollectionOptions({
      client,
      query,
      refreshQuery: renew,
      getKey: key,
    }),
  );
}
type RemoteCollection<Row extends object> = ReturnType<
  typeof collectionFor<Row>
>;

export function useRemoteRows<Row extends object>(
  api: JournalAPI,
  client: RealtimeClient | undefined,
  spec: LiveSpec | undefined,
  path: string | undefined,
  key: (row: Row) => string,
) {
  const signature = spec ? JSON.stringify(spec) : undefined;
  const [source, setSource] = useState<{
    signature: string;
    collection: RemoteCollection<Row>;
  }>();
  const [snapshot, setSnapshot] = useState<{ path: string; rows: Row[] }>();
  const [fallbackFor, setFallbackFor] = useState<string>();
  const [retries, setRetries] = useState(0);
  const collection =
    source?.signature === signature ? source?.collection : undefined;
  const live = useLiveQuery(() => collection);

  useEffect(() => {
    if (!client || !signature) return;
    let stopped = false;
    let active: RemoteCollection<Row> | undefined;
    setSource(undefined);
    const seal = () =>
      api.read<SealedLiveQuery<Row>>("/live", JSON.parse(signature));
    void seal()
      .then((query) => {
        if (stopped) return;
        active = collectionFor(client, query, seal, key);
        setSource({ signature, collection: active });
      })
      .catch(() => {
        if (!stopped) setFallbackFor(signature);
      });
    return () => {
      stopped = true;
      void active?.cleanup({ dependents: true }).catch(() => {});
    };
  }, [api, client, key, signature, retries]);

  const healthy = !!collection && live.isReady && !live.isSyncError;
  const terminal = live.isLoadingError || live.status === "error";
  useEffect(() => {
    if (!signature || !client) return;
    if (healthy) {
      setFallbackFor((value) => (value === signature ? undefined : value));
      return;
    }
    const timer = setTimeout(
      () => setFallbackFor(signature),
      terminal || live.isSyncError ? 0 : 4000,
    );
    return () => clearTimeout(timer);
  }, [signature, client, healthy, terminal, live.isSyncError]);

  const fallback =
    !!path && (!client || (!healthy && fallbackFor === signature));
  const needsNewSubscription = !collection || terminal;
  useEffect(() => {
    if (!client || !fallback || !needsNewSubscription) return;
    const timer = setTimeout(() => setRetries((attempt) => attempt + 1), 8000);
    return () => clearTimeout(timer);
  }, [client, fallback, needsNewSubscription, retries, signature]);

  useEffect(() => {
    if (!path || !fallback) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout>;
    async function refresh() {
      try {
        const rows = await api.read<Row[]>(path!);
        if (!stopped) setSnapshot({ path: path!, rows });
      } catch {
        // Keep the last visible rows while reconnecting.
      }
      if (!stopped) timer = setTimeout(refresh, 15_000);
    }
    void refresh();
    return () => {
      stopped = true;
      clearTimeout(timer);
    };
  }, [api, path, fallback]);

  const rows = healthy
    ? live.data
    : snapshot?.path === path
      ? snapshot?.rows
      : live.data;
  return {
    rows,
    fallback,
    ready: healthy || (snapshot?.path === path && !!snapshot),
  };
}
