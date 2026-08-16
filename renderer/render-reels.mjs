#!/usr/bin/env node
// Renderiza um Reels de tipografia animada (1080x1920, ~7s, sem áudio) a
// partir de UM slide { eyebrow, title, body, cta }.
// Uso: node render-reels.mjs <slide.json> <out-dir>
// Sempre grava em <out-dir>/post-01.mp4 (mesma convenção de nome fixo do
// render.mjs — o slug final é aplicado depois, no gerar-post.sh).
import { readFileSync, writeFileSync, mkdirSync, unlinkSync, readdirSync, renameSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { punchStyle, wipeStyle, revealStyle, splitLastWord } from './reels-timing.mjs';
import { pickFile, pickStartOffset } from './reels-audio.mjs';

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
const { rest: titleRest, last: titleLast } = splitLastWord(slide.title);

const FPS = 24;
// Timeline (em frames, 24fps): eyebrow entra em "punch" -> título varre em
// "wipe" -> palavra de destaque pousa em "punch" -> corpo revela -> CTA
// pousa em "punch" (o "beat que aterrissa" no fim da animação).
const EYEBROW = { start: 0, dur: 12 };
const TITLE = { start: 8, dur: 24 };
const TITLE_HL = { start: 30, dur: 18 };
const BODY = { start: 44, dur: 22 };
const CTA = { start: 62, dur: 22 };
const ANIM_FRAMES = 90;          // ~3.75s de animação renderizada quadro a quadro
const TOTAL_SECONDS = 7;         // dentro da faixa 7-15s de maior taxa de conclusão
const HOLD_SECONDS = +(TOTAL_SECONDS - ANIM_FRAMES / FPS).toFixed(3);

for (let frame = 0; frame < ANIM_FRAMES; frame++) {
  const html = baseHtml
    .replace('{{EYEBROW}}', esc(slide.eyebrow || ''))
    .replace('{{TITLE_REST}}', esc(titleRest))
    .replace('{{TITLE_LAST}}', esc(titleLast))
    .replace('{{BODY}}', esc(slide.body || ''))
    .replace('{{CTA}}', esc(slide.cta || 'WhatsApp na bio →'))
    .replace('{{EYEBROW_STYLE}}', punchStyle(frame, EYEBROW.start, EYEBROW.dur))
    .replace('{{TITLE_STYLE}}', wipeStyle(frame, TITLE.start, TITLE.dur))
    .replace('{{TITLE_HL_STYLE}}', punchStyle(frame, TITLE_HL.start, TITLE_HL.dur))
    .replace('{{BODY_STYLE}}', revealStyle(frame, BODY.start, BODY.dur))
    .replace('{{CTA_STYLE}}', punchStyle(frame, CTA.start, CTA.dur));

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

// Zoom lento e contínuo (tipo Ken Burns) aplicado ao vídeo INTEIRO — inclusive
// no trecho "hold" clonado do último frame — pra nunca ficar com imagem
// parada na tela (era o principal motivo do reels anterior parecer estático).
const ZOOM_MAX = 1.08;
const zoompan = `zoompan=z='min(${ZOOM_MAX},1+0.00055*on)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1080x1920:fps=${FPS}`;

const mp4Path = join(outDir, 'post-01.mp4');
execFileSync('ffmpeg', [
  '-y', '-framerate', String(FPS),
  '-i', join(outDir, 'reels-frame-%03d.png'),
  '-vf', `tpad=stop_mode=clone:stop_duration=${HOLD_SECONDS},${zoompan},format=yuv420p`,
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
  mp4Path,
], { stdio: ['ignore', 'ignore', 'inherit'] });

for (let frame = 0; frame < ANIM_FRAMES; frame++) {
  unlinkSync(join(outDir, `reels-frame-${String(frame).padStart(3, '0')}.png`));
}

// ===== Trilha de fundo (opcional; não-fatal) =====
// Sorteia um mp3 de renderer/audio/ e um trecho aleatório do tamanho do
// vídeo, com fade-out no último segundo. Sem faixas na pasta -> reels mudo.
try {
  const audioDir = join(__dir, 'audio');
  const audioFiles = readdirSync(audioDir).filter(f => f.endsWith('.mp3'));
  const track = pickFile(audioFiles);
  if (track) {
    const trackPath = join(audioDir, track);
    const trackDuration = parseFloat(execFileSync('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1', trackPath,
    ]).toString().trim()) || TOTAL_SECONDS;
    const startAt = pickStartOffset(trackDuration, TOTAL_SECONDS);
    const withAudio = join(outDir, 'post-01-audio.mp4');
    execFileSync('ffmpeg', [
      '-y', '-i', mp4Path,
      '-ss', String(startAt), '-t', String(TOTAL_SECONDS), '-i', trackPath,
      '-filter_complex', `[1:a]volume=0.85,afade=t=out:st=${TOTAL_SECONDS - 1}:d=1[a]`,
      '-map', '0:v', '-map', '[a]',
      '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k', '-shortest',
      withAudio,
    ], { stdio: ['ignore', 'ignore', 'inherit'] });
    renameSync(withAudio, mp4Path);
    console.log(`✓ trilha: ${track} (${startAt}s-${(startAt + TOTAL_SECONDS).toFixed(1)}s)`);
  } else {
    console.log('sem trilha em renderer/audio/; reels fica mudo');
  }
} catch (err) {
  console.error(`AVISO: trilha de fundo falhou (${err.message}); reels segue mudo`);
}

console.log(`✓ ${mp4Path}`);
