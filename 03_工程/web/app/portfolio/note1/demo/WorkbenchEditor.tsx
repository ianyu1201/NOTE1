"use client";

import { forwardRef, useImperativeHandle, useRef, useState, useEffect } from "react";
import type { Inspiration } from "./domain/types";
import { useNote1 } from "./Note1Provider";

export type EditorHandle = { flush: () => Promise<boolean> };

// Keep the draft alive until persistence succeeds. Switching objects and ending
// a round wait for this same save path instead of relying on blur/unmount.
export const WorkbenchEditor = forwardRef<EditorHandle, { member: Inspiration }>(function WorkbenchEditor({ member }, ref) {
  const { store } = useNote1();
  const [text, setText] = useState(member.text);
  const [status, setStatus] = useState("已保存");
  const draft = useRef(member.text);
  const saved = useRef(member.text);
  const sessionOriginal = useRef(member.text);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pending = useRef<Promise<boolean> | null>(null);
  const alive = useRef(true);

  async function flush(): Promise<boolean> {
    if (timer.current) clearTimeout(timer.current);
    if (pending.current) {
      if (!await pending.current) return false;
      return flush();
    }
    if (draft.current === saved.current) return true;
    const value = draft.current;
    if (alive.current) setStatus("正在保存…");
    const operation = store.updateInspiration(member.id, value).then(() => {
      saved.current = value;
      if (alive.current) setStatus(draft.current === value ? "已保存" : "待保存");
      return true;
    }).catch(() => {
      if (alive.current) setStatus("未保存，请重试");
      return false;
    });
    pending.current = operation;
    const ok = await operation;
    pending.current = null;
    return ok && (draft.current === saved.current || await flush());
  }

  useImperativeHandle(ref, () => ({ flush: async () => {
    if (!await flush()) return false;
    try {
      if (sessionOriginal.current !== saved.current) {
        await store.finishInspirationEditSession(member.id, sessionOriginal.current, saved.current);
        sessionOriginal.current = saved.current;
      }
      return true;
    } catch { setStatus("未保存，请重试"); return false; }
  } }));
  useEffect(() => {
    alive.current = true;
    const warn = (event: BeforeUnloadEvent) => {
      if (draft.current !== saved.current) { event.preventDefault(); event.returnValue = ""; }
    };
    window.addEventListener("beforeunload", warn);
    return () => {
      alive.current = false;
      if (timer.current) clearTimeout(timer.current);
      // Hash/back navigation may unmount without pressing our return button.
      // Finish the pending draft against the still-live store in that case.
      void flush();
      window.removeEventListener("beforeunload", warn);
    };
    // The editor is keyed by member ID; refs hold the latest draft on cleanup.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return <div className="note1-workbench-paper">
    <textarea aria-label="编辑当前灵感" value={text} onChange={(event) => {
      draft.current = event.target.value;
      setText(event.target.value);
      setStatus("待保存");
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => void flush(), 500);
    }} onBlur={() => void flush()} />
    <div className="note1-workbench-save" role="status">{status}
      {status.startsWith("未保存") && <button className="note1-text-btn" onClick={() => void flush()} type="button">重试</button>}
    </div>
  </div>;
});
