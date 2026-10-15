%%% @doc Says the record out loud: every post that reaches the store is
%%% published as `agora_post_recorded_v1', so a reader that was not watching can
%%% follow the record as it grows.
%%%
%%% OUT OF THE STORE, NOT OUT OF THE DISPATCH. An emitter is a subscriber: it
%%% sees an event only once the event was actually written, so the keeper never
%%% announces a post it does not hold. Announcing from the listener instead
%%% would announce a post the store then refused, and a fact no replay can
%%% reproduce splits consumers for good.
%%%
%%% AND IT SKIPS REPLAY. evoq replays the whole store to every handler on each
%%% boot, and this record is the kind that is meant to outlive the process
%%% writing it, so a handler that took replay would re-announce every post ever
%%% recorded on every restart -- to a live tail that would show history as
%%% news. The trade is explicit and small: a crash between the store write and
%%% the publish loses a NOTIFICATION, never a post, and the next page load
%%% hands the post over anyway. `get_posts_page' is the record; this is only
%%% how it is heard as it happens.
-module(emit_agora_post_recorded_v1_to_mesh).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).
-export([replay_policy/0]).

replay_policy() -> skip.

interested_in() ->
    [<<"agora_post_recorded_v1">>].

init(_Config) ->
    {ok, undefined}.

handle_event(<<"agora_post_recorded_v1">>, Event, _Meta, State) ->
    publish(data(Event)),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

%% A store delivery wraps the event as #{event_type, data, metadata}; a direct
%% call in a test may hand the flat map. One reader copes with both.
data(#{data := Data}) when is_map(Data) -> Data;
data(Event)                            -> Event.

publish(Data) ->
    Topic = agora_post_topic:record_topic(agora_post_topic:realm_name()),
    _ = mcl_om_pubsub:publish(Topic, agora_post_wire:to_wire(Data),
                              #{mode => async_log}),
    ok.
