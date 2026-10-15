%%% @doc State of one `agora_post' stream.
%%%
%%% One stream per post_id, and one status integer holding bit flags
%%% (`agora_post_status.hrl'). `recorded' is the only question the aggregate
%%% ever asks of it, and it is what makes a redelivery a no-op: the record
%%% holds one post per post_id, so the second fact under an id the stream
%%% already carries is refused rather than written again.
-module(agora_post_state).

-behaviour(evoq_state).

-include("agora_post_status.hrl").

-export([new/1, apply_event/2, to_map/1, status/1, recorded/1]).

-record(agora_post_state, {
    post_id :: binary(),
    status = 0 :: non_neg_integer()
}).

-opaque t() :: #agora_post_state{}.
-export_type([t/0]).

-spec new(binary()) -> t().
new(PostId) -> #agora_post_state{post_id = PostId}.

-spec apply_event(t(), map()) -> t().
apply_event(#agora_post_state{status = Status} = State, _Event) ->
    State#agora_post_state{status = evoq_bit_flags:set(Status, ?AGORA_POST_RECORDED)}.

%% @doc The state as a map, which is the shape evoq carries it in a snapshot.
-spec to_map(t()) -> map().
to_map(#agora_post_state{post_id = PostId, status = Status}) ->
    #{post_id => PostId, status => Status}.

-spec status(t()) -> non_neg_integer().
status(#agora_post_state{status = Status}) -> Status.

%% @doc Whether this post is already on the record, which is the only question
%% the aggregate ever asks.
-spec recorded(t()) -> boolean().
recorded(State) ->
    evoq_bit_flags:has(status(State), ?AGORA_POST_RECORDED).
