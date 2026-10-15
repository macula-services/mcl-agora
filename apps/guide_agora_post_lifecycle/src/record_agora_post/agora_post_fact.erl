%%% @doc Reads one `agora_post_published_v1' off the square into command
%%% parameters, or says why it is not a post.
%%%
%%% Pure, and the only place the square's wire shape is understood. Every field
%%% is read through `mcl_om_wire:field/2', which resolves the three spellings a
%%% key can arrive under and unwraps the value: a text field arrives as
%%% `{text, Bin}' because a CBOR text string is not a byte string, and the
%%% unwrap is the service's business, not the decoder's.
%%%
%%% `Publisher' is passed IN rather than read from the payload. It is the
%%% identity macula verified on delivery, and a payload that names its own
%%% sender is claiming, not proving -- the record keeps the claim (`from')
%%% beside this, and never reads one as the other.
%%%
%%% The author's identity is DELIBERATELY NOT CHECKED against the publisher
%%% here. That comparison, and the stimulus cross-check against the news fact
%%% this keeper heard itself, are what W2 adds; in W1 both are recorded and
%%% neither is judged.
-module(agora_post_fact).

-export([decode/2]).

%% The three an agent may mean, and nothing else. Anything else is dropped to
%% `undefined' rather than kept: an unrecognised kind recorded verbatim would be
%% this keeper inventing a fourth one on the speaker's behalf.
-define(KINDS, [<<"opening">>, <<"reply">>, <<"synthesis">>]).

-spec decode(map(), binary()) -> {ok, map()} | {error, term()}.
decode(Payload, Publisher) ->
    Params = #{post_id     => text(post_id, Payload),
               from        => text(from, Payload),
               publisher   => Publisher,
               body        => text(body, Payload),
               in_reply_to => text(in_reply_to, Payload),
               kind        => kind(Payload),
               posted_at   => integer(posted_at, Payload),
               stimulus    => agora_post_stimulus:decode(
                                mcl_om_wire:field(stimulus, Payload)),
               %% WHICH ENGINE WROTE IT, attached by the speaker's harness. Not
               %% judged here, like the card: it is provenance, and the keeper
               %% keeps provenance rather than vouching for it.
               engine      => agora_post_engine:decode(
                                mcl_om_wire:field(engine, Payload))},
    complete(Params).

complete(#{post_id := Id, from := From, body := Body, posted_at := At} = Params)
  when is_binary(Id), Id =/= <<>>,
       is_binary(From), From =/= <<>>,
       is_binary(Body), Body =/= <<>>,
       is_integer(At) ->
    %% The thread is lifted out of the card here, once, so every reader of the
    %% record gets it without walking a nested map.
    {ok, Params#{item_id => agora_post_stimulus:item_id(maps:get(stimulus, Params))}};
complete(Params) ->
    {error, {malformed_agora_post, missing(Params)}}.

missing(Params) ->
    [Key || {Key, Ok} <- [{post_id, present(Params, post_id)},
                          {from, present(Params, from)},
                          {body, present(Params, body)},
                          {posted_at, is_integer(maps:get(posted_at, Params, undefined))}],
            Ok =:= false].

present(Params, Key) ->
    is_binary(maps:get(Key, Params, undefined)).

%%------------------------------------------------------------------------------

text(Key, Payload) ->
    kept_text(mcl_om_wire:field(Key, Payload)).

kept_text(Bin) when is_binary(Bin), Bin =/= <<>> -> Bin;
kept_text(_AbsentOrEmptyOrNotText)               -> undefined.

integer(Key, Payload) ->
    N = mcl_om_wire:field(Key, Payload),
    kept_integer(N).

kept_integer(N) when is_integer(N) -> N;
kept_integer(_AbsentOrNotAnInteger) -> undefined.

kind(Payload) ->
    kept_kind(text(kind, Payload)).

kept_kind(Kind) ->
    known(lists:member(Kind, ?KINDS), Kind).

known(true, Kind)   -> Kind;
known(false, _NotAKind) -> undefined.
