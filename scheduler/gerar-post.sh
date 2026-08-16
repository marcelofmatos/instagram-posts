#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# ===== Caminhos (parametrizáveis por env, com defaults do container) =====
SCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO_DIR:-/repo}"
RENDERER="${RENDERER_DIR:-/app/renderer}"
DATA="${DATA_DIR:-/data}"
QUEUE="$REPO/posts-queue"
OUT="$DATA/out"
LOGDIR="$DATA/logs"
HIST="$DATA/historico.ndjson"
LOCK="$DATA/run.lock"
MODEL="${MODEL:-sonnet}"
REPO_SLUG="${REPO_SLUG:-marcelofmatos/instagram-posts}"
WA_WEBHOOK="${WA_WEBHOOK:-}"
WA_NUM="${WA_NUM:-}"
# Template da arte: v4 (layout do v2 — chip/barra/pílula — + foto de fundo por lâmina).
# Configurável por env; o render.mjs lê POST_TEMPLATE.
export POST_TEMPLATE="${POST_TEMPLATE:-template-v4.html}"

DRY=0
TEMA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry) DRY=1; shift;;
    --tema) TEMA="${2:-}"; shift 2;;
    -h|--help) echo "uso: gerar-post.sh [--dry] [--tema \"texto\"]"; exit 0;;
    *) echo "argumento desconhecido: $1 (uso: [--dry] [--tema \"texto\"])"; exit 1;;
  esac
done

# shellcheck source=/dev/null
source "$SCH/lib.sh"

mkdir -p "$OUT" "$LOGDIR" "$QUEUE"
TODAY="$(date +%Y-%m-%d)"
LOG="$LOGDIR/${TODAY}.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
abort() { log "ABORT: $*"; exit 1; }

# ===== Estado p/ alerta de falha =====
STEP="início"
SLUG="(indefinido)"

notify_wa() {  # $1=texto ; sempre não-fatal
  [ -n "$WA_WEBHOOK" ] || { log "WA_WEBHOOK vazio; pulando aviso"; return 0; }
  local payload
  payload="$(jq -nc --arg para "$WA_NUM" --arg texto "$1" '{para:$para, texto:$texto}')"
  if retry "webhook" -- curl -fsS -m 20 -X POST "$WA_WEBHOOK" \
       -H 'Content-Type: application/json' -d "$payload" >>"$LOG" 2>&1; then
    return 0
  fi
  log "AVISO: webhook do WhatsApp falhou (segue mesmo assim)"
  return 0
}

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "FALHA (exit $rc) no passo: $STEP"
    notify_wa "$(printf '\xE2\x9D\x8C *Falha ao gerar post*\nPasso: %s\nSlug: %s\nData: %s' "$STEP" "$SLUG" "$TODAY")"
  fi
  exit "$rc"
}
trap on_exit EXIT

# ===== Lock anti-duplicata (execução sobreposta = skip limpo, não falha) =====
exec 9>"$LOCK"
if ! flock -n 9; then
  log "outra execução em andamento (lock $LOCK); saindo sem rodar"
  exit 0
fi

log "=== início (dry=$DRY) ==="

# ===== 1. Sincronizar a main =====
STEP="sincronizar main"
cd "$REPO"
git_sync() { git checkout -q main && git pull --no-rebase --quiet origin main; }
retry "git sync" -- git_sync || abort "git sync falhou (working tree sujo?)"

# ===== 2. Pilar do dia + pauta + dedup =====
STEP="pilar/dedup"
DOW="${DOW_OVERRIDE:-$(date +%u)}"
PILAR="$(pilar_do_dia "$DOW")"
# FORMATO = "imagem"|"reels" (flag de máquina); não confundir com FORMATO_LABEL (texto pro PR/WhatsApp)
FORMATO="$(formato_do_dia "$DOW")"
export POST_PILLAR="$PILAR"   # fallback de ícone de fundo no render.mjs (v3)
SCHED="$(proximo_horario_publicacao)"
RECENTES="$(temas_recentes "$HIST" 10)"
[ -z "$RECENTES" ] && RECENTES="(nenhum ainda)"

TEMA_ID=""
CASO_TXT="(nenhum — tema livre)"
if [ -z "$TEMA" ]; then
  EXCL_IDS="$(tema_ids_recentes "$HIST" "$PILAR" 6)"
  PAUTA="$(escolher_tema "$SCH/pautas.json" "$PILAR" "$EXCL_IDS")" || abort "escolher_tema: nenhuma pauta cadastrada pro pilar $PILAR"
  TEMA_ID="$(printf '%s' "$PAUTA" | jq -r '.id')"
  TEMA="$(printf '%s' "$PAUTA" | jq -r '.gancho')"
  CASO_TXT="$(printf '%s' "$PAUTA" | jq -r '.caso')"
fi
log "pilar=$PILAR scheduled_for=$SCHED tema_id=${TEMA_ID:-manual} tema=$TEMA formato=$FORMATO"

# ===== 3. Montar prompt e chamar o claude =====
STEP="gerar conteúdo (claude)"
rm -f "$OUT/conteudo.json" "$OUT/meta.json"
TEMA_TXT="${TEMA:-"(livre — pesquise e escolha o melhor ângulo do nicho para o pilar de hoje)"}"
if [ "$FORMATO" = "reels" ]; then
  FORMATO_INSTRUCAO="Gere **exatamente 1 lâmina** (sem carrossel) — este post vira um Reels de tipografia animada. Título BEM curto (até 40 caracteres, cabe em 1-2 linhas grandes na tela); 1 ideia forte só; body opcional e curto (1 frase)."
else
  FORMATO_INSTRUCAO="Decida pelo tema/pilar:
- **Imagem única** (1 lâmina): mensagem direta, 1 ideia.
- **Carrossel (3 a 6 lâminas)**: quando o tema rende sequência — passo a passo, lista, antes/depois, mito x verdade.
  Narrativa: **lâmina 1 = capa/gancho**; lâminas do meio = valor; **última lâmina = CTA** (WhatsApp)."
fi
PROMPT="$(sed \
  -e "s|__PILAR__|$PILAR|g" \
  -e "s|__SCHEDULED_FOR__|$SCHED|g" \
  -e "s|__OUTDIR__|$OUT|g" \
  "$SCH/prompt-criar-post.md")"
PROMPT="${PROMPT/__RECENTES__/$RECENTES}"
PROMPT="${PROMPT/__TEMA__/$TEMA_TXT}"
PROMPT="${PROMPT/__CASO__/$CASO_TXT}"
PROMPT="${PROMPT/__FORMATO_INSTRUCAO__/$FORMATO_INSTRUCAO}"

log "chamando claude -p ($MODEL)…"
# Roda a partir de $OUT: o claude grava os arquivos no cwd, então o cwd precisa
# ser o diretório de saída (subshell preserva o cwd /repo do restante do script).
# timeout: o claude -p pode travar esperando aprovação interativa (ex.: tentar uma
# ferramenta fora do --allowedTools); o timeout garante que o retry assuma em vez
# de pendurar o pipeline e segurar o lock indefinidamente.
call_claude() { ( cd "$OUT" && printf '%s' "$PROMPT" | timeout "${CLAUDE_TIMEOUT:-600}" claude -p --model "$MODEL" --allowedTools "WebSearch,Write" ) >>"$LOG" 2>&1; }
retry "claude -p" -- call_claude || abort "claude -p falhou (ver log)"

# ===== 4. Validar os JSONs =====
STEP="validar JSON"
[ -f "$OUT/conteudo.json" ] || abort "conteudo.json não foi gerado"
[ -f "$OUT/meta.json" ]     || abort "meta.json não foi gerado"
jq -e 'type=="array" and ((length==1) or (length>=3 and length<=6)) and all(.[]; has("num") and has("eyebrow") and has("title"))' \
   "$OUT/conteudo.json" >/dev/null || abort "conteudo.json inválido (1 ou 3-6 lâminas, cada uma com num/eyebrow/title)"
NSLIDES="$(jq 'length' "$OUT/conteudo.json")"
log "lâminas=$NSLIDES ($([ "$NSLIDES" -eq 1 ] && echo 'imagem única' || echo 'carrossel'))"
if [ "$FORMATO" = "reels" ] && [ "$NSLIDES" -ne 1 ]; then
  abort "formato reels exige exatamente 1 lâmina (recebeu $NSLIDES)"
fi
if [ "$FORMATO" = "reels" ]; then
  RTITLE="$(jq -r '.[0].title' "$OUT/conteudo.json")"
  [ "${#RTITLE}" -le 40 ] || abort "formato reels exige título ≤40 chars (recebeu ${#RTITLE}: \"$RTITLE\")"
fi
jq -e 'has("slug") and has("pillar") and has("caption") and has("scheduled_for")' \
   "$OUT/meta.json" >/dev/null || abort "meta.json inválido"

TITLE="$(jq -r '.[0].title' "$OUT/conteudo.json")"
RAWSLUG="$(jq -r '.slug' "$OUT/meta.json")"
CAPTION="$(jq -r '.caption' "$OUT/meta.json")"
while IFS= read -r t; do
  [ "${#t}" -le 70 ] || log "AVISO: título com ${#t} chars (>70) pode ficar ilegível: \"$t\""
done < <(jq -r '.[].title' "$OUT/conteudo.json")

# ===== 4.5 Buscar fotos ilustrativas (Pexels) — não-fatal; sem foto => emoji =====
STEP="buscar fotos (pexels)"
rm -f "$OUT"/img-*.jpg
if [ -n "${PEXELS_API_KEY:-}" ]; then
  for i in $(seq 1 "$NSLIDES"); do
    ii="$(printf '%02d' "$i")"
    q="$(jq -r ".[$((i-1))].query // empty" "$OUT/conteudo.json")"
    [ -n "$q" ] || continue
    qenc="$(jq -rn --arg q "$q" '$q|@uri')"
    pexels_search() { curl -fsS -m 20 -H "Authorization: $PEXELS_API_KEY" \
      "https://api.pexels.com/v1/search?orientation=portrait&per_page=1&query=$qenc"; }
    resp="$(retry "pexels $ii" -- pexels_search 2>>"$LOG")" \
      || { log "pexels: busca falhou ($ii); usando emoji"; continue; }
    url="$(printf '%s' "$resp" | jq -r '.photos[0].src.portrait // .photos[0].src.large // empty')"
    [ -n "$url" ] || { log "pexels: sem resultado p/ \"$q\" ($ii); usando emoji"; continue; }
    pexels_dl() { curl -fsSL -m 30 "$url" -o "$OUT/img-$ii.jpg"; }
    retry "pexels dl $ii" -- pexels_dl >>"$LOG" 2>&1 \
      || { rm -f "$OUT/img-$ii.jpg"; log "pexels: download falhou ($ii); usando emoji"; }
  done
  log "fotos: $(find "$OUT" -name 'img-*.jpg' 2>/dev/null | wc -l)/$NSLIDES baixada(s)"
else
  log "PEXELS_API_KEY vazio; pulando fotos (usando emoji)"
fi

# ===== 5. Renderizar a arte =====
STEP="renderizar arte"
if [ "$FORMATO" = "reels" ]; then
  jq '.[0]' "$OUT/conteudo.json" > "$OUT/slide.json"
  node "$RENDERER/render-reels.mjs" "$OUT/slide.json" "$OUT" >>"$LOG" 2>&1 || abort "render-reels.mjs falhou"
  [ -f "$OUT/post-01.mp4" ] || abort "render não produziu post-01.mp4"
else
  node "$RENDERER/render.mjs" "$OUT/conteudo.json" "$OUT" >>"$LOG" 2>&1 || abort "render.mjs falhou"
  for i in $(seq 1 "$NSLIDES"); do
    ii="$(printf '%02d' "$i")"
    [ -f "$OUT/post-$ii.png" ] || abort "render não produziu post-$ii.png"
  done
fi

# ===== 6. Thumbnails =====
STEP="thumbnails"
if [ "$FORMATO" != "reels" ] && command -v convert >/dev/null; then
  for i in $(seq 1 "$NSLIDES"); do
    ii="$(printf '%02d' "$i")"
    convert "$OUT/post-$ii.png" -resize 360x "$OUT/thumb-$ii.png" 2>>"$LOG" || true
  done
  log "thumbnails: $NSLIDES gerado(s) em $OUT/thumb-*.png"
fi

# ===== 7. Slug único contra a fila =====
STEP="slug único"
SLUG="${TODAY}-$(slugify "$RAWSLUG")"
BASE="$SLUG"; i=2
while [ -e "$QUEUE/$BASE.json" ] || [ -e "$QUEUE/$BASE.png" ]; do BASE="${SLUG}-${i}"; i=$((i+1)); done
SLUG="$BASE"

build_images() {  # popula IMAGES e copia post-0i.png -> nome final em "$1"
  local dest="$1"; IMAGES=()
  if [ "$NSLIDES" -eq 1 ]; then
    cp "$OUT/post-01.png" "$dest/$SLUG.png"; IMAGES=("$SLUG.png")
  else
    for i in $(seq 1 "$NSLIDES"); do
      ii="$(printf '%02d' "$i")"
      cp "$OUT/post-$ii.png" "$dest/$SLUG-$ii.png"; IMAGES+=("$SLUG-$ii.png")
    done
  fi
}
images_json() { printf '%s\n' "${IMAGES[@]}" | jq -R . | jq -s .; }

build_video() {  # popula VIDEO com o nome final em "$1"
  local dest="$1"
  cp "$OUT/post-01.mp4" "$dest/$SLUG.mp4"; VIDEO="$SLUG.mp4"
}
build_manifest() {  # $1 = caminho de saída do manifesto; usa $FORMATO/$IMAGES/$VIDEO
  if [ "$FORMATO" = "reels" ]; then
    jq -n --arg sf "$SCHED" --arg p "$PILAR" --arg c "$CAPTION" --arg v "$VIDEO" \
      '{scheduled_for:$sf, pillar:$p, caption:$c, media_type:"reels", video:$v}' > "$1"
  else
    jq -n --arg sf "$SCHED" --arg p "$PILAR" --arg c "$CAPTION" --argjson imgs "$(images_json)" \
      '{scheduled_for:$sf, pillar:$p, caption:$c, images:$imgs}' > "$1"
  fi
}

# ===== 8. Dry-run: para aqui (sem branch/PR) =====
if [ "$DRY" -eq 1 ]; then
  if [ "$FORMATO" = "reels" ]; then build_video "$OUT"; else build_images "$OUT"; fi
  build_manifest "$OUT/$SLUG.json"
  log "DRY: formato=$FORMATO; manifesto em $OUT/$SLUG.json; mídia em $OUT/ (sem branch/PR)."
  log "=== fim (dry) ==="
  exit 0
fi

# ===== 9. Branch + arquivos da fila =====
STEP="branch + push"
BRANCH="post/$SLUG"
git checkout -q -b "$BRANCH" || abort "não consegui criar a branch $BRANCH"
if [ "$FORMATO" = "reels" ]; then build_video "$QUEUE"; else build_images "$QUEUE"; fi
build_manifest "$QUEUE/$SLUG.json"
git add "$QUEUE/$SLUG.json"
if [ "$FORMATO" = "reels" ]; then
  git add "$QUEUE/$VIDEO"
else
  for img in "${IMAGES[@]}"; do git add "$QUEUE/$img"; done
fi
git commit -q -m "post: $SLUG ($PILAR, $FORMATO)"
git_push() { git push -q -u origin "$BRANCH"; }
retry "git push" -- git_push || abort "git push da branch falhou"

# ===== 10. Abrir o Pull Request =====
STEP="abrir PR"
if [ "$FORMATO" = "reels" ]; then
  IMGMD="**Vídeo:** https://raw.githubusercontent.com/$REPO_SLUG/$BRANCH/posts-queue/$VIDEO"$'\n'
  FORMATO_LABEL="reels"
else
  IMGMD=""
  for img in "${IMAGES[@]}"; do
    IMGMD="$IMGMD![${img}](https://raw.githubusercontent.com/$REPO_SLUG/$BRANCH/posts-queue/$img)"$'\n'
  done
  FORMATO_LABEL="imagem única"; [ "$NSLIDES" -gt 1 ] && FORMATO_LABEL="carrossel ${NSLIDES}x"
fi
BODY="$(cat <<EOF
${IMGMD}
**Formato:** $FORMATO_LABEL
**Pilar:** $PILAR
**Agendado para:** $SCHED

**Legenda:**

$CAPTION

---
Merge = aprovado (entra em \`posts-queue/\` e o n8n publica no próximo ciclo, a cada 6h). Fechar = rejeitado.
EOF
)"
gh_pr() { gh pr create --repo "$REPO_SLUG" --base main --head "$BRANCH" \
  --title "post: $SLUG ($FORMATO_LABEL, $PILAR)" --body "$BODY"; }
PR_URL="$(retry "gh pr create" -- gh_pr)" || abort "gh pr create falhou"

# ===== 11. Histórico + volta pra main =====
STEP="histórico"
jq -nc --arg d "$TODAY" --arg s "$SLUG" --arg p "$PILAR" --arg t "$TITLE" --arg ti "$TEMA_ID" \
  '{date:$d, slug:$s, pillar:$p, title:$t, tema_id:($ti | if . == "" then null else . end)}' >> "$HIST"
git checkout -q main
log "PR aberto: $PR_URL"

# ===== 12. Avisar no WhatsApp (não-fatal) =====
STEP="avisar WhatsApp"
notify_wa "$(printf '\xF0\x9F\x93\xB2 *Novo post pra aprovar*\n%s (%s \xC2\xB7 %s)\nAgendado: %s\n\nRevisar e dar merge: %s' \
  "$SLUG" "$FORMATO_LABEL" "$PILAR" "$SCHED" "$PR_URL")"

log "=== fim ==="
