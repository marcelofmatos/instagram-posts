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

# proximo_dia_util_0900 <YYYY-MM-DD>  -> ISO do PRÓXIMO dia útil às 09:00 -03:00
proximo_dia_util_0900() {
  local base="$1" d
  d="$base"
  while :; do
    d="$(date -d "$d + 1 day" +%Y-%m-%d)"
    local dow; dow="$(date -d "$d" +%u)"   # 1..7
    if [ "$dow" -le 5 ]; then break; fi    # seg..sex
  done
  echo "${d}T09:00:00-03:00"
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
