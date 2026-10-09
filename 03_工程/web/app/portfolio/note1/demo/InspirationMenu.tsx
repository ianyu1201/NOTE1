"use client";

import { useState } from "react";
import { ActionMenu } from "./ActionMenu";
import { Icon } from "./ui";

export type InspirationOptions = { scope: "active" | "tucked" | "all"; sort: "updated" | "newest" | "oldest"; selecting: boolean };
export const initialInspirationOptions: InspirationOptions = { scope: "active", sort: "newest", selecting: false };
export function InspirationMenu({ options, onChange }: { options: InspirationOptions; onChange: (value: InspirationOptions) => void }) {
  const [section, setSection] = useState<"main" | "sort" | "scope">("main");
  const openSection = (value: typeof section) => {
    setSection(value);
    requestAnimationFrame(() => document.querySelector<HTMLButtonElement>('.note1-title-menu [role="menu"] button')?.focus());
  };
  const sortLabels = { newest: "创建日期 · 从新到旧", oldest: "创建日期 · 从旧到新", updated: "最近修改" };
  const scopeLabels = { active: "进行中", tucked: "已收起", all: "全部灵感" };
  return <ActionMenu label="灵感视图选项" className="note1-title-menu" onOpen={() => setSection("main")} trigger={<>NOTE1 <Icon name="chevron-down" size={16} /></>}>
    {(close) => {
      const done = () => { setSection("main"); close(); };
      return section === "main" ? <>
        <button role="menuitem" onClick={() => { onChange({ ...options, selecting: !options.selecting }); done(); }}><Icon name="select" /><span>{options.selecting ? "结束多选" : "选择灵感"}</span></button>
        <button role="menuitem" onClick={() => openSection("sort")}><Icon name="sort" /><span>排序方式<small>{sortLabels[options.sort]}</small></span><Icon name="chevron-right" size={16} /></button>
        <button role="menuitem" onClick={() => openSection("scope")}><Icon name="filter" /><span>筛选灵感<small>{scopeLabels[options.scope]}</small></span><Icon name="chevron-right" size={16} /></button>
      </> : <>
        <button role="menuitem" onClick={() => openSection("main")}><Icon name="chevron-left" /><span>{section === "sort" ? "排序方式" : "筛选灵感"}</span></button>
        {section === "sort" ? (Object.keys(sortLabels) as InspirationOptions["sort"][]).map((sort) => <button key={sort} role="menuitemradio" aria-checked={options.sort === sort} onClick={() => { onChange({ ...options, sort }); done(); }}><span>{sortLabels[sort]}</span>{options.sort === sort && <Icon name="check" size={18} />}</button>) : (Object.keys(scopeLabels) as InspirationOptions["scope"][]).map((scope) => <button key={scope} role="menuitemradio" aria-checked={options.scope === scope} onClick={() => { onChange({ ...options, scope, selecting: false }); done(); }}><span>{scopeLabels[scope]}</span>{options.scope === scope && <Icon name="check" size={18} />}</button>)}
      </>;
    }}
  </ActionMenu>;
}
