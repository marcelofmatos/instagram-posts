# Spec — Template v3 (fundo que ilustra a ideia)

- **Data:** 2026-06-19
- **Autor:** Marcelo Matos (via brainstorming assistido)
- **Status:** aprovada para virar plano de implementação
- **Repo:** `marcelofmatos/instagram-posts`

## 1. Contexto

A arte dos posts é renderizada por `renderer/render.mjs` (Chromium headless →
PNG 1080×1350), que preenche um template HTML escolhido por `POST_TEMPLATE`
(`render.mjs` lê `process.env.POST_TEMPLATE || 'template.html'`). Hoje existem:

- `template.html` (**v1**): fundo cósmico (base `#0a0617`, glows ciano/roxo,
  gradiente azul→roxo, grid sutil).
- `template-v2.html` (**v2**, default atual do pipeline): eyebrow em **chip**, **barra
  de acento** sobre o título e **CTA em pílula** — fundo mais sóbrio que o v1.

O conteúdo vem do `claude -p`, que grava `conteudo.json` (array de lâminas) e
`meta.json`. Cada lâmina hoje tem: `num`, `eyebrow`, `title`, **um** de
`body`/`bullets`/`steps`, e `cta`.

## 2. Objetivo

Criar o **template v3**: um fundo que **ilustra a ideia** de cada lâmina, mantendo a
**legibilidade no thumbnail do grid** (prioridade da marca) e a regra **Docker-first**
(sem dependência/serviço externo novo).

Direção escolhida (no brainstorming): **fundo abstrato on-brand gerado no próprio
template** (não foto, não imagem externa) + um **ícone temático (emoji) por lâmina**,
escolhido pelo claude. Paleta: a do **template-v1** (que carrega a identidade da marca
e do site `marcelomatos.dev`).

### 2.1 In scope
- Novo `renderer/template-v3.html` = **fundo cósmico do v1** + **layout do v2** +
  um **ícone temático** (emoji) grande e apagado por lâmina.
- Campo novo **`bg`** (1 emoji) por lâmina no `conteudo.json`, escolhido pelo claude.
- `render.mjs` injeta esse emoji no template (placeholder `{{BG_ICON}}`).
- v3 vira o **default** do pipeline (`POST_TEMPLATE`), com v1/v2 ainda acessíveis.

### 2.2 Out of scope (YAGNI)
- Imagens fotográficas ou geradas por IA (API de imagem) — descartado por
  legibilidade, custo e dependência.
- Mudar a estratégia de conteúdo, o prompt além do campo `bg`, ou o fluxo n8n.

> O **ícone primário** vem do claude por lâmina (`bg`). Existe um **mapa por pilar**
> apenas como **fallback** quando o claude omite `bg` (ver §4.1) — não é a fonte primária.

## 3. Decisões (fechadas no brainstorming)

| Tema | Decisão | Motivo |
|------|---------|--------|
| Direção do fundo | Abstrato on-brand gerado no template (opção "C") | Legibilidade + Docker-first |
| Paleta | A do template-v1 (`#0a0617` + ciano `#2fcfe9` + roxo `#7b3aec` + gradiente `#46a0f0`→`#a85cf2` + glows) | Identidade da marca/site |
| Layout | Reusa o do v2 (chip, barra de acento, CTA pílula) | Já validado, legível no thumbnail |
| Ícone | **Emoji por lâmina**, escolhido pelo claude | "Ilustra a ideia" de cada lâmina |
| Fonte do ícone | Campo `bg` no `conteudo.json` | Mínima mudança; claude já gera JSON |
| Ausência de `bg` | Renderiza o fundo cósmico, ícone relativo ao pillar | Retrocompatível; nunca quebra |

## 4. Arquitetura

Sem novos componentes/serviços. O Chromium da imagem já tem
`fonts-noto-color-emoji`, então o emoji renderiza sem dependência nova.

### 4.1 Contrato de dados (`conteudo.json`)

Cada lâmina ganha um campo **opcional** `bg` = **uma** string de emoji que ilustra a
ideia daquela lâmina:

```json
[
  { "num": 1, "eyebrow": "DOR", "title": "5 min sem resposta e o cliente já foi",
    "body": "…", "cta": "Arrasta →", "bg": "⏱️" },
  { "num": 2, "eyebrow": "EDUCAÇÃO", "title": "3 sistemas e nenhum conversa",
    "bullets": [{ "ic": "🧩", "text": "…" }], "cta": "Arrasta →", "bg": "🧩" }
]
```

- `bg` é **opcional**. Ausente/inválido → `render.mjs` aplica um **ícone de fallback
  por pilar** (fundo cósmico mantido); nunca quebra.
- **Mapa de fallback por pilar:** `dor`→⚠️, `antes-depois`→🔄, `educacao`→💡,
  `prova`→📊 (ajustável). O `render.mjs` recebe o pilar via env **`POST_PILLAR`**
  (exportado pelo `gerar-post.sh`, que já o calcula). Pilar desconhecido → sem ícone.
- A validação `jq` do `gerar-post.sh` **não** passa a exigir `bg` (segue exigindo
  `num`/`eyebrow`/`title`).

### 4.2 Render (`render.mjs`)

Mudança **aditiva**: para cada lâmina, além dos placeholders atuais
(`{{EYEBROW}}`, `{{TITLE}}`, `{{CONTENT}}`, `{{CTA}}`, `{{PROGRESS}}`), substitui
`{{BG_ICON}}` por `slide.bg` ou, se ausente, pelo emoji de fallback do pilar (mapa de
`POST_PILLAR`; ver §4.1). Templates que não usam `{{BG_ICON}}` (v1/v2) ficam
inalterados — retrocompatível.

### 4.3 Template (`template-v3.html`)

- **Fundo** (camadas, z-index baixo): base `#0a0617`; glows radiais ciano
  (`rgba(29,147,184,.40)` topo-direita) e roxo (`rgba(123,58,236,.42)` topo-esquerda,
  `.30` base); grid `rgba(255,255,255,~.14)`; tudo herdado do v1.
- **Ícone** `{{BG_ICON}}`: emoji grande (~130–150px no canvas 1080×1350), opacidade
  **~0.12–0.15**, posicionado num canto (ex.: direita), atrás do conteúdo (acima do
  fundo, abaixo do texto). O `render.mjs` já resolve `bg`→fallback do pilar; só fica
  vazio se nem `bg` nem o pilar derem ícone (degrada sem quebrar).
- **Conteúdo** (z-index alto): eyebrow chip, barra de acento (gradiente
  `#46a0f0`→`#a85cf2`), título (branco, `text-shadow` forte), `{{CONTENT}}`, CTA pílula
  (gradiente roxo `#8b4bff`→`#6a28d8`) — herdado do v2.
- Mesmos placeholders do v2 **+** `{{BG_ICON}}`. Mesmas fontes vendorizadas.

### 4.4 Prompt (`prompt-criar-post.md`)

Acrescenta a instrução: cada item de `conteudo.json` deve incluir `bg` = **1 emoji**
que ilustre a ideia daquela lâmina (sem texto, só o emoji). Sem outras mudanças de
estratégia/legenda.

### 4.5 Pipeline (`gerar-post.sh`)

Troca o default: `export POST_TEMPLATE="${POST_TEMPLATE:-template-v3.html}"` e exporta
`export POST_PILLAR="$PILAR"` (para o fallback de ícone do `render.mjs`). Continua
sobreponível por env (v1/v2 acessíveis para comparação/rollback).

## 5. Legibilidade (prioridade)

- Ícone sempre em opacidade baixa e fora do bloco central do título.
- Título com `text-shadow` (herdado do v2) para destacar sobre o fundo.
- Critério de aceite visual: o **título permanece legível no thumbnail** (~1/3 do
  tamanho) em todas as lâminas, com e sem ícone.

## 6. Verificação / testes

- **Render com `bg`:** `conteudo.json` de exemplo com `bg` em cada lâmina →
  `render.mjs` (POST_TEMPLATE=template-v3.html) gera PNGs **1080×1350**.
- **Fallback por pilar:** lâmina **sem** `bg` (com `POST_PILLAR` setado) renderiza com
  o emoji de fallback do pilar (fundo cósmico mantido); v1/v2 continuam renderizando
  igual (placeholder `{{BG_ICON}}` não os afeta).
- **A/B visual:** mesma `conteudo.json` em v2 e v3 produz PNGs diferentes, ambos
  1080×1350.
- **No container:** o render do v3 roda na imagem (Chromium + emoji) e o
  `gerar-post.sh --dry` produz a arte v3 em `/data/out`.

## 7. Layout de arquivos (entregável)

```
renderer/
  template-v3.html     # novo (v1 bg + v2 layout + {{BG_ICON}})
  render.mjs           # + suporte a {{BG_ICON}} (slide.bg)
scheduler/
  prompt-criar-post.md # + campo bg por lâmina
  gerar-post.sh        # default POST_TEMPLATE=template-v3.html
docs/superpowers/specs/
  2026-06-19-template-v3-design.md
```

## 8. Riscos / pontos de atenção

- **Divergência da skill:** `render.mjs`/`prompt`/templates são vendorizados; a skill
  `marcelomatos-instagram-post` pode evoluir em paralelo. Documentar que o v3 vive no
  repo; ressincronizar manualmente quando necessário (não automatizado).
- **Emoji inconsistente entre plataformas:** a renderização usa
  `fonts-noto-color-emoji` no container — o resultado é o emoji estilo Noto, estável e
  igual em toda execução.
- **Claude omitir `bg`:** tratado pelo fallback de ícone por pilar (via `POST_PILLAR`),
  não fatal.
