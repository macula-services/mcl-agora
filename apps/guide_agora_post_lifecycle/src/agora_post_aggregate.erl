%%% @doc The `agora_post' aggregate: one stream per post on the record.
%%%
%%% The stream exists because a post is evidence. Its id is the post_id the
%%% speaker minted, so a redelivery -- a mesh that hands the same fact over
%%% twice, a subscriber that reconnects mid-flight -- addresses this same
%%% stream and is refused here with the sanctioned no-op `{ok, []}'.
%%%
%%% That refusal IS the idempotency: no second event, so no second
%%% `agora_post_recorded_v1', so no second fact on the mesh and no second
%%% read-model write. A repeat is heard and counted, and nothing else happens.
-module(agora_post_aggregate).

-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> agora_post_state.

init(PostId) ->
    {ok, agora_post_state:new(PostId)}.

-spec stream_id(binary()) -> binary().
stream_id(PostId) when is_binary(PostId) ->
    <<"agora-post-", PostId/binary>>.

apply(State, Event) ->
    agora_post_state:apply_event(State, Event).

%% `command_type' is read out of the command's own payload (evoq takes it from
%% there, not from the type evoq_command:new/4 was handed), which is why
%% record_agora_post_v1:to_map/1 spells it as a binary.
execute(State, #{command_type := <<"record_agora_post">>} = Payload) ->
    recorded(agora_post_state:recorded(State), Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

recorded(true, _Payload) ->
    %% Already on the record. The no-op: the caller reads it as a duplicate.
    {ok, []};
recorded(false, Payload) ->
    maybe_record_agora_post:handle_from_map(Payload).
