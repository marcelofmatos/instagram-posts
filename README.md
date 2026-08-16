# Marcelo Matos · Dev & IA — @marcelomatos.dev

> Automatizo o trabalho manual da sua empresa: **sistemas, integrações e chatbots sob medida**.
> Menos tarefa repetitiva, mais tempo pro que importa.

## 👋 Quem sou
Desenvolvedor há 15+ anos. Sou o **braço de TI que sua empresa precisa**:
tiro do papel, deixo rodando e fico de olho pra não te dar dor de cabeça.

## ⚙️ O que eu resolvo
- Automação de processos (o carro-chefe)
- Integrações entre sistemas que você já usa
- Chatbots e agentes de IA que atendem 24h
- DevOps e infraestrutura em nuvem

## 📲 Diagnóstico de automação **grátis**
Tem uma tarefa manual consumindo o tempo da equipe? Fala comigo:
- Instagram: [@marcelomatos.dev](https://instagram.com/marcelomatos.dev)
- WhatsApp: [wa.me/5511977974431](https://wa.me/5511977974431?text=Quero%20meu%20diagn%C3%B3stico%20de%20automa%C3%A7%C3%A3o)

---
## Automação dos posts
Os posts deste feed são gerados por uma stack Docker (v2). Ver
[`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

---
## Pautas inspiradas em posts salvos

Além do banco fixo de 20 pautas (`scheduler/pautas.json`), o Marcelo pode colar links de posts
que salvou no Instagram (guardados numa sala Matrix pessoal — não integrada automaticamente)
diretamente numa sessão com o Claude. O fluxo, seguido interativamente:

1. Pra cada link colado, checar `scheduler/historico-links-inspiracao.ndjson` — se já processado, pular.
2. Abrir o link (página pública do post) e ler legenda + imagem.
3. Extrair só o **ângulo/insight** — nunca a frase ou o caso exato do post original. Se não der pra
   gerar algo honesto sem citar o original, descartar o link.
4. Escrever uma pauta nova no formato de `pautas.json` (`id/pilar/tema/gancho/caso`), com
   `tema: "inspirado"`, usando um caso real do Marcelo (`../../MEUS_SERVICOS.md`) quando o ângulo
   mapear pra algo que ele já fez, ou uma reflexão genérica do nicho quando não mapear.
5. Adicionar a pauta a `scheduler/pautas.json` e registrar `{date, url, pauta_id}` em
   `scheduler/historico-links-inspiracao.ndjson`.
6. Commitar. A pauta nova entra automaticamente no rodízio existente (`escolher_tema`,
   `scheduler/lib.sh`) — nenhuma mudança de código necessária.

Ver spec: `docs/superpowers/specs/2026-08-16-pautas-inspiradas-salvos-design.md`.

