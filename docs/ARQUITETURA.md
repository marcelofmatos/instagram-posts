# Arquitetura — Gerador de Posts v2 (Docker)

Stack local (mbm6) em `~/docker/instagram-post-generator/`. Substitui o scheduler
em bash no cron do host. Detalhe completo na spec
`docs/superpowers/specs/2026-06-19-instagram-post-generator-v2-docker-design.md`.

## Componentes

```mermaid
flowchart TB
    subgraph host["Host mbm6"]
        ofelia["ofelia (sidecar)<br/>agenda job-exec"]
        gen["generator (idle)<br/>node+chromium+gh+claude"]
        subgraph vols["Volumes"]
            repo[("ig-repo /repo")]
            state[("ig-state /data")]
        end
        claudeauth[["~/.claude (rw)"]]
        claudecfg[["~/.claude.json (ro, seed)"]]
        ghauth[["~/.config/gh (rw)"]]
    end
    ofelia -- "job-exec (SCHEDULE)" --> gen
    gen --> repo
    gen --> state
    gen -. token .-> claudeauth
    gen -. config seed .-> claudecfg
    gen -. push/PR .-> ghauth
    gen -- "claude -p" --> anthropic["API Claude"]
    gen -- "push + PR" --> github["GitHub"]
    gen -- "webhook" --> n8n["n8n"]
    n8n -- "publica posts-queue/" --> ig["Instagram"]
```

## Fluxo de um post

```mermaid
sequenceDiagram
    autonumber
    participant O as ofelia
    participant G as gerar-post.sh
    participant C as claude -p
    participant R as render.mjs
    participant GH as GitHub
    participant WA as WhatsApp
    O->>G: dispara (job-exec)
    G->>G: flock (skip se já rodando)
    G->>G: checkout main + pull [retry]
    G->>C: prompt -> conteudo/meta.json [retry + timeout]
    G->>G: valida (jq)
    G->>R: render -> PNG 1080x1350
    G->>GH: branch + push + PR [retry]
    G->>WA: aviso de sucesso
    Note over G,WA: falha em qualquer passo -> trap envia alerta e sai ≠0
```
