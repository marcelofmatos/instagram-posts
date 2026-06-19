#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../lib.sh"

fails=0
check() { # check <descrição> <esperado> <obtido>
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FALHOU: $1 (esperado '$2', obtido '$3')"; fails=$((fails+1)); fi
}

# pilares por dia (date +%u: 1=seg..7=dom)
check "pilar seg" "dor" "$(pilar_do_dia 1)"
check "pilar ter" "antes-depois" "$(pilar_do_dia 2)"
check "pilar qua" "educacao" "$(pilar_do_dia 3)"
check "pilar qui" "prova" "$(pilar_do_dia 4)"
check "pilar sex" "dor" "$(pilar_do_dia 5)"
check "pilar dom (fallback)" "dor" "$(pilar_do_dia 7)"

# slugify (ascii — evita variação de locale no //TRANSLIT)
check "slugify simples" "mitos-automacao-pme" "$(slugify 'Mitos Automacao PME')"
check "slugify pontuação" "tres-coisas" "$(slugify 'Tres   Coisas!!!')"

# proximo_horario_publicacao: slots 12:00 (manhã) e 19:00 (tarde) do mesmo dia;
# se já passou dos dois, 12:00 do dia seguinte (literal, sem pular fim de semana).
check "antes das 12h -> manhã hoje"      "2026-06-19T12:00:00-03:00" "$(proximo_horario_publicacao '2026-06-19 09:00:00')"
check "12h em ponto -> tarde hoje"       "2026-06-19T19:00:00-03:00" "$(proximo_horario_publicacao '2026-06-19 12:00:00')"
check "à tarde -> tarde hoje"            "2026-06-19T19:00:00-03:00" "$(proximo_horario_publicacao '2026-06-19 15:30:00')"
check "19h em ponto -> manhã amanhã"     "2026-06-20T12:00:00-03:00" "$(proximo_horario_publicacao '2026-06-19 19:00:00')"
check "à noite -> manhã do dia seguinte" "2026-06-20T12:00:00-03:00" "$(proximo_horario_publicacao '2026-06-19 21:00:00')"
check "sexta à noite -> sábado (literal)" "2026-06-20T12:00:00-03:00" "$(proximo_horario_publicacao '2026-06-19 23:00:00')"

# retry: falha 1x e sucede na 2ª (sem espera)
attempts=0
flaky() { attempts=$((attempts+1)); [ "$attempts" -ge 2 ]; }
RETRY_MAX=3 RETRY_BASE_SECONDS=0 retry "flaky" -- flaky
check "retry sucede após falha" "0:2" "$?:$attempts"

# retry: esgota tentativas e retorna ≠0
attempts=0
always_fail() { attempts=$((attempts+1)); return 1; }
RETRY_MAX=2 RETRY_BASE_SECONDS=0 retry "fail" -- always_fail
rc=$?
check "retry esgota (rc≠0)" "1:2" "$([ "$rc" -ne 0 ] && echo 1 || echo 0):$attempts"

[ "$fails" -eq 0 ] && echo "TODOS OS TESTES PASSARAM" || { echo "$fails teste(s) falharam"; exit 1; }
