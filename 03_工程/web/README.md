# NOTE1 Web

NOTE1 的单设备本地 Web 版本：灵感、卡片预览、构思集、小票册，以及历史、搜索、回收站、备份与恢复。

## 运行

需要 Node.js 22.13 或更新版本和 npm。依赖版本由 `package-lock.json` 固定。

```sh
npm ci
npm run dev
```

打开终端显示的本机地址（默认 `http://127.0.0.1:5173`），点击“打开 NOTE1 Web”，或直接访问 `/portfolio/note1/demo/`。根路径为独立项目首页，`/portfolio/note1` 提供项目说明。原业务界面保留站点返回通栏，其中“个人主页”链接落到独立项目首页的 `#portfolio` 锚点，不依赖原个人网站。

```sh
npm test
npm run build
npm run preview
```

`npm test` 运行领域逻辑、备份校验和卡片手势三组测试；构建先检查业务源码与独立入口的 TypeScript 类型，再生成 `dist/`。托管 `dist/` 时需支持 SPA 回退到 `index.html`，以便直接访问项目说明与演示路径。开发与预览默认仅监听本机地址。

## 端到端测试

便携脚本重用本轮业务验收的 45 个检查，使用独立的浏览器上下文和测试数据。先安装 Chromium：

```sh
npx playwright install chromium
```

终端 1 启动服务：

```sh
npm run dev -- --port 5173
```

终端 2 执行测试：

```sh
npm run test:e2e
```

`BASE_URL` 指完整应用页面地址，默认 `http://127.0.0.1:5173/portfolio/note1/demo/`。测试构建后的预览版本时，先在另一个终端运行 `npm run preview`，然后执行：

```sh
BASE_URL=http://127.0.0.1:4173/portfolio/note1/demo/ npm run test:e2e
```

运行证据写入 `.test-results/`，已忽略上传。Playwright 固定为既有验收使用的公开 npm 版本 `1.64.0-alpha-1790635538000`；浏览器安装需要网络。浏览器真实录音、跨浏览器及真机能力不由这些测试证明。

## 源码结构

- `app/portfolio/note1/demo/`：来自原 Web 版本的生产业务文件，逐字保留。
- `tests/note1-*.test.mjs`：既有 26 个业务单元测试，保留原相对路径。
- `src/`、`index.html`、`vite.config.ts`：新增独立运行宿主，不依赖个人网站其余内容。
- `app/portfolio/note1/demo/page.tsx`：原 Next 路由的元数据包装，保留用于核对来源；独立 Vite 宿主不编译该文件，也不需要 Next.js。

运行时依赖仅为 React 和 React DOM；图标、存储、业务规则均由本项目源码提供。此包不包含个人网站其他页面、服务、私有文件、浏览器数据、导出备份或构建产物。

## 本机数据

数据与附件保存在当前浏览器的 IndexedDB 中，跨标签页通过 BroadcastChannel 和刷新机制同步。同一设备上不同浏览器、不同源地址及原生 APP 的数据互相独立。本包不提供账号、服务器、云同步或跨端备份互导。语音采集需要浏览器授权并支持 MediaRecorder，文件操作能力取决于浏览器。

公开源码不包含真实笔记或测试导入数据。使用设置中的导出备份保存自己的数据，恢复时会校验备份格式和完整性。
