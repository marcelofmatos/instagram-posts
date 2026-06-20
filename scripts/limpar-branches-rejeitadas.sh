#!/usr/bin/env bash
# Apaga as branches `post/*` das PRs FECHADAS-NÃO-MERGEADAS (rejeitadas) do repo.
# PRs mergeadas (aprovadas) já apagam a branch sozinhas (delete_branch_on_merge=true);
# o GitHub NÃO auto-apaga branch quando o PR é só fechado — este script faz isso.
#
# Idempotente: branch que já não existe é ignorada. Nunca toca em PR aberta/mergeada.
# Requer `gh` autenticado. Uso: limpar-branches-rejeitadas.sh [owner/repo]
set -euo pipefail
REPO="${1:-marcelofmatos/instagram-posts}"

mapfile -t branches < <(
  gh pr list --repo "$REPO" --state closed --limit 200 \
    --json headRefName,mergedAt \
    --jq '.[] | select(.mergedAt == null) | .headRefName'
)

if [ "${#branches[@]}" -eq 0 ]; then
  echo "Nenhuma PR rejeitada encontrada em $REPO."
  exit 0
fi

apagadas=0
for b in "${branches[@]}"; do
  [ -n "$b" ] || continue
  if gh api -X DELETE "repos/$REPO/git/refs/heads/$b" >/dev/null 2>&1; then
    echo "✓ apagada: $b"
    apagadas=$((apagadas + 1))
  else
    echo "· já não existia: $b"
  fi
done
echo "Pronto: $apagadas branch(es) apagada(s) de PRs rejeitadas em $REPO."
