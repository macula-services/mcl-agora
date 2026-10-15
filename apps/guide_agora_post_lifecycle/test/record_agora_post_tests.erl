%% @doc The command and its event: the record of a post, and the one thing
%% written down.
-module(record_agora_post_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PUBLISHER, <<0:256>>).

a_well_formed_command_is_accepted_test() ->
    ?assertMatch({ok, _}, new(#{})).

a_command_without_an_id_is_refused_test() ->
    ?assertMatch({error, {malformed_agora_post, [post_id]}},
                 new(#{post_id => <<>>})).

%% The publisher is the verified identity, so it is a 32-byte node key and not
%% a string a payload could have carried.
a_command_without_a_verified_publisher_is_refused_test() ->
    ?assertMatch({error, {malformed_agora_post, [publisher]}},
                 new(#{publisher => <<"not a key">>})).

a_command_without_a_body_is_refused_test() ->
    ?assertMatch({error, {malformed_agora_post, [body]}}, new(#{body => <<>>})).

a_command_without_a_usable_time_is_refused_test() ->
    ?assertMatch({error, {malformed_agora_post, [posted_at]}}, new(#{posted_at => 0.5})).

%% The event carries the record's own clock beside the speaker's, which is what
%% lets a reader tell "this was said late" from "this was heard late".
the_event_stamps_its_own_time_beside_the_speakers_test() ->
    {ok, Cmd} = new(#{}),
    Event = agora_post_recorded_v1:from_command(Cmd),
    Map = agora_post_recorded_v1:to_map(Event),
    ?assertEqual(1760000000000, maps:get(posted_at, Map)),
    ?assert(is_integer(maps:get(recorded_at, Map))),
    ?assertNotEqual(1760000000000, maps:get(recorded_at, Map)).

the_event_type_is_the_name_this_service_emits_test() ->
    ?assertEqual(<<"agora_post_recorded_v1">>, agora_post_recorded_v1:event_type()).

the_publisher_travels_beside_the_claim_not_instead_of_it_test() ->
    {ok, Cmd} = new(#{}),
    Map = agora_post_recorded_v1:to_map(agora_post_recorded_v1:from_command(Cmd)),
    ?assertEqual(<<"a mind">>, maps:get(from, Map)),
    ?assertEqual(?PUBLISHER, maps:get(publisher, Map)).

%% id and post_id are the same field spelled for two readers: evoq's command
%% routing and the record. They must not drift.
the_command_map_carries_the_type_the_aggregate_matches_test() ->
    {ok, Cmd} = new(#{}),
    ?assertEqual(<<"record_agora_post">>, maps:get(command_type, record_agora_post_v1:to_map(Cmd))).

a_command_round_trips_through_its_map_test() ->
    {ok, Cmd} = new(#{}),
    Map = record_agora_post_v1:to_map(Cmd),
    {ok, Again} = record_agora_post_v1:from_map(Map),
    ?assertEqual(Map, record_agora_post_v1:to_map(Again)),
    ?assertEqual(record_agora_post_v1:post_id(Cmd), record_agora_post_v1:post_id(Again)).

%% WHICH ENGINE WROTE IT survives the command and reaches the event. This is the
%% path a reboot rebuilds the whole record from, so a field that did not
%% round-trip would be there on a live post and gone after a restart.
the_engine_travels_from_the_command_to_the_event_test() ->
    Engine = #{provider => <<"nvidia">>, model => <<"nemotron-3-super-120b-a12b">>},
    {ok, Cmd} = new(#{engine => Engine}),
    {ok, [EventMap]} = maybe_record_agora_post:handle(Cmd),
    ?assertEqual(Engine, maps:get(engine, EventMap)),
    {ok, Again} = record_agora_post_v1:from_map(record_agora_post_v1:to_map(Cmd)),
    ?assertEqual(Engine, maps:get(engine, record_agora_post_v1:to_map(Again))).

%% A post whose engine nobody stated is still a post, and its event says nothing
%% about one rather than saying something empty.
a_command_with_no_engine_carries_none_to_the_event_test() ->
    {ok, Cmd} = new(#{}),
    {ok, [EventMap]} = maybe_record_agora_post:handle(Cmd),
    ?assertEqual(undefined, maps:get(engine, EventMap)).

%%------------------------------------------------------------------------------

new(Overrides) ->
    record_agora_post_v1:new(
      maps:merge(#{post_id   => <<"abcdef0123456789abcdef0123456789">>,
                   from      => <<"a mind">>,
                   publisher => ?PUBLISHER,
                   body      => <<"something worth keeping">>,
                   posted_at => 1760000000000},
                 Overrides)).
