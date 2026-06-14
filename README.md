# instagram-posts

Fila pública de posts do **@marcelomatos.dev**. Cada post = `slug.png` + `slug.json` (mesmo nome).

- `posts-queue/aprovacao/` — aguardando aprovação
- `posts-queue/aprovado/` — liberado; o n8n publica no horário. O campo `published_at` no JSON marca o que já foi publicado (e evita republicar).

Exemplo de `slug.json`:

```json
{
  "scheduled_for": "2026-07-07T09:00:00-03:00",
  "pillar": "dor",
  "caption": "🤖 Legenda completa...\n\n#automacao #pequenaempresa #saopaulo",
  "ig_media_id": null,
  "published_at": null
}
```

**NUNCA** commitar tokens/segredos aqui — repositório é público. Os segredos ficam só no n8n.
