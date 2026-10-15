%%% @doc The `mcl-agora/get_posts_page' procedure: the record over the mesh.
%%%
%%% A THIN WIRE WRAPPER, ON PURPOSE. Everything a caller can observe is decided
%%% in `get_posts_page' and `agora_post_wire'; this module's whole job is to
%%% read a request that arrived in wire form and shape the answer. That is why
%%% it has no logic to test of its own beyond those two transitions.
%%%
%%% Fields are read through `mcl_om_wire:field/2', which resolves the three
%%% spellings a key can arrive under and unwraps the value: a number sent as
%%% CBOR text arrives as `{text, <<"50">>}' is NOT accepted here and becomes the
%%% default, because a caller who sent a string meant something this desk does
%%% not have to guess at.
-module(get_posts_page_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(Args, State) when is_map(Args) ->
    {reply, reply(get_posts_page:get(request(Args))), State};
handle_request(_NotAMap, State) ->
    {reply, #{ok => 0, error => <<"bad_request">>}, State}.

%% Absent fields are dropped rather than passed as undefined, so the query sees
%% exactly the bounds the caller actually asked for.
request(Args) ->
    maps:filter(fun(_Key, Value) -> Value =/= undefined end,
                #{limit    => integer(limit, Args),
                  before   => integer(before, Args),
                  'after'  => integer('after', Args)}).

integer(Key, Args) ->
    kept(mcl_om_wire:field(Key, Args)).

kept(N) when is_integer(N) -> N;
kept(_AbsentOrNotAnInteger) -> undefined.

reply(#{posts := Posts, next_before := Next}) ->
    with_next(#{ok => 1, posts => [agora_post_wire:to_wire(P) || P <- Posts]}, Next).

%% Omitted on the last page rather than sent as a sentinel, which a caller
%% could not tell from a real timestamp.
with_next(Reply, undefined) -> Reply;
with_next(Reply, Next)      -> Reply#{next_before => Next}.
