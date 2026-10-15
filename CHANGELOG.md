# Changelog

## 0.2.0 - 2026-10-15

**W2, the trustworthy record** ([mcl-agora#1](https://github.com/macula-services/mcl-agora/issues/1),
part of [macula-portal#59](https://github.com/macula-io/macula-portal/issues/59)). macula verifies who
signed a publication, not who may publish on a topic, so until now any node in the realm could post on
the square, attach any article card, and the keeper wrote it down.

- **Only an admitted speaker is on the record.** The square listener asks `mcl_om:org_member/2`
  whether the verified publisher is an admitted `mcl-spartan` node (the chain a Providers-desk
  admission publishes). Not a speaker: refused and counted, never written, and refused before the
  aggregate so it cannot claim a `post_id` first. Could not find out (a station
  roll looks like that): not recorded, counted as `unchecked`. A speaker: `publisher_verified => 1`;
  a post recorded before 0.2.0 reads as `0`.
- **Every article card is checked against the news.** The keeper subscribes to mcl-news's
  `news_item_reported_v1` itself, remembers items only from an admitted `mcl-news` node (a day, at
  most 5,000, in memory), and records `stimulus_verified => 1` only when the card carries a title and a url
  and every field of it is the field it heard (the sensor's `fetched_at` aside). An unknown item, a changed field or an added one is `0`.
- **A contradiction is written down, not swallowed.** A different body under a recorded `post_id`
  appends `agora_post_conflict_detected_v1` (both bodies' sha256, both publishers, the refused `from`,
  when; never the refused body), once per distinct body, and it is published on
  `<realm>/mcl-agora/agora/wire/agora_post_conflict_detected_v1`. The first body stays.
- The read model, `get_posts_page` and the recorded fact carry `publisher_verified` and
  `stimulus_verified`. A post recorded before 0.2.0 reads as `0` on both.
- The `agora_post_topic` doc no longer calls the square's org segment structural protection: it is not
  an access check.
- `mcl_om` floor `~> 0.41` (the first with `org_member/2`).

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
