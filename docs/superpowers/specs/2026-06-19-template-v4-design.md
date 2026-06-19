# Spec — Template v4 (foto ilustrativa de fundo, via Pexels)

- **Data:** 2026-06-19
- **Autor:** Marcelo Matos (via brainstorming assistido)
- **Status:** aprovada para virar plano de implementação
- **Repo:** `marcelofmatos/instagram-posts`

## 1. Contexto

A arte é renderizada por `renderer/render.mjs` (Chromium → PNG 1080×1350), que
preenche o template escolhido por `POST_TEMPLATE`. Templates existentes:
`template.html` (v1), `template-v2.html` (v2, layout chip/barra/pílula),
`template-v3.html` (v3 = v2 + **ícone temático de fundo** por lâmina, campo `bg`).

O conteúdo vem do `claude -p` no `conteudo.json` (array de lâminas); cada lâmina hoje
tem `num`, `eyebrow`, `title`, um de `body`/`bullets`/`steps`, `cta`, `bg` (emoji).

## 2. Objetivo

Criar o **template v4**: usar uma **foto ilustrativa de fundo** (de banco) por lâmina,
que ilustra a ideia, mantendo a **legibilidade no thumbnail** (scrim escuro) e a regra
**Docker-first**. Quando não houver foto, **cai no emoji do v3 (fallback)**.

Decisões fechadas no brainstorming:
- **Fonte:** **Pexels** (chave grátis; **sem exigência de atribuição**).
- **Tratamento:** **A** — foto full-bleed + **scrim escuro** (sem duotone de marca).
- **Granularidade:** **por lâmina** (cada lâmina tem sua foto).
- **Fallback:** o **emoji** do canto (template-v3), quando não há foto.

### 2.1 In scope
- `renderer/template-v4.html` = layout v3/v2 + camada de foto + scrim + emoji-fallback.
- Campo novo **`query`** (keywords em inglês p/ o Pexels) por lâmina no `conteudo.json`.
- `gerar-post.sh` busca/baixa 1 foto **portrait** por lâmina do Pexels (`PEXELS_API_KEY`).
- `render.mjs` compõe foto+scrim quando a foto existe; senão usa o emoji (`bg`).
- v4 vira o **default** (`POST_TEMPLATE`); imagem nova **1.2.0** + `latest`.

### 2.2 Out of scope (YAGNI)
- IA generativa de imagem.
- Duotone/recolor da marca (tratamentos B/C do brainstorming).
- Atribuição/crédito (Pexels não exige).
- Mudar estratégia de conteúdo/legenda/n8n.

## 3. Decisões (tabela)

| Tema | Decisão | Motivo |
|------|---------|--------|
| Fonte da foto | Pexels (`/v1/search`) | Grátis, sem atribuição, API simples |
| Tratamento | A (foto + scrim escuro) | Legibilidade sem perder a foto |
| Keyword | `query` por lâmina, gerada pelo claude (inglês) | Busca de banco funciona melhor em inglês |
| Orientação | `orientation=portrait` | Casa com 1080×1350 (4:5) |
| Sem foto | Fallback: emoji do canto (v3) | Nunca quebra; degrada com elegância |
| Onde busca | `gerar-post.sh` (curl no container) | Docker-first; mesmo padrão do webhook |
| Versão | imagem 1.2.0 (MINOR) | Feature retrocompatível |

## 4. Arquitetura

Sem novo serviço. A busca é um `curl` à API do Pexels de dentro do container (mesmo
padrão do webhook do WhatsApp). Nova credencial: `PEXELS_API_KEY` no `.env` (grátis).

### 4.1 Contrato de dados (`conteudo.json`)

Cada lâmina ganha um campo **opcional** `query` = **keywords em inglês** (2–4 palavras)
de uma foto que ilustra a ideia daquela lâmina. Mantém o `bg` (emoji de fallback):

```json
[
  { "num": 1, "eyebrow": "DOR", "title": "5 min sem resposta e o cliente já foi",
    "body": "…", "cta": "Arrasta →", "bg": "⏱️", "query": "frustrated customer waiting phone" },
  { "num": 2, "eyebrow": "EDUCAÇÃO", "title": "3 sistemas e nenhum conversa",
    "bullets": [{ "ic": "🧩", "text": "…" }], "cta": "Arrasta →", "bg": "🧩", "query": "disconnected computer systems dark" }
]
```

- `query` é **opcional**. Ausente → sem busca → fallback emoji.
- A validação `jq` do `gerar-post.sh` **não** passa a exigir `query`/`bg`.

### 4.2 Busca da foto (`gerar-post.sh`, novo passo entre validar JSON e renderizar)

Para cada lâmina `i` (1..NSLIDES):
1. `query="$(jq -r ".[i-1].query // empty" conteudo.json)"`. Vazio → pula (emoji).
2. Se `PEXELS_API_KEY` setado e `query` não vazio: `curl` em
   `https://api.pexels.com/v1/search?orientation=portrait&per_page=1&query=<urlenc>`
   com header `Authorization: $PEXELS_API_KEY` (envolto em `retry`).
3. Extrai a URL: `jq -r '.photos[0].src.portrait // .photos[0].src.large // empty'`.
   Vazio → pula (emoji).
4. Baixa a foto: `curl -fsSL "<url>" -o "$OUT/img-0i.jpg"` (envolto em `retry`).
5. **Não-fatal:** qualquer falha (sem chave, sem resultado, erro de rede, download
   falho) → não cria `img-0i.jpg` → o render usa o emoji daquela lâmina.

### 4.3 Render (`render.mjs`)

Para cada lâmina, render.mjs decide a camada de fundo:
- Se `existsSync(<outdir>/img-<num>.jpg)` → preenche `{{PHOTO_LAYER}}` com
  `<div class="photo" style="background-image:url(file://…/img-0i.jpg)"></div>` +
  o scrim; o `{{BG_ICON}}` daquela lâmina fica vazio (`''`) para não competir.
- Senão → `{{PHOTO_LAYER}}` vazio e `{{BG_ICON}}` = `bg`/fallback por pilar (lógica v3).
- Templates sem `{{PHOTO_LAYER}}` (v1/v2/v3) ficam inalterados (replace no-op) —
  retrocompatível.

### 4.4 Template (`template-v4.html`)

Cópia do `template-v3.html` + a camada de foto, abaixo do conteúdo:
- `{{PHOTO_LAYER}}` logo após `<div class="canvas">` (z-index baixo, acima do fundo
  cósmico): a `.photo` cobre o canvas (`position:absolute;inset:0;background-size:cover;
  background-position:center`), e o `.scrim` é um gradiente escuro por cima
  (ex.: `linear-gradient(180deg, rgba(10,6,23,.35) 0%, rgba(10,6,23,.72) 55%,
  rgba(10,6,23,.93) 100%)`) — tratamento A.
- Mantém o `.bgicon`/`{{BG_ICON}}` (fallback) e todo o layout do v3.
- **Ordem de empilhamento (z-index) — exata:** fundo cósmico (base) < `.bgicon`
  (emoji) `z-index:0` < `.photo` e `.scrim` `z-index:1` < conteúdo `.canvas>*`
  `z-index:2`. Ou seja, o v4 **eleva o conteúdo para `z-index:2`** (no v2/v3 era 1) e
  coloca foto/scrim em 1, para o texto ficar sempre acima da foto e o emoji (0) só
  aparecer quando não há foto.

### 4.5 Prompt (`prompt-criar-post.md`)

Acrescenta: cada item do `conteudo.json` inclui `query` = **2–4 palavras-chave em
inglês** descrevendo uma foto que ilustra a lâmina (ex.: "automation workflow dark",
"developer working laptop night"). Manter o `bg` (emoji de fallback). Sem outras
mudanças de estratégia.

### 4.6 Pipeline (`gerar-post.sh`)

- Novo passo de busca (§4.2) entre "validar JSON" e "renderizar".
- Troca o default: `export POST_TEMPLATE="${POST_TEMPLATE:-template-v4.html}"`.
- `POST_PILLAR` continua exportado (fallback de emoji do v3 segue valendo).

## 5. Configuração / versão

- `.env`: **`PEXELS_API_KEY`** (chave grátis do Pexels). Ausente → 100% emoji (não quebra).
- `template-v4.html` é o default; `POST_TEMPLATE` ainda alterna v1/v2/v3/v4.
- Imagem **`1.2.0`** + `latest` (1.1.0=v3 emoji, 1.0.0=v2 para rollback).

## 6. Legibilidade (prioridade)

- Scrim escuro garante contraste do título/eyebrow/CTA sobre qualquer foto.
- `text-shadow` no título (herdado). Critério: título legível no **thumbnail** com
  foto e com emoji.

## 7. Verificação / testes

- **render com foto:** colocar um `img-01.jpg` em OUT + `conteudo.json` → render.mjs
  (POST_TEMPLATE=template-v4.html) compõe foto+scrim, 1080×1350; o emoji não aparece.
- **render sem foto:** sem `img-01.jpg` → cai no emoji (lógica v3), 1080×1350.
- **retrocompat:** v1/v2/v3 renderizam igual (replace de `{{PHOTO_LAYER}}` é no-op).
- **busca Pexels:** com `PEXELS_API_KEY`, uma `query` baixa `img-01.jpg` (verificar o
  parse do JSON e o download); sem chave/sem resultado, não baixa (não-fatal).
- **A/B v3 vs v4:** mesma `conteudo.json` (com `query`) → PNGs diferentes.
- **dry-run no container:** o claude emite `query`+`bg`; a stack baixa as fotos e
  renderiza a arte v4 em `/data/out`.

## 8. Layout de arquivos (entregável)

```
renderer/
  template-v4.html     # novo (v3 + camada de foto + scrim)
  render.mjs           # + {{PHOTO_LAYER}} (foto+scrim se img-<num>.jpg existir)
scheduler/
  prompt-criar-post.md # + campo query por lâmina
  gerar-post.sh        # busca Pexels por lâmina + default template-v4
docs/superpowers/specs/
  2026-06-19-template-v4-design.md
```
Stack (`~/docker/instagram-post-generator/`, não versionado): `.env` ganha
`PEXELS_API_KEY`; README documenta a chave e a versão 1.2.0.

## 9. Riscos / pontos de atenção

- **Rate limit do Pexels** (~200/h): um carrossel usa ≤6 buscas/run — folgado.
- **Foto fora de contexto/feia:** risco inerente a banco por keyword; o scrim ajuda, e
  o `query` em inglês melhora o acerto. Tuning do scrim é possível depois.
- **Chave ausente/ inválida:** degrada para emoji (não-fatal); a chave **nunca** entra
  em commit/imagem/log (só no `.env`, gitignored e fora do build).
- **Legibilidade com foto clara:** o scrim do tratamento A é forte; se algum tema ficar
  ruim, ajustar opacidade do scrim (não bloqueia esta entrega).
- **Divergência da skill:** render.mjs/prompt/templates são vendorizados; ressincronizar
  manualmente quando a skill evoluir.
