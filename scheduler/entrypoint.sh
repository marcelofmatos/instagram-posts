#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO_DIR:-/repo}"
DATA="${DATA_DIR:-/data}"

# bootstrap_state -> ready | clone | init  (lê REPO_DIR/REPO_GIT_URL do ambiente)
bootstrap_state() {
  local repo="${REPO_DIR:-/repo}"
  if [ -d "$repo/.git" ]; then echo "ready"; return; fi
  if git ls-remote "${REPO_GIT_URL:-}" >/dev/null 2>&1; then echo "clone"; else echo "init"; fi
}

# O gh guarda o token no keyring do host, então o ~/.config/gh montado NÃO traz o
# token. O token é entregue como arquivo (oauth.token, dentro do mount ~/.config/gh)
# e aqui materializamos um hosts.yml em GH_CONFIG_DIR (container-local, não mexe no
# config do host) para autenticar o gh — necessário para git push e gh pr create.
setup_gh_auth() {
  local tok="$HOME/.config/gh/oauth.token" dir="${GH_CONFIG_DIR:-$HOME/.config/gh}"
  [ -f "$tok" ] || return 0
  mkdir -p "$dir"
  printf 'github.com:\n    user: %s\n    oauth_token: %s\n    git_protocol: https\n' \
    "${GH_USER:-}" "$(cat "$tok")" > "$dir/hosts.yml"
  chmod 600 "$dir/hosts.yml"
}

setup_git() {
  git config --global user.name "${GIT_AUTHOR_NAME:-Marcelo Matos}"
  git config --global user.email "${GIT_AUTHOR_EMAIL:-contato@marcelomatos.dev}"
  git config --global --add safe.directory "$REPO"
  gh auth setup-git 2>/dev/null || true   # usa o token semeado por setup_gh_auth
}

rotate_logs() {
  find "$DATA/logs" -name '*.log' -type f -mtime +"${LOG_RETENTION_DAYS:-30}" -delete 2>/dev/null || true
}

# O config do claude é o arquivo ~/.claude.json (no HOME), separado do diretório
# montado ~/.claude. Ele é efêmero no container; sem ele o `claude -p` refaz o
# init de primeira execução e às vezes trava no modo não-interativo. Semeia de um
# seed read-only montado (config do host), só quando ainda não existe.
seed_claude_config() {
  local target="$HOME/.claude.json" seed="${CLAUDE_SEED:-/seed/claude.json}"
  [ -f "$target" ] && return 0
  [ -f "$seed" ] || return 0
  cp "$seed" "$target" || echo "[entrypoint] AVISO: não consegui semear $target a partir de $seed" >&2
  return 0
}

seed_repo() {  # cria repo remoto + estrutura mínima (greenfield) — ver spec §6.1
  gh repo create "$REPO_SLUG" --private --confirm 2>/dev/null || true
  mkdir -p "$REPO/posts-queue"
  git -C "$REPO" init -q
  : > "$REPO/posts-queue/.gitkeep"
  printf '# %s\n' "$REPO_SLUG" > "$REPO/README.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "init: estrutura inicial"
  git -C "$REPO" branch -M main
  git -C "$REPO" remote add origin "$REPO_GIT_URL"
  git -C "$REPO" push -qu origin main
}

main() {
  mkdir -p "$DATA/logs" "$DATA/out"
  rotate_logs
  setup_gh_auth
  setup_git
  seed_claude_config

  case "$(bootstrap_state)" in
    ready) echo "[entrypoint] repo já presente em $REPO" ;;
    clone) echo "[entrypoint] clonando $REPO_GIT_URL"; git clone "$REPO_GIT_URL" "$REPO" ;;
    init)
      if [ "${BOOTSTRAP_INIT:-0}" != "1" ]; then
        echo "[entrypoint] remoto inexistente e BOOTSTRAP_INIT!=1; abortando" >&2
        exit 1
      fi
      echo "[entrypoint] bootstrap do zero (init+seed+push)"; seed_repo ;;
  esac

  exec "$@"
}

# Só executa main() quando rodado direto (permite sourcear nos testes).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
