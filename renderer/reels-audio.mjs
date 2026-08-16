// Seleção de trilha de fundo — funções puras (recebem `rand` por injeção,
// em vez de chamar Math.random() direto, pra dar pra testar determinístico).

export function pickFile(files, rand = Math.random()) {
  if (!files.length) return null;
  return files[Math.floor(rand * files.length) % files.length];
}

// Ponto de corte aleatório dentro da faixa, do tamanho do clipe (7s do reels).
// Se a faixa for mais curta que o clipe, corta do início (sem espaço pra variar).
export function pickStartOffset(trackDuration, clipSeconds, rand = Math.random()) {
  const room = trackDuration - clipSeconds;
  if (room <= 0) return 0;
  return +(rand * room).toFixed(2);
}
