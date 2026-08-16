#!/usr/bin/env bash
# Funções puras do scheduler + helper de retry. Sem efeitos colaterais.

# pilar_do_dia <1..7>  (1=segunda ... 7=domingo, conforme `date +%u`)
pilar_do_dia() {
  case "$1" in
    1) echo "dor" ;;
    2) echo "antes-depois" ;;
    3) echo "educacao" ;;
    4) echo "prova" ;;
    5) echo "dor" ;;
    *) echo "dor" ;;   # fim de semana não roda no cron; fallback seguro
  esac
}

# slugify <texto>  -> kebab-case ascii, só [a-z0-9-]
slugify() {
  echo "$1" \
    | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# proximo_horario_publicacao [<ref>]  -> ISO do próximo slot de publicação (-03:00).
# Slots = os horários em que o n8n publica: 12:00 (manhã) e 19:00 (tarde).
# Mesmo dia se ainda houver slot no futuro; senão, 12:00 do dia seguinte (literal,
# sem pular fim de semana). <ref> = data/hora de referência (default: agora).
proximo_horario_publicacao() {
  local ref="${1:-now}" hm dia
  hm="$(date -d "$ref" +%H%M)"
  dia="$(date -d "$ref" +%Y-%m-%d)"
  if [ "$((10#$hm))" -lt 1200 ]; then
    echo "${dia}T12:00:00-03:00"
  elif [ "$((10#$hm))" -lt 1900 ]; then
    echo "${dia}T19:00:00-03:00"
  else
    echo "$(date -d "$ref + 1 day" +%Y-%m-%d)T12:00:00-03:00"
  fi
}

# temas_recentes <arquivo_ndjson> <n>  -> títulos das últimas n linhas
temas_recentes() {
  local arq="$1" n="${2:-10}"
  [ -f "$arq" ] || return 0
  tail -n "$n" "$arq" | jq -r '.title' 2>/dev/null || true
}

# retry <descrição> -- <comando...>  -> re-tenta com backoff exponencial.
# Config por env: RETRY_MAX (default 3), RETRY_BASE_SECONDS (default 5).
retry() {
  local desc="$1"; shift
  [ "${1:-}" = "--" ] && shift
  local n=1 max="${RETRY_MAX:-3}" base="${RETRY_BASE_SECONDS:-5}"
  while :; do
    if "$@"; then return 0; fi
    if [ "$n" -ge "$max" ]; then return 1; fi
    local wait=$(( base * (2 ** (n - 1)) ))
    echo "retry: '$desc' falhou (tentativa $n/$max); aguardando ${wait}s" >&2
    sleep "$wait"
    n=$((n + 1))
  done
}

# tema_ids_recentes <historico.ndjson> <pilar> <n>  -> ids de tema (campo
# tema_id) usados nas entradas do mesmo pilar, uma por linha. Usado pra
# excluir da próxima escolha e nunca repetir a pauta imediatamente anterior
# do mesmo pilar.
tema_ids_recentes() {
  local arq="$1" pilar="$2" n="${3:-6}"
  [ -f "$arq" ] || return 0
  jq -rc --arg p "$pilar" 'select(.pillar == $p) | .tema_id // empty' "$arq" 2>/dev/null | tail -n "$n" || true
}

# escolher_tema <pautas.json> <pilar> <ids_excluidos (uma por linha)>
# -> objeto JSON da pauta escolhida. rc=1 se não houver NENHUMA pauta pro
# pilar. Se os excluídos esgotarem as opções do pilar, reaproveita o banco
# inteiro daquele pilar (nunca falha só por causa do rodízio).
escolher_tema() {
  local arq="$1" pilar="$2" excluidos="$3" excl_json disponiveis n idx
  excl_json="$(printf '%s\n' "$excluidos" | jq -R . | jq -sc 'map(select(length>0))')"
  disponiveis="$(jq -c --arg p "$pilar" --argjson ex "$excl_json" \
    '[.[] | select(.pilar == $p) | select(([.id] - $ex) == [.id])]' "$arq")"
  n="$(printf '%s' "$disponiveis" | jq 'length')"
  if [ "$n" -eq 0 ]; then
    disponiveis="$(jq -c --arg p "$pilar" '[.[] | select(.pilar == $p)]' "$arq")"
    n="$(printf '%s' "$disponiveis" | jq 'length')"
  fi
  [ "$n" -gt 0 ] || return 1
  idx=$((RANDOM % n))
  printf '%s' "$disponiveis" | jq -c --argjson i "$idx" '.[$i]'
}
