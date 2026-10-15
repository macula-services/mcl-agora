%%% @doc Event: agora_post_conflict_detected_v1 -- the same post_id arrived with
%%% a different body.
%%%
%%% MECHANICAL, NOT SEMANTIC. A byte comparison of two bodies, no model and no
%%% judgement about what was said. It means a speaker reused an id, a replay
%%% was altered, or an instance re-rendered a post; which one is for a reader
%%% (the sentinel, a vigil surface) to decide. The first body stays on the
%%% record and the second is never preferred.
%%%
%%% CARRIES HASHES, NEVER THE SECOND BODY. The record already holds the first
%%% one, and repeating the second would put the disputed words on the record
%%% and on the wire under the keeper's own name. Ported from hecate-agora's
%%% `agora_post_conflict_detected_v1'.
-module(agora_post_conflict_detected_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, detected/2, to_map/1]).

-record(agora_post_conflict_detected_v1, {
    post_id             :: binary(),
    kept_body_sha256    :: binary(),
    kept_publisher      :: binary() | undefined,
    refused_body_sha256 :: binary(),
    refused_publisher   :: binary(),
    refused_from        :: binary(),
    detected_at         :: integer()
}).

-opaque t() :: #agora_post_conflict_detected_v1{}.
-export_type([t/0]).

event_type() -> <<"agora_post_conflict_detected_v1">>.

%% @doc The conflict between what the stream holds and the command that
%% contradicts it.
-spec detected(agora_post_state:t(), map()) -> t().
detected(State, #{post_id := PostId, body := Body, publisher := Publisher, from := From}) ->
    new(#{post_id => PostId,
          kept_body_sha256 => agora_post_state:body_sha256(State),
          kept_publisher => agora_post_state:publisher(State),
          refused_body_sha256 => agora_post_state:digest(Body),
          refused_publisher => Publisher,
          refused_from => From}).

-spec new(map()) -> t().
new(#{post_id := PostId, kept_body_sha256 := Kept, refused_body_sha256 := Refused,
      refused_publisher := Publisher, refused_from := From} = Fields) ->
    #agora_post_conflict_detected_v1{
       post_id = PostId,
       kept_body_sha256 = Kept,
       kept_publisher = maps:get(kept_publisher, Fields, undefined),
       refused_body_sha256 = Refused,
       refused_publisher = Publisher,
       refused_from = From,
       detected_at = maps:get(detected_at, Fields, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#agora_post_conflict_detected_v1{} = E) ->
    #{event_type          => event_type(),
      post_id             => E#agora_post_conflict_detected_v1.post_id,
      kept_body_sha256    => E#agora_post_conflict_detected_v1.kept_body_sha256,
      kept_publisher      => E#agora_post_conflict_detected_v1.kept_publisher,
      refused_body_sha256 => E#agora_post_conflict_detected_v1.refused_body_sha256,
      refused_publisher   => E#agora_post_conflict_detected_v1.refused_publisher,
      refused_from        => E#agora_post_conflict_detected_v1.refused_from,
      detected_at         => E#agora_post_conflict_detected_v1.detected_at}.
