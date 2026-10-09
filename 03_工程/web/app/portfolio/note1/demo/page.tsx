import type { Metadata } from "next";
import { Note1App } from "./Note1App";

export const metadata: Metadata = {
  title: "NOTE1 Web · 本机灵感工具 | ianyu",
  description:
    "NOTE1 单设备本地版：记录灵感、卡片预览、归入构思集、生成小票。数据只保存在当前浏览器。",
  robots: { index: false, follow: false },
  alternates: { canonical: "/portfolio/note1" },
};

export default function Note1DemoPage() {
  return <Note1App />;
}