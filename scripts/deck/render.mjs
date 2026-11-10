// Renders every <section data-label> in deck.html to app/public/pitch, one 1920x1080 PNG per slide and one PDF
// Run from here with `npm install` once, then `npm run render`, it drives the local Chrome
import { readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
// OUT points a preview render somewhere else
const out = resolve(process.env.OUT ?? join(here, "../../app/public/pitch"));
const source = readFileSync(join(here, "deck.html"), "utf8");

// The deck runtime shows one slide at a time, so the slides are laid out flat on a plain page instead
const head = source.match(/<helmet>([\s\S]*?)<\/helmet>/)[1];
const sections = source.match(/<section data-label[\s\S]*?<\/section>/g);
const flat = join(here, ".render.html");
writeFileSync(
    flat,
    `<!doctype html><html><head><meta charset="utf-8">${head}<style>
        @page { size: 1920px 1080px; margin: 0; }
        body { margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        section[data-label] { width: 1920px; height: 1080px; overflow: hidden; break-after: page; }
    </style></head><body>${sections.join("\n")}</body></html>`,
);

const browser = await chromium.launch({ channel: "chrome" });
try {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
    await page.goto(pathToFileURL(flat).href, { waitUntil: "networkidle" });
    await page.evaluate(() => document.fonts.ready);

    // Old slides go first, so a shorter deck leaves no stale page behind
    for (const name of readdirSync(out)) if (/^slide-\d+\.png$/.test(name)) rmSync(join(out, name));
    const slides = page.locator("section[data-label]");
    const count = await slides.count();
    for (let i = 0; i < count; i++) {
        const name = `slide-${String(i + 1).padStart(2, "0")}.png`;
        await slides.nth(i).screenshot({ path: join(out, name) });
        console.log(name, await slides.nth(i).getAttribute("data-label"));
    }
    await page.pdf({ path: join(out, "feasy-deck.pdf"), width: "1920px", height: "1080px", printBackground: true });
    console.log("feasy-deck.pdf", count, "pages");
} finally {
    await browser.close();
    rmSync(flat, { force: true });
}
