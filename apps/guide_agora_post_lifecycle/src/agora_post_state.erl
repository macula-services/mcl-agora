%%% @doc State of one `agora_post' stream.
%%%
%%% One stream per post_id, one status integer holding bit flags
%%% (`agora_post_status.hrl'), and what the aggregate needs to tell a
%%% redelivery from a contradiction: the sha256 of the body on the record, the
%%% publisher it came from, and the hashes of every different body already
%%% refused, so a contradiction delivered twice is written down once.
%%%
%%% It reads an event in either shape evoq hands it: the flat map `execute/2'
%%% returned, or the stored envelope a replay reads back, with the fields under
%%% `data' and its keys possibly binaries.
-module(agora_post_state).

-behaviour(evoq_state).

-include("agora_post_status.hrl").

-export([new/1, apply_event/2, to_map/1, status/1, recorded/1, conflicted/1]).
-export([body_sha256/1, publisher/1, refused/2, digest/1]).

-record(agora_post_state, {
    post_id :: binary(),
    status = 0 :: non_neg_integer(),
    body_sha256 :: binary() | undefined,
    publisher :: binary() | undefined,
    refused = [] :: [binary()]
}).

-opaque t() :: #agora_post_state{}.
-export_type([t/0]).

-spec new(binary()) -> t().
new(PostId) -> #agora_post_state{post_id = PostId}.

-spec apply_event(t(), map()) -> t().
apply_event(State, Event) ->
    applied(field(event_type, Event), fields(Event), State).

applied(<<"agora_post_recorded_v1">>, Data, #agora_post_state{status = Status} = State) ->
    State#agora_post_state{status = evoq_bit_flags:set(Status, ?AGORA_POST_RECORDED),
                           body_sha256 = digest(field(body, Data)),
                           publisher = field(publisher, Data)};
applied(<<"agora_post_conflict_detected_v1">>, Data,
        #agora_post_state{status = Status, refused = Refused} = State) ->
    State#agora_post_state{status = evoq_bit_flags:set(Status, ?AGORA_POST_CONFLICTED),
                           refused = [field(refused_body_sha256, Data) | Refused]};
applied(_Other, _Data, State) ->
    State.

%% @doc The state as a map, which is the shape evoq carries it in a snapshot.
-spec to_map(t()) -> map().
to_map(#agora_post_state{post_id = PostId, status = Status, body_sha256 = Hash,
                         publisher = Publisher, refused = Refused}) ->
    #{post_id => PostId, status => Status, body_sha256 => Hash,
      publisher => Publisher, refused => Refused}.

-spec status(t()) -> non_neg_integer().
status(#agora_post_state{status = Status}) -> Status.

%% @doc Whether this post is already on the record.
-spec recorded(t()) -> boolean().
recorded(State) ->
    evoq_bit_flags:has(status(State), ?AGORA_POST_RECORDED).

%% @doc Whether a different body has ever been heard under this post_id.
-spec conflicted(t()) -> boolean().
conflicted(State) ->
    evoq_bit_flags:has(status(State), ?AGORA_POST_CONFLICTED).

-spec body_sha256(t()) -> binary() | undefined.
body_sha256(#agora_post_state{body_sha256 = Hash}) -> Hash.

-spec publisher(t()) -> binary() | undefined.
publisher(#agora_post_state{publisher = Publisher}) -> Publisher.

%% @doc Whether this body hash was already refused as a contradiction.
-spec refused(t(), binary()) -> boolean().
refused(#agora_post_state{refused = Refused}, Hash) ->
    lists:member(Hash, Refused).

%%------------------------------------------------------------------------------

fields(#{data := Data}) when is_map(Data) -> Data;
fields(#{<<"data">> := Data}) when is_map(Data) -> Data;
fields(Event) -> Event.

field(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).

%% @doc A body's sha256, lowercase hex: how a body is compared and how a
%% contradiction names the two bodies without repeating either.
-spec digest(term()) -> binary() | undefined.
digest(Body) when is_binary(Body) -> binary:encode_hex(crypto:hash(sha256, Body), lowercase);
digest(_NoBody) -> undefined.
