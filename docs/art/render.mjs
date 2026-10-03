// Renders the HTML art sources in this folder to PNGs in docs/images and the Stream Deck plugin icons.
// Requires Playwright with Chromium: npx playwright install chromium (or set PLAYWRIGHT_BROWSERS_PATH).
import { chromium } from "playwright";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const url = (file, hash = "") => pathToFileURL(path.join(here, file)).href + hash;
const jobs = [
  { src: url("banner.html"), out: "docs/images/banner.png", width: 1600, height: 520, scale: 1 },
  { src: url("banner.html", "#social"), out: "docs/images/social-preview.png", width: 1280, height: 640, scale: 1 },
  { src: url("streamdeck.html"), out: "docs/images/streamdeck-keys.png", width: 840, height: 600, scale: 1.5 },
  { src: pathToFileURL(path.join(root, "docs/images/app-icon.svg")).href, out: "apps/streamdeck/dev.kslight.controller.sdPlugin/imgs/plugin.png", width: 256, height: 256, scale: 1, icon: true },
  { src: pathToFileURL(path.join(root, "docs/images/app-icon.svg")).href, out: "apps/streamdeck/dev.kslight.controller.sdPlugin/imgs/plugin@2x.png", width: 256, height: 256, scale: 2, icon: true },
];

const browser = await chromium.launch();
for (const job of jobs) {
  const page = await browser.newPage({ viewport: { width: job.width, height: job.height }, deviceScaleFactor: job.scale });
  if (job.icon) {
    await page.setContent(`<style>html,body{margin:0;background:transparent}img{width:${job.width}px;height:${job.height}px;display:block}</style><img src="${job.src}">`);
  } else {
    await page.goto(job.src);
  }
  await page.waitForTimeout(150);
  await page.screenshot({ path: path.join(root, job.out), omitBackground: Boolean(job.icon) });
  await page.close();
  console.log("wrote", job.out);
}
await browser.close();
