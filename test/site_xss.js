// Regression test for the download page's use of GitHub release data
// (GitHub issue #28). Serves nothing itself: start any static server on the
// site folder first, then
//
//   python3 -m http.server 8765 --directory site &
//   NODE_PATH=$(npm root -g) node test/site_xss.js
//
// Needs Playwright (`npm i -g playwright`). Exits non-zero if a script in the
// release name or tag ran, or if a link that is not an https GitHub URL was
// put in an href.
const { chromium } = require('playwright');
const URL_ = process.env.SITE_URL || 'http://localhost:8765/index.html';

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  let fired = false;
  await p.exposeFunction('pwned', () => { fired = true; });
  p.on('dialog', (d) => { fired = true; d.dismiss(); });
  await p.route('**/api/latest', (r) => r.fulfill({ json: {
    name: '<img src=x onerror="pwned()">',
    tag_name: 'v9<script>pwned()</script>',
    html_url: 'javascript:pwned()',
    published_at: '2026-11-01T00:00:00Z',
    assets: [
      { name: 'a-setup.exe', size: 5e7, browser_download_url: 'https://github.com/icmric/openote/releases/download/v9/a-setup.exe' },
      { name: 'windows-x64.zip', size: 5e7, browser_download_url: 'javascript:pwned()' },
      { name: 'x.deb', size: 1e6, browser_download_url: 'https://evil.example/x.deb' },
      { name: 'x.rpm', size: 1e6, browser_download_url: 'https://github.com/icmric/openote/releases/download/v9/x.rpm' },
    ],
  } }));
  await p.goto(URL_);
  await p.waitForTimeout(800);

  const hrefs = await p.$$eval('a', (as) => as.map((a) => a.getAttribute('href') || ''));
  const bad = hrefs.filter((h) => /^\s*javascript:/i.test(h) || /evil\.example/.test(h));
  const injected = await p.locator('#release-line img, #release-line script').count();
  await b.close();

  const problems = [];
  if (fired) problems.push('script ran');
  if (bad.length) problems.push('unsafe hrefs: ' + bad.join(', '));
  if (injected) problems.push('markup from the release name became elements');
  if (problems.length) { console.error('FAIL: ' + problems.join('; ')); process.exit(1); }
  console.log('ok: release data is shown as text, and unsafe links are refused');
})();
