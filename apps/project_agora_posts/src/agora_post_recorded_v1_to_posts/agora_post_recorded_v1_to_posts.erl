%%% @doc Projection: agora_post_recorded_v1 -> the posts read model.
%%%
%%% One event, one row, written once. A post's event is immutable and its
%%% stream refuses a second one, so this projection has no update path and
%%% needs none: a replayed event writes the row it already wrote, which is why
%%% a boot can rebuild the whole read model by replaying the store.
%%%
%%% THE ROW IS REBUILT THROUGH THE SAME NORMALISERS THE FACT WENT IN THROUGH,
%%% not by re-deriving the shape. An event comes back off the store as it was
%%% written, and a decoded map's keys may be atoms or binaries depending on what
%%% the decoder knew at the time; reading it tolerantly here and handing the
%%% card back to `agora_post_stimulus:decode/1' means the row has exactly the
%%% shape a live fact produces, whether it was projected live or replayed.
-module(agora_post_recorded_v1_to_posts).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"agora_post_recorded_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets,
                                   #{name => agora_posts_projection}),
    {ok, #{}, RM}.

project(#{event_type := <<"agora_post_recorded_v1">>, data := Data}, _Metadata, State, RM) ->
    PostId = field(post_id, Data),
    ok = project_agora_posts_store:put_post(PostId, row(PostId, Data)),
    {ok, State, RM};
project(_Other, _Metadata, State, RM) ->
    {ok, State, RM}.

%% `item_id' is DERIVED FROM THE CARD rather than copied from the event. They
%% are the same value on the way in, and deriving it here means a row's thread
%% can never disagree with the card sitting beside it in the same row.
row(PostId, Data) ->
    Stimulus = agora_post_stimulus:decode(field(stimulus, Data)),
    #{post_id     => PostId,
      from        => field(from, Data),
      publisher   => field(publisher, Data),
      body        => field(body, Data),
      in_reply_to => field(in_reply_to, Data),
      item_id     => agora_post_stimulus:item_id(Stimulus),
      kind        => field(kind, Data),
      posted_at   => field(posted_at, Data),
      recorded_at => field(recorded_at, Data),
      stimulus    => Stimulus,
      %% A post recorded before the keeper checked anything carries neither
      %% verdict. It reads as unchecked (0), never as verified: the page does
      %% not show what nobody checked.
      publisher_verified => verdict(field(publisher_verified, Data), 0),
      stimulus_verified  => card_verdict(Stimulus, field(stimulus_verified, Data))}.

verdict(V, _Default) when V =:= 0; V =:= 1 -> V;
verdict(_Absent, Default) -> Default.

card_verdict(undefined, _Verdict) -> undefined;
card_verdict(_Card, Verdict) -> verdict(Verdict, 0).

%% macula's frame decoder makes a key an atom only when that atom already
%% exists in this VM, and leaves it as sent otherwise, so a round-tripped event
%% may read back under either spelling.
field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
