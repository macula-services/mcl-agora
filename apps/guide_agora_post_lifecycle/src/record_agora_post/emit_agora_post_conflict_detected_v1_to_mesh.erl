%%% @doc Says a contradiction on the record out loud, under the keeper's own org.
%%%
%%% Hashes and publishers only, never the refused body: repeating it would put
%%% the disputed words on the wire under the keeper's name. Text is tagged as
%%% CBOR text, ids and hashes as lowercase hex, times as integers, and nothing
%%% is a boolean. Fire and forget, and never on a replay: a contradiction is
%%% news once.
-module(emit_agora_post_conflict_detected_v1_to_mesh).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).
-export([replay_policy/0, to_wire/1]).

replay_policy() -> skip.

interested_in() ->
    [<<"agora_post_conflict_detected_v1">>].

init(_Config) ->
    {ok, undefined}.

handle_event(<<"agora_post_conflict_detected_v1">>, Event, _Meta, State) ->
    Topic = agora_post_topic:conflict_topic(agora_post_topic:realm_name()),
    _ = mcl_om_pubsub:publish(Topic, to_wire(data(Event)), #{mode => async_log}),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

data(#{data := Data}) when is_map(Data) -> Data;
data(Event)                            -> Event.

%% @doc The fact for one contradiction.
-spec to_wire(map()) -> map().
to_wire(Conflict) ->
    maps:filter(fun(_Key, Value) -> Value =/= undefined end,
                #{post_id             => text(field(post_id, Conflict)),
                  kept_body_sha256    => text(field(kept_body_sha256, Conflict)),
                  kept_publisher      => hex(field(kept_publisher, Conflict)),
                  refused_body_sha256 => text(field(refused_body_sha256, Conflict)),
                  refused_publisher   => hex(field(refused_publisher, Conflict)),
                  refused_from        => text(field(refused_from, Conflict)),
                  detected_at         => field(detected_at, Conflict)}).

field(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).

text(Bin) when is_binary(Bin), Bin =/= <<>> -> {text, Bin};
text(_AbsentOrEmpty)                        -> undefined.

hex(Key) when is_binary(Key), byte_size(Key) =:= 32 -> {text, binary:encode_hex(Key, lowercase)};
hex(_AbsentOrNotAKey)                              -> undefined.
