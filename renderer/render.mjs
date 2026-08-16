#!/usr/bin/env node
// Renderiza posts do Instagram (1080x1350) da marca Marcelo Matos | Dev & IA
// Uso: node render.mjs <posts.json> <out-dir>
// posts.json: array de { num, eyebrow, title, body?, bullets?[{ic,text}], steps?[string], cta? }
import { readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const __dir = dirname(fileURLToPath(import.meta.url));
const [postsPath, outDirArg] = process.argv.slice(2);
if (!postsPath) {
  console.error('Uso: node render.mjs <posts.json> <out-dir>');
  process.exit(1);
}
const outDir = resolve(outDirArg || 'out');
mkdirSync(outDir, { recursive: true });

const CHROME = ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']
  .map(b => { try { return execFileSync('which', [b]).toString().trim(); } catch { return ''; } })
  .find(Boolean);
if (!CHROME) { console.error('Chrome/Chromium não encontrado.'); process.exit(1); }

let HAS_CONVERT = false;
try { execFileSync('which', ['convert']); HAS_CONVERT = true; } catch {}

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Template padrão: template.html. Para usar o v2 (eyebrow em chip, barra de
// acento e CTA em pílula), exporte POST_TEMPLATE=template-v2.html antes de rodar.
const templateFile = process.env.POST_TEMPLATE || 'template.html';
let template = readFileSync(join(__dir, templateFile), 'utf8');

// Embute as fontes inline com caminho absoluto — o HTML é gravado na pasta de
// saída, então um href relativo a fonts.css quebraria (fallback p/ serifa).
const fontsDir = join(__dir, 'fonts');
const fontCss = readFileSync(join(fontsDir, 'fonts.css'), 'utf8')
  .replace(/url\((f\d+\.woff2)\)/g, (_, f) => `url(file://${join(fontsDir, f)})`);
template = template.replace(
  /<link rel="stylesheet" href="fonts\.css" \/>/,
  `<style>\n${fontCss}\n</style>`
);

function buildContent(p) {
  if (Array.isArray(p.bullets) && p.bullets.length) {
    const items = p.bullets.map(b =>
      `<div class="item"><div class="ic">${esc(b.ic || '•')}</div><div>${esc(b.text)}</div></div>`).join('\n');
    return `<div class="list">\n${items}\n</div>`;
  }
  if (Array.isArray(p.steps) && p.steps.length) {
    const items = p.steps.map((t, i) =>
      `<div class="item step"><div class="ic">${i + 1}</div><div>${esc(t)}</div></div>`).join('\n');
    return `<div class="list">\n${items}\n</div>`;
  }
  return p.body ? `<div class="body">${esc(p.body)}</div>` : '';
}

// título mais longo => fonte menor, mantendo dentro da zona segura.
// Valores ajustados p/ o padding lateral de 116px (conteúdo ~848px de largura).
function titleSize(title) {
  const n = title.length;
  if (n <= 18) return 98;
  if (n <= 30) return 88;
  if (n <= 46) return 78;
  return 66;
}

// Ícone de fundo (v3): vem de p.bg; se ausente, cai no fallback por pilar (POST_PILLAR).
const PILLAR_ICON = { 'dor': '⚠️', 'antes-depois': '🔄', 'educacao': '💡', 'prova': '📊' };
const bgFor = p => p.bg || PILLAR_ICON[process.env.POST_PILLAR] || '';

const posts = JSON.parse(readFileSync(postsPath, 'utf8'));
const list = Array.isArray(posts) ? posts : [posts];

const total = list.length;
for (let idx = 0; idx < total; idx++) {
  const p = list[idx];
  const num = String(p.num ?? (idx + 1)).padStart(2, '0');
  const imgPath = join(outDir, `img-${num}.jpg`);
  const hasPhoto = existsSync(imgPath);
  const photoLayer = hasPhoto
    ? `<div class="photo" style="background-image:url(file://${imgPath})"></div><div class="scrim"></div>`
    : '';
  // bolinhas de progresso: só em carrossel (>1 lâmina); vazio em imagem única
  const progress = total > 1
    ? '<div class="dots">' + Array.from({ length: total }, (_, i) =>
        `<span class="dot${i === idx ? ' on' : ''}"></span>`).join('') + '</div>'
    : '';
  const html = template
    .replace('--title-size,96px', `--title-size,${titleSize(p.title || '')}px`)
    .replace('{{PROGRESS}}', progress)
    .replace('{{EYEBROW}}', esc(p.eyebrow || ''))
    .replace('{{TITLE}}', esc(p.title || ''))
    .replace('{{CONTENT}}', buildContent(p))
    .replace('{{CTA}}', esc(p.cta || 'WhatsApp na bio →'))
    .replace('{{BG_ICON}}', esc(hasPhoto ? '' : bgFor(p)))
    .replace('{{PHOTO_LAYER}}', photoLayer);

  const base = `post-${num || 'x'}`;
  const htmlPath = join(outDir, `${base}.html`);
  const rawPng = join(outDir, `${base}.raw.png`);
  const finalPng = join(outDir, `${base}.png`);
  writeFileSync(htmlPath, html);

  execFileSync(CHROME, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
    '--force-device-scale-factor=2',
    '--default-background-color=00000000',
    `--screenshot=${rawPng}`,
    '--window-size=1080,1350',
    `file://${htmlPath}`,
  ], { stdio: 'ignore' });

  if (HAS_CONVERT) {
    // 2160x2700 -> 1080x1350 (downscale = texto mais nítido)
    execFileSync('convert', [rawPng, '-resize', '1080x1350', '-strip', '-quality', '92', finalPng]);
    unlinkSync(rawPng);
  } else {
    execFileSync('mv', [rawPng, finalPng]);
  }
  unlinkSync(htmlPath);
  console.log(`✓ ${finalPng}`);
}
console.log(`\n${list.length} post(s) em ${outDir}`);
