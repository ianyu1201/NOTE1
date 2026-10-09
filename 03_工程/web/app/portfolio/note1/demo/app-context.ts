"use client";

import { createContext, useContext } from "react";
import type { Route, Toast } from "./ui";

export interface AppActions {
  navigate: (route: Route) => void;
  openComposer: () => void;
  openEditor: (inspirationId: string) => void;
  openJoin: (collectionId: string) => void;
  showToast: (message: string, action?: Toast["action"]) => void;
}

export const AppContext = createContext<AppActions | null>(null);

export function useApp(): AppActions {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp 必须在 NOTE1 应用壳内使用");
  return ctx;
}