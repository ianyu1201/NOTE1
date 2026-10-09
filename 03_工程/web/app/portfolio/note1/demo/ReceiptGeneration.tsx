"use client";

import { useEffect, useState } from "react";
import type { Receipt } from "./domain/types";
import { ReceiptPaper } from "./ReceiptPaper";
import { useApp } from "./app-context";

export function ReceiptGeneration({ receipt }: { receipt: Receipt }) {
  const { navigate } = useApp();
  const [printing, setPrinting] = useState(true);
  useEffect(() => {
    const finish = () => setPrinting(false);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { finish(); return; }
    const timer = setTimeout(finish, 1900);
    document.addEventListener("visibilitychange", finish);
    return () => { clearTimeout(timer); document.removeEventListener("visibilitychange", finish); };
  }, []);
  return <div className={`note1-generation ${printing ? "is-printing" : "is-complete"}`}>
    <p className="note1-generation-status" role="status">已生成并保存小票册</p>
    <div className="note1-print-stage">
      <div className="note1-printer" aria-hidden="true"><span>NOTE1</span><i /></div>
      <button className="note1-generated-ticket" disabled={printing} aria-label={`阅读 ${receipt.snapshot.collectionName} 的完整小票`} onClick={() => navigate({ name: "receipt", id: receipt.id })} type="button">
        <ReceiptPaper receipt={receipt} dense />
      </button>
    </div>
    <button className="note1-text-btn" onClick={() => navigate({ name: "collections" })} type="button">返回构思集</button>
  </div>;
}
