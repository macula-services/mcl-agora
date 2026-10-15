%%% @doc Hears the square, and writes down what it heard.
%%%
%%% The ONE place a fact from outside becomes a command, and therefore the one
%%% place the keeper's input is decided. Everything downstream -- the aggregate,
%%% the store, the projection, the emitter -- works from a command that already
%%% passed through here.
%%%
%%% WHO MAY SPEAK IS DECIDED HERE, BEFORE ANYTHING IS WRITTEN. `publisher' is
%%% the identity macula verified on delivery, never a field the payload claims.
%%% But macula verifies who signed, not who may publish on the square, so the
%%% keeper asks the realm whether that publisher is an admitted speaker
%%% (`mcl_om:org_member/2' with the speakers' org):
%%%
%%%   a speaker            recorded with `publisher_verified => 1'
%%%   not a speaker        refused and counted, never written down: a stranger
%%%                        cannot fill the keeper's disk, and because this is
%%%                        decided before the aggregate, cannot claim a post_id
%%%                        first either
%%%   could not find out   recorded with `publisher_verified => 0', which the
%%%                        page does not show; a real post heard during a
%%%                        lookup failure stays hidden, which fails safe
%%%
%%% WHETHER THE CARD IS REAL IS DECIDED HERE TOO, once, at the moment the post
%%% is heard: `stimulus_verified' is 1 only when the card matches the item the
%%% keeper heard mcl-news report itself (`heard_news_items'). The verdict is
%%% written down with the post, so a replay never decides it again.
%%%
%%% What it does decide besides is whether there is a post at all: a fact with
%%% no usable post_id, from, body or posted_at is logged and dropped, because a
%%% post with no id cannot be deduplicated and a post with no body is not
%%% speech. A refusal is a WARNING naming the fields, not an error: the topic
%%% carries one fact shape, so anything else is a producer whose contract
%%% moved, which is a thing to be told about rather than to crash on. A
%%% stranger's fact is only counted: its volume is the stranger's to choose.
%%%
%%% A REPEAT IS NOT AN ERROR HERE EITHER. It reaches the aggregate, which has
%%% already recorded that post_id and answers the sanctioned no-op, so the
%%% keeper counts it and says nothing. That is where idempotency lives, so a
%%% redelivery is a non-event no matter how the subscriber is restarted. A
%%% repeat with a different body is a contradiction: the aggregate writes it
%%% down, the keeper logs it as an error and counts it.
-module(on_agora_post_published_from_mesh_maybe_record_agora_post).

-behaviour(macula_subscriber).

-export([init/1, handle_event/4]).

%% What the listener has heard since boot: how many facts became posts, how
%% many were repeats, and how many were dropped. It is the subscriber's own
%% record of itself, the thing that makes "the keeper recorded nothing today"
%% answerable at all, and the tests read it, which is why the three paths
%% above are pinned rather than merely exercised.
init(_Args) ->
    {ok, #{recorded => 0, duplicates => 0, refused => 0, not_a_speaker => 0, conflicts => 0}}.

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
    spoken(mcl_om:org_member(agora_post_topic:speakers(), Publisher), Payload, Publisher);
attributed(_Unverified, _Payload) ->
    {error, unverified_publisher}.

spoken({ok, _ExpiresAt}, Payload, Publisher) ->
    judged(agora_post_fact:decode(Payload, Publisher), 1);
spoken({error, {unavailable, _}}, Payload, Publisher) ->
    judged(agora_post_fact:decode(Payload, Publisher), 0);
spoken({error, {not_a_member, _}}, _Payload, _Publisher) ->
    not_a_speaker.

judged({ok, Params}, PublisherVerified) ->
    {ok, Params#{publisher_verified => PublisherVerified,
                 stimulus_verified => card_verified(maps:get(stimulus, Params, undefined))}};
judged({error, _} = Refused, _PublisherVerified) ->
    Refused.

card_verified(undefined) ->
    undefined;
card_verified(Card) ->
    agora_post_stimulus:verified(Card, heard_news_items:heard(agora_post_stimulus:item_id(Card))).

heard({ok, Command}, State) ->
    recorded(maybe_record_agora_post:dispatch(Command), State);
heard(not_a_speaker, State) ->
    tally(not_a_speaker, State);
heard({error, Reason}, State) ->
    warning(Reason, State).

%% The aggregate refused a post_id it already holds: no second event, no second
%% recorded fact, no second read-model write. Counted, not logged per fact.
recorded({ok, _Version, [#{event_type := <<"agora_post_conflict_detected_v1">>} = Conflict]}, State) ->
    logger:error("[agora] contradiction: post ~s arrived with a different body than the one "
                 "on record; keeping the first", [maps:get(post_id, Conflict)]),
    tally(conflicts, State);
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
