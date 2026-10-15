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
              fun an_unrelated_event_is_ignored/0,
              fun the_verdicts_reach_the_row/0,
              fun the_engine_reaches_the_row/0,
              fun a_post_with_no_engine_has_no_engine_on_the_row/0,
              fun a_post_recorded_before_any_check_reads_as_unchecked/0]
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

%% W2: the page decides what to show from these two, so they must reach it.
the_verdicts_reach_the_row() ->
    #{data := Data} = Event = event(),
    ok = project(Event#{data => Data#{post_id => <<"post-2">>, publisher_verified => 1,
                                      stimulus_verified => 1}}),
    ?assertMatch({ok, #{publisher_verified := 1, stimulus_verified := 1}},
                 project_agora_posts_store:get_post(<<"post-2">>)).

%% WHICH ENGINE WROTE IT reaches the row, so the page can show it without asking
%% the speaker again: the row is the whole of what a reader sees.
the_engine_reaches_the_row() ->
    #{data := Data} = Event = event(),
    ok = project(Event#{data => Data#{post_id => <<"post-4">>,
                                      engine => #{provider => <<"nvidia">>,
                                                  model => <<"nemotron-3-super-120b-a12b">>}}}),
    ?assertMatch({ok, #{engine := #{provider := <<"nvidia">>,
                                    model := <<"nemotron-3-super-120b-a12b">>}}},
                 project_agora_posts_store:get_post(<<"post-4">>)).

%% A post whose engine nobody stated has NO engine on the row, rather than a
%% half one: the page shows nothing rather than something it cannot support.
a_post_with_no_engine_has_no_engine_on_the_row() ->
    #{data := Data} = Event = event(),
    ok = project(Event#{data => Data#{post_id => <<"post-5">>}}),
    {ok, Row} = project_agora_posts_store:get_post(<<"post-5">>),
    ?assertEqual(undefined, maps:get(engine, Row, undefined)).

%% A post the keeper wrote down before it checked anything is not verified by
%% default: it reads as unchecked, and its card as unchecked too.
a_post_recorded_before_any_check_reads_as_unchecked() ->
    #{data := Data} = Event = event(),
    ok = project(Event#{data => Data#{post_id => <<"post-3">>}}),
    ?assertMatch({ok, #{publisher_verified := 0, stimulus_verified := 0}},
                 project_agora_posts_store:get_post(<<"post-3">>)).

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
