"use client";

import { useMemo } from "react";
import { useNote1 } from "../Note1Provider";
import { useApp } from "../app-context";
import { ReceiptPaper } from "../ReceiptPaper";
import * as engine from "../domain/engine";
import { EmptyState, Icon, formatDisplay } from "../ui";

export function ReceiptsView() {
  const { state } = useNote1();
  const { navigate } = useApp();
  const receipts = useMemo(
    () => [...state.receipts].sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1)),
    [state.receipts],
  );

  if (receipts.length === 0) {
    return (
      <div className="note1-page-body note1-page-body-scroll">
        <EmptyState
          icon="receipt"
          message="结束一轮构思并生成小票后，会在这里看到最新小票和全部索引。"
          title="还没有构思小票"
        />
      </div>
    );
  }

  const latest = receipts[0];

  return (
    <div className="note1-page-body note1-page-body-scroll">
      <section className="note1-receipt-latest">
        <p className="note1-context-label">最新小票</p>
        <button
          className="note1-receipt-latest-paper"
          onClick={() => navigate({ name: "receipt", id: latest.id })}
          type="button"
        >
          <ReceiptPaper dense receipt={latest} />
        </button>
      </section>

      <section className="note1-receipt-index">
        <p className="note1-context-label">全部小票</p>
        <div className="note1-card-list">
          {receipts.map((receipt) => {
            const stats = engine.receiptStatistics(receipt.snapshot);
            return (
              <button
                className="note1-receipt-row"
                key={receipt.id}
                onClick={() => navigate({ name: "receipt", id: receipt.id })}
                type="button"
              >
                <span className="note1-receipt-row-icon">
                  <Icon name="receipt" size={20} />
                </span>
                <div className="note1-receipt-row-meta">
                  <h3>{receipt.snapshot.collectionName}</h3>
                  <p>
                    {engine.roundTitle(stats.roundNumber)} · {stats.inspirationCount} 条灵感 ·{" "}
                    {formatDisplay(receipt.createdAt)}
                  </p>
                </div>
                <Icon name="chevron-right" />
              </button>
            );
          })}
        </div>
      </section>
    </div>
  );
}