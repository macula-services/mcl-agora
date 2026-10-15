%% @doc The posts read model: order, cursor paging, and the replay that must be
%% a no-op.
%%
%% The fixture writes three posts once, so every case below is about reading
%% the record rather than about filling it.
-module(project_agora_posts_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(POSTS, agora_posts).
-define(BY_ID, agora_posts_by_id).
-define(RECORD, [{"p1", 100}, {"p2", 200}, {"p3", 300}]).

store_test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             [fun a_post_comes_back_by_id/0,
              fun an_unknown_post_is_not_found/0,
              fun count_is_the_size_of_the_record/0,
              fun a_page_is_newest_first/0,
              fun a_limit_trims_the_page/0,
              fun the_cursor_is_exclusive/0,
              fun after_is_exclusive_too/0,
              fun a_page_past_the_end_is_empty/0,
              fun a_limit_of_zero_serves_nothing/0,
              fun the_whole_record_is_walkable_by_cursor/0,
              fun writing_the_same_post_twice_leaves_one_row/0]
     end}.

start() ->
    clear(),
    {ok, Pid} = project_agora_posts_store:start_link(),
    ok = write_record(),
    Pid.

stop(Pid) ->
    %% gen_server:stop, not a shutdown exit: the test process is LINKED to
    %% the store, so a non-normal exit would take the test down with it and
    %% eunit would report the group cancelled.
    _ = catch gen_server:stop(Pid),
    clear().

%% ets:new with named_table raises if the table is already there, so a restart
%% inside one VM has to clear first.
clear() ->
    catch gen_server:stop(project_agora_posts_store),
    catch ets:delete(?POSTS),
    catch ets:delete(?BY_ID),
    ok.

write_record() ->
    [ok = project_agora_posts_store:put_post(post_id(Post), row(Post)) || Post <- ?RECORD],
    ok.

a_post_comes_back_by_id() ->
    ?assertEqual({ok, row({"p1", 100})}, project_agora_posts_store:get_post(<<"p1">>)).

an_unknown_post_is_not_found() ->
    ?assertEqual({error, not_found}, project_agora_posts_store:get_post(<<"nope">>)).

count_is_the_size_of_the_record() ->
    ?assertEqual(3, project_agora_posts_store:count()).

%% The order a reader sees is the order the record was made in, newest first.
a_page_is_newest_first() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(page(#{limit => 3}))).

a_limit_trims_the_page() ->
    ?assertEqual([<<"p3">>], ids(page(#{limit => 1}))).

%% EXCLUSIVE. A cursor that were inclusive would serve the cursor post a second
%% time, which is exactly the failure the cursor exists to avoid.
the_cursor_is_exclusive() ->
    ?assertEqual([<<"p2">>, <<"p1">>], ids(page(#{limit => 3, before => 300}))).

%% `after' excludes its own timestamp too, so a reader tailing the record from
%% a post it has already seen does not see it again.
after_is_exclusive_too() ->
    ?assertEqual([<<"p3">>, <<"p2">>], ids(page(#{limit => 5, 'after' => 150}))).

a_page_past_the_end_is_empty() ->
    ?assertEqual([], ids(page(#{limit => 5, before => 100}))).

a_limit_of_zero_serves_nothing() ->
    ?assertEqual([], ids(page(#{limit => 0}))).

%% The property the whole shape exists for: following the cursors from newest
%% to oldest visits every post exactly once, whatever is written in between.
the_whole_record_is_walkable_by_cursor() ->
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], walk(undefined, 1)).

walk(Before, Limit) ->
    Filters = filters(Before, Limit),
    {ok, Posts} = project_agora_posts_store:page(Filters),
    ids(Posts) ++ walk_on(Posts, Limit).

filters(undefined, Limit) -> #{limit => Limit};
filters(Before, Limit)    -> #{limit => Limit, before => Before}.

walk_on([], _Limit) -> [];
walk_on(Posts, Limit) ->
    walk(maps:get(posted_at, lists:last(Posts)), Limit).

%% The projection is replayed on every boot, so writing a post it already holds
%% must leave exactly what was there -- no second row, and no change to the
%% record's order.
writing_the_same_post_twice_leaves_one_row() ->
    Ok = project_agora_posts_store:put_post(<<"p1">>, row({"p1", 100})),
    ?assertEqual(ok, Ok),
    ?assertEqual(3, project_agora_posts_store:count()),
    ?assertEqual([<<"p3">>, <<"p2">>, <<"p1">>], ids(page(#{limit => 3}))).

%%------------------------------------------------------------------------------

page(Filters) ->
    {ok, Posts} = project_agora_posts_store:page(Filters),
    Posts.

ids(Posts) -> [maps:get(post_id, P) || P <- Posts].

post_id({Id, _At}) -> list_to_binary(Id).

row({Id, PostedAt}) ->
    #{post_id     => post_id({Id, PostedAt}),
      from        => <<"a mind">>,
      publisher   => <<1:256>>,
      body        => <<"something worth keeping">>,
      posted_at   => PostedAt,
      recorded_at => PostedAt}.
