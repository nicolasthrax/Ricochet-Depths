// Renders the store art with Playwright's Chromium: `npm i playwright && node render.js`, run in
// this folder with russo.ttf and rajdhani.ttf (Russo One and Rajdhani, from Google Fonts) beside
// art.html. Writes icon.png and thumb1-3.png one folder up, into marketing/.
const path = require('path');
const { chromium } = require('playwright');

const SHOTS = [['icon', 512, 512], ['thumb1', 1920, 1080], ['thumb2', 1920, 1080], ['thumb3', 1920, 1080]];

(async () => {
  const browser = await chromium.launch();
  for (const [mode, width, height] of SHOTS) {
    const page = await browser.newPage({ viewport: { width, height } });
    await page.goto('file://' + path.join(__dirname, 'art.html') + '?mode=' + mode);
    await page.waitForSelector('body[data-ready="1"]');
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(__dirname, '..', mode + '.png') });
    await page.close();
  }
  await browser.close();
})();
