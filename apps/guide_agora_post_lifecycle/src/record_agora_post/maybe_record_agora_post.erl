%%% @doc Handler for record_agora_post_v1: turns the command into the one event
%%% that puts a post on the record, and dispatches it.
%%%
%%% The aggregate decides whether the command gets this far at all. By the time
%%% `handle/1' runs, the post is either unknown or already refused.
-module(maybe_record_agora_post).

-export([handle/1, handle_from_map/1, dispatch/1]).

-define(STORE_ID, mcl_agora_store).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(record_agora_post_v1:from_map(Payload)).

with_command({ok, Cmd})       -> handle(Cmd);
with_command({error, _} = Err) -> Err.

-spec handle(record_agora_post_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    Event = agora_post_recorded_v1:from_command(Cmd),
    {ok, [agora_post_recorded_v1:to_map(Event)]}.

%% @doc Record one post. `{ok, _, []}' means the stream already holds it: the
%% aggregate refused a post_id it has already written down, and nothing was
%% dispatched to the store.
-spec dispatch(map()) -> {ok, integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_command_for_dispatch(record_agora_post_v1:new(Params)).

with_command_for_dispatch({ok, Cmd}) ->
    PostId = record_agora_post_v1:post_id(Cmd),
    EvoqCmd = evoq_command:new(record_agora_post, agora_post_aggregate,
                               agora_post_aggregate:stream_id(PostId),
                               record_agora_post_v1:to_map(Cmd),
                               #{timestamp => erlang:system_time(millisecond)}),
    evoq_command_router:dispatch(EvoqCmd, #{store_id => ?STORE_ID,
                                            adapter => reckon_evoq_adapter,
                                            consistency => eventual});
with_command_for_dispatch({error, _} = Error) ->
    Error.
