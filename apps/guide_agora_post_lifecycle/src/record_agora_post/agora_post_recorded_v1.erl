%%% @doc Event: agora_post_recorded_v1 -- a post is on the record.
%%%
%%% The record's own event, and the only thing the keeper ever writes down. It
%%% carries what was heard, plus two fields the keeper originates:
%%%
%%%   recorded_at  this keeper's clock at the moment it wrote the post down.
%%%                Never `posted_at', which is the speaker's clock and may be
%%%                anything at all; the pair is what lets a reader tell "this
%%%                was said late" from "this was heard late".
%%%   item_id      lifted out of `stimulus' -- the mcl-news item the post reacts
%%%                to, which is the thread. Lifted here rather than derived at
%%%                every read, so a read model does not have to dig through a
%%%                nested card to group a story.
%%%
%%% `publisher_verified' and `stimulus_verified' are the listener's verdicts
%%% at the moment the post was heard (see record_agora_post_v1), written down
%%% with it so a replay never decides them again.
%%%
%%% `stimulus' itself is kept as it arrived. It was attached by the speaker's
%%% harness, never written by a model, and the keeper records provenance rather
%%% than authoring it.
-module(agora_post_recorded_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([post_id/1]).

-record(agora_post_recorded_v1, {
    post_id     :: binary(),
    from        :: binary(),
    publisher   :: binary(),
    body        :: binary(),
    in_reply_to :: binary() | undefined,
    item_id     :: binary() | undefined,
    kind        :: binary() | undefined,
    posted_at   :: integer(),
    recorded_at :: integer(),
    stimulus    :: map() | undefined,
    engine      :: map() | undefined,
    publisher_verified :: 0 | 1,
    stimulus_verified  :: 0 | 1 | undefined
}).

-opaque t() :: #agora_post_recorded_v1{}.
-export_type([t/0]).

event_type() -> <<"agora_post_recorded_v1">>.

-spec new(map()) -> t().
new(#{post_id := Id, from := From, publisher := Publisher, body := Body,
      posted_at := At} = Fields) ->
    #agora_post_recorded_v1{post_id = Id,
                            from = From,
                            publisher = Publisher,
                            body = Body,
                            in_reply_to = optional(Fields, in_reply_to),
                            item_id = optional(Fields, item_id),
                            kind = optional(Fields, kind),
                            posted_at = At,
                            recorded_at = erlang:system_time(millisecond),
                            stimulus = optional_map(Fields, stimulus),
                            engine = optional_map(Fields, engine),
                            publisher_verified = maps:get(publisher_verified, Fields, 0),
                            stimulus_verified = maps:get(stimulus_verified, Fields, undefined)}.

optional(Fields, Key) ->
    case maps:get(Key, Fields, undefined) of
        Bin when is_binary(Bin), Bin =/= <<>> -> Bin;
        _AbsentOrNotText                      -> undefined
    end.

optional_map(Fields, Key) ->
    case maps:get(Key, Fields, undefined) of
        Map when is_map(Map), map_size(Map) > 0 -> Map;
        _AbsentOrNotAMap                        -> undefined
    end.

-spec from_command(record_agora_post_v1:t()) -> t().
from_command(Cmd) ->
    new(record_agora_post_v1:to_map(Cmd)).

-spec to_map(t()) -> map().
to_map(#agora_post_recorded_v1{} = E) ->
    #{event_type  => event_type(),
      post_id     => E#agora_post_recorded_v1.post_id,
      from        => E#agora_post_recorded_v1.from,
      publisher   => E#agora_post_recorded_v1.publisher,
      body        => E#agora_post_recorded_v1.body,
      in_reply_to => E#agora_post_recorded_v1.in_reply_to,
      item_id     => E#agora_post_recorded_v1.item_id,
      kind        => E#agora_post_recorded_v1.kind,
      posted_at   => E#agora_post_recorded_v1.posted_at,
      recorded_at => E#agora_post_recorded_v1.recorded_at,
      stimulus    => E#agora_post_recorded_v1.stimulus,
      engine      => E#agora_post_recorded_v1.engine,
      publisher_verified => E#agora_post_recorded_v1.publisher_verified,
      stimulus_verified  => E#agora_post_recorded_v1.stimulus_verified}.

-spec post_id(t()) -> binary().
post_id(#agora_post_recorded_v1{post_id = V}) -> V.
