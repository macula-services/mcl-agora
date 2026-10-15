%%% @doc Supervises the QRY department.
%%%
%%% Owns no processes and no advertising worker: the one capability this
%%% department answers, `get_posts_page', is declared in
%%% `mcl_agora_service:capabilities/0' and advertised generically by
%%% `mcl_om:boot/1'. A bespoke worker here duplicating that job is a demon the
%%% corpus has already exorcised once.
-module(query_agora_posts_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.
