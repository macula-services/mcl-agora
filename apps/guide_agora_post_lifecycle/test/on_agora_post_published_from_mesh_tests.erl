%% @doc The listener: what the keeper does with a fact off the square.
%%
%% Where the aggregate test proves a repeat produces no event, this proves the
%% listener treats that outcome as a non-event: it counts the repeat and does
%% nothing else. No log line per duplicate, and -- the part that matters -- no
%% path from here to the mesh. The only thing that publishes a recorded fact is
%% the emitter, and the emitter reads the store, so a post the store refused
%% cannot be announced.
-module(on_agora_post_published_from_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LISTENER, on_agora_post_published_from_mesh_maybe_record_agora_post).
-define(PUBLISHER, <<3:256>>).
-define(TOPIC, <<"io.macula/mcl-spartan/agora/wire/agora_post_published_v1">>).

-define(COMMAND, #{post_id   => <<"abcdef0123456789abcdef0123456789">>,
                   from      => <<"a mind">>,
                   publisher => ?PUBLISHER,
                   body      => <<"something worth keeping">>,
                   posted_at => 1760000000000}).

a_verified_post_is_dispatched_and_counted_test() ->
    with_dispatch({ok, 1, [event()]},
                  fun() ->
                      ?assertEqual(counts(#{recorded => 1}),
                                   state(heard()))
                  end).

%% THE REPEAT. The store already holds this post_id, the aggregate refused it,
%% and the keeper says nothing about it beyond the count.
a_repeat_is_counted_and_nothing_else_happens_test() ->
    with_dispatch({ok, 1, []},
                  fun() ->
                      ?assertEqual(counts(#{duplicates => 1}),
                                   state(heard()))
                  end).

%% A post the store could not write is not a post that happened, so it is not
%% counted as recorded.
a_refused_write_is_not_counted_as_recorded_test() ->
    with_dispatch({error, no_store},
                  fun() ->
                      ?assertEqual(counts(#{refused => 1}),
                                   state(heard()))
                  end).

%% A fact the mesh could not attribute is dropped before any command exists: it
%% would otherwise reach the record with nothing set beside the author it
%% claims, which is the one thing the record must never hold.
an_unverified_publisher_is_dropped_test() ->
    ?assertEqual(counts(#{refused => 1}),
                 state(?LISTENER:handle_event(topic(), payload(), unverified_meta(), fresh()))).

a_fact_with_no_publisher_at_all_is_dropped_test() ->
    ?assertEqual(counts(#{refused => 1}),
                 state(?LISTENER:handle_event(topic(), payload(), #{}, fresh()))).

a_payload_that_is_not_a_map_is_dropped_test() ->
    ?assertEqual(counts(#{refused => 1}),
                 state(?LISTENER:handle_event(topic(), <<"not a post">>, meta(), fresh()))).

%% A malformed fact is dropped BEFORE any dispatch, so nothing reaches the
%% store. If this ever dispatched, a bad payload would be written down.
a_malformed_post_is_dropped_without_dispatching_test() ->
    with_dispatch({ok, 1, [event()]},
                  fun() ->
                      _ = state(?LISTENER:handle_event(topic(), payload(#{<<"body">> => {text, <<>>}}),
                                                     meta(), fresh())),
                      ?assertEqual(0, meck:num_calls(maybe_record_agora_post, dispatch, 1))
                  end).

%%------------------------------------------------------------------------------
%% Who may speak (W2): the realm's answer about the publisher, asked before
%% anything is written.

%% A publisher the realm says is not a speaker never reaches the store: no
%% dispatch at all, so it cannot fill the record or claim a post_id first.
a_publisher_that_is_not_a_speaker_is_never_dispatched_test() ->
    with_dispatch({ok, 1, [event()]}, {error, {not_a_member, {procedure_delegation, not_found}}},
                  fun() ->
                      ?assertEqual(counts(#{not_a_speaker => 1}), state(heard())),
                      ?assertEqual(0, meck:num_calls(maybe_record_agora_post, dispatch, 1))
                  end).

a_speaker_is_recorded_as_verified_test() ->
    with_dispatch({ok, 1, [event()]},
                  fun() ->
                      _ = heard(),
                      ?assertMatch(#{publisher_verified := 1}, dispatched())
                  end).

%% Could not find out is not a refusal: the post is written down, marked
%% unchecked, and the page does not show it.
a_speaker_that_could_not_be_checked_is_recorded_as_unchecked_test() ->
    with_dispatch({ok, 1, [event()]}, {error, {unavailable, timeout}},
                  fun() ->
                      ?assertEqual(counts(#{recorded => 1}), state(heard())),
                      ?assertMatch(#{publisher_verified := 0}, dispatched())
                  end).

%% The speaker is asked about by the org that owns the square, and the identity
%% asked about is the one macula verified, never a field in the payload.
the_speaker_check_asks_about_the_verified_publisher_test() ->
    with_dispatch({ok, 1, [event()]},
                  fun() ->
                      _ = heard(),
                      ?assert(meck:called(mcl_om, org_member, [<<"mcl-spartan">>, ?PUBLISHER]))
                  end).

%% A contradiction is counted as one, not as a record.
a_contradiction_is_counted_test() ->
    with_dispatch({ok, 2, [#{event_type => <<"agora_post_conflict_detected_v1">>,
                             post_id => maps:get(post_id, ?COMMAND)}]},
                  fun() -> ?assertEqual(counts(#{conflicts => 1}), state(heard())) end).

%%------------------------------------------------------------------------------
%% Whether the card is real (W2).

a_card_that_matches_what_the_keeper_heard_is_verified_test() ->
    with_news(fun() ->
        ok = heard_news_items:remember(<<"item-1">>, agora_post_stimulus:decode(news_item())),
        _ = state(heard_with_card(news_item())),
        ?assertMatch(#{stimulus_verified := 1}, dispatched())
    end).

a_card_with_one_field_changed_is_not_verified_test() ->
    with_news(fun() ->
        ok = heard_news_items:remember(<<"item-1">>, agora_post_stimulus:decode(news_item())),
        _ = state(heard_with_card(news_item(#{<<"title">> => {text, <<"Something that never ran">>}}))),
        ?assertMatch(#{stimulus_verified := 0}, dispatched())
    end).

a_card_for_an_item_the_keeper_never_heard_is_not_verified_test() ->
    with_news(fun() ->
        _ = state(heard_with_card(news_item())),
        ?assertMatch(#{stimulus_verified := 0}, dispatched())
    end).

a_post_with_no_card_has_no_card_verdict_test() ->
    with_news(fun() ->
        _ = heard(),
        ?assertNot(is_integer(maps:get(stimulus_verified, dispatched(), undefined)))
    end).

%%------------------------------------------------------------------------------

heard() ->
    ?LISTENER:handle_event(topic(), payload(), meta(), fresh()).

fresh() -> counts(#{}).

counts(Overrides) ->
    maps:merge(#{recorded => 0, duplicates => 0, refused => 0, not_a_speaker => 0, conflicts => 0},
               Overrides).

state({noreply, State}) -> State.

topic() -> ?TOPIC.

meta() ->
    #{publisher => ?PUBLISHER, publisher_verified => true}.

unverified_meta() ->
    #{publisher => ?PUBLISHER, publisher_verified => false}.

payload() -> payload(#{}).

payload(Overrides) ->
    maps:merge(#{<<"post_id">>   => {text, maps:get(post_id, ?COMMAND)},
                 <<"from">>      => {text, <<"a mind">>},
                 <<"body">>      => {text, <<"something worth keeping">>},
                 <<"posted_at">> => 1760000000000},
               Overrides).

event() ->
    #{event_type => <<"agora_post_recorded_v1">>, post_id => maps:get(post_id, ?COMMAND)}.

%% Stands in for the store: the listener's only seam with it is the dispatch
%% and its outcome.
%% The realm's answer about the publisher is the other seam: mcl_om asks
%% macula, and the test answers for both.
with_dispatch(Outcome, Body) ->
    with_dispatch(Outcome, {ok, 1760000000000 + 1800000}, Body).

with_dispatch(Outcome, Membership, Body) ->
    meck:new(maybe_record_agora_post, [passthrough, no_link]),
    meck:expect(maybe_record_agora_post, dispatch, 1, Outcome),
    meck:new(mcl_om, [passthrough, no_link, non_strict]),
    meck:expect(mcl_om, org_member, 2, Membership),
    try
        Body()
    after
        meck:unload(mcl_om),
        meck:unload(maybe_record_agora_post)
    end.

%% With the keeper's memory of the news running, as it is under the CMD
%% department's supervisor.
with_news(Body) ->
    {ok, Pid} = heard_news_items:start_link(),
    unlink(Pid),
    try
        with_dispatch({ok, 1, [event()]}, Body)
    after
        exit(Pid, kill),
        wait_down(Pid)
    end.

wait_down(Pid) ->
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.

%% The command the listener handed the store.
dispatched() ->
    [{_Pid, {maybe_record_agora_post, dispatch, [Command]}, _Result}] =
        meck:history(maybe_record_agora_post),
    Command.

heard_with_card(Card) ->
    ?LISTENER:handle_event(topic(), payload(#{<<"stimulus">> => Card}), meta(), fresh()).

%% An mcl-news item in the wire shape a mind attaches it in.
news_item() -> news_item(#{}).

news_item(Overrides) ->
    maps:merge(#{<<"item_id">> => {text, <<"item-1">>},
                 <<"title">> => {text, <<"A real headline">>},
                 <<"url">> => {text, <<"https://news.example/a">>},
                 <<"source">> => {text, <<"An example wire">>},
                 <<"published_at">> => 1760000000000},
               Overrides).
