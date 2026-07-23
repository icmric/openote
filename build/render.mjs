import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const FONT_DIR = '/tmp/fonts/node_modules/@fontsource';
const b64 = (p) => fs.readFileSync(p).toString('base64');
const face = (family, weight, file, style='normal') =>
  `@font-face{font-family:'${family}';font-style:${style};font-weight:${weight};font-display:block;` +
  `src:url(data:font/woff2;base64,${b64(file)}) format('woff2');}`;

const fontCss = `<style>
${face('Inter',400,`${FONT_DIR}/inter/files/inter-latin-400-normal.woff2`)}
${face('Inter',600,`${FONT_DIR}/inter/files/inter-latin-600-normal.woff2`)}
${face('Inter',700,`${FONT_DIR}/inter/files/inter-latin-700-normal.woff2`)}
${face('Source Serif 4',400,`${FONT_DIR}/source-serif-4/files/source-serif-4-latin-400-normal.woff2`)}
${face('Source Serif 4',600,`${FONT_DIR}/source-serif-4/files/source-serif-4-latin-600-normal.woff2`)}
${face('JetBrains Mono',400,`${FONT_DIR}/jetbrains-mono/files/jetbrains-mono-latin-400-normal.woff2`)}
${face('JetBrains Mono',600,`${FONT_DIR}/jetbrains-mono/files/jetbrains-mono-latin-600-normal.woff2`)}
${face('JetBrains Mono',700,`${FONT_DIR}/jetbrains-mono/files/jetbrains-mono-latin-700-normal.woff2`)}
</style>`;

const jobs = [
  { in: 'build/overview.html',   out: 'Openote-Product-and-Design-Overview.pdf' },
  { in: 'build/styleguide.html', out: 'Openote-Brand-and-Style-Guide.pdf' },
];

const browser = await chromium.launch();
for (const job of jobs) {
  let html = fs.readFileSync(job.in, 'utf8').replace('<!--FONTS-->', fontCss);
  const page = await browser.newPage();
  await page.setContent(html, { waitUntil: 'networkidle' });
  await page.emulateMedia({ media: 'print' });
  await page.pdf({
    path: job.out,
    printBackground: true,
    preferCSSPageSize: true,
  });
  await page.close();
  console.log('rendered', job.out, fs.statSync(job.out).size, 'bytes');
}
await browser.close();
