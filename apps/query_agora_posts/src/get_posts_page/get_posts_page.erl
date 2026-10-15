%%% @doc Query: the record, one page at a time, newest first.
%%%
%%% Cursor, not offset. The record grows while a reader is reading it, and a
%%% reader tailing it is the normal case here rather than the exception, so an
%%% offset page would skip or repeat posts every time a new one landed. What a
%%% caller gets back instead is `next_before': the cursor to hand to the next
%%% call, and by its absence, the fact that it has reached the end.
%%%
%%% `next_before' is OMITTED rather than sent as a sentinel. A caller cannot
%%% tell a sentinel timestamp from a real one, so one would loop forever.
%%%
%%% A limit that is absent or unusable is not an error, it is the default: this
%%% is a question about a record, and refusing to answer it because the caller
%%% was vague about how much they wanted would be useless.
-module(get_posts_page).

-export([get/1]).

-define(DEFAULT_LIMIT, 50).
-define(MAX_LIMIT, 200).

-spec get(map()) -> #{posts := [map()], next_before := integer() | undefined}.
get(Request) ->
    Limit = clamp(maps:get(limit, Request, ?DEFAULT_LIMIT)),
    {ok, Posts} = project_agora_posts_store:page(filters(Request, Limit)),
    #{posts => Posts, next_before => next_before(length(Posts) =:= Limit, Posts)}.

%% The bounds the caller actually asked for, plus the limit this desk decided
%% on: the store is handed a complete window, never a request it has to
%% interpret.
filters(Request, Limit) ->
    (maps:with([before, 'after'], Request))#{limit => Limit}.

clamp(N) when is_integer(N), N >= 1, N =< ?MAX_LIMIT -> N;
clamp(N) when is_integer(N), N > ?MAX_LIMIT -> ?MAX_LIMIT;
clamp(_AbsentOrUnusable) -> ?DEFAULT_LIMIT.

%% A full page means there may be more behind it; a short one means there is
%% not. The cursor is the oldest post served, which the next call passes back
%% as `before' -- exclusive, so the cursor post itself is not served twice.
next_before(true, Posts) -> maps:get(posted_at, lists:last(Posts));
next_before(false, _Posts) -> undefined.
