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

# seed_claude_config: copia o seed quando o config ainda não existe
tmp_home="$(mktemp -d)"; seed_file="$(mktemp)"; echo '{"x":1}' > "$seed_file"
HOME="$tmp_home" CLAUDE_SEED="$seed_file" seed_claude_config
check "seed copia config ausente" '{"x":1}' "$(cat "$tmp_home/.claude.json" 2>/dev/null)"

# seed_claude_config: NÃO sobrescreve um config já existente
echo '{"keep":1}' > "$tmp_home/.claude.json"
HOME="$tmp_home" CLAUDE_SEED="$seed_file" seed_claude_config
check "seed não sobrescreve existente" '{"keep":1}' "$(cat "$tmp_home/.claude.json" 2>/dev/null)"

# setup_gh_auth: semeia hosts.yml em GH_CONFIG_DIR a partir do token montado
tmp_h="$(mktemp -d)"; mkdir -p "$tmp_h/.config/gh"; echo "TOKENXYZ" > "$tmp_h/.config/gh/oauth.token"
tmp_cfg="$(mktemp -d)"
HOME="$tmp_h" GH_CONFIG_DIR="$tmp_cfg" GH_USER="someuser" setup_gh_auth
check "gh auth seed cria hosts.yml" "1" "$([ -f "$tmp_cfg/hosts.yml" ] && echo 1 || echo 0)"
check "gh auth seed inclui o token" "1" "$(grep -c 'TOKENXYZ' "$tmp_cfg/hosts.yml" 2>/dev/null)"

# setup_gh_auth: no-op quando não há token montado
tmp_h2="$(mktemp -d)"; tmp_cfg2="$(mktemp -d)"
HOME="$tmp_h2" GH_CONFIG_DIR="$tmp_cfg2" setup_gh_auth
check "gh auth seed no-op sem token" "0" "$([ -f "$tmp_cfg2/hosts.yml" ] && echo 1 || echo 0)"

rm -rf "$tmp_ready" "$tmp_home" "$seed_file" "$tmp_h" "$tmp_cfg" "$tmp_h2" "$tmp_cfg2"
[ "$fails" -eq 0 ] && echo "TODOS OS TESTES PASSARAM" || { echo "$fails teste(s) falharam"; exit 1; }
