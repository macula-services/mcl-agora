%%% @doc What the keeper heard mcl-news report, by item_id, so a card can be
%%% checked against it.
%%%
%%% A card is attached by the speaker's harness, which makes it a claim the
%%% speaker's node makes about the news. The keeper does not take that claim:
%%% it hears the wire itself, from admitted mcl-news nodes only, and keeps each
%%% item in the same normalised form a card is recorded in
%%% (`agora_post_stimulus:decode/1'), so checking a card is a comparison and
%%% nothing else.
%%%
%%% MEMORY, NOT A RECORD, AND BOUNDED. An item is kept for a day and at most
%%% `?MAX_ITEMS' are held, oldest out first: the mind speaks about an item
%%% within a minute of hearing it, and the keeper needs to remember only long
%%% enough to check that. Lost on restart, deliberately: an item heard before a
%%% restart and posted about after it reads as unverified, its card is not
%%% shown, and the post still is. That fails safe.
-module(heard_news_items).

-behaviour(gen_server).

-export([start_link/0, remember/2, heard/1, count/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(ITEMS, heard_news_items).
-define(BY_AGE, heard_news_items_by_age).
-define(MAX_ITEMS, 5000).
-define(KEEP_MS, 24 * 60 * 60 * 1000).
-define(SWEEP_MS, 60 * 1000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Remember one item, by its item_id. A second report of the same item
%% replaces the first: mcl-news owns the item, and the latest word is its own.
-spec remember(binary(), map()) -> ok.
remember(ItemId, Item) when is_binary(ItemId), is_map(Item) ->
    gen_server:call(?MODULE, {remember, ItemId, Item}).

%% @doc The item as the keeper heard it, or `undefined'.
-spec heard(binary() | undefined) -> map() | undefined.
heard(ItemId) when is_binary(ItemId) ->
    found(ets:lookup(?ITEMS, ItemId));
heard(_NoItem) ->
    undefined.

found([{_ItemId, Item, _HeardAt}]) -> Item;
found([]) -> undefined.

-spec count() -> non_neg_integer().
count() -> ets:info(?ITEMS, size).

%%------------------------------------------------------------------------------
%% One writer, so the two tables cannot disagree; readers go straight to ETS.

init([]) ->
    ?ITEMS = ets:new(?ITEMS, [named_table, protected, set, {read_concurrency, true}]),
    ?BY_AGE = ets:new(?BY_AGE, [named_table, protected, ordered_set]),
    {ok, sweep_later(#{})}.

handle_call({remember, ItemId, Item}, _From, State) ->
    Now = erlang:monotonic_time(millisecond),
    ok = forget(ets:lookup(?ITEMS, ItemId)),
    true = ets:insert(?ITEMS, {ItemId, Item, Now}),
    true = ets:insert(?BY_AGE, {{Now, ItemId}}),
    ok = trim(ets:info(?ITEMS, size) - ?MAX_ITEMS),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(sweep, State) ->
    ok = expire(erlang:monotonic_time(millisecond) - ?KEEP_MS),
    {noreply, sweep_later(State)};
handle_info(_Other, State) ->
    {noreply, State}.

forget([{ItemId, _Item, HeardAt}]) ->
    true = ets:delete(?BY_AGE, {HeardAt, ItemId}),
    true = ets:delete(?ITEMS, ItemId),
    ok;
forget([]) ->
    ok.

%% Oldest out first, until the table is back at its bound.
trim(Over) when Over > 0 ->
    ok = drop_oldest(ets:first(?BY_AGE)),
    trim(Over - 1);
trim(_AtOrUnder) ->
    ok.

drop_oldest('$end_of_table') -> ok;
drop_oldest({_HeardAt, ItemId}) -> forget(ets:lookup(?ITEMS, ItemId)).

expire(Before) ->
    expired(ets:first(?BY_AGE), Before).

expired({HeardAt, ItemId}, Before) when HeardAt < Before ->
    ok = forget(ets:lookup(?ITEMS, ItemId)),
    expired(ets:first(?BY_AGE), Before);
expired(_YoungerOrEnd, _Before) ->
    ok.

sweep_later(State) ->
    _ = erlang:send_after(?SWEEP_MS, self(), sweep),
    State.
