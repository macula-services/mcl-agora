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
                      ?assertEqual(#{recorded => 1, duplicates => 0, refused => 0},
                                   state(heard()))
                  end).

%% THE REPEAT. The store already holds this post_id, the aggregate refused it,
%% and the keeper says nothing about it beyond the count.
a_repeat_is_counted_and_nothing_else_happens_test() ->
    with_dispatch({ok, 1, []},
                  fun() ->
                      ?assertEqual(#{recorded => 0, duplicates => 1, refused => 0},
                                   state(heard()))
                  end).

%% A post the store could not write is not a post that happened, so it is not
%% counted as recorded.
a_refused_write_is_not_counted_as_recorded_test() ->
    with_dispatch({error, no_store},
                  fun() ->
                      ?assertEqual(#{recorded => 0, duplicates => 0, refused => 1},
                                   state(heard()))
                  end).

%% A fact the mesh could not attribute is dropped before any command exists: it
%% would otherwise reach the record with nothing set beside the author it
%% claims, which is the one thing the record must never hold.
an_unverified_publisher_is_dropped_test() ->
    ?assertEqual(#{recorded => 0, duplicates => 0, refused => 1},
                 state(?LISTENER:handle_event(topic(), payload(), unverified_meta(), fresh()))).

a_fact_with_no_publisher_at_all_is_dropped_test() ->
    ?assertEqual(#{recorded => 0, duplicates => 0, refused => 1},
                 state(?LISTENER:handle_event(topic(), payload(), #{}, fresh()))).

a_payload_that_is_not_a_map_is_dropped_test() ->
    ?assertEqual(#{recorded => 0, duplicates => 0, refused => 1},
                 state(?LISTENER:handle_event(topic(), <<"not a post">>, meta(), fresh()))).

%% A malformed fact is dropped BEFORE any dispatch, so nothing reaches the
%% store. If this ever dispatched, a bad payload would be written down.
a_malformed_post_is_dropped_without_dispatching_test() ->
    meck:new(maybe_record_agora_post, [passthrough, no_link]),
    try
        _ = state(?LISTENER:handle_event(topic(), payload(#{<<"body">> => {text, <<>>}}),
                                       meta(), fresh())),
        ?assertEqual(0, meck:num_calls(maybe_record_agora_post, dispatch, 1))
    after
        meck:unload(maybe_record_agora_post)
    end.

%%------------------------------------------------------------------------------

heard() ->
    ?LISTENER:handle_event(topic(), payload(), meta(), fresh()).

fresh() -> #{recorded => 0, duplicates => 0, refused => 0}.

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
with_dispatch(Outcome, Body) ->
    meck:new(maybe_record_agora_post, [passthrough, no_link]),
    meck:expect(maybe_record_agora_post, dispatch, 1, Outcome),
    try
        Body()
    after
        meck:unload(maybe_record_agora_post)
    end.
