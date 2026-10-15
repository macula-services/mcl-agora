%%% @doc Command: record_agora_post_v1 -- write one post the square carried
%%% down onto the record.
%%%
%%% A post that cannot be recorded is not a post, and this is where that is
%%% decided. Four fields are required, and the reasons are not stylistic:
%%%
%%%   post_id    a post with no identity cannot be deduplicated, so a
%%%              redelivery would be indistinguishable from a second post
%%%   from       an unattributed remark is not someone speaking
%%%   body       a post with no body is not speech
%%%   posted_at  a post that cannot be placed cannot be paged in any order
%%%
%%% `publisher' is required too, but it comes from the delivery rather than the
%%% payload: it is the identity the mesh verified, and a post the mesh could not
%%% attribute never reaches this command at all (see the listener).
%%%
%%% Everything else is optional and is recorded as it arrived.
-module(record_agora_post_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([post_id/1]).

-record(record_agora_post_v1, {
    post_id    :: binary(),
    from       :: binary(),
    publisher  :: binary(),
    body       :: binary(),
    in_reply_to :: binary() | undefined,
    item_id    :: binary() | undefined,
    kind       :: binary() | undefined,
    posted_at  :: integer(),
    stimulus   :: map() | undefined
}).

-opaque t() :: #record_agora_post_v1{}.
-export_type([t/0]).

%% The evoq command type. The payload map carries its OWN `command_type', which
%% is what the aggregate matches on; this one names the command to evoq.
command_type() -> record_agora_post.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{post_id := Id, from := From, publisher := Publisher, body := Body,
      posted_at := At} = Params)
  when is_binary(Id), Id =/= <<>>,
       is_binary(From), From =/= <<>>,
       is_binary(Publisher), byte_size(Publisher) =:= 32,
       is_binary(Body), Body =/= <<>>,
       is_integer(At) ->
    {ok, #record_agora_post_v1{post_id = Id,
                               from = From,
                               publisher = Publisher,
                               body = Body,
                               in_reply_to = optional(Params, in_reply_to),
                               item_id = optional(Params, item_id),
                               kind = optional(Params, kind),
                               posted_at = At,
                               stimulus = optional_map(Params, stimulus)}};
new(Params) when is_map(Params) ->
    {error, {malformed_agora_post, missing(Params)}};
new(_NotAMap) ->
    {error, not_a_map}.

%% What was wrong, so the warning in the listener names the fields rather than
%% just the fact, in the order the guard above reads them.
missing(Params) ->
    [Key || {Key, Ok} <- checks(Params), Ok =:= false].

checks(Params) ->
    [{post_id, text(Params, post_id)},
     {from, text(Params, from)},
     {publisher, publisher(Params)},
     {body, text(Params, body)},
     {posted_at, is_integer(maps:get(posted_at, Params, undefined))}].

text(Params, Key) ->
    case maps:get(Key, Params, undefined) of
        Bin when is_binary(Bin), Bin =/= <<>> -> true;
        _AbsentOrNotText                      -> false
    end.

publisher(Params) ->
    case maps:get(publisher, Params, undefined) of
        Key when is_binary(Key), byte_size(Key) =:= 32 -> true;
        _AbsentOrNotAKey                               -> false
    end.

optional(Params, Key) ->
    value(maps:get(Key, Params, undefined)).

value(Bin) when is_binary(Bin), Bin =/= <<>> -> Bin;
value(_AbsentOrNotText)                      -> undefined.

optional_map(Params, Key) ->
    case maps:get(Key, Params, undefined) of
        Map when is_map(Map), map_size(Map) > 0 -> Map;
        _AbsentOrNotAMap                        -> undefined
    end.

-spec to_map(t()) -> map().
to_map(#record_agora_post_v1{} = Cmd) ->
    %% The atom `command_type' the aggregate matches, spelled as a binary so it
    %% round-trips through the store unchanged under any decoder.
    #{command_type => <<"record_agora_post">>,
      post_id      => Cmd#record_agora_post_v1.post_id,
      from         => Cmd#record_agora_post_v1.from,
      publisher    => Cmd#record_agora_post_v1.publisher,
      body         => Cmd#record_agora_post_v1.body,
      in_reply_to  => Cmd#record_agora_post_v1.in_reply_to,
      item_id      => Cmd#record_agora_post_v1.item_id,
      kind         => Cmd#record_agora_post_v1.kind,
      posted_at    => Cmd#record_agora_post_v1.posted_at,
      stimulus     => Cmd#record_agora_post_v1.stimulus}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{post_id := _, from := _, publisher := _, body := _, posted_at := _} = Map) ->
    new(Map);
from_map(_Missing) ->
    {error, missing_required_fields}.

-spec post_id(t()) -> binary().
post_id(#record_agora_post_v1{post_id = V}) -> V.
