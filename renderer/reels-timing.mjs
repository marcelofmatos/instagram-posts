// Funções puras de timing/easing do Reels de tipografia animada. Sem efeitos
// colaterais — mantidas separadas de render-reels.mjs para poderem ser testadas
// sem precisar de Chrome/ffmpeg.

export const easeOutQuad = t => 1 - (1 - t) * (1 - t);

// Easing com leve "overshoot" (ultrapassa 1 e volta) — usado nas entradas em
// "punch"/bounce (mais impacto que um fade simples).
export const easeOutBack = (t, s = 1.70158) => {
  const tt = t - 1;
  return tt * tt * ((s + 1) * tt + s) + 1;
};

function progress(frame, startFrame, durationFrames) {
  return Math.min(1, Math.max(0, (frame - startFrame) / durationFrames));
}

// Fade + leve subida (translateY). Usado no corpo do texto.
export function revealStyle(frame, startFrame, durationFrames, { from = 40 } = {}) {
  const e = easeOutQuad(progress(frame, startFrame, durationFrames));
  return `opacity:${e.toFixed(3)};transform:translateY(${Math.round((1 - e) * from)}px)`;
}

// Entrada em "punch": escala de fromScale -> 1 com overshoot + fade rápido.
// Usado no eyebrow, na palavra de destaque do título e no CTA (o "beat que
// aterrissa" no fim do vídeo).
export function punchStyle(frame, startFrame, durationFrames, { fromScale = 1.22 } = {}) {
  const t = progress(frame, startFrame, durationFrames);
  const e = easeOutBack(t);
  const scale = fromScale - (fromScale - 1) * e;
  const opacity = Math.min(1, Math.max(0, t / 0.35));
  return `opacity:${opacity.toFixed(3)};transform:scale(${scale.toFixed(3)})`;
}

// Revelação "wipe" (varredura esquerda->direita) via clip-path, com leve
// subida — dá a sensação de tipografia entrando em movimento, não só
// aparecendo. Retorna a % ainda oculta à direita.
export function wipeStyle(frame, startFrame, durationFrames, { from = 24 } = {}) {
  const e = easeOutQuad(progress(frame, startFrame, durationFrames));
  const hiddenPct = (1 - e) * 100;
  return `clip-path:inset(0 ${hiddenPct.toFixed(2)}% 0 0);transform:translateY(${Math.round((1 - e) * from)}px)`;
}

// Separa a última palavra do título (destaque de cor) do restante da frase.
// Título de 1 palavra só: não há "resto", só a palavra em destaque.
export function splitLastWord(title) {
  const words = String(title || '').trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return { rest: '', last: '' };
  const last = words.pop();
  return { rest: words.join(' '), last };
}
