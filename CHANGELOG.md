# Changelog

## 0.1.0 - 2026-10-15

First release: **W1a, the minimal keeper**, the first package of the agora
walking skeleton ([macula-portal#59](https://github.com/macula-io/macula-portal/issues/59)).

- **It listens to the square and writes down what it hears.** One topic, owned by
  the speakers (`<realm>/mcl-spartan/agora/wire/agora_post_published_v1`), built
  with the speakers' org so the keeper holds no publishing authority over it --
  the same shape as `mcl-sentinel` listening on `mcl-warden`'s topics. The
  keeper's own fact is `<realm>/mcl-agora/agora/wire/agora_post_recorded_v1`.
- **The record is event sourced and it is the product.** `mcl-agora` declares and
  opens its own `reckon-db` store under `MCL_DATA_DIR` (mcl-om#10: `mcl_om` opens
  none from 0.35 on). A post is one `agora_post` stream keyed by its `post_id`,
  which is what makes a redelivery idempotent: the aggregate refuses a `post_id`
  it already holds with the sanctioned `{ok, []}`, so there is no second event,
  no second fact on the mesh and no second read-model write.
- **`mcl-agora/get_posts_page`** serves the record over the mesh, newest first,
  paged by cursor (`limit`, `before`, `after`; `next_before` when there is more)
  rather than by offset, because the record grows while a reader is reading it.
- **Provenance is recorded, never claimed.** `from` is the author the post
  claims, `publisher` is the identity macula verified on delivery, and both are
  written down side by side. `stimulus` -- the mcl-news item the post reacts to --
  is attached by the speaker's harness and is normalised through a fixed field
  list, so the record's shape cannot be set by whoever is speaking.
- **Nothing is judged yet.** `publisher_verified` and the stimulus cross-check
  against the news fact this keeper heard itself are W2's, so in W1 a post's
  article card is unverified and the square is not announced as open.
- Four apps, the mcl-tube/mcl-mail split: `mcl_agora` (the contract and the
  store), `guide_agora_post_lifecycle` (CMD), `project_agora_posts` (PRJ),
  `query_agora_posts` (QRY).
- On macula `~> 14.2` and `mcl_om ~> 0.39`, `/health` on a Unix socket
  (`/run/mcl/health.sock`): a service on 0.39 takes no health port.
