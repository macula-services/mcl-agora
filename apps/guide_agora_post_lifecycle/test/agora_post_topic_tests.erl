%% @doc The two topics and the realm check.
-module(agora_post_topic_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<"io.macula">>).

%% The keeper's whole reason for holding no publishing authority over the
%% square is that the square is not under its org. This is that claim, stated
%% as a test rather than as a comment.
the_square_belongs_to_the_speakers_and_the_record_to_the_keeper_test() ->
    {ok, Square} = macula_topic:parse(square_topic()),
    {ok, Record} = macula_topic:parse(record_topic()),
    ?assertNotEqual(maps:get(org, Square), maps:get(org, Record)),
    ?assertEqual(<<"mcl-agora">>, maps:get(org, Record)),
    ?assertEqual(<<"mcl-spartan">>, maps:get(org, Square)).

both_topics_are_canonical_app_facts_test() ->
    ?assertEqual(ok, macula_topic:validate(square_topic())),
    ?assertEqual(ok, macula_topic:validate(record_topic())).

%% Spelled out, because these two binaries are the contract: a change to
%% either is a change to what every peer must listen on or publish to, and it
%% should be impossible to make one by accident.
the_topics_are_the_paths_the_readme_states_test() ->
    ?assertEqual(<<"io.macula/mcl-spartan/agora/wire/agora_post_published_v1">>,
                 square_topic()),
    ?assertEqual(<<"io.macula/mcl-agora/agora/wire/agora_post_recorded_v1">>,
                 record_topic()).

%% Both, not just the one it publishes: a segment that is not canonical hashes
%% right and then fails every fact, at publish time rather than at boot.
check_realm_name_accepts_the_matching_name_test() ->
    Tag = crypto:hash(sha256, ?REALM),
    ?assertEqual(ok, agora_post_topic:check_realm_name(?REALM, Tag)).

check_realm_name_refuses_a_mismatch_test() ->
    Tag = crypto:hash(sha256, <<"some.other.realm">>),
    ?assertError({mcl_agora_realm_name_mismatch, ?REALM, Tag},
                 agora_post_topic:check_realm_name(?REALM, Tag)).

%%------------------------------------------------------------------------------

square_topic() -> agora_post_topic:square_topic(?REALM).
record_topic() -> agora_post_topic:record_topic(?REALM).
