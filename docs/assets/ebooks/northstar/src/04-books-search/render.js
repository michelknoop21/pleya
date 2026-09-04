// Renders one HTML mockup page at the iPhone 15 Pro viewport (393x852 @3x =
// 1179x2556), the same frame the iOS Unified 2026 northstar set was shot on.
// The optional fourth argument overrides the height, for the specimen frame
// that is a detail crop rather than a full screen.
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const [, , htmlFile, outFile, screen, height] = process.argv;
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 393, height: height ? parseInt(height, 10) : 852 },
    deviceScaleFactor: 3,
    isMobile: true,
    hasTouch: true,
    colorScheme: 'dark',
  });
  const page = await ctx.newPage();
  const url = 'file://' + path.resolve(htmlFile) + (screen ? '?screen=' + screen : '');
  await page.goto(url, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  await page.screenshot({ path: outFile, fullPage: false });
  await browser.close();
  console.log('wrote', outFile);
})();
