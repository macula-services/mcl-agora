%% @doc The aggregate: one stream per post, and the no-op that makes a repeat
%% a repeat.
%%
%% The idempotency test is the point of this file. "A new post_id is recorded,
%% a repeat is ignored" is the keeper's first rule, and where it is enforced is
%% here: the stream already holds the post, so the command is refused with the
%% sanctioned `{ok, []}' and NO event is produced -- which is what makes there
%% be no second fact on the mesh and no second row in the read model, without
%% either of those having to defend itself.
-module(agora_post_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

-define(POST_ID, <<"a1b2c3d4e5f60718293a4b5c6d7e8f90">>).
-define(PUBLISHER, <<0:256>>).

%% The stream's shape is agora_post_stream_id_tests' business. What matters
%% here is that it is a valid stream id -- the aggregate is worth nothing if
%% reckon-db refuses every append.
one_stream_per_post_id_test() ->
    StreamId = agora_post_aggregate:stream_id(?POST_ID),
    ?assertEqual(ok, reckon_gater_stream_id:validate(StreamId)),
    ?assertEqual(<<"agorapost-">>, binary:part(StreamId, 0, 10)).

a_first_post_produces_exactly_one_event_test() ->
    {ok, Events} = execute(fresh_stream()),
    ?assertEqual(1, length(Events)),
    ?assertEqual(<<"agora_post_recorded_v1">>, maps:get(event_type, hd(Events))).

%% THE IDEMPOTENCY. A redelivery -- the mesh hands the same fact over twice, a
%% subscriber reconnects mid-flight -- addresses the same stream and produces
%% nothing at all.
a_repeat_post_id_produces_no_second_event_test() ->
    Recorded = recorded_stream(),
    ?assertEqual({ok, []}, execute(Recorded)).

%% And it is the POST ID that decides, not the body or the author: the same
%% words from the same mind, sent twice, are one post.
a_repeat_is_refused_whatever_the_rest_of_the_command_says_test() ->
    Other = command(#{body => <<"something else entirely">>,
                      from => <<"someone.else">>,
                      posted_at => 9999999999999}),
    ?assertEqual({ok, []}, agora_post_aggregate:execute(recorded_stream(), Other)).

a_command_the_aggregate_does_not_know_is_refused_test() ->
    ?assertEqual({error, unknown_command},
                 agora_post_aggregate:execute(fresh_stream(), #{command_type => <<"other">>})).

%% The state's own view, so a failure above points at the right half.
the_stream_reports_a_post_as_recorded_only_after_its_event_test() ->
    ?assertNot(agora_post_state:recorded(fresh_stream())),
    ?assert(agora_post_state:recorded(recorded_stream())).

%%------------------------------------------------------------------------------

execute(State) ->
    agora_post_aggregate:execute(State, command(#{})).

fresh_stream() ->
    agora_post_state:new(?POST_ID).

recorded_stream() ->
    agora_post_state:apply_event(fresh_stream(), #{}).

%% A command as it reaches the aggregate: the flat payload evoq takes
%% `command_type' out of, with the author's claim and the verified publisher
%% both present.
command(Overrides) ->
    maps:merge(#{command_type => <<"record_agora_post">>,
                 post_id      => ?POST_ID,
                 from         => <<"did:macula:example">>,
                 publisher    => ?PUBLISHER,
                 body         => <<"the record outlives the speakers">>,
                 posted_at    => 1760000000000},
               Overrides).
