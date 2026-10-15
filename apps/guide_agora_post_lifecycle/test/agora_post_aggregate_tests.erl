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

%% It is the post_id and the BODY that decide, not the author or the clock: the
%% same words under the same id, whoever claims them and whenever, are one post.
a_repeat_with_the_same_body_is_refused_whatever_else_it_says_test() ->
    Other = command(#{from => <<"someone.else">>, posted_at => 9999999999999}),
    ?assertEqual({ok, []}, agora_post_aggregate:execute(recorded_stream(), Other)).

%% THE CONTRADICTION. A different body under a post_id already on the record is
%% written down as a conflict, by hashes, and the first body stays.
a_different_body_under_a_recorded_post_id_is_a_conflict_test() ->
    {ok, [Conflict]} = agora_post_aggregate:execute(recorded_stream(), different()),
    ?assertEqual(<<"agora_post_conflict_detected_v1">>, maps:get(event_type, Conflict)),
    ?assertEqual(digest(<<"the record outlives the speakers">>), maps:get(kept_body_sha256, Conflict)),
    ?assertEqual(digest(<<"something else entirely">>), maps:get(refused_body_sha256, Conflict)),
    ?assertEqual(?PUBLISHER, maps:get(kept_publisher, Conflict)),
    ?assertEqual(<<1:256>>, maps:get(refused_publisher, Conflict)),
    %% Never the refused body itself.
    ?assertNot(lists:member(<<"something else entirely">>, maps:values(Conflict))).

%% The same contradiction delivered twice is written down once.
a_contradiction_heard_again_is_a_redelivery_test() ->
    {ok, [Conflict]} = agora_post_aggregate:execute(recorded_stream(), different()),
    Conflicted = agora_post_state:apply_event(recorded_stream(), Conflict),
    ?assert(agora_post_state:conflicted(Conflicted)),
    ?assertEqual({ok, []}, agora_post_aggregate:execute(Conflicted, different())),
    %% And the original body is still a plain redelivery.
    ?assertEqual({ok, []}, execute(Conflicted)).

%% A replay hands the state the stored envelope, fields under `data' with
%% binary keys: it must come back to the same state as the live path.
a_replayed_envelope_rebuilds_the_same_state_test() ->
    {ok, [Recorded]} = execute(fresh_stream()),
    Envelope = #{event_type => <<"agora_post_recorded_v1">>,
                 data => maps:from_list([{atom_to_binary(K), V} || {K, V} <- maps:to_list(Recorded)])},
    Replayed = agora_post_state:apply_event(fresh_stream(), Envelope),
    ?assertEqual(agora_post_state:to_map(recorded_stream()), agora_post_state:to_map(Replayed)).

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
    {ok, [Recorded]} = execute(fresh_stream()),
    agora_post_state:apply_event(fresh_stream(), Recorded).

different() ->
    command(#{body => <<"something else entirely">>, publisher => <<1:256>>}).

digest(Body) ->
    binary:encode_hex(crypto:hash(sha256, Body), lowercase).

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
