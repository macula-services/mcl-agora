%% @doc The projection: one event, one row.
%%
%% Tested without a running store by checking the row it builds, because that
%% row is the whole of what this module decides -- the write itself is the
%% store's, and the store's tests are its own.
-module(agora_post_recorded_v1_to_posts_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PROJECTION, agora_post_recorded_v1_to_posts).

the_projection_only_wants_the_one_event_test() ->
    ?assertEqual([<<"agora_post_recorded_v1">>], ?PROJECTION:interested_in()).

projection_test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             [fun a_live_event_projects_a_row/0,
              fun a_replayed_event_projects_the_same_row/0,
              fun an_unrelated_event_is_ignored/0]
     end}.

start() ->
    clear(),
    {ok, Pid} = project_agora_posts_store:start_link(),
    Pid.

stop(Pid) ->
    %% gen_server:stop, not a shutdown exit: the test process is LINKED to
    %% the store, so a non-normal exit would take the test down with it and
    %% eunit would report the group cancelled.
    _ = catch gen_server:stop(Pid),
    clear().

clear() ->
    catch gen_server:stop(project_agora_posts_store),
    catch ets:delete(agora_posts),
    catch ets:delete(agora_posts_by_id),
    ok.

a_live_event_projects_a_row() ->
    ok = project(event()),
    ?assertMatch({ok, #{post_id := <<"post-1">>, kind := <<"opening">>}},
                 project_agora_posts_store:get_post(<<"post-1">>)).

%% THE PROPERTY A BOOT DEPENDS ON. The event is delivered once live and once
%% more from the store on the next restart, so the same row must come out both
%% times: same fields, and the record's order unchanged.
a_replayed_event_projects_the_same_row() ->
    ok = project(event()),
    {ok, Live} = project_agora_posts_store:get_post(<<"post-1">>),
    ok = project(replayed()),
    ?assertMatch({ok, Live}, project_agora_posts_store:get_post(<<"post-1">>)),
    ?assertEqual(1, project_agora_posts_store:count()).

an_unrelated_event_is_ignored() ->
    Before = project_agora_posts_store:count(),
    {ok, _, _} = project_raw(#{event_type => <<"something_else_v1">>, data => #{}}),
    ?assertEqual(Before, project_agora_posts_store:count()).

%%------------------------------------------------------------------------------

project(Event) ->
    {ok, _, _} = project_raw(Event),
    ok.

project_raw(Event) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => test_projection}),
    ?PROJECTION:project(Event, #{}, #{}, RM).

%% A live delivery, as the dispatch produced it.
event() ->
    #{event_type => <<"agora_post_recorded_v1">>,
      data => #{post_id     => <<"post-1">>,
                from        => <<"a mind">>,
                publisher   => <<1:256>>,
                body        => <<"something worth keeping">>,
                in_reply_to => undefined,
                item_id     => <<"item-1">>,
                kind        => <<"opening">>,
                posted_at   => 1760000000000,
                recorded_at => 1760000000001,
                stimulus    => #{item_id => <<"item-1">>, title => <<"A headline">>}}}.

%% The same event after a round-trip through the store, where a key that was
%% not an atom in this VM comes back as the text it was sent as.
replayed() ->
    #{event_type => <<"agora_post_recorded_v1">>,
      data => #{<<"post_id">>     => <<"post-1">>,
                <<"from">>        => <<"a mind">>,
                <<"publisher">>   => <<1:256>>,
                <<"body">>        => <<"something worth keeping">>,
                <<"kind">>        => <<"opening">>,
                <<"posted_at">>   => 1760000000000,
                <<"recorded_at">> => 1760000000001,
                <<"stimulus">>    => #{<<"item_id">> => <<"item-1">>,
                                       <<"title">>   => <<"A headline">>}}}.
