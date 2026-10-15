%% @doc The keeper's memory of the news wire, and who it will hear it from.
%%
%% The card check is only as good as what it checks against: an item a stranger
%% reported would make a forged card verify against itself. So the listener
%% remembers only what an admitted mcl-news node said, and the memory is
%% bounded so a flood cannot grow it.
-module(remember_news_item_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LISTENER, on_news_item_reported_from_mesh_remember_news_item).
-define(SENSOR, <<5:256>>).

news_test_() ->
    {foreach,
     fun() -> {ok, Pid} = heard_news_items:start_link(), unlink(Pid), Pid end,
     fun(Pid) -> exit(Pid, kill), wait_down(Pid) end,
     [fun an_item_from_the_news_sensor_is_remembered/1,
      fun an_item_from_a_node_that_is_not_the_news_sensor_is_not/1,
      fun an_item_the_keeper_could_not_check_is_not_remembered/1,
      fun an_unverified_publication_is_not_even_checked/1,
      fun a_later_report_of_the_same_item_replaces_the_first/1,
      fun the_memory_is_bounded_oldest_out_first/1]}.

an_item_from_the_news_sensor_is_remembered(_Pid) ->
    ?_test(with_membership({ok, 1}, fun() ->
        {noreply, State} = ?LISTENER:handle_event(<<"t">>, item(<<"item-1">>), meta(), fresh()),
        ?assertEqual(1, maps:get(remembered, State)),
        ?assertMatch(#{title := <<"A real headline">>}, heard_news_items:heard(<<"item-1">>)),
        ?assert(meck:called(mcl_om, org_member, [<<"mcl-news">>, ?SENSOR]))
    end)).

an_item_from_a_node_that_is_not_the_news_sensor_is_not(_Pid) ->
    ?_test(with_membership({error, {not_a_member, delegation_mismatch}}, fun() ->
        {noreply, State} = ?LISTENER:handle_event(<<"t">>, item(<<"item-1">>), meta(), fresh()),
        ?assertEqual(1, maps:get(not_the_news_sensor, State)),
        ?assertEqual(undefined, heard_news_items:heard(<<"item-1">>))
    end)).

an_item_the_keeper_could_not_check_is_not_remembered(_Pid) ->
    ?_test(with_membership({error, {unavailable, timeout}}, fun() ->
        {noreply, State} = ?LISTENER:handle_event(<<"t">>, item(<<"item-1">>), meta(), fresh()),
        ?assertEqual(1, maps:get(unchecked, State)),
        ?assertEqual(undefined, heard_news_items:heard(<<"item-1">>))
    end)).

an_unverified_publication_is_not_even_checked(_Pid) ->
    ?_test(with_membership({ok, 1}, fun() ->
        Meta = #{publisher => ?SENSOR, publisher_verified => false},
        {noreply, State} = ?LISTENER:handle_event(<<"t">>, item(<<"item-1">>), Meta, fresh()),
        ?assertEqual(1, maps:get(refused, State)),
        ?assertNot(meck:called(mcl_om, org_member, '_'))
    end)).

a_later_report_of_the_same_item_replaces_the_first(_Pid) ->
    ?_test(begin
        ok = heard_news_items:remember(<<"item-1">>, #{item_id => <<"item-1">>, title => <<"first">>}),
        ok = heard_news_items:remember(<<"item-1">>, #{item_id => <<"item-1">>, title => <<"second">>}),
        ?assertEqual(#{item_id => <<"item-1">>, title => <<"second">>}, heard_news_items:heard(<<"item-1">>)),
        ?assertEqual(1, heard_news_items:count())
    end).

the_memory_is_bounded_oldest_out_first(_Pid) ->
    ?_test(begin
        [ok = heard_news_items:remember(integer_to_binary(N), #{n => N}) || N <- lists:seq(1, 5001)],
        ?assertEqual(5000, heard_news_items:count()),
        ?assertEqual(undefined, heard_news_items:heard(<<"1">>)),
        ?assertEqual(#{n => 5001}, heard_news_items:heard(<<"5001">>))
    end).

%%------------------------------------------------------------------------------

fresh() -> #{remembered => 0, not_the_news_sensor => 0, unchecked => 0, refused => 0}.

meta() -> #{publisher => ?SENSOR, publisher_verified => true}.

item(ItemId) ->
    #{<<"item_id">> => {text, ItemId},
      <<"title">> => {text, <<"A real headline">>},
      <<"url">> => {text, <<"https://news.example/a">>}}.

with_membership(Answer, Body) ->
    meck:new(mcl_om, [passthrough, no_link, non_strict]),
    meck:expect(mcl_om, org_member, 2, Answer),
    try Body() after meck:unload(mcl_om) end.

wait_down(Pid) ->
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.
