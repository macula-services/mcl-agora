%% @doc The query and its wire wrapper.
%%
%% The page itself is the store's, tested there; what is decided here is the
%% limit, the cursor and what the caller receives.
-module(get_posts_page_tests).

-include_lib("eunit/include/eunit.hrl").

-define(RECORD, [{"p1", 100}, {"p2", 200}, {"p3", 300}]).

-define(PUBLISHER, <<0:256>>).

page_test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             [fun a_page_is_newest_first/0,
              fun a_full_page_hands_back_a_cursor/0,
              fun the_cursor_walks_the_record_once/0,
              fun a_short_page_omits_the_cursor/0,
              fun an_empty_record_is_an_empty_page_not_an_error/0,
              fun an_absent_limit_is_the_default/0,
              fun an_unusable_limit_is_the_default/0,
              fun a_huge_limit_is_capped/0,
              fun the_reply_is_tagged_for_the_wire/0,
              fun the_reply_omits_the_cursor_when_there_is_none/0,
              fun a_request_that_is_not_a_map_is_refused/0,
              fun a_string_limit_is_not_a_number/0]
     end}.

start() ->
    clear(),
    {ok, Pid} = project_agora_posts_store:start_link(),
    ok = write_record(),
    Pid.

stop(Pid) ->
    %% gen_server:stop, not a shutdown exit: the test process is LINKED to the
    %% store, so a non-normal exit would take the test down with it and eunit
    %% would report the group cancelled.
    _ = catch gen_server:stop(Pid),
    clear().

clear() ->
    catch gen_server:stop(project_agora_posts_store),
    catch ets:delete(agora_posts),
    catch ets:delete(agora_posts_by_id),
    ok.

write_record() ->
    [ok = project_agora_posts_store:put_post(post_id(Post), row(Post)) || Post <- ?RECORD],
    ok.

a_page_is_newest_first() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(answer(#{limit => 3}))).

a_full_page_hands_back_a_cursor() ->
    ?assertEqual(300, maps:get(next_before, answer(#{limit => 1}))).

%% Following the cursor to the end visits every post exactly once, and the
%% walk TERMINATES -- which it can only do because the last page carries no
%% cursor. A sentinel there would loop forever.
the_cursor_walks_the_record_once() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], walk(undefined, [])).

a_short_page_omits_the_cursor() ->
    ?assertEqual(undefined, maps:get(next_before, answer(#{limit => 5}))).

%% "Nothing has been said" is an answer, not a failure.
an_empty_record_is_an_empty_page_not_an_error() ->
    Result = answer(#{limit => 5, before => 100}),
    ?assertEqual([], maps:get(posts, Result)),
    ?assertEqual(undefined, maps:get(next_before, Result)).

an_absent_limit_is_the_default() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(answer(#{}))).

an_unusable_limit_is_the_default() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(answer(#{limit => 0}))),
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(answer(#{limit => -3}))).

a_huge_limit_is_capped() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(answer(#{limit => 100000}))).

%% Text goes out tagged, so a consumer outside the BEAM gets a string; the node
%% id goes out in hex so it can be compared with one already held.
the_reply_is_tagged_for_the_wire() ->
    Reply = responder(#{<<"limit">> => 1}),
    ?assertEqual(1, maps:get(ok, Reply)),
    [Post] = maps:get(posts, Reply),
    ?assertEqual({text, <<"a mind">>}, maps:get(from, Post)),
    ?assertEqual({text, <<"something worth keeping">>}, maps:get(body, Post)),
    ?assertEqual({text, binary:copy(<<"00">>, 32)}, maps:get(publisher, Post)).

%% OMITTED, not sent as a sentinel: a caller cannot tell a sentinel timestamp
%% from a real one, so sending one would loop it forever.
the_reply_omits_the_cursor_when_there_is_none() ->
    Reply = responder(#{<<"limit">> => 5}),
    ?assertEqual(false, maps:is_key(next_before, Reply)).

a_request_that_is_not_a_map_is_refused() ->
    {reply, Reply, _} = get_posts_page_responder:handle_request(<<"nonsense">>, undefined),
    ?assertEqual(#{ok => 0, error => <<"bad_request">>}, Reply).

%% A caller who sent the number as text meant something this desk does not have
%% to guess at, so it is treated as absent and the default applies.
a_string_limit_is_not_a_number() ->
    ?assertEqual(3, length(maps:get(posts, responder(#{<<"limit">> => {text, <<"2">>}})))).

%%------------------------------------------------------------------------------

answer(Request) -> get_posts_page:get(Request).

responder(Args) ->
    {reply, Reply, _} = get_posts_page_responder:handle_request(Args, undefined),
    Reply.

ids(Result) -> [maps:get(post_id, P) || P <- maps:get(posts, Result)].

walk(Before, Acc) ->
    Result = answer(filters(Before)),
    walk_on(maps:get(next_before, Result), Acc ++ ids(Result)).

walk_on(undefined, Acc) -> Acc;
walk_on(Next, Acc)      -> walk(Next, Acc).

filters(undefined) -> #{limit => 1};
filters(Before)    -> #{limit => 1, before => Before}.

post_id({Id, _At}) -> list_to_binary(Id).

row({Id, PostedAt}) ->
    #{post_id     => post_id({Id, PostedAt}),
      from        => <<"a mind">>,
      publisher   => ?PUBLISHER,
      body        => <<"something worth keeping">>,
      posted_at   => PostedAt,
      recorded_at => PostedAt}.
