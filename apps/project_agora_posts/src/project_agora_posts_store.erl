%%% @doc The posts read model: the record, as `get_posts_page' reads it.
%%%
%%% NOT DURABLE, AND DELIBERATELY SO. This holds no information of its own --
%%% every row is a projection of an `agora_post_recorded_v1' in the event store
%%% -- so it is rebuilt from the store on boot and never needs to survive
%%% anything. The keeper's memory of what it recorded IS the event log; this is
%%% just the shape a reader wants.
%%%
%%% Two tables, one writer. `agora_posts' is an ordered_set keyed
%%% `{posted_at, post_id}', which is what makes a page a bounded walk rather
%%% than a sort of the whole record: iterating backwards from a cursor IS
%%% newest-first order, so paging costs the page and not the record.
%%% `agora_posts_by_id' is the point lookup, and it is what keeps a replayed
%%% projection from writing a second row for a post the aggregate already
%%% refused.
%%%
%%% EVERY WRITE GOES THROUGH THIS PROCESS so the two tables cannot disagree; a
%%% reader may go straight to ETS, because a read that sees a row at all sees a
%%% fully written one.
-module(project_agora_posts_store).

-behaviour(gen_server).

-export([start_link/0]).
-export([put_post/2, get_post/1, page/1, count/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(POSTS, agora_posts).
-define(BY_ID, agora_posts_by_id).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Write one post. A post already here is written again unchanged: the
%% projection is replayed on every boot, and a replay must be a no-op.
-spec put_post(binary(), map()) -> ok.
put_post(PostId, Row) ->
    gen_server:call(?MODULE, {put_post, PostId, Row}).

-spec get_post(binary()) -> {ok, map()} | {error, not_found}.
get_post(PostId) ->
    case ets:lookup(?BY_ID, PostId) of
        [{PostId, Key}] -> found(ets:lookup(?POSTS, Key));
        []              -> {error, not_found}
    end.

found([{_Key, Row}]) -> {ok, Row};
found([])            -> {error, not_found}.

%% @doc How many posts the record holds.
-spec count() -> non_neg_integer().
count() ->
    ets:info(?POSTS, size).

%% @doc One page of the record, newest first.
%%
%% `limit' is how many rows are wanted. `before' and `after' are bounds on
%% `posted_at', BOTH EXCLUSIVE, and each is what lets a caller walk the record
%% without missing or repeating anything while it grows underneath.
%%
%% `posted_at' is the SPEAKER's clock, so it is read defensively here and a row
%% with a non-integer is kept rather than crashing a page: the record's job is
%% to give back what it holds, not to be right about a clock it does not own.
-spec page(map()) -> {ok, [map()]}.
page(#{limit := Limit} = Filters) when is_integer(Limit), Limit >= 0 ->
    After = maps:get('after', Filters, undefined),
    {ok, lists:reverse(page_from(cursor(Filters), After, Limit, []))}.

cursor(#{before := Before}) when is_integer(Before) ->
    %% Every key with this posted_at is >= {Before, <<>>}, so the previous key
    %% is the newest post strictly older than the cursor.
    ets:prev(?POSTS, {Before, <<>>});
cursor(_Newest) ->
    ets:last(?POSTS).

page_from(_Key, _After, Limit, Acc) when Limit =< 0 -> Acc;
page_from('$end_of_table', _After, _Limit, Acc) -> Acc;
page_from(Key, After, Limit, Acc) ->
    Prev = ets:prev(?POSTS, Key),
    case ets:lookup(?POSTS, Key) of
        [{Key, Row}] -> keep(Prev, After, Limit, Acc, Row);
        []           -> page_from(Prev, After, Limit, Acc)
    end.

keep(Prev, After, Limit, Acc, Row) ->
    newer(Prev, After, Limit, Acc, Row, newer_than(Row, After)).

newer(Prev, After, Limit, Acc, Row, true) ->
    page_from(Prev, After, Limit - 1, [Row | Acc]);
newer(Prev, After, Limit, Acc, _Row, false) ->
    page_from(Prev, After, Limit, Acc).

newer_than(_Row, undefined) -> true;
newer_than(Row, After)      -> posted_at(Row) > After.

posted_at(Row) ->
    N = maps:get(posted_at, Row, 0),
    kept_integer(N).

kept_integer(N) when is_integer(N) -> N;
kept_integer(_NotAnInteger)        -> 0.

%%------------------------------------------------------------------------------

init([]) ->
    _ = ets:new(?POSTS, [ordered_set, public, named_table, {read_concurrency, true}]),
    _ = ets:new(?BY_ID, [set, public, named_table, {read_concurrency, true}]),
    {ok, #{}}.

handle_call({put_post, PostId, Row}, _From, State) ->
    ok = write(PostId, Row),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.

write(PostId, Row) ->
    Key = {posted_at(Row), PostId},
    true = ets:insert(?POSTS, {Key, Row}),
    true = ets:insert(?BY_ID, {PostId, Key}),
    ok.
