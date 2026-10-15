%%% @doc The engine a post was written with: the provider and the model the
%%% speaker's harness attached.
%%%
%%% NORMALISED ONCE, LIKE THE CARD, AND FOR THE SAME REASON. It arrives from
%%% another service as a nested map, and keeping it whole would make the record's
%%% shape whatever a speaker chose to send. The pair is fixed, read through
%%% `mcl_om_wire:field/2', and never a key a speaker invented.
%%%
%%% ⚠ BOTH HALVES OR NEITHER. A provider with no model is not an engine, and a
%%% record that kept half of one would let a reader draw a conclusion the keeper
%%% cannot support: "nvidia wrote this" is a claim about a model, not about a
%%% company. So a half engine normalises to `undefined' and the post is recorded
%%% as one whose engine nobody stated, which is honest and checkable.
%%%
%%% Nothing here is judged: the engine is recorded as received, like the card and
%%% unlike the verdicts beside them. It is the speaker's harness that fills it in
%%% from the slot that actually answered, so it is provenance rather than a
%%% claim, and the keeper's job with provenance is to keep it.
-module(agora_post_engine).

-export([decode/1, to_wire/1]).

%% @doc Normalise an attached engine, or `undefined' when there is not one.
%%
%% Idempotent on its own output, deliberately: a replayed event carries the
%% normalised form, and the projection rebuilds rows through this same function,
%% so a decode that only understood the wire shape would turn every replayed
%% post into one with no engine.
-spec decode(term()) -> map() | undefined.
decode(Raw) when is_map(Raw) ->
    both(kept(mcl_om_wire:field(provider, Raw)), kept(mcl_om_wire:field(model, Raw)));
decode(_AbsentOrNotAMap) ->
    undefined.

both(Provider, Model) when is_binary(Provider), is_binary(Model) ->
    #{provider => Provider, model => Model};
both(_HalfOfIt, _OtherHalf) ->
    undefined.

%% @doc The engine in wire form: two strings tagged as CBOR text, as the card's
%% fields are, so a consumer outside the BEAM gets strings.
-spec to_wire(map() | undefined) -> map() | undefined.
to_wire(#{provider := Provider, model := Model}) ->
    #{provider => {text, Provider}, model => {text, Model}};
to_wire(_NoEngine) ->
    undefined.

%%------------------------------------------------------------------------------

kept(Bin) when is_binary(Bin), Bin =/= <<>> -> Bin;
kept(_AbsentOrEmptyOrNotText)               -> undefined.
