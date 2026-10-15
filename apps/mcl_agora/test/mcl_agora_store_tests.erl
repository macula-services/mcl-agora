%% @doc The thing W1a is FOR, through a real reckon-db: a post is recorded, a
%% repeat is not, the read model gives the one row back, and the record is
%% still there after the read model is thrown away and rebuilt.
%%
%% WHY THIS SUITE EXISTS. Every other test in this repository either meck's the
%% dispatch or calls execute/2 directly, which is fast and precise and also how
%% a stream id that reckon-db refuses on every append reached a green suite of
%% 113. A meck'd dispatch cannot fail the way the real one does. So this opens
%% the same store the service opens, at the same id and directory, and
%% dispatches for real.
-module(mcl_agora_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PUBLISHER, <<7:256>>).
-define(POST_ID, <<"abcdef0123456789abcdef0123456789">>).
-define(WAIT_MS, 5000).

store_test_() ->
    {setup, fun start/0, fun stop/1,
     [{timeout, 60, fun a_post_is_recorded_and_served_back/0},
      {timeout, 60, fun a_repeat_records_nothing_and_serves_one_row/0},
      {timeout, 60, fun the_record_survives_the_read_model_being_rebuilt/0},
      {timeout, 60, fun opening_an_open_store_is_no_error/0}]}.

%% THE WHOLE POINT, IN ONE TEST: dispatch lands an event, and the read model
%% the query desk answers from holds exactly that post.
a_post_is_recorded_and_served_back() ->
    {ok, _Version, [_Event]} = dispatch(?POST_ID),
    {ok, Row} = wait_for_post(?POST_ID),
    ?assertEqual(<<"a mind">>, maps:get(from, Row)),
    ?assertEqual(<<"something worth keeping">>, maps:get(body, Row)),
    ?assertEqual(?PUBLISHER, maps:get(publisher, Row)),
    ?assertEqual(1760000000000, maps:get(posted_at, Row)).

%% IDEMPOTENT, THROUGH THE REAL STORE. The aggregate refuses the post id it
%% already holds with the sanctioned `{ok, _, []}', so no second event is
%% appended and the read model still holds one row.
a_repeat_records_nothing_and_serves_one_row() ->
    %% The version is deliberately not pinned here: what this test is about is
    %% that NO EVENT comes back, whatever version the store is at.
    ?assertMatch({ok, _Version, []}, dispatch(?POST_ID)),
    ?assertMatch({ok, _}, project_agora_posts_store:get_post(?POST_ID)),
    {ok, Posts} = project_agora_posts_store:page(#{limit => 100}),
    ?assertEqual([?POST_ID], [maps:get(post_id, P) || P <- Posts]).

%% "SURVIVES A RESTART", which is what the read model is: ETS, thrown away and
%% rebuilt from the event store on the next boot. Stopping and starting the PRJ
%% department is exactly that, and the row has to come back -- if it does not,
%% the store was never really written to and the keeper is holding nothing.
the_record_survives_the_read_model_being_rebuilt() ->
    ?assertMatch({ok, _}, project_agora_posts_store:get_post(?POST_ID)),
    ok = application:stop(project_agora_posts),
    %% The read model is genuinely gone: the store facade and its ETS tables
    %% both. Asserting this is the point -- "the row came back" means nothing
    %% if it never went away.
    ?assertEqual(undefined, whereis(project_agora_posts_store)),
    ?assertEqual(undefined, ets:info(agora_posts, size)),
    ok = application:start(project_agora_posts),
    ?assertMatch({ok, _}, wait_for_post(?POST_ID)).

%% mcl_om opens no store from 0.35 on, so nothing else proves this one opens.
opening_an_open_store_is_no_error() ->
    ?assertEqual(ok, mcl_agora_store:open(mcl_agora_service:event_store())).

%%------------------------------------------------------------------------------

dispatch(PostId) ->
    maybe_record_agora_post:dispatch(#{post_id   => PostId,
                                       from      => <<"a mind">>,
                                       publisher => ?PUBLISHER,
                                       body      => <<"something worth keeping">>,
                                       posted_at => 1760000000000}).

%% The projection is fed by the store's subscription and so runs a moment
%% behind the dispatch. Poll rather than sleep a fixed amount.
wait_for_post(PostId) ->
    wait_for_post(PostId, erlang:monotonic_time(millisecond) + ?WAIT_MS).

wait_for_post(PostId, Deadline) ->
    case project_agora_posts_store:get_post(PostId) of
        {ok, _} = Found -> Found;
        {error, not_found} = Missing -> retry(PostId, Missing, Deadline)
    end.

retry(PostId, Missing, Deadline) ->
    case erlang:monotonic_time(millisecond) > Deadline of
        true  -> Missing;
        false -> timer:sleep(50), wait_for_post(PostId, Deadline)
    end.

start() ->
    Dir = filename:join("/tmp", "mcl_agora_store_tests_" ++
                        integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    %% Test isolation, not production code: a sibling module's teardown deletes
    %% these tables, but eunit's module order is not ours to rely on, and
    %% ets:new on an existing named table raises.
    _ = catch ets:delete(agora_posts),
    _ = catch ets:delete(agora_posts_by_id),
    _ = application:load(evoq),
    [ok = application:set_env(evoq, K, V)
     || {K, V} <- [{event_store_adapter, reckon_evoq_adapter},
                   {subscription_adapter, reckon_evoq_adapter},
                   {snapshot_store_adapter, reckon_evoq_adapter},
                   {store_id, mcl_agora_store}]],
    {ok, Started} = application:ensure_all_started([reckon_db, evoq, reckon_evoq]),
    %% The departments first, then the store -- the same order the release
    %% boots in, and for the same reason: the projection must be registered
    %% before the store's subscription starts delivering.
    ok = application:start(project_agora_posts),
    #{id := Id, dir := StoreDir} = mcl_agora_service:event_store(),
    ok = mcl_agora_store:ensure(Id, StoreDir),
    {Dir, Started}.

stop({Dir, Started}) ->
    _ = catch application:stop(project_agora_posts),
    [application:stop(App) || App <- lists:reverse(Started)],
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.
