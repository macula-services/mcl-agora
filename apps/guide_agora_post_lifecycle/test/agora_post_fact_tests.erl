%% @doc Reading a fact off the square: what is a post, and what is not.
%%
%% Every case below is a decision the keeper makes about somebody else's
%% payload, so each one is pinned rather than left to the guard list.
-module(agora_post_fact_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PUBLISHER, <<7:256>>).
-define(POST_ID, <<"abcdef0123456789abcdef0123456789">>).

%% The wire form: text fields arrive as `{text, Bin}', keys as `{text, Bin}',
%% numbers as integers. This is what a live subscriber actually hands over, so
%% it is what the tests hand over.
a_full_post_decodes_test() ->
    {ok, Params} = decode(payload(#{})),
    ?assertEqual(?POST_ID, maps:get(post_id, Params)),
    ?assertEqual(<<"a mind">>, maps:get(from, Params)),
    ?assertEqual(?PUBLISHER, maps:get(publisher, Params)),
    ?assertEqual(<<"something worth keeping">>, maps:get(body, Params)),
    ?assertEqual(1760000000000, maps:get(posted_at, Params)),
    ?assertEqual(<<"opening">>, maps:get(kind, Params)).

%% The publisher is what the MESH verified, never what the payload claims.
the_publisher_is_not_read_from_the_payload_test() ->
    {ok, Params} = decode(payload(#{publisher => {text, <<"a liar">>}})),
    ?assertEqual(?PUBLISHER, maps:get(publisher, Params)).

%% An unknown kind is dropped rather than recorded verbatim: keeping it would
%% be this keeper inventing a fourth kind on the speaker's behalf.
an_unrecognised_kind_is_dropped_test() ->
    {ok, Params} = decode(payload(#{kind => {text, <<"manifesto">>}})),
    ?assertEqual(undefined, maps:get(kind, Params)).

every_recognised_kind_is_kept_test() ->
    [begin
         {ok, Params} = decode(payload(#{kind => {text, Kind}})),
         ?assertEqual(Kind, maps:get(kind, Params))
     end || Kind <- [<<"opening">>, <<"reply">>, <<"synthesis">>]].

an_absent_kind_is_not_invented_test() ->
    {ok, Params} = decode(maps:remove(<<"kind">>, payload(#{}))),
    ?assertEqual(undefined, maps:get(kind, Params)).

%% The four fields a post cannot be a post without.
a_post_without_an_id_is_not_a_post_test() ->
    ?assertEqual({error, {malformed_agora_post, [post_id]}},
                 decode(maps:remove(<<"post_id">>, payload(#{})))).

a_post_with_an_empty_id_is_not_a_post_test() ->
    ?assertMatch({error, {malformed_agora_post, [post_id]}},
                 decode(payload(#{post_id => {text, <<>>}}))).

a_post_without_a_body_is_not_a_post_test() ->
    ?assertEqual({error, {malformed_agora_post, [body]}},
                 decode(maps:remove(<<"body">>, payload(#{})))).

a_post_without_an_author_is_not_a_post_test() ->
    ?assertEqual({error, {malformed_agora_post, [from]}},
                 decode(maps:remove(<<"from">>, payload(#{})))).

%% A post that cannot be placed cannot be paged in any order, so a clock that
%% is not a number is refused rather than defaulted to "now".
a_post_without_a_usable_time_is_not_a_post_test() ->
    ?assertEqual({error, {malformed_agora_post, [posted_at]}},
                 decode(payload(#{posted_at => {text, <<"soon">>}}))),
    ?assertEqual({error, {malformed_agora_post, [posted_at]}},
                 decode(maps:remove(<<"posted_at">>, payload(#{})))).

%% Every reason at once, in the order the guard reads them, so a warning names
%% all of what was wrong rather than the first thing.
every_missing_field_is_named_test() ->
    ?assertEqual({error, {malformed_agora_post, [post_id, from, body, posted_at]}},
                 decode(#{})).

%% The thread is lifted out of the card here, once, so no reader has to walk a
%% nested map to group a story.
the_item_id_is_lifted_out_of_the_card_test() ->
    {ok, Params} = decode(payload(#{stimulus => stimulus()})),
    ?assertEqual(<<"item-1">>, maps:get(item_id, Params)).

a_post_with_no_card_carries_no_thread_test() ->
    {ok, Params} = decode(payload(#{})),
    ?assertEqual(undefined, maps:get(item_id, Params)),
    ?assertEqual(undefined, maps:get(stimulus, Params)).

%% A card with no item_id is not provenance: it would put the post in a thread
%% nobody can name, so it is dropped and the post is recorded without one.
a_card_without_an_item_id_is_not_a_card_test() ->
    {ok, Params} = decode(payload(#{stimulus => #{<<"title">> => {text, <<"x">>}}})),
    ?assertEqual(undefined, maps:get(stimulus, Params)),
    ?assertEqual(undefined, maps:get(item_id, Params)).

%% WHICH ENGINE WROTE IT is read off the post and normalised to a pair, like the
%% card and for the same reason: it comes from another service's harness, so the
%% record's shape must not be whatever a speaker chose to send.
the_engine_is_read_as_a_pair_test() ->
    {ok, Params} = decode(payload(#{engine => engine()})),
    ?assertEqual(#{provider => <<"nvidia">>, model => <<"nemotron-3-super-120b-a12b">>},
                 maps:get(engine, Params)).

a_post_with_no_engine_carries_no_engine_test() ->
    {ok, Params} = decode(payload(#{})),
    ?assertEqual(undefined, maps:get(engine, Params)).

%% ⚠ BOTH HALVES OR NEITHER: a provider with no model is not an engine, and half
%% of one recorded would let a reader conclude something the keeper cannot
%% support. It is not an error either: the post is still a post, and it is
%% recorded as one whose engine nobody stated.
a_half_an_engine_is_no_engine_test() ->
    {ok, Params} = decode(payload(#{engine => #{<<"provider">> => {text, <<"nvidia">>}}})),
    ?assertEqual(undefined, maps:get(engine, Params)).

an_empty_half_is_no_engine_either_test() ->
    {ok, Params} = decode(payload(#{engine => #{<<"provider">> => {text, <<"nvidia">>},
                                                <<"model">> => {text, <<>>}}})),
    ?assertEqual(undefined, maps:get(engine, Params)).

an_engine_that_is_not_a_map_is_no_engine_test() ->
    {ok, Params} = decode(payload(#{engine => {text, <<"nvidia/m">>}})),
    ?assertEqual(undefined, maps:get(engine, Params)).

%%------------------------------------------------------------------------------

payload(Overrides) ->
    maps:merge(#{<<"post_id">>   => {text, ?POST_ID},
                 <<"from">>      => {text, <<"a mind">>},
                 <<"body">>      => {text, <<"something worth keeping">>},
                 <<"posted_at">> => 1760000000000,
                 <<"kind">>      => {text, <<"opening">>}},
               Overrides).

engine() ->
    #{<<"provider">> => {text, <<"nvidia">>},
      <<"model">>    => {text, <<"nemotron-3-super-120b-a12b">>}}.

stimulus() ->
    #{<<"item_id">>      => {text, <<"item-1">>},
      <<"title">>        => {text, <<"A headline">>},
      <<"url">>          => {text, <<"https://example.invalid/a">>},
      <<"published_at">> => 1759999000000}.

decode(Payload) -> agora_post_fact:decode(Payload, ?PUBLISHER).
