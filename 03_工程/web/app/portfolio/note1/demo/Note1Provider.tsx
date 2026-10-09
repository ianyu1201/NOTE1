"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import { Note1Store, type Note1Snapshot } from "./store";

const Note1Context = createContext<Note1Store | null>(null);

export function Note1Provider({ children }: { children: ReactNode }) {
  const store = useMemo(() => new Note1Store(), []);
  useEffect(() => {
    void store.load();
    return () => store.dispose();
  }, [store]);
  return <Note1Context.Provider value={store}>{children}</Note1Context.Provider>;
}

export function useNote1Store(): Note1Store {
  const store = useContext(Note1Context);
  if (!store) throw new Error("useNote1Store 必须在 Note1Provider 内使用");
  return store;
}

export function useNote1(): Note1Snapshot & { store: Note1Store } {
  const store = useNote1Store();
  const snapshot = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot,
  );
  return { ...snapshot, store };
}
