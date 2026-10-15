%% @doc The emitter: what the keeper says out loud, and when it stays quiet.
%%
%% This is the second half of "a repeat produces no second recorded fact". The
%% aggregate promises no second event; this is the module that would announce
%% one if it existed, and it can only fire off the store. A repeat never
%% reaches the store, so it never reaches here.
%%
%% The two pure answers -- the replay policy and what it listens for -- need no
%% mesh, so they are ordinary tests; the three that watch a publish run inside
%% a configured realm, because building the topic reads the realm name.
-module(emit_agora_post_recorded_v1_to_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

-define(EMITTER, emit_agora_post_recorded_v1_to_mesh).
-define(PUBLISHER, binary:copy(<<16#cd>>, 32)).
-define(TOPIC, <<"io.macula/mcl-agora/agora/wire/agora_post_recorded_v1">>).

%% A restart must not re-announce the record. evoq replays the whole store to
%% every handler on boot, and a live tail that took the replay would show
%% history as news.
replay_is_skipped_test() ->
    ?assertEqual(skip, ?EMITTER:replay_policy()).

only_the_recorded_event_is_wanted_test() ->
    ?assertEqual([<<"agora_post_recorded_v1">>], ?EMITTER:interested_in()).

the_publishing_test_() ->
    {setup, fun configure_realm/0, fun unconfigure_realm/1,
     fun(_) ->
             [fun the_recorded_event_is_published_on_the_record_topic/0,
              fun a_delivery_in_the_store_envelope_is_read_too/0,
              %% A fact no post produced is not a post, so nothing is said.
              fun an_unrelated_event_publishes_nothing/0]
     end}.

the_recorded_event_is_published_on_the_record_topic() ->
    with_publish(
      fun(Calls) ->
          {ok, _} = ?EMITTER:handle_event(<<"agora_post_recorded_v1">>, event(), #{}, undefined),
          ?assertEqual([{?TOPIC, payload(Calls())}], Calls())
      end).

a_delivery_in_the_store_envelope_is_read_too() ->
    with_publish(
      fun(Calls) ->
          {ok, _} = ?EMITTER:handle_event(<<"agora_post_recorded_v1">>,
                                          #{event_type => <<"agora_post_recorded_v1">>,
                                            data => data(),
                                            metadata => #{}},
                                          #{}, undefined),
          ?assertEqual([{?TOPIC, payload(Calls())}], Calls())
      end).

an_unrelated_event_publishes_nothing() ->
    with_publish(
      fun(Calls) ->
          {ok, _} = ?EMITTER:handle_event(<<"something_else_v1">>, #{}, #{}, undefined),
          ?assertEqual([], Calls())
      end).

configure_realm() ->
    _ = application:load(guide_agora_post_lifecycle),
    Existing = application:get_env(guide_agora_post_lifecycle, realm_name),
    application:set_env(guide_agora_post_lifecycle, realm_name, "io.macula"),
    Existing.

unconfigure_realm(undefined) ->
    application:unset_env(guide_agora_post_lifecycle, realm_name);
unconfigure_realm({ok, Value}) ->
    application:set_env(guide_agora_post_lifecycle, realm_name, Value).

%%------------------------------------------------------------------------------

payload([{_Topic, Fact}]) -> Fact.

event() ->
    #{event_type => <<"agora_post_recorded_v1">>, data => data()}.

data() ->
    #{post_id     => <<"post-1">>,
      from        => <<"a mind">>,
      publisher   => ?PUBLISHER,
      body        => <<"something worth keeping">>,
      in_reply_to => undefined,
      item_id     => <<"item-1">>,
      kind        => <<"opening">>,
      posted_at   => 1760000000000,
      recorded_at => 1760000000001,
      stimulus    => #{item_id => <<"item-1">>, title => <<"A headline">>}}.

%% Stands in for the mesh: the emitter's only seam with it is the publish, and
%% what it publishes is the whole of what this module decides.
with_publish(Body) ->
    Key = {?MODULE, calls},
    meck:new(mcl_om_pubsub, [passthrough, no_link]),
    meck:expect(mcl_om_pubsub, publish, 3,
                fun(Topic, Fact, _Opts) ->
                    persistent_term:put(Key, [{Topic, Fact} | calls()]),
                    ok
                end),
    persistent_term:erase(Key),
    try
        Body(fun calls/0)
    after
        persistent_term:erase(Key),
        meck:unload(mcl_om_pubsub)
    end.

calls() ->
    lists:reverse(persistent_term:get({?MODULE, calls}, [])).
