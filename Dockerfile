FROM node:20-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    REPO_DIR=/repo \
    DATA_DIR=/data \
    RENDERER_DIR=/app/renderer \
    SCHEDULER_DIR=/app/scheduler

# Toolchain: git, jq, ImageMagick, Chromium headless, fontes (incl. emoji), gh, tzdata.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git jq imagemagick chromium \
      fontconfig fonts-noto-color-emoji tzdata \
 && mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# CLI do Claude (usa a assinatura via ~/.claude montado em runtime).
RUN npm install -g @anthropic-ai/claude-code

# Usuário não-root com HOME compatível com o mount de ~/.claude.
RUN useradd -m -d /home/app -s /bin/bash app

WORKDIR /app
COPY scheduler/ /app/scheduler/
COPY renderer/ /app/renderer/
RUN chmod +x /app/scheduler/*.sh \
 && mkdir -p /repo /data \
 && chown -R app:app /app /repo /data /home/app

USER app
ENTRYPOINT ["/app/scheduler/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
