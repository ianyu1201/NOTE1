const fs = require('node:fs');
const path = require('node:path');

const target = new URL(process.env.BASE_URL || 'http://127.0.0.1:5173/portfolio/note1/demo/');
target.search = '';
target.hash = '';
if (!target.pathname.endsWith('/')) target.pathname += '/';

const out = path.resolve(process.env.E2E_OUTPUT_DIR || path.join(__dirname, '../../.test-results/note1-e2e'));
fs.mkdirSync(out, { recursive: true });

module.exports = {
  out,
  url: target.href,
  launchOptions: {
    headless: true,
    ...(process.env.BROWSER_CHANNEL ? { channel: process.env.BROWSER_CHANNEL } : {}),
  },
};
