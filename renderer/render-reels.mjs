#!/usr/bin/env node
// Renderiza um Reels de tipografia animada (1080x1920, ~5s, sem áudio) a
// partir de UM slide { eyebrow, title, body, cta }.
// Uso: node render-reels.mjs <slide.json> <out-dir>
// Sempre grava em <out-dir>/post-01.mp4 (mesma convenção de nome fixo do
// render.mjs — o slug final é aplicado depois, no gerar-post.sh).
import { readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const __dir = dirname(fileURLToPath(import.meta.url));
const [slidePath, outDirArg] = process.argv.slice(2);
if (!slidePath) {
  console.error('Uso: node render-reels.mjs <slide.json> <out-dir>');
  process.exit(1);
}
const outDir = resolve(outDirArg || 'out');
mkdirSync(outDir, { recursive: true });

const CHROME = ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']
  .map(b => { try { return execFileSync('which', [b]).toString().trim(); } catch { return ''; } })
  .find(Boolean);
if (!CHROME) { console.error('Chrome/Chromium não encontrado.'); process.exit(1); }
try { execFileSync('which', ['ffmpeg']); } catch { console.error('ffmpeg não encontrado.'); process.exit(1); }

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const template = readFileSync(join(__dir, 'template-reels.html'), 'utf8');
const fontsDir = join(__dir, 'fonts');
const fontCss = readFileSync(join(fontsDir, 'fonts.css'), 'utf8')
  .replace(/url\((f\d+\.woff2)\)/g, (_, f) => `url(file://${join(fontsDir, f)})`);
const baseHtml = template.replace(
  /<link rel="stylesheet" href="fonts\.css" \/>/,
  `<style>\n${fontCss}\n</style>`
);

const slide = JSON.parse(readFileSync(slidePath, 'utf8'));

const FPS = 24;
const ANIM_FRAMES = 47;         // ~1.96s de animação renderizada quadro a quadro
const TOTAL_SECONDS = 5;
const HOLD_SECONDS = +(TOTAL_SECONDS - ANIM_FRAMES / FPS).toFixed(3);

// Entrada em 3 estágios (eyebrow -> título -> corpo), cada um com easeOutQuad.
const easeOutQuad = t => 1 - (1 - t) * (1 - t);
function reveal(frame, startFrame, durationFrames) {
  const t = Math.min(1, Math.max(0, (frame - startFrame) / durationFrames));
  const e = easeOutQuad(t);
  return `opacity:${e.toFixed(3)};transform:translateY(${Math.round((1 - e) * 40)}px)`;
}

for (let frame = 0; frame < ANIM_FRAMES; frame++) {
  const html = baseHtml
    .replace('{{EYEBROW}}', esc(slide.eyebrow || ''))
    .replace('{{TITLE}}', esc(slide.title || ''))
    .replace('{{BODY}}', esc(slide.body || ''))
    .replace('{{CTA}}', esc(slide.cta || 'WhatsApp na bio →'))
    .replace('{{EYEBROW_STYLE}}', reveal(frame, 0, 14))
    .replace('{{TITLE_STYLE}}', reveal(frame, 10, 20))
    .replace('{{BODY_STYLE}}', reveal(frame, 26, 20));

  const num = String(frame).padStart(3, '0');
  const htmlPath = join(outDir, `reels-frame-${num}.html`);
  const pngPath = join(outDir, `reels-frame-${num}.png`);
  writeFileSync(htmlPath, html);
  execFileSync(CHROME, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
    '--force-device-scale-factor=1',
    '--default-background-color=00000000',
    `--screenshot=${pngPath}`,
    '--window-size=1080,1920',
    `file://${htmlPath}`,
  ], { stdio: 'ignore' });
  unlinkSync(htmlPath);
}

const mp4Path = join(outDir, 'post-01.mp4');
execFileSync('ffmpeg', [
  '-y', '-framerate', String(FPS),
  '-i', join(outDir, 'reels-frame-%03d.png'),
  '-vf', `tpad=stop_mode=clone:stop_duration=${HOLD_SECONDS},format=yuv420p`,
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
  mp4Path,
], { stdio: ['ignore', 'ignore', 'inherit'] });

for (let frame = 0; frame < ANIM_FRAMES; frame++) {
  unlinkSync(join(outDir, `reels-frame-${String(frame).padStart(3, '0')}.png`));
}
console.log(`✓ ${mp4Path}`);
