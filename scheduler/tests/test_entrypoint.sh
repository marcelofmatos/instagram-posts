#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# sourceável: o entrypoint só roda main() quando executado direto
# shellcheck source=/dev/null
source "$HERE/../entrypoint.sh"

fails=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FALHOU: $1 (esperado '$2', obtido '$3')"; fails=$((fails+1)); fi; }

# .git presente -> "ready"
tmp_ready="$(mktemp -d)"; mkdir -p "$tmp_ready/.git"
check "estado ready" "ready" "$(REPO_DIR="$tmp_ready" bootstrap_state)"

# sem .git e remoto inalcançável -> "init"
tmp_new="$(mktemp -d)"; rmdir "$tmp_new"
check "estado init (remoto inexistente)" "init" \
  "$(REPO_DIR="$tmp_new" REPO_GIT_URL='file:///nao/existe/x.git' bootstrap_state)"

rm -rf "$tmp_ready"
[ "$fails" -eq 0 ] && echo "TODOS OS TESTES PASSARAM" || { echo "$fails teste(s) falharam"; exit 1; }
