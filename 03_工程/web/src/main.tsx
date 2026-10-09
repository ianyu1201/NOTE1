import { createRoot } from "react-dom/client";
import { Note1App } from "../app/portfolio/note1/demo/Note1App";
import "./host.css";

function ProjectHome() {
  return (
    <main className="project-description" id="portfolio">
      <h1>NOTE1 Web</h1>
      <p>本机灵感工具：记录灵感、卡片预览、归入构思集、生成小票。</p>
      <p>这个独立宿主只包含 NOTE1 项目。</p>
      <p><a href="/portfolio/note1/demo">打开 NOTE1 Web</a></p>
      <p><a href="/portfolio/note1">查看项目说明</a></p>
    </main>
  );
}

function ProjectDescription() {
  return (
    <main className="project-description">
      <h1>NOTE1 项目说明</h1>
      <p>通过灵感、卡片预览、构思集、小票册四个入口，完成从捕捉想法到结束构思、回顾与继续构思的流程。</p>
      <p>数据保存在当前浏览器的 IndexedDB 中。导出备份后可在本 Web 版本恢复；原生端与 Web 端备份格式独立。</p>
      <p><a href="/portfolio/note1/demo">打开 NOTE1 Web</a></p>
      <p><a href="/#portfolio">返回项目首页</a></p>
    </main>
  );
}

const path = window.location.pathname;
const content = path === "/" ? <ProjectHome /> : /^\/portfolio\/note1\/?$/.test(path) ? <ProjectDescription /> : <Note1App />;
createRoot(document.getElementById("root")!).render(content);
