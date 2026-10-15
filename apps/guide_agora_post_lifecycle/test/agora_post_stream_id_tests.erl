%% @doc The stream id, against the thing that actually accepts or refuses it.
%%
%% THIS SUITE EXISTS BECAUSE OF A BUG THAT SHIPPED PAST 113 GREEN TESTS. The
%% first stream id was `<<"agora-post-", PostId/binary>>', which reckon-db
%% refuses on every append (`^[a-z]{1,32}-[a-f0-9]{32}$' allows one hyphen and
%% no hyphen at all in the prefix), so nothing could ever have been recorded.
%% Every test at the time meck'd the dispatch or called execute/2 directly, and
%% none of them asked the validator.
%%
%% So this does not restate the regex in a second place: it calls the real
%% reckon_gater_stream_id:validate/1, the same function reckon-db calls, for a
%% spread of post ids an actual speaker might mint.
-module(agora_post_stream_id_tests).

-include_lib("eunit/include/eunit.hrl").

%% The ids below are deliberately awkward: hex like a node id, a uuid like a
%% clip, a plain word, something with a hyphen, something with an underscore,
%% something unicode, and something very long. Deriving the suffix means the
%% keeper survives all of them, and this is where that claim is checked.
odd_post_ids() ->
    [<<"abcdef0123456789abcdef0123456789">>,
     <<"0193c0de-7a2b-7f4c-9d61-2f9b0a5c1e44">>,
     <<"opening">>,
     <<"a-mind-said-this">>,
     <<"snake_case_id">>,
     <<"een post met accenten éàü">>,
     binary:copy(<<"x">>, 4096)].

every_post_id_the_speaker_might_mint_gives_a_stream_id_reckon_db_accepts_test() ->
    [?assertEqual(ok, reckon_gater_stream_id:validate(agora_post_aggregate:stream_id(Id)))
     || Id <- odd_post_ids()],
    %% And a bare non-id, which must still be a stream id even though it is not
    %% one: validation is about the STREAM id, never about the speaker's format.
    ?assertEqual(ok, reckon_gater_stream_id:validate(agora_post_aggregate:stream_id(<<>>))).

%% It has to split back apart, because the store's structural layout keys on
%% the prefix and the suffix: exactly one hyphen is what makes that possible.
the_prefix_is_the_aggregate_and_the_suffix_is_derived_test() ->
    StreamId = agora_post_aggregate:stream_id(<<"opening">>),
    ?assertEqual(<<"agorapost">>, reckon_gater_stream_id:prefix_of(StreamId)),
    ?assertEqual(32, byte_size(reckon_gater_stream_id:suffix_of(StreamId))),
    ?assertEqual(StreamId, <<"agorapost-", (reckon_gater_stream_id:suffix_of(StreamId))/binary>>).

%% DETERMINISTIC, which is what makes a redelivery a redelivery: the same post
%% id always addresses the same stream, so the aggregate's refusal can fire.
the_same_post_id_always_gives_the_same_stream_test() ->
    Id = <<"abcdef0123456789abcdef0123456789">>,
    ?assertEqual(agora_post_aggregate:stream_id(Id), agora_post_aggregate:stream_id(Id)).

%% And different posts are different streams, or the second post would be
%% refused as a repeat of the first.
two_posts_are_two_streams_test() ->
    ?assertNotEqual(agora_post_aggregate:stream_id(<<"one">>),
                    agora_post_aggregate:stream_id(<<"two">>)).
