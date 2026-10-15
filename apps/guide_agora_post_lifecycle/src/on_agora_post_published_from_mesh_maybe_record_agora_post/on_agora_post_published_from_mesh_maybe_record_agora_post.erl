%%% @doc Hears the square, and writes down what it heard.
%%%
%%% The ONE place a fact from outside becomes a command, and therefore the one
%%% place the keeper's input is decided. Everything downstream -- the aggregate,
%%% the store, the projection, the emitter -- works from a command that already
%%% passed through here.
%%%
%%% IT DECIDES ALMOST NOTHING. Who wrote it is not decided: `publisher' is the
%%% identity macula verified on delivery, never a field the payload claims, and
%%% macula drops a publication whose signature did not verify unless a
%%% deployment has explicitly turned that off -- so a card the keeper holds can
%%% always be set beside it. What the post is about is not decided either: the
%%% card is attached by the speaker's harness, normalised against a fixed field
%%% list and recorded as received.
%%%
%%% What it does decide is whether there is a post at all: a fact with no
%%% usable post_id, from, body or posted_at is logged and dropped, because a
%%% post with no id cannot be deduplicated and a post with no body is not
%%% speech. A refusal is a WARNING naming the fields, not an error: the topic
%%% carries one fact shape, so anything else is a producer whose contract
%%% moved, which is a thing to be told about rather than to crash on.
%%%
%%% A REPEAT IS NOT AN ERROR HERE EITHER. It reaches the aggregate, which has
%%% already recorded that post_id and answers the sanctioned no-op, so the
%%% keeper counts it and says nothing. That is where idempotency lives, so a
%%% redelivery is a non-event no matter how the subscriber is restarted.
-module(on_agora_post_published_from_mesh_maybe_record_agora_post).

-behaviour(macula_subscriber).

-export([init/1, handle_event/4]).

%% What the listener has heard since boot: how many facts became posts, how
%% many were repeats, and how many were dropped. It is the subscriber's own
%% record of itself — the thing that makes "the keeper recorded nothing today"
%% answerable at all — and the tests read it, which is why the three paths
%% above are pinned rather than merely exercised.
init(_Args) ->
    {ok, #{recorded => 0, duplicates => 0, refused => 0}}.

-spec handle_event(binary(), term(), map(), map()) -> {noreply, map()}.
handle_event(_Topic, Payload, Meta, State) when is_map(Payload), is_map(Meta) ->
    {noreply, heard(decoded(Payload, Meta), State)};
handle_event(_Topic, Payload, _Meta, State) ->
    {noreply, warning({not_a_map, Payload}, State)}.

%% Only a post the mesh could attribute is worth recording: `publisher' is the
%% node id macula verified, and a fact that arrived without one has nothing to
%% set beside the author it claims.
decoded(Payload, Meta) ->
    attributed(Meta, Payload).

attributed(#{publisher := Publisher, publisher_verified := true}, Payload)
  when is_binary(Publisher), byte_size(Publisher) =:= 32 ->
    agora_post_fact:decode(Payload, Publisher);
attributed(_Unverified, _Payload) ->
    {error, unverified_publisher}.

heard({ok, Command}, State) ->
    recorded(maybe_record_agora_post:dispatch(Command), State);
heard({error, Reason}, State) ->
    warning(Reason, State).

%% The aggregate refused a post_id it already holds: no second event, no second
%% recorded fact, no second read-model write. Counted, not logged per fact.
recorded({ok, _Version, [_ | _]}, State) ->
    tally(recorded, State);
recorded({ok, _Version, []}, State) ->
    tally(duplicates, State);
recorded({error, Reason}, State) ->
    warning(Reason, State).

%% The fact never became a command: nothing was dispatched, so there is no
%% outcome to report beyond the reason.
warning(Reason, State) ->
    logger:warning("[agora] dropped a fact on the square: ~p", [Reason]),
    tally(refused, State).

tally(Key, State) ->
    maps:update_with(Key, fun(N) -> N + 1 end, 1, State).
